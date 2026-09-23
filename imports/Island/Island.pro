QT += qml dbus
CONFIG += plugin c++17
TEMPLATE = lib
TARGET = islandplugin

# Build in-place so qmldir's `plugin islandplugin` resolves libislandplugin.so
# from this very directory.
DESTDIR = $$PWD

SOURCES += \
    island_plugin.cpp \
    mediacontroller.cpp \
    notificationmonitor.cpp \
    volumecontrol.cpp \
    brightnesscontrol.cpp \
    bluetoothcontrol.cpp

HEADERS += \
    island_plugin.h \
    mediacontroller.h \
    notificationmonitor.h \
    volumecontrol.h \
    brightnesscontrol.h \
    bluetoothcontrol.h

# Keep the plugin loadable from QML without installing anything system-wide.
target.path = $$PWD
INSTALLS += target
