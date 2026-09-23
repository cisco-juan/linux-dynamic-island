#pragma once

#include <QQmlExtensionPlugin>

// QML extension plugin entry point for the `Island` module.
class IslandPlugin : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)

public:
    void registerTypes(const char *uri) override;
};
