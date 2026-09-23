pragma ComponentBehavior: Bound

import QtQuick
import Island 1.0
import ".."

// Hosts a third-party widget on the `widget` page of the expanded card.
//
// The widget is a standalone QML file discovered by `IslandApi` under
// `<GenericDataLocation>/dynamic-island/widgets/<id>/widget.qml`. This view
// loads it into a `Loader` and assigns the island context object to the
// widget's root `island` property, which is the only way the widget talks back
// to the island (see docs/widgets.md).
//
// Sizing: the Loader fills the card minus `Config.contentMargin`, so the
// loaded item is resized to that content area. The same size is reported to
// the widget as `island.cardWidth` / `island.cardHeight`.
Item {
    id: view

    property string widgetId: ""
    // Context object assigned to the widget's `island` property.
    property var bridge: null
    // True while the widget page is the visible page (kept for parity with the
    // other page components).
    property bool active: false

    // Absolute file URL of the widget entry point. Reading `widgetsRevision`
    // makes the binding re-evaluate whenever the registry is rescanned.
    readonly property string sourceUrl: {
        IslandApi.widgetsRevision
        if (widgetId === "")
            return ""
        const path = IslandApi.widgetSource(widgetId)
        return path === "" ? "" : "file://" + path
    }

    Loader {
        id: loader
        anchors.fill: parent
        anchors.margins: Config.contentMargin
        // Declarative: never assign `source` imperatively, or the binding would
        // be destroyed and later ShowWidget calls would not take effect.
        source: view.sourceUrl
        asynchronous: false

        onLoaded: {
            if (!item)
                return
            try {
                item.island = view.bridge
            } catch (error) {
                console.warn("WidgetView: widget " + view.widgetId
                             + " has no writable `island` property: " + error)
            }
        }

        onStatusChanged: {
            if (status !== Loader.Error)
                return
            console.warn("WidgetView: failed to load " + source)
            // The widget cannot render. Reset the bridge state through the
            // same dismissal path widgets use, so `GetStatus.widget` does not
            // keep a stale id and the island falls back to the default page.
            // Deferred: a synchronous load error fires while `root.widget` is
            // still being assigned, and resetting it there would re-enter the
            // assignment (binding loop) and race the page switch.
            Qt.callLater(function() {
                if (view.bridge && view.bridge.dismiss)
                    view.bridge.dismiss()
            })
        }
    }

    // Reload the shown widget when the registry is rescanned (for example after
    // an edit on disk). Toggling `active` recreates the item without touching
    // the bound `source`.
    Connections {
        target: IslandApi
        function onWidgetsChanged() {
            if (loader.source === "")
                return
            loader.active = false
            Qt.callLater(function() { loader.active = true })
        }
    }

    // Empty/error state: no widget selected, or it was removed while shown.
    Text {
        anchors.centerIn: parent
        visible: view.sourceUrl === "" || loader.status === Loader.Error
        text: "Widget unavailable"
        color: Config.secondaryTextColor
        font.pixelSize: Config.smallSize
    }
}
