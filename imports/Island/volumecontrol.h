#pragma once

#include <QObject>
#include <QProcess>
#include <QQueue>
#include <QString>
#include <QStringList>
#include <QTimer>

// Controls the default audio sink through WirePlumber's `wpctl` CLI.
//
// `wpctl` is used instead of a D-Bus API because it is present on every
// WirePlumber/PulseAudio setup and abstracts the backend. The sink volume is
// polled only while `active` is true (the settings page is visible) and
// refreshed immediately after every set so the UI never shows a stale value.
//
// Every `wpctl` invocation is asynchronous: the GUI thread never waits on the
// child process. A short watchdog timer kills a hung `wpctl` so a single slow
// invocation cannot wedge the queue.
class VolumeControl : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(double volume READ volume NOTIFY volumeChanged)
    Q_PROPERTY(bool muted READ muted NOTIFY mutedChanged)
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)

public:
    explicit VolumeControl(QObject *parent = nullptr);

    bool available() const { return m_available; }
    double volume() const { return m_volume; }
    bool muted() const { return m_muted; }
    bool active() const { return m_active; }
    void setActive(bool active);

public slots:
    // `volume` is a 0..1 fraction.
    void setVolume(double volume);
    void toggleMute();

signals:
    void availableChanged();
    void volumeChanged();
    void mutedChanged();
    void activeChanged();

private slots:
    void refresh();
    void onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onProcessError(QProcess::ProcessError error);
    void onProcessTimeout();

private:
    struct Command {
        QStringList args;
        bool query = false;
    };

    void enqueue(const QStringList &args, bool query);
    void pump();
    void requestRefresh();
    void finishCurrent(bool ok, const QString &output);
    void parseVolume(const QString &output);

    QString m_wpctlPath;
    bool m_available = false;
    double m_volume = 0.0;
    bool m_muted = false;
    bool m_active = false;
    QTimer m_pollTimer;
    QProcess m_process;
    QTimer m_killTimer;
    QQueue<Command> m_queue;
    bool m_busy = false;
    bool m_runningQuery = false;
    // True while a `get-volume` query is running or queued, so overlapping
    // refreshes do not pile up.
    bool m_queryPending = false;
};
