import QtQuick
import org.kde.layershell as LayerShell
import Island 1.0
import "components"

// Layer-shell overlay: a frameless, transparent, non-focus-stealing window
// anchored to the top of the screen. KWin centers the unanchored axis.
Window {
    id: root
    visible: true
    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus

    // ---- state machine -----------------------------------------------------
    // mode: "idle" | "media" | "notification"
    property string mode: "idle"
    property bool expanded: false
    property var currentNotification: null

    // Page shown by the expanded card: "media" | "calendar" | "settings" | "notification".
    property string page: "calendar"

    // The settings page is offered only while at least one of its backends
    // (volume, brightness, bluetooth) is available.
    readonly property bool settingsAvailable: volume.available || brightness.available
                                             || bluetooth.available

    // Pages available right now. Calendar is always present; the others only
    // while they have something to show.
    readonly property var pages: {
        var list = []
        if (media.available && media.title !== "")
            list.push("media")
        list.push("calendar")
        if (root.settingsAvailable)
            list.push("settings")
        if (root.currentNotification !== null)
            list.push("notification")
        return list
    }

    readonly property int targetWidth: {
        if (root.expanded)
            return Config.mediaExpandedWidth // every expanded page is 420 wide
        if (mode === "notification")
            return Config.notificationCompactWidth
        if (mode === "media")
            return Config.mediaCompactWidth
        return Config.idleWidth
    }

    readonly property int targetHeight: {
        if (root.expanded)
            return root.page === "notification" ? Config.notificationExpandedHeight
                                                : Config.mediaExpandedHeight
        if (mode === "notification")
            return Config.notificationCompactHeight
        if (mode === "media")
            return Config.mediaCompactHeight
        return Config.idleHeight
    }

    width: targetWidth
    height: targetHeight + Config.topPadding

    Behavior on width { NumberAnimation { duration: Config.sizeDuration; easing.type: Easing.OutBack } }
    Behavior on height { NumberAnimation { duration: Config.sizeDuration; easing.type: Easing.OutBack } }

    // ---- layer shell -------------------------------------------------------
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone
    LayerShell.Window.exclusionZone: 0
    LayerShell.Window.scope: "dynamic-island"

    // ---- backends ----------------------------------------------------------
    MediaController {
        id: media
    }

    NotificationMonitor {
        id: notifier
    }

    // Settings-page backends. Each one polls/re-reads only while the settings
    // page is visible in an expanded card.
    VolumeControl {
        id: volume
        active: root.page === "settings" && root.expanded
    }

    BrightnessControl {
        id: brightness
        active: root.page === "settings" && root.expanded
    }

    BluetoothControl {
        id: bluetooth
        active: root.page === "settings" && root.expanded
    }

    Island {
        id: island
        mode: root.mode
        expanded: root.expanded
        page: root.page
        pages: root.pages
        media: media
        notification: root.currentNotification
        volume: volume
        brightness: brightness
        bluetooth: bluetooth
        onToggleRequested: root.toggle()
        onNextPageRequested: root.cyclePage(1)
        onPreviousPageRequested: root.cyclePage(-1)
    }

    // ---- behavior ----------------------------------------------------------
    function defaultPage() {
        if (root.currentNotification !== null)
            return "notification"
        if (media.available && media.title !== "")
            return "media"
        return "calendar"
    }

    function cyclePage(step) {
        const list = root.pages
        if (list.length <= 1)
            return
        var index = list.indexOf(root.page)
        if (index < 0)
            index = 0
        root.page = list[(index + step + list.length) % list.length]
    }

    function toggle() {
        root.expanded = !root.expanded
        if (root.expanded) {
            collapseTimer.stop()
            root.page = root.defaultPage()
        } else {
            root.settle()
        }
    }

    function settle() {
        if (root.mode === "notification") {
            root.mode = (media.available && media.title !== "") ? "media" : "idle"
        } else if (root.mode === "media") {
            if (!media.available || media.title === "")
                root.mode = "idle"
        }
        root.page = root.defaultPage()
    }

    function showMedia() {
        root.mode = "media"
    }

    function expandBriefly(interval) {
        root.page = root.defaultPage()
        root.expanded = true
        collapseTimer.interval = interval
        collapseTimer.restart()
    }

    // Dev/test hook: force the page requested through ISLAND_DEBUG_PAGE. For
    // `notification`, seed a placeholder when no real notification exists so
    // the page has something to render.
    function forceDebugPage(id) {
        if (id !== "media" && id !== "calendar" && id !== "settings"
                && id !== "notification")
            return
        if (id === "notification" && root.currentNotification === null) {
            root.currentNotification = {
                "appName": "Dynamic Island",
                "appIcon": "dialog-information",
                "summary": "Debug notification",
                "body": "Placeholder seeded by ISLAND_DEBUG_PAGE.",
                "id": 0
            }
            root.mode = "notification"
        }
        root.page = id
    }

    Timer {
        id: collapseTimer
        onTriggered: {
            // Never collapse mid-interaction: the user may be dragging a
            // slider on the settings page.
            if (island.hovered || island.interacting)
                return
            root.expanded = false
            root.settle()
        }
    }

    Connections {
        target: island
        function onHoveredChanged() {
            if (island.hovered) {
                collapseTimer.stop()
                if (root.mode !== "idle") {
                    root.page = root.defaultPage()
                    root.expanded = true
                }
            } else if (root.expanded && !island.interacting) {
                root.expanded = false
                root.settle()
            }
        }

        // A slider drag released with the pointer outside the pill produces no
        // hover-out event, so collapse when the interaction ends instead.
        function onInteractingChanged() {
            if (root.expanded && !island.interacting && !island.hovered) {
                root.expanded = false
                root.settle()
            }
        }
    }

    Connections {
        target: media

        function onPlayingChanged() {
            if (media.playing && root.mode === "idle")
                root.expandBriefly(Config.mediaExpandTimeout)
        }

        function onAvailableChanged() {
            if (!media.available) {
                if (root.mode === "media")
                    root.mode = "idle"
            } else if (root.mode === "idle" && media.title !== "") {
                root.showMedia()
            }
        }

        function onMetadataChanged() {
            if (root.mode === "idle" && media.available && media.title !== "")
                root.showMedia()
        }
    }

    Connections {
        target: notifier

        function onNotificationReceived(notification) {
            root.currentNotification = notification
            root.mode = "notification"
            root.page = "notification"
            root.expandBriefly(Config.notificationTimeout)
        }

        function onNotificationClosed(id) {
            if (!root.currentNotification)
                return
            // `id` is the daemon-assigned id, which differs from the
            // replaces_id captured from Notify (0 for brand-new
            // notifications). With a single visible notification, treat a
            // close of the tracked id or of an unassigned notification as ours.
            const trackedId = root.currentNotification.id
            if (trackedId !== id && trackedId !== 0)
                return
            root.currentNotification = null
            if (root.mode === "notification") {
                root.expanded = false
                root.settle()
            } else {
                root.page = root.defaultPage()
            }
        }
    }

    Component.onCompleted: {
        // Adopt whatever the media backend already knows at startup.
        if (media.available && media.title !== "")
            root.showMedia()
        if (media.playing)
            root.expandBriefly(Config.mediaExpandTimeout)

        // Dev/test hook: force the initial state so screenshots can target a
        // specific page. No effect unless the env vars are set.
        if (Debug.expand || Debug.page !== "") {
            if (Debug.page !== "")
                root.forceDebugPage(Debug.page)
            else
                root.page = root.defaultPage()
            root.expanded = true
            collapseTimer.stop()
        }
    }
}
