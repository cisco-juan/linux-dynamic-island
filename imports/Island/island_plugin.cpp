#include "island_plugin.h"

#include "bluetoothcontrol.h"
#include "brightnesscontrol.h"
#include "mediacontroller.h"
#include "notificationmonitor.h"
#include "volumecontrol.h"

#include <QJSEngine>
#include <QJSValue>
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
    return flags;
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
}
