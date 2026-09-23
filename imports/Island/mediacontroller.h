#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariant>
#include <QTimer>

// Tracks the active MPRIS media player over the session D-Bus bus.
//
// Player selection: the first player reporting PlaybackStatus == "Playing",
// otherwise the first available player. Metadata changes are picked up from
// org.freedesktop.DBus.Properties.PropertiesChanged; Position has no signal in
// MPRIS, so it is polled on a timer.
class MediaController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(bool playing READ playing NOTIFY playingChanged)
    Q_PROPERTY(QString title READ title NOTIFY metadataChanged)
    Q_PROPERTY(QString artist READ artist NOTIFY metadataChanged)
    Q_PROPERTY(QString albumArt READ albumArt NOTIFY metadataChanged)
    Q_PROPERTY(bool canGoNext READ canGoNext NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canGoPrevious READ canGoPrevious NOTIFY capabilitiesChanged)
    Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
    Q_PROPERTY(qint64 duration READ duration NOTIFY metadataChanged)
    Q_PROPERTY(QString playerName READ playerName NOTIFY availableChanged)

public:
    explicit MediaController(QObject *parent = nullptr);

    bool available() const { return m_available; }
    bool playing() const { return m_playing; }
    QString title() const { return m_title; }
    QString artist() const { return m_artist; }
    QString albumArt() const { return m_albumArt; }
    bool canGoNext() const { return m_canGoNext; }
    bool canGoPrevious() const { return m_canGoPrevious; }
    qint64 position() const { return m_position; }
    qint64 duration() const { return m_duration; }
    QString playerName() const { return m_playerName; }

public slots:
    void playPause();
    void next();
    void previous();

signals:
    void availableChanged();
    void playingChanged();
    void metadataChanged();
    void capabilitiesChanged();
    void positionChanged();

private slots:
    void refreshPlayers();
    void pollPosition();
    void onPropertiesChanged(const QString &interfaceName,
                             const QVariantMap &changed,
                             const QStringList &invalidated);

private:
    void selectPlayer(const QString &service);
    void clearPlayer();
    void loadAllProperties();

    static QVariant getProperty(const QString &service, const QString &name);
    static bool serviceIsPlaying(const QString &service);
    static QVariant unwrapVariant(const QVariant &value);
    static QVariantMap toVariantMap(const QVariant &value);
    static QStringList toStringList(const QVariant &value);
    static QVariant metadataValue(const QVariantMap &metadata, const QString &key);

    QString m_service;
    QString m_playerName;
    bool m_available = false;
    bool m_playing = false;
    QString m_title;
    QString m_artist;
    QString m_albumArt;
    bool m_canGoNext = false;
    bool m_canGoPrevious = false;
    qint64 m_position = 0;
    qint64 m_duration = 0;

    QTimer m_pollTimer;
    QTimer m_scanTimer;
};
