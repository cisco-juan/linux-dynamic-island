#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <QTimer>

// Controls the system Bluetooth adapter through BlueZ on the system bus.
//
// The adapter is discovered (and the connected-device count computed) from
// org.freedesktop.DBus.ObjectManager.GetManagedObjects. The adapter's
// `PropertiesChanged` keeps `powered` live; the count is re-read on a poll
// while `active` because connect/disconnect notifications come from individual
// device paths. The poll is faster while an adapter is present and slows down
// while none is, so a machine without bluetooth is not queried every 2 s.
//
// Every bus call is asynchronous (QDBusPendingCallWatcher): the GUI thread
// never blocks on BlueZ, even if the daemon is unresponsive.
class BluetoothControl : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(bool powered READ powered NOTIFY poweredChanged)
    Q_PROPERTY(QString adapterName READ adapterName NOTIFY adapterNameChanged)
    Q_PROPERTY(int connectedCount READ connectedCount NOTIFY connectedCountChanged)
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)

public:
    explicit BluetoothControl(QObject *parent = nullptr);

    bool available() const { return m_available; }
    bool powered() const { return m_powered; }
    QString adapterName() const { return m_adapterName; }
    int connectedCount() const { return m_connectedCount; }
    bool active() const { return m_active; }
    void setActive(bool active);

public slots:
    void togglePower();

signals:
    void availableChanged();
    void poweredChanged();
    void adapterNameChanged();
    void connectedCountChanged();
    void activeChanged();

private slots:
    void refresh();
    void onPropertiesChanged(const QString &interfaceName, const QVariantMap &changed,
                             const QStringList &invalidated);

private:
    void parseManagedObjects(const QVariant &value);
    void readPowered();
    void setAvailable(bool available);
    void updatePollInterval();

    QString m_adapterPath;
    QString m_adapterName;
    bool m_available = false;
    bool m_powered = false;
    int m_connectedCount = 0;
    bool m_active = false;
    // True while a GetManagedObjects call is in flight, so polls do not pile up.
    bool m_refreshing = false;
    QTimer m_pollTimer;
};
