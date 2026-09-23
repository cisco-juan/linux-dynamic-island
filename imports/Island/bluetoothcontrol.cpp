#include "bluetoothcontrol.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusVariant>

namespace {
constexpr auto kService = "org.bluez";
constexpr auto kRootPath = "/";
constexpr auto kObjectManager = "org.freedesktop.DBus.ObjectManager";
constexpr auto kPropsInterface = "org.freedesktop.DBus.Properties";
constexpr auto kAdapterInterface = "org.bluez.Adapter1";
constexpr auto kDeviceInterface = "org.bluez.Device1";
constexpr int kPollIntervalMs = 2000;
// Slower poll while no adapter is present.
constexpr int kSlowPollIntervalMs = 10000;
} // namespace

BluetoothControl::BluetoothControl(QObject *parent)
    : QObject(parent)
{
    m_pollTimer.setInterval(kPollIntervalMs);
    connect(&m_pollTimer, &QTimer::timeout, this, &BluetoothControl::refresh);

    refresh();
}

void BluetoothControl::setActive(bool active)
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

void BluetoothControl::setAvailable(bool available)
{
    if (available == m_available)
        return;

    m_available = available;
    emit availableChanged();
}

void BluetoothControl::updatePollInterval()
{
    const int target = m_available ? kPollIntervalMs : kSlowPollIntervalMs;
    if (m_pollTimer.interval() != target)
        m_pollTimer.setInterval(target);
}

void BluetoothControl::refresh()
{
    if (m_refreshing)
        return;

    m_refreshing = true;

    const QDBusMessage msg = QDBusMessage::createMethodCall(
        QString::fromLatin1(kService), QString::fromLatin1(kRootPath),
        QString::fromLatin1(kObjectManager), QStringLiteral("GetManagedObjects"));
    const QDBusPendingCall pending = QDBusConnection::systemBus().asyncCall(msg);
    auto *watcher = new QDBusPendingCallWatcher(pending, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this](QDBusPendingCallWatcher *w) {
                const bool error = w->isError();
                const QVariant value = error ? QVariant()
                                             : w->reply().arguments().value(0);
                w->deleteLater();
                m_refreshing = false;
                if (error)
                    setAvailable(false);
                else
                    parseManagedObjects(value);
                updatePollInterval();
            });
}

void BluetoothControl::parseManagedObjects(const QVariant &value)
{
    if (!value.isValid()) {
        setAvailable(false);
        return;
    }

    // Walk a{oa{sa{sv}}}: object path -> interface -> properties.
    const QDBusArgument arg = qvariant_cast<QDBusArgument>(value);
    QString adapterPath;
    QString adapterName;
    bool adapterPowered = false;
    int connected = 0;

    arg.beginMap();
    while (!arg.atEnd()) {
        arg.beginMapEntry();
        QDBusObjectPath path;
        arg >> path;

        arg.beginMap();
        while (!arg.atEnd()) {
            arg.beginMapEntry();
            QString interface;
            arg >> interface;
            QVariantMap props; // a{sv}
            arg >> props;
            arg.endMapEntry();

            if (interface == QLatin1String(kAdapterInterface) && adapterPath.isEmpty()) {
                adapterPath = path.path();
                adapterName = props.value(QStringLiteral("Name")).toString();
                if (adapterName.isEmpty())
                    adapterName = props.value(QStringLiteral("Alias")).toString();
                adapterPowered = props.value(QStringLiteral("Powered")).toBool();
            } else if (interface == QLatin1String(kDeviceInterface)) {
                if (props.value(QStringLiteral("Connected")).toBool())
                    ++connected;
            }
        }
        arg.endMap();
        arg.endMapEntry();
    }
    arg.endMap();

    if (adapterPath != m_adapterPath) {
        if (!m_adapterPath.isEmpty()) {
            QDBusConnection::systemBus().disconnect(
                QString::fromLatin1(kService), m_adapterPath,
                QString::fromLatin1(kPropsInterface), QStringLiteral("PropertiesChanged"),
                this, SLOT(onPropertiesChanged(QString, QVariantMap, QStringList)));
        }
        m_adapterPath = adapterPath;
        if (!m_adapterPath.isEmpty()) {
            QDBusConnection::systemBus().connect(
                QString::fromLatin1(kService), m_adapterPath,
                QString::fromLatin1(kPropsInterface), QStringLiteral("PropertiesChanged"),
                this, SLOT(onPropertiesChanged(QString, QVariantMap, QStringList)));
        }
    }

    setAvailable(!adapterPath.isEmpty());
    if (!m_available)
        return;

    if (adapterName != m_adapterName) {
        m_adapterName = adapterName;
        emit adapterNameChanged();
    }
    if (adapterPowered != m_powered) {
        m_powered = adapterPowered;
        emit poweredChanged();
    }
    if (connected != m_connectedCount) {
        m_connectedCount = connected;
        emit connectedCountChanged();
    }
}

