#include "volumecontrol.h"

#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>

namespace {
constexpr int kPollIntervalMs = 1000;
constexpr int kProcessTimeoutMs = 800;
constexpr auto kDefaultSink = "@DEFAULT_AUDIO_SINK@";
} // namespace

VolumeControl::VolumeControl(QObject *parent)
    : QObject(parent)
{
    m_wpctlPath = QStandardPaths::findExecutable(QStringLiteral("wpctl"));
    m_available = !m_wpctlPath.isEmpty();

    m_pollTimer.setInterval(kPollIntervalMs);
    connect(&m_pollTimer, &QTimer::timeout, this, &VolumeControl::refresh);

    // Watchdog: kill a hung `wpctl` so the next queued command can run.
    m_killTimer.setSingleShot(true);
    connect(&m_killTimer, &QTimer::timeout, this, &VolumeControl::onProcessTimeout);

    connect(&m_process, &QProcess::finished, this, &VolumeControl::onProcessFinished);
    connect(&m_process, &QProcess::errorOccurred, this, &VolumeControl::onProcessError);

    // Prime the value once so the page shows the real volume the moment it
    // opens, even before `active` is set.
    if (m_available)
        refresh();
}

void VolumeControl::enqueue(const QStringList &args, bool query)
{
    m_queue.enqueue(Command{args, query});
    pump();
}

void VolumeControl::pump()
{
    if (m_busy || m_queue.isEmpty())
        return;

    const Command command = m_queue.dequeue();
    m_runningQuery = command.query;
    m_busy = true;
    m_process.start(m_wpctlPath, command.args);
    m_killTimer.start(kProcessTimeoutMs);
}

void VolumeControl::onProcessTimeout()
{
    if (m_process.state() != QProcess::NotRunning)
        m_process.kill();
}

void VolumeControl::onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    const QString output = QString::fromUtf8(m_process.readAllStandardOutput()).trimmed();
    const bool ok = (exitStatus == QProcess::NormalExit && exitCode == 0);
    finishCurrent(ok, output);
}

void VolumeControl::onProcessError(QProcess::ProcessError error)
{
    if (error != QProcess::FailedToStart || !m_busy)
        return;

    // QProcess does not emit finished() when the program could not be started,
    // so clear the in-flight command here.
    finishCurrent(false, QString());
}

void VolumeControl::finishCurrent(bool ok, const QString &output)
{
    m_killTimer.stop();
    m_busy = false;

    if (m_runningQuery) {
        m_queryPending = false;
        if (ok)
            parseVolume(output);
    } else {
        // A set always triggers an immediate refresh so the UI never shows a
        // stale value, whether or not the write succeeded.
        requestRefresh();
    }
    pump();
}

void VolumeControl::requestRefresh()
{
    if (m_queryPending)
        return;

    m_queryPending = true;
    enqueue({QStringLiteral("get-volume"), QString::fromLatin1(kDefaultSink)}, true);
}

void VolumeControl::setActive(bool active)
{
    if (active == m_active)
        return;

    m_active = active;
    if (m_active) {
        refresh();
        m_pollTimer.start();
    } else {
        m_pollTimer.stop();
    }
    emit activeChanged();
}

void VolumeControl::setVolume(double volume)
{
    if (!m_available)
        return;

    const double clamped = qBound(0.0, volume, 1.0);
    enqueue({QStringLiteral("set-volume"), QString::fromLatin1(kDefaultSink),
             QString::number(qRound(clamped * 100.0)) + QStringLiteral("%")}, false);
}

void VolumeControl::toggleMute()
{
    if (!m_available)
        return;

    enqueue({QStringLiteral("set-mute"), QString::fromLatin1(kDefaultSink),
             QStringLiteral("toggle")}, false);
}

void VolumeControl::refresh()
{
    if (!m_available)
        return;

    requestRefresh();
}

void VolumeControl::parseVolume(const QString &output)
{
    if (output.isEmpty())
        return;

    // "Volume: 0.95" or "Volume: 0.95 MUTED".
    static const QRegularExpression volumePattern(
        QStringLiteral("Volume:\\s*([0-9]*\\.?[0-9]+)"));
    const QRegularExpressionMatch match = volumePattern.match(output);
    if (!match.hasMatch())
        return;

    const double volume = match.captured(1).toDouble();
    const bool muted = output.contains(QLatin1String("MUTED"));

    // qFuzzyCompare is unreliable around zero, so compare shifted values.
    if (!qFuzzyCompare(volume + 1.0, m_volume + 1.0)) {
        m_volume = volume;
        emit volumeChanged();
    }
    if (muted != m_muted) {
        m_muted = muted;
        emit mutedChanged();
    }
}
