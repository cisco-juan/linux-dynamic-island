#include "islandconfig.h"

#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QScreen>
#include <QSettings>
#include <QStandardPaths>

namespace {

constexpr int kSaveDelayMs = 300;
constexpr int kMinTopOffset = 0;
constexpr int kMaxTopOffset = 40;
constexpr double kMinScale = 0.75;
constexpr double kMaxScale = 1.5;
constexpr double kMinOpacity = 0.5;
constexpr double kMaxOpacity = 1.0;
constexpr int kMinAnimationDuration = 0;
constexpr int kMaxAnimationDuration = 600;

const QString kDefaultAlignment = QStringLiteral("center");
const QString kDefaultEasing = QStringLiteral("back");
const QString kDefaultScreenMode = QStringLiteral("default");

QString normalizeAlignment(const QString &value)
{
    if (value == QLatin1String("left") || value == QLatin1String("center")
        || value == QLatin1String("right"))
        return value;
    return kDefaultAlignment;
}

QString normalizeEasing(const QString &value)
{
    if (value == QLatin1String("back") || value == QLatin1String("cubic")
        || value == QLatin1String("quad"))
        return value;
    return kDefaultEasing;
}

QString normalizeScreenMode(const QString &value)
{
    const QString trimmed = value.trimmed();
    if (trimmed.isEmpty())
        return kDefaultScreenMode;
    // "primary" was the pre-v1.3 default, but it resolved to Qt's primary
    // screen, which can differ from the compositor's chosen output and moved
    // the island on existing installs. Map it to "default" so a stored ini
    // cannot resurrect that regression.
    if (trimmed == QLatin1String("primary"))
        return kDefaultScreenMode;
    return trimmed;
}

} // namespace

IslandConfig::IslandConfig(QObject *parent)
    : QObject(parent)
{
    // QSettings resolves `~/.config` from the XDG config location; build the
    // app-specific path below it and make sure the directory exists.
    const QString configDir =
        QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
        + QStringLiteral("/dynamic-island");
    QDir().mkpath(configDir);
    m_settingsPath = configDir + QStringLiteral("/config.ini");

    load();

    m_saveTimer.setSingleShot(true);
    m_saveTimer.setInterval(kSaveDelayMs);
    connect(&m_saveTimer, &QTimer::timeout, this, &IslandConfig::save);

    // A graceful quit must not drop a change that is still waiting on the
    // debounce timer.
    if (QCoreApplication *app = QCoreApplication::instance())
        connect(app, &QCoreApplication::aboutToQuit, this, &IslandConfig::save);

    // Keep the resolved screen (and the offered names) fresh across hotplug and
    // primary-screen changes.
    if (QGuiApplication *app = qGuiApp) {
        connect(app, &QGuiApplication::screenAdded, this, &IslandConfig::refreshScreens);
        connect(app, &QGuiApplication::screenRemoved, this, &IslandConfig::refreshScreens);
        connect(app, &QGuiApplication::primaryScreenChanged, this,
                &IslandConfig::refreshScreens);
    }

    refreshScreens();
}

IslandConfig::~IslandConfig() = default;

IslandConfig *IslandConfig::instance()
{
    // Leaked on purpose: the singleton must outlive every QML engine.
    static IslandConfig *config = new IslandConfig();
    return config;
}

void IslandConfig::load()
{
    QSettings settings(m_settingsPath, QSettings::IniFormat);

    m_alignment = normalizeAlignment(
        settings.value(QStringLiteral("alignment"), m_alignment).toString());
    m_topOffset = qBound(kMinTopOffset,
                         settings.value(QStringLiteral("topOffset"), m_topOffset).toInt(),
                         kMaxTopOffset);
    m_scale = qBound(kMinScale,
                     settings.value(QStringLiteral("scale"), m_scale).toDouble(),
                     kMaxScale);
    m_opacity = qBound(kMinOpacity,
                       settings.value(QStringLiteral("opacity"), m_opacity).toDouble(),
                       kMaxOpacity);
    m_animationDuration =
        qBound(kMinAnimationDuration,
               settings.value(QStringLiteral("animationDuration"), m_animationDuration).toInt(),
               kMaxAnimationDuration);
    m_easing = normalizeEasing(
        settings.value(QStringLiteral("easing"), m_easing).toString());
    m_screenMode = normalizeScreenMode(
        settings.value(QStringLiteral("screenMode"), m_screenMode).toString());
}

