#include "islandapi.h"

#include <QDBusConnection>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QStandardPaths>

namespace {

const QString kBusName = QStringLiteral("io.github.cisco_juan.DynamicIsland");
const QString kObjectPath = QStringLiteral("/Island");

// `<GenericDataLocation>/dynamic-island/widgets/<id>/widget.qml`
QString widgetsRoot()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
        + QStringLiteral("/dynamic-island/widgets");
}

} // namespace

IslandApi::IslandApi(QObject *parent)
    : QObject(parent)
{
    registerOnBus();
    scanWidgets();
}

IslandApi::~IslandApi()
{
    if (!m_serviceAvailable)
        return;
    QDBusConnection bus = QDBusConnection::sessionBus();
    bus.unregisterService(kBusName);
    bus.unregisterObject(kObjectPath);
}

IslandApi *IslandApi::instance()
{
    // Leaked on purpose: the singleton must outlive every QML engine.
    static IslandApi *api = new IslandApi();
    return api;
}

void IslandApi::registerOnBus()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        qWarning() << "IslandApi: session bus unavailable; running without the D-Bus service";
        return;
    }

    if (!bus.registerObject(kObjectPath, this,
                            QDBusConnection::ExportAllSlots
                                | QDBusConnection::ExportAllSignals
                                | QDBusConnection::ExportAllProperties)) {
        qWarning() << "IslandApi: could not register" << kObjectPath
                   << "on the session bus; running without the D-Bus service";
        return;
    }

    if (!bus.registerService(kBusName)) {
        // Another instance owns the name. Drop our object registration so the
        // bus is left exactly as we found it, and keep running UI-only.
        qWarning() << "IslandApi: bus name" << kBusName
                   << "is already owned; running without the D-Bus service";
        bus.unregisterObject(kObjectPath);
        return;
    }

    m_serviceAvailable = true;
}

// ---- state written back by QML -------------------------------------------

void IslandApi::setMode(const QString &value)
{
    if (value == m_mode)
        return;
    m_mode = value;
    emit modeChanged();
}

void IslandApi::setPage(const QString &value)
{
    if (value == m_page)
        return;
    m_page = value;
    emit pageChanged();
    emit PageChanged(value);
}

void IslandApi::setExpanded(bool value)
{
    if (value == m_expanded)
        return;
    m_expanded = value;
    emit expandedChanged();
    emit ExpansionChanged(value);
}

void IslandApi::setWidget(const QString &value)
{
    if (value == m_widget)
        return;
    m_widget = value;
    emit widgetChanged();
    if (!value.isEmpty())
        emit WidgetShown(value);
}

void IslandApi::setAvailablePages(const QStringList &pages)
{
    m_pages = pages;
}

void IslandApi::reportCardShown(uint id, const QString &appName, const QString &title)
{
    emit CardShown(id, appName, title);
}

void IslandApi::reportCardDismissed(uint id)
{
    emit CardDismissed(id);
}

// ---- D-Bus methods --------------------------------------------------------

uint IslandApi::ShowCard(const QString &appName, const QString &title, const QString &body,
                         const QString &icon, int urgency, int timeoutMs)
{
    const uint id = m_nextCardId++;
    emit cardRequested(id, appName, title, body, icon, urgency, timeoutMs);
    return id;
}

void IslandApi::DismissCard(uint id)
{
    emit cardDismissRequested(id);
}

void IslandApi::DismissAll()
{
    emit dismissAllRequested();
}

void IslandApi::Expand()
{
    emit expandRequested(true);
}

void IslandApi::Collapse()
{
    emit expandRequested(false);
}

void IslandApi::Toggle()
{
    // Toggle targets the opposite of the state the island last reported.
    emit expandRequested(!m_expanded);
}

void IslandApi::ShowPage(const QString &pageId)
{
    emit pageRequested(pageId);
}

QStringList IslandApi::ListPages() const
{
    return m_pages;
}

void IslandApi::ShowWidget(const QString &widgetId)
{
    emit widgetRequested(widgetId);
}

void IslandApi::HideWidget()
{
    emit hideWidgetRequested();
}

QStringList IslandApi::ListWidgets() const
{
    return m_widgets;
}

void IslandApi::ReloadWidgets()
{
    scanWidgets();
}

QVariantMap IslandApi::GetStatus() const
{
    QVariantMap status;
    status.insert(QStringLiteral("mode"), m_mode);
    status.insert(QStringLiteral("page"), m_page);
    status.insert(QStringLiteral("expanded"), m_expanded);
    status.insert(QStringLiteral("widget"), m_widget);
    status.insert(QStringLiteral("version"), version());
    status.insert(QStringLiteral("widgets"), m_widgets);
    status.insert(QStringLiteral("pages"), m_pages);
    return status;
}

