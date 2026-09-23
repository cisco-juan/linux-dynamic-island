#include "mediacontroller.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDBusVariant>

namespace {
constexpr auto kMprisPrefix = "org.mpris.MediaPlayer2.";
constexpr auto kPlayerPath = "/org/mpris/MediaPlayer2";
constexpr auto kPlayerInterface = "org.mpris.MediaPlayer2.Player";
constexpr auto kPropsInterface = "org.freedesktop.DBus.Properties";
} // namespace

MediaController::MediaController(QObject *parent)
    : QObject(parent)
{
    m_pollTimer.setInterval(1000);
    connect(&m_pollTimer, &QTimer::timeout, this, &MediaController::pollPosition);

    m_scanTimer.setInterval(2000);
    connect(&m_scanTimer, &QTimer::timeout, this, &MediaController::refreshPlayers);

    m_scanTimer.start();
    refreshPlayers();
}

QVariant MediaController::unwrapVariant(const QVariant &value)
{
    // org.freedesktop.DBus.Properties.Get returns a `v`, which QtDBus hands back
    // as a QDBusVariant. Unwrap it before converting to a concrete type.
    if (value.metaType().id() == qMetaTypeId<QDBusVariant>())
        return value.value<QDBusVariant>().variant();
    return value;
}

QVariant MediaController::getProperty(const QString &service, const QString &name)
{
    QDBusMessage msg = QDBusMessage::createMethodCall(service, kPlayerPath,
                                                      kPropsInterface, QStringLiteral("Get"));
    msg << kPlayerInterface << name;
    // Blocking call on the GUI thread: pass a short explicit timeout so an
    // unresponsive player degrades gracefully instead of freezing the island
    // for the default 25 s.
    const QDBusMessage reply = QDBusConnection::sessionBus().call(msg, QDBus::Block, 300);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty())
        return {};
    return unwrapVariant(reply.arguments().first());
}

bool MediaController::serviceIsPlaying(const QString &service)
{
    return getProperty(service, QStringLiteral("PlaybackStatus")).toString()
           == QLatin1String("Playing");
}

QVariantMap MediaController::toVariantMap(const QVariant &value)
{
    const QVariant unwrapped = unwrapVariant(value);
    if (unwrapped.metaType().id() == qMetaTypeId<QDBusArgument>()) {
        QDBusArgument arg = unwrapped.value<QDBusArgument>();
        QVariantMap map;
        arg >> map;
        return map;
    }
    return unwrapped.toMap();
}

QStringList MediaController::toStringList(const QVariant &value)
{
    const QVariant unwrapped = unwrapVariant(value);
    if (unwrapped.metaType().id() == qMetaTypeId<QDBusArgument>()) {
        QDBusArgument arg = unwrapped.value<QDBusArgument>();
        QStringList list;
        arg >> list;
        return list;
    }
    return unwrapped.toStringList();
}

QVariant MediaController::metadataValue(const QVariantMap &metadata, const QString &key)
{
    return unwrapVariant(metadata.value(key));
}

void MediaController::refreshPlayers()
{
    QDBusConnectionInterface *iface = QDBusConnection::sessionBus().interface();
    if (!iface)
        return;

    const QDBusReply<QStringList> reply = iface->registeredServiceNames();
    if (!reply.isValid())
        return;

    QStringList services;
    for (const QString &name : reply.value()) {
        if (name.startsWith(QLatin1String(kMprisPrefix)))
            services << name;
    }

    QString chosen;
    for (const QString &service : services) {
        if (serviceIsPlaying(service)) {
            chosen = service;
            break;
        }
    }
    if (chosen.isEmpty() && !services.isEmpty())
        chosen = services.first();

    if (chosen == m_service)
        return;

    if (chosen.isEmpty())
        clearPlayer();
    else
        selectPlayer(chosen);
}

void MediaController::selectPlayer(const QString &service)
{
    if (!m_service.isEmpty()) {
        QDBusConnection::sessionBus().disconnect(
            m_service, kPlayerPath, kPropsInterface, QStringLiteral("PropertiesChanged"),
            this, SLOT(onPropertiesChanged(QString, QVariantMap, QStringList)));
    }

    m_service = service;
    m_playerName = service.mid(QString::fromLatin1(kMprisPrefix).size());

    QDBusConnection::sessionBus().connect(
        m_service, kPlayerPath, kPropsInterface, QStringLiteral("PropertiesChanged"),
        this, SLOT(onPropertiesChanged(QString, QVariantMap, QStringList)));

    m_pollTimer.start();
    loadAllProperties();

    emit availableChanged();
}

void MediaController::clearPlayer()
{
    if (!m_service.isEmpty()) {
        QDBusConnection::sessionBus().disconnect(
            m_service, kPlayerPath, kPropsInterface, QStringLiteral("PropertiesChanged"),
            this, SLOT(onPropertiesChanged(QString, QVariantMap, QStringList)));
    }

    m_service.clear();
    m_playerName.clear();
    m_pollTimer.stop();

    const bool hadAvailability = m_available;
    m_available = false;
    m_playing = false;
    m_title.clear();
    m_artist.clear();
    m_albumArt.clear();
    m_canGoNext = false;
    m_canGoPrevious = false;
    m_position = 0;
    m_duration = 0;

    if (hadAvailability)
        emit availableChanged();
    emit playingChanged();
    emit metadataChanged();
    emit capabilitiesChanged();
    emit positionChanged();
}

