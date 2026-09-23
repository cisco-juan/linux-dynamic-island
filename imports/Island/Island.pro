QT += qml gui dbus
CONFIG += plugin c++17
TEMPLATE = lib
TARGET = islandplugin

# Build in-place so qmldir's `plugin islandplugin` resolves libislandplugin.so
# from this very directory.
DESTDIR = $$PWD

SOURCES += \
    island_plugin.cpp \
    islandconfig.cpp \
    mediacontroller.cpp \
    notificationmonitor.cpp \
    volumecontrol.cpp \
    brightnesscontrol.cpp \
    bluetoothcontrol.cpp \
    eventstore.cpp \
    eventnotifier.cpp \
    islandapi.cpp

HEADERS += \
    island_plugin.h \
    islandconfig.h \
    mediacontroller.h \
    notificationmonitor.h \
    volumecontrol.h \
    brightnesscontrol.h \
    bluetoothcontrol.h \
    eventstore.h \
    eventnotifier.h \
    islandapi.h

# Keep the plugin loadable from QML without installing anything system-wide.
target.path = $$PWD
INSTALLS += target
