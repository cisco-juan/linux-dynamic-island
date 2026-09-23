#include "brightnesscontrol.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDateTime>

namespace {
constexpr auto kService = "org.kde.Solid.PowerManagement";
constexpr auto kPath = "/org/kde/Solid/PowerManagement/Actions/BrightnessControl";
constexpr auto kInterface = "org.kde.Solid.PowerManagement.Actions.BrightnessControl";
constexpr int kPollIntervalMs = 1000;
// Window after a set during which incoming change signals are treated as the
// echo of our own write and ignored.
constexpr qint64 kSuppressionMs = 700;
} // namespace

BrightnessControl::BrightnessControl(QObject *parent)
    : QObject(parent)
{
    m_pollTimer.setInterval(kPollIntervalMs);
    connect(&m_pollTimer, &QTimer::timeout, this, &BrightnessControl::refresh);

    // Keep in sync with brightness keys / other clients even while the page is
    // hidden; the poll only runs while `active`.
    QDBusConnection::sessionBus().connect(
        QString::fromLatin1(kService), QString::fromLatin1(kPath),
        QString::fromLatin1(kInterface), QStringLiteral("brightnessChanged"),
        this, SLOT(onBrightnessChanged(int)));
    QDBusConnection::sessionBus().connect(
        QString::fromLatin1(kService), QString::fromLatin1(kPath),
        QString::fromLatin1(kInterface), QStringLiteral("brightnessMaxChanged"),
        this, SLOT(onBrightnessMaxChanged(int)));

    refresh();
}

void BrightnessControl::requestAsync(const QString &method,
                                     const std::function<void(const QVariant &)> &callback)
{
    const QDBusMessage msg = QDBusMessage::createMethodCall(
        QString::fromLatin1(kService), QString::fromLatin1(kPath),
        QString::fromLatin1(kInterface), method);
    const QDBusPendingCall pending = QDBusConnection::sessionBus().asyncCall(msg);
    auto *watcher = new QDBusPendingCallWatcher(pending, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [watcher, callback](QDBusPendingCallWatcher *) {
                // Read the raw reply rather than QDBusPendingReply<T>: the
                // latter maps a QVariant template argument to QDBusVariant and
                // would reject the plain `i` replies this interface returns.
                const bool error = watcher->isError();
                const QVariant value = error ? QVariant()
                                             : watcher->reply().arguments().value(0);
                watcher->deleteLater();
                callback(value);
            });
}

bool BrightnessControl::suppressed() const
{
    return QDateTime::currentMSecsSinceEpoch() < m_suppressUntilMs;
}

void BrightnessControl::setActive(bool active)
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

void BrightnessControl::setPercent(int percent)
{
    if (!m_available || m_max <= m_min)
        return;

    const int clamped = qBound(0, percent, 100);
    const int raw = qBound(m_min,
                           m_min + qRound(double(clamped) / 100.0 * double(m_max - m_min)),
                           m_max);

    // Reflect the value immediately and suppress the resulting echo so a rapid
    // drag does not judder; the D-Bus write is fire-and-forget.
    m_suppressUntilMs = QDateTime::currentMSecsSinceEpoch() + kSuppressionMs;
    m_raw = raw;
    if (clamped != m_percent) {
        m_percent = clamped;
        emit percentChanged();
    }

    QDBusMessage msg = QDBusMessage::createMethodCall(
        QString::fromLatin1(kService), QString::fromLatin1(kPath),
        QString::fromLatin1(kInterface), QStringLiteral("setBrightness"));
    msg << raw;
    QDBusConnection::sessionBus().call(msg, QDBus::NoBlock);
}

void BrightnessControl::refresh()
{
    if (m_refreshing)
        return;

    m_refreshing = true;

    requestAsync(QStringLiteral("brightnessMax"), [this](const QVariant &maxValue) {
        const int max = maxValue.toInt();
        const bool available = max > 0;
        if (available != m_available) {
            m_available = available;
            emit availableChanged();
        }
        if (!m_available) {
            m_refreshing = false;
            m_pollTimer.stop();
            return;
        }

        requestAsync(QStringLiteral("brightnessMin"), [this, max](const QVariant &minValue) {
            m_min = minValue.toInt();
            m_max = max;
            requestAsync(QStringLiteral("brightness"), [this](const QVariant &rawValue) {
                m_raw = rawValue.toInt();
                if (!suppressed())
                    publishPercent();
                m_refreshing = false;
            });
        });
    });
}

void BrightnessControl::onBrightnessChanged(int value)
{
    m_raw = value;
    if (!suppressed())
        publishPercent();
}

void BrightnessControl::onBrightnessMaxChanged(int value)
{
    m_max = value;
    if (!suppressed())
        publishPercent();
}

void BrightnessControl::publishPercent()
{
    if (m_max <= m_min)
        return;

    const int percent = qBound(0,
        qRound(double(m_raw - m_min) / double(m_max - m_min) * 100.0), 100);
    if (percent != m_percent) {
        m_percent = percent;
        emit percentChanged();
    }
}