void MediaController::loadAllProperties()
{
    if (m_service.isEmpty())
        return;

    m_available = true;

    const bool playing = serviceIsPlaying(m_service);
    if (playing != m_playing) {
        m_playing = playing;
        emit playingChanged();
    }

    const bool canNext = getProperty(m_service, QStringLiteral("CanGoNext")).toBool();
    const bool canPrev = getProperty(m_service, QStringLiteral("CanGoPrevious")).toBool();
    if (canNext != m_canGoNext || canPrev != m_canGoPrevious) {
        m_canGoNext = canNext;
        m_canGoPrevious = canPrev;
        emit capabilitiesChanged();
    }

    const QVariantMap metadata = toVariantMap(getProperty(m_service, QStringLiteral("Metadata")));

    const QString title = metadataValue(metadata, QStringLiteral("xesam:title")).toString();
    const QStringList artists = toStringList(metadataValue(metadata, QStringLiteral("xesam:artist")));
    const QString artist = artists.join(QStringLiteral(", "));
    const QString artUrl = metadataValue(metadata, QStringLiteral("mpris:artUrl")).toString();
    const qint64 lengthUs = metadataValue(metadata, QStringLiteral("mpris:length")).toLongLong();
    const qint64 durationMs = lengthUs > 0 ? lengthUs / 1000 : 0;

    if (title != m_title || artist != m_artist || artUrl != m_albumArt || durationMs != m_duration) {
        m_title = title;
        m_artist = artist;
        m_albumArt = artUrl;
        m_duration = durationMs;
        emit metadataChanged();
    }
}

void MediaController::pollPosition()
{
    if (m_service.isEmpty())
        return;

    const QVariant value = getProperty(m_service, QStringLiteral("Position"));
    if (!value.isValid())
        return;

    const qint64 positionMs = value.toLongLong() / 1000;
    if (positionMs != m_position) {
        m_position = positionMs;
        emit positionChanged();
    }
}

void MediaController::onPropertiesChanged(const QString &interfaceName,
                                          const QVariantMap &changed,
                                          const QStringList &invalidated)
{
    Q_UNUSED(invalidated)
    if (interfaceName != QLatin1String(kPlayerInterface))
        return;

    if (changed.contains(QStringLiteral("PlaybackStatus"))) {
        const bool playing = unwrapVariant(changed.value(QStringLiteral("PlaybackStatus"))).toString()
                             == QLatin1String("Playing");
        if (playing != m_playing) {
            m_playing = playing;
            emit playingChanged();
        }
        // A player may have started playing: re-evaluate which player is active.
        if (playing)
            m_scanTimer.start();
    }

    if (changed.contains(QStringLiteral("CanGoNext")) || changed.contains(QStringLiteral("CanGoPrevious"))) {
        if (changed.contains(QStringLiteral("CanGoNext")))
            m_canGoNext = unwrapVariant(changed.value(QStringLiteral("CanGoNext"))).toBool();
        if (changed.contains(QStringLiteral("CanGoPrevious")))
            m_canGoPrevious = unwrapVariant(changed.value(QStringLiteral("CanGoPrevious"))).toBool();
        emit capabilitiesChanged();
    }

    if (changed.contains(QStringLiteral("Metadata"))) {
        const QVariantMap metadata = toVariantMap(changed.value(QStringLiteral("Metadata")));
        const QString title = metadataValue(metadata, QStringLiteral("xesam:title")).toString();
        const QStringList artists = toStringList(metadataValue(metadata, QStringLiteral("xesam:artist")));
        const QString artist = artists.join(QStringLiteral(", "));
        const QString artUrl = metadataValue(metadata, QStringLiteral("mpris:artUrl")).toString();
        const qint64 lengthUs = metadataValue(metadata, QStringLiteral("mpris:length")).toLongLong();
        const qint64 durationMs = lengthUs > 0 ? lengthUs / 1000 : 0;

        if (title != m_title || artist != m_artist || artUrl != m_albumArt || durationMs != m_duration) {
            m_title = title;
            m_artist = artist;
            m_albumArt = artUrl;
            m_duration = durationMs;
            emit metadataChanged();
        }
        // New track: restart position reporting from zero.
        if (m_position != 0) {
            m_position = 0;
            emit positionChanged();
        }
    }
}

void MediaController::playPause()
{
    if (m_service.isEmpty())
        return;
    QDBusMessage msg = QDBusMessage::createMethodCall(m_service, kPlayerPath,
                                                      kPlayerInterface, QStringLiteral("PlayPause"));
    QDBusConnection::sessionBus().call(msg, QDBus::NoBlock);
}

void MediaController::next()
{
    if (m_service.isEmpty())
        return;
    QDBusMessage msg = QDBusMessage::createMethodCall(m_service, kPlayerPath,
                                                      kPlayerInterface, QStringLiteral("Next"));
    QDBusConnection::sessionBus().call(msg, QDBus::NoBlock);
}

void MediaController::previous()
{
    if (m_service.isEmpty())
        return;
    QDBusMessage msg = QDBusMessage::createMethodCall(m_service, kPlayerPath,
                                                      kPlayerInterface, QStringLiteral("Previous"));
    QDBusConnection::sessionBus().call(msg, QDBus::NoBlock);
}