void IslandConfig::save()
{
    m_saveTimer.stop();

    QSettings settings(m_settingsPath, QSettings::IniFormat);
    settings.setValue(QStringLiteral("alignment"), m_alignment);
    settings.setValue(QStringLiteral("topOffset"), m_topOffset);
    settings.setValue(QStringLiteral("scale"), m_scale);
    settings.setValue(QStringLiteral("opacity"), m_opacity);
    settings.setValue(QStringLiteral("animationDuration"), m_animationDuration);
    settings.setValue(QStringLiteral("easing"), m_easing);
    settings.setValue(QStringLiteral("screenMode"), m_screenMode);
    settings.sync();
}

void IslandConfig::scheduleSave()
{
    m_saveTimer.start();
}

void IslandConfig::flush()
{
    save();
}

QScreen *IslandConfig::resolveScreen() const
{
    // "default" leaves the surface unpinned: LayerShell.Window.screen is null
    // and the compositor places the surface exactly as it did before the
    // customize page existed.
    if (m_screenMode == QLatin1String("default"))
        return nullptr;

    // "active" is handled by the compositor through wantsToBeOnActiveScreen;
    // the base screen is the primary one.
    if (m_screenMode == QLatin1String("active"))
        return QGuiApplication::primaryScreen();

    const auto screens = QGuiApplication::screens();
    for (QScreen *screen : screens) {
        if (screen->name() == m_screenMode)
            return screen;
    }
    // The configured monitor is not connected right now: fall back to primary.
    return QGuiApplication::primaryScreen();
}

void IslandConfig::refreshScreens()
{
    QStringList names;
    const auto screens = QGuiApplication::screens();
    names.reserve(screens.size());
    for (QScreen *screen : screens)
        names.append(screen->name());

    if (names != m_screenNames) {
        m_screenNames = names;
        emit screenNamesChanged();
    }

    QScreen *resolved = resolveScreen();
    if (resolved != m_targetScreen) {
        m_targetScreen = resolved;
        emit targetScreenChanged();
    }
}

void IslandConfig::setAlignment(const QString &value)
{
    const QString normalized = normalizeAlignment(value);
    if (normalized == m_alignment)
        return;
    m_alignment = normalized;
    emit alignmentChanged();
    scheduleSave();
}

void IslandConfig::setTopOffset(int value)
{
    const int clamped = qBound(kMinTopOffset, value, kMaxTopOffset);
    if (clamped == m_topOffset)
        return;
    m_topOffset = clamped;
    emit topOffsetChanged();
    scheduleSave();
}

void IslandConfig::setScale(double value)
{
    const double clamped = qBound(kMinScale, value, kMaxScale);
    if (qFuzzyCompare(clamped + 1.0, m_scale + 1.0))
        return;
    m_scale = clamped;
    emit scaleChanged();
    scheduleSave();
}

void IslandConfig::setOpacity(double value)
{
    const double clamped = qBound(kMinOpacity, value, kMaxOpacity);
    if (qFuzzyCompare(clamped + 1.0, m_opacity + 1.0))
        return;
    m_opacity = clamped;
    emit opacityChanged();
    scheduleSave();
}

void IslandConfig::setAnimationDuration(int value)
{
    const int clamped = qBound(kMinAnimationDuration, value, kMaxAnimationDuration);
    if (clamped == m_animationDuration)
        return;
    m_animationDuration = clamped;
    emit animationDurationChanged();
    scheduleSave();
}

void IslandConfig::setEasing(const QString &value)
{
    const QString normalized = normalizeEasing(value);
    if (normalized == m_easing)
        return;
    m_easing = normalized;
    emit easingChanged();
    scheduleSave();
}

void IslandConfig::setScreenMode(const QString &value)
{
    const QString normalized = normalizeScreenMode(value);
    if (normalized == m_screenMode)
        return;

    const bool followedActiveBefore = followActiveScreen();
    m_screenMode = normalized;
    emit screenModeChanged();
    if (followActiveScreen() != followedActiveBefore)
        emit followActiveScreenChanged();
    scheduleSave();

    QScreen *resolved = resolveScreen();
    if (resolved != m_targetScreen) {
        m_targetScreen = resolved;
        emit targetScreenChanged();
    }
}

void IslandConfig::reset()
{
    setAlignment(kDefaultAlignment);
    setTopOffset(6);
    setScale(1.0);
    setOpacity(0.92);
    setAnimationDuration(300);
    setEasing(kDefaultEasing);
    setScreenMode(kDefaultScreenMode);
    save();
}
