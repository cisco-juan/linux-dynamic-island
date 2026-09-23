#include "island_plugin.h"

#include "bluetoothcontrol.h"
#include "brightnesscontrol.h"
#include "eventnotifier.h"
#include "eventstore.h"
#include "islandapi.h"
#include "islandconfig.h"
#include "mediacontroller.h"
#include "notificationmonitor.h"
#include "volumecontrol.h"

#include <QJSEngine>
#include <QJSValue>
#include <QQmlEngine>
#include <qqml.h>

namespace {

// Dev/test flags exposed to QML as the read-only `Debug` singleton. Qt Quick
// has no built-in environment access, so the values are captured here once,
// when the singleton is first created at startup. They have no effect unless
// the corresponding environment variable is set.
QJSValue makeDebugFlags(QQmlEngine *, QJSEngine *engine)
{
    QJSValue flags = engine->newObject();
    flags.setProperty(QStringLiteral("expand"),
                      qEnvironmentVariableIntValue("ISLAND_DEBUG_EXPAND") == 1);
    flags.setProperty(QStringLiteral("page"),
                      QString::fromLocal8Bit(qgetenv("ISLAND_DEBUG_PAGE")).trimmed());
    flags.setProperty(QStringLiteral("date"),
                      QString::fromLocal8Bit(qgetenv("ISLAND_DEBUG_DATE")).trimmed());
    return flags;
}

// Provider for the `IslandConfig` singleton. It hands out the process-wide
// instance but is invoked on the engine's thread, so the QObject is created
// there (a static created at module-load time may live on a different thread).
// The instance outlives the engine, so QML must never delete it.
QObject *makeIslandConfig(QQmlEngine *engine, QJSEngine *)
{
    Q_UNUSED(engine)
    IslandConfig *config = IslandConfig::instance();
    QQmlEngine::setObjectOwnership(config, QQmlEngine::CppOwnership);
    return config;
}

// Providers for the event singletons, with the same ownership contract.
QObject *makeEventStore(QQmlEngine *engine, QJSEngine *)
{
    Q_UNUSED(engine)
    EventStore *store = EventStore::instance();
    QQmlEngine::setObjectOwnership(store, QQmlEngine::CppOwnership);
    return store;
}

QObject *makeEventNotifier(QQmlEngine *engine, QJSEngine *)
{
    Q_UNUSED(engine)
    EventNotifier *notifier = EventNotifier::instance();
    QQmlEngine::setObjectOwnership(notifier, QQmlEngine::CppOwnership);
    return notifier;
}

// Provider for the D-Bus service singleton. Creating it registers the object
// and claims the bus name (or degrades gracefully); it is referenced by
// main.qml at startup, so the service is up as soon as the island runs.
QObject *makeIslandApi(QQmlEngine *engine, QJSEngine *)
{
    Q_UNUSED(engine)
    IslandApi *api = IslandApi::instance();
    QQmlEngine::setObjectOwnership(api, QQmlEngine::CppOwnership);
    return api;
}

} // namespace

void IslandPlugin::registerTypes(const char *uri)
{
    qmlRegisterType<MediaController>(uri, 1, 0, "MediaController");
    qmlRegisterType<NotificationMonitor>(uri, 1, 0, "NotificationMonitor");
    qmlRegisterType<VolumeControl>(uri, 1, 0, "VolumeControl");
    qmlRegisterType<BrightnessControl>(uri, 1, 0, "BrightnessControl");
    qmlRegisterType<BluetoothControl>(uri, 1, 0, "BluetoothControl");
    qmlRegisterSingletonType(uri, 1, 0, "Debug", makeDebugFlags);
    qmlRegisterSingletonType<IslandConfig>(uri, 1, 0, "IslandConfig", makeIslandConfig);
    qmlRegisterSingletonType<EventStore>(uri, 1, 0, "EventStore", makeEventStore);
    qmlRegisterSingletonType<EventNotifier>(uri, 1, 0, "EventNotifier", makeEventNotifier);
    qmlRegisterSingletonType<IslandApi>(uri, 1, 0, "IslandApi", makeIslandApi);
}