// ---- custom widget registry ----------------------------------------------

void IslandApi::scanWidgets()
{
    m_widgets.clear();
    m_widgetInfos.clear();

    const QDir root(widgetsRoot());
    if (root.exists()) {
        const QString canonicalRoot = root.canonicalPath();
        const QFileInfoList entries =
            root.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
        for (const QFileInfo &entry : entries) {
            const QString id = entry.fileName();

            // Never follow symlinks: a symlinked directory can point outside
            // the widgets root and would load foreign QML. Only a plain
            // directory is a supported widget.
            if (entry.isSymLink()) {
                qWarning() << "IslandApi: widget" << id
                           << "skipped: symlinked directories are not supported";
                continue;
            }
            // Defence in depth: the resolved directory must stay inside the
            // widgets root even if some path component resolves elsewhere.
            const QString canonicalDir = entry.canonicalFilePath();
            if (canonicalRoot.isEmpty() || canonicalDir.isEmpty()
                || !canonicalDir.startsWith(canonicalRoot + QLatin1Char('/'))) {
                qWarning() << "IslandApi: widget" << id
                           << "skipped: resolves outside the widgets root";
                continue;
            }

            const QString qmlPath = entry.absoluteFilePath() + QStringLiteral("/widget.qml");
            if (!QFileInfo::exists(qmlPath)) {
                qWarning() << "IslandApi: widget" << id << "skipped: no widget.qml";
                continue;
            }
            // The entry point itself must not resolve outside the root either
            // (for example a `widget.qml` that is a symlink to a foreign file).
            const QString canonicalQml = QFileInfo(qmlPath).canonicalFilePath();
            if (canonicalQml.isEmpty()
                || !canonicalQml.startsWith(canonicalRoot + QLatin1Char('/'))) {
                qWarning() << "IslandApi: widget" << id
                           << "skipped: entry point resolves outside the widgets root";
                continue;
            }

            QVariantMap info;
            info.insert(QStringLiteral("id"), id);
            info.insert(QStringLiteral("name"), id);
            info.insert(QStringLiteral("icon"), QString());
            info.insert(QStringLiteral("path"), qmlPath);

            const QString metaPath = entry.absoluteFilePath() + QStringLiteral("/metadata.json");
            QFile metaFile(metaPath);
            if (metaFile.exists()) {
                if (metaFile.open(QIODevice::ReadOnly)) {
                    QJsonParseError error;
                    const QJsonDocument doc = QJsonDocument::fromJson(metaFile.readAll(), &error);
                    if (error.error == QJsonParseError::NoError && doc.isObject()) {
                        const QJsonObject object = doc.object();
                        const QJsonValue name = object.value(QStringLiteral("name"));
                        if (name.isString() && !name.toString().isEmpty())
                            info.insert(QStringLiteral("name"), name.toString());
                        const QJsonValue icon = object.value(QStringLiteral("icon"));
                        if (icon.isString())
                            info.insert(QStringLiteral("icon"), icon.toString());
                    } else {
                        qWarning() << "IslandApi: widget" << id
                                   << "metadata.json is not valid JSON:"
                                   << error.errorString() << "- using defaults";
                    }
                } else {
                    qWarning() << "IslandApi: widget" << id << "metadata.json is unreadable"
                               << "- using defaults";
                }
            }

            m_widgets.append(id);
            m_widgetInfos.append(info);
        }
    }

    ++m_widgetsRevision;
    emit widgetsChanged();
}

QString IslandApi::widgetSource(const QString &widgetId) const
{
    for (const QVariant &entry : m_widgetInfos) {
        const QVariantMap map = entry.toMap();
        if (map.value(QStringLiteral("id")).toString() == widgetId)
            return map.value(QStringLiteral("path")).toString();
    }
    return QString();
}

QString IslandApi::widgetName(const QString &widgetId) const
{
    for (const QVariant &entry : m_widgetInfos) {
        const QVariantMap map = entry.toMap();
        if (map.value(QStringLiteral("id")).toString() == widgetId)
            return map.value(QStringLiteral("name")).toString();
    }
    return widgetId;
}

QString IslandApi::widgetIcon(const QString &widgetId) const
{
    for (const QVariant &entry : m_widgetInfos) {
        const QVariantMap map = entry.toMap();
        if (map.value(QStringLiteral("id")).toString() == widgetId)
            return map.value(QStringLiteral("icon")).toString();
    }
    return QString();
}