void BluetoothControl::togglePower()
{
    if (!m_available || m_adapterPath.isEmpty())
        return;

    QDBusMessage msg = QDBusMessage::createMethodCall(
        QString::fromLatin1(kService), m_adapterPath,
        QString::fromLatin1(kPropsInterface), QStringLiteral("Set"));
    msg << QString::fromLatin1(kAdapterInterface) << QStringLiteral("Powered")
        << QVariant::fromValue(QDBusVariant(!m_powered));

    const QDBusPendingCall pending = QDBusConnection::systemBus().asyncCall(msg);
    auto *watcher = new QDBusPendingCallWatcher(pending, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this](QDBusPendingCallWatcher *w) {
                const bool error = w->isError();
                w->deleteLater();
                if (error)
                    return;
                // Re-read Powered from the bus instead of trusting the cached
                // value; the adapter's PropertiesChanged signal may be missed.
                readPowered();
            });
}

void BluetoothControl::readPowered()
{
    if (m_adapterPath.isEmpty())
        return;

    QDBusMessage msg = QDBusMessage::createMethodCall(
        QString::fromLatin1(kService), m_adapterPath,
        QString::fromLatin1(kPropsInterface), QStringLiteral("Get"));
    msg << QString::fromLatin1(kAdapterInterface) << QStringLiteral("Powered");

    const QDBusPendingCall pending = QDBusConnection::systemBus().asyncCall(msg);
    auto *watcher = new QDBusPendingCallWatcher(pending, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this](QDBusPendingCallWatcher *w) {
                const bool error = w->isError();
                const QVariant value = error ? QVariant()
                                             : w->reply().arguments().value(0);
                w->deleteLater();
                if (error)
                    return;
                // Properties.Get wraps the value in a D-Bus variant.
                const bool powered = value.value<QDBusVariant>().variant().toBool();
                if (powered != m_powered) {
                    m_powered = powered;
                    emit poweredChanged();
                }
            });
}

void BluetoothControl::onPropertiesChanged(const QString &interfaceName,
                                           const QVariantMap &changed,
                                           const QStringList &invalidated)
{
    Q_UNUSED(invalidated)
    if (interfaceName != QLatin1String(kAdapterInterface))
        return;

    if (changed.contains(QStringLiteral("Powered"))) {
        const bool powered = changed.value(QStringLiteral("Powered")).toBool();
        if (powered != m_powered) {
            m_powered = powered;
            emit poweredChanged();
        }
    }
    if (changed.contains(QStringLiteral("Name")) || changed.contains(QStringLiteral("Alias"))) {
        const QString name = changed.value(QStringLiteral("Name")).toString();
        const QString effective = name.isEmpty()
            ? changed.value(QStringLiteral("Alias")).toString() : name;
        if (!effective.isEmpty() && effective != m_adapterName) {
            m_adapterName = effective;
            emit adapterNameChanged();
        }
    }
}
