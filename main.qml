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

    // Page shown by the expanded card: "media" | "calendar" | "agenda" |
    // "settings" | "customize" | "widget" | "notification".
    property string page: "calendar"

    // Id of the custom widget currently shown on the `widget` page ("" = none).
    // Set through the D-Bus API (`ShowWidget`) or by a widget calling
    // `island.showCard(...)`/`dismiss()`; cleared by `HideWidget`.
    property string widget: ""

    // ISO date shown by the agenda page; day clicks in the calendar move it.
    property string selectedDate: Qt.formatDate(new Date(), "yyyy-MM-dd")

    // The settings page is offered only while at least one of its backends
    // (volume, brightness, bluetooth) is available.
    readonly property bool settingsAvailable: volume.available || brightness.available
                                             || bluetooth.available

    // Pages available right now. Calendar is always present; the agenda always
    // follows it, so a reminder or a day click has a destination.
    readonly property var pages: {
        var list = []
        if (media.available && media.title !== "")
            list.push("media")
        list.push("calendar")
        list.push("agenda")
        if (root.settingsAvailable)
            list.push("settings")
        list.push("customize")
        if (root.widget !== "")
            list.push("widget")
        if (root.currentNotification !== null)
            list.push("notification")
        return list
    }

    readonly property int targetWidth: {
        if (root.expanded)
            return root.page === "customize" ? Config.customizeWidth
                 : root.page === "agenda" ? Config.agendaWidth
                 : root.page === "widget" ? Config.widgetWidth
                                             : Config.mediaExpandedWidth
        if (mode === "notification")
            return Config.notificationCompactWidth
        if (mode === "media")
            return Config.mediaCompactWidth
        return Config.idleWidth
    }

    readonly property int targetHeight: {
        if (root.expanded) {
            if (root.page === "notification")
                return Config.notificationExpandedHeight
            if (root.page === "customize")
                return Config.customizeHeight
            if (root.page === "agenda")
                return Config.agendaHeight
            if (root.page === "widget")
                return Config.widgetHeight
            return Config.mediaExpandedHeight
        }
        if (mode === "notification")
            return Config.notificationCompactHeight
        if (mode === "media")
            return Config.mediaCompactHeight
        return Config.idleHeight
    }

    width: targetWidth
    height: targetHeight + Config.topPadding

    Behavior on width { NumberAnimation { duration: Config.sizeDuration; easing.type: Config.sizeEasing } }
    Behavior on height { NumberAnimation { duration: Config.sizeDuration; easing.type: Config.sizeEasing } }

    // ---- layer shell -------------------------------------------------------
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    // Horizontal placement follows the customize page's alignment knob. The
    // unanchored axis is centered by the compositor, so plain AnchorTop means
    // "center"; AnchorLeft/AnchorRight pin the pill to an edge (no margins).
    LayerShell.Window.anchors: {
        var value = LayerShell.Window.AnchorTop
        if (IslandConfig.alignment === "left")
            value |= LayerShell.Window.AnchorLeft
        else if (IslandConfig.alignment === "right")
            value |= LayerShell.Window.AnchorRight
        return value
    }
    // Layer-shell keyboard interactivity: None by default (the surface must not
    // steal focus), OnDemand while the agenda create form needs typed input.
    // The OnDemand switch is what makes KWin activate the surface;
    // requestActivate() is a no-op here because the window carries
    // Qt::WindowDoesNotAcceptFocus. The form's title input takes focus itself
    // through forceActiveFocus() when the form opens.
    LayerShell.Window.keyboardInteractivity: island.keyboardRequested
        ? LayerShell.Window.KeyboardInteractivityOnDemand
        : LayerShell.Window.KeyboardInteractivityNone
    LayerShell.Window.exclusionZone: 0
    LayerShell.Window.scope: "dynamic-island"

    // Target monitor chosen on the customize page. `wantsToBeOnActiveScreen`
    // lets the compositor follow focus when the user picked "active"; otherwise
    // the surface is pinned to the resolved screen.
    LayerShell.Window.screen: IslandConfig.targetScreen
    LayerShell.Window.wantsToBeOnActiveScreen: IslandConfig.followActiveScreen

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
        widget: root.widget
        widgetBridge: widgetBridge
        selectedDate: root.selectedDate
        media: media
        notification: root.currentNotification
        volume: volume
        brightness: brightness
        bluetooth: bluetooth
        onToggleRequested: root.toggle()
        onNextPageRequested: root.cyclePage(1)
        onPreviousPageRequested: root.cyclePage(-1)
        onDayClicked: function(isoDate) { root.openAgenda(isoDate) }
        onDateChanged: function(isoDate) { root.selectedDate = isoDate }
    }

    // Context object handed to custom widgets (assigned to their `island`
    // property by WidgetView). It is the widget-facing face of the island: a
    // widget calls these functions and reads these values; it never reaches
    // into the island's internals. Documented in docs/widgets.md.
    QtObject {
        id: widgetBridge

        // Content area of the widget page, in logical pixels.
        readonly property int cardWidth: Config.widgetWidth - 2 * Config.contentMargin
        readonly property int cardHeight: Config.widgetHeight - 2 * Config.contentMargin
        readonly property real scale: Config.scale
        readonly property string widgetId: root.widget
        // Theme colors, kept in sync with the island.
        readonly property color pillColor: Config.pillColor
        readonly property color textColor: Config.textColor
        readonly property color accentColor: Config.accentColor

        // Show an island card through the same path notifications use. The
        // card is informational only (no return value, no id).
        function showCard(appName, title, body, icon, urgency, timeoutMs) {
            root.showApiCard(0, appName, title, body, icon, urgency, timeoutMs)
        }
        // Hide the widget and return the island to its default page.
        function dismiss() {
            root.hideWidget()
        }
        function expand() {
            root.expandFromApi()
        }
        function collapse() {
            root.collapseFromApi()
        }
    }

    // While the create form is open the surface must be keyboard-active; when
    // it closes, focus is released and the surface returns to None.
    Connections {
        target: island
        function onKeyboardRequestedChanged() {
            if (island.keyboardRequested) {
                root.requestActivate()
            } else {
                // No-op with Qt::WindowDoesNotAcceptFocus; the layer-shell
                // keyboardInteractivity switch above does the real work.
                root.requestActivate()
            }
        }
    }

    // ---- behavior ----------------------------------------------------------
    function isValidIsoDate(value) {
        return /^\d{4}-\d{2}-\d{2}$/.test(value)
            && !isNaN(new Date(value + "T00:00:00").getTime())
    }

    function defaultPage() {
        // A live card (notification or API/widget-raised) outranks the widget
        // page: showing a card must be visible even while a widget is open.
        if (root.currentNotification !== null)
            return "notification"
        if (root.widget !== "")
            return "widget"
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

    // A day click in the calendar selects the date and jumps to the agenda.
    function openAgenda(isoDate) {
        if (isoDate !== "")
            root.selectedDate = isoDate
        root.page = "agenda"
        root.expanded = true
        collapseTimer.stop()
    }

    // Body for the reminder card: "Starts in N min — HH:MM" (or "Now — HH:MM"
    // once the event has started).
    function reminderBody(event) {
        const time = event.time
        const now = new Date()
        const start = new Date(event.date + "T" + time + ":00")
        const minutes = Math.round((start - now) / 60000)
        if (minutes > 0)
            return "Starts in " + minutes + " min \u2014 " + time
        return "Now \u2014 " + time
    }

    // Show the reminder as an island card, and (optionally) post it through
    // org.freedesktop.Notifications so it lands in KDE's notification history.
    function showReminder(event) {
        const body = root.reminderBody(event)
        root.replaceNotification({
            "appName": "Dynamic Island",
            "appIcon": "view-calendar",
            "summary": event.title,
            "body": body,
            "id": 0
        })
        root.mode = "notification"
        root.page = "notification"
        root.expandBriefly(Config.notificationTimeout)

        if (IslandConfig.postReminders) {
            EventNotifier.post("Dynamic Island", event.title, body, "view-calendar")
        }
    }

    // ---- D-Bus API bridge ---------------------------------------------------
    // Every function here fulfils an `IslandApi` request using the same paths
    // the interactive UI uses. The API never touches the UI directly; these
    // handlers are the only place requests become state.

    // Clear the tracked notification, reporting the dismissal of an API card
    // (one whose id was allocated by `ShowCard`) exactly once.
    function clearNotification() {
        if (root.currentNotification !== null
                && root.currentNotification.apiCardId > 0)
            IslandApi.reportCardDismissed(root.currentNotification.apiCardId)
        root.currentNotification = null
    }

    // Replace the tracked notification. The card being dropped is cleared
    // through `clearNotification()`, so an API card reports exactly one
    // CardDismissed before it is overwritten. A plain notification being
    // replaced emits nothing (clearNotification only reports apiCardId > 0).
    function replaceNotification(notification) {
        root.clearNotification()
        root.currentNotification = notification
    }

    // Show a card requested through the API (or by a widget). `id` is 0 for
    // widget-originated cards, which have no API identity.
    function showApiCard(id, appName, title, body, icon, urgency, timeoutMs) {
        root.replaceNotification({
            "appName": appName,
            "appIcon": icon,
            "summary": title,
            "body": body,
            // -1 marks an API card: it is never matched by the notification
            // monitor's daemon-id close path, so only DismissCard/DismissAll
            // (or the timeout) clear it.
            "id": -1,
            "apiCardId": id,
            "urgency": urgency
        })
        root.mode = "notification"
        root.page = "notification"
        var interval = Config.notificationTimeout
        if (timeoutMs > 0)
            interval = Math.max(500, Math.min(timeoutMs, 60000))
        root.expandBriefly(interval)
        if (id > 0)
            IslandApi.reportCardShown(id, appName, title)
    }

    function expandFromApi() {
        root.expanded = true
        collapseTimer.stop()
        if (root.page === "")
            root.page = root.defaultPage()
    }

    function collapseFromApi() {
        root.expanded = false
        root.settle()
    }

    function showPageFromApi(pageId) {
        // Validate against the pages the island actually offers right now.
        if (root.pages.indexOf(pageId) < 0)
            return
        root.page = pageId
        root.expanded = true
        collapseTimer.stop()
    }

    function showWidgetFromApi(widgetId) {
        if (IslandApi.widgets.indexOf(widgetId) < 0)
            return
        root.widget = widgetId
        root.page = "widget"
        root.expanded = true
        collapseTimer.stop()
    }

    function hideWidget() {
        root.widget = ""
        if (root.page === "widget") {
            root.expanded = false
            root.settle()
        }
    }

    // Dev/test hook: force the page requested through ISLAND_DEBUG_PAGE. For
    // `notification`, seed a placeholder when no real notification exists so
    // the page has something to render.
    function forceDebugPage(id) {
        if (id !== "media" && id !== "calendar" && id !== "agenda"
                && id !== "settings" && id !== "customize" && id !== "notification")
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
            // An API card that expires is dismissed for real.
            if (root.currentNotification !== null
                    && root.currentNotification.apiCardId > 0)
                root.clearNotification()
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
            // Ignore the echo of a reminder we posted ourselves, so exactly one
            // island card is shown (the one built in showReminder()).
            if (notification.appName === "Dynamic Island")
                return
            // Replacing a card: report the dismissal of an API card before
            // dropping it, so every shown id gets exactly one CardDismissed.
            root.replaceNotification(notification)
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
            root.clearNotification()
            if (root.mode === "notification") {
                root.expanded = false
                root.settle()
            } else {
                root.page = root.defaultPage()
            }
        }
    }

    Connections {
        target: EventStore
        function onReminderDue(event) {
            root.showReminder(event)
        }
    }

    // ---- D-Bus API requests -------------------------------------------------
    // The island only ever reacts to these signals; it never exposes its UI to
    // the service. `IslandApi`'s live state is written back through the
    // bindings below.
    Connections {
        target: IslandApi

        function onCardRequested(id, appName, title, body, icon, urgency, timeoutMs) {
            root.showApiCard(id, appName, title, body, icon, urgency, timeoutMs)
        }

        function onCardDismissRequested(id) {
            if (root.currentNotification !== null
                    && root.currentNotification.apiCardId === id) {
                root.clearNotification()
                if (root.mode === "notification") {
                    root.expanded = false
                    root.settle()
                }
            }
        }

        function onDismissAllRequested() {
            root.clearNotification()
            if (root.mode === "notification") {
                root.expanded = false
                root.settle()
            }
        }

        function onExpandRequested(expanded) {
            if (expanded)
                root.expandFromApi()
            else
                root.collapseFromApi()
        }

        function onPageRequested(pageId) {
            root.showPageFromApi(pageId)
        }

        function onWidgetRequested(widgetId) {
            root.showWidgetFromApi(widgetId)
        }

        function onHideWidgetRequested() {
            root.hideWidget()
        }

        // A rescan (for example `ReloadWidgets`) can drop the widget that is
        // currently shown. Reset the bridge state so `GetStatus.widget` does
        // not keep a stale id and the page falls back to the default.
        function onWidgetsChanged() {
            if (root.widget !== "" && IslandApi.widgets.indexOf(root.widget) < 0)
                root.hideWidget()
        }
    }

    // Live state written back so `GetStatus()` and the API's own signals are
    // truthful. These bindings re-evaluate whenever the island changes.
    Binding { target: IslandApi; property: "mode"; value: root.mode }
    Binding { target: IslandApi; property: "page"; value: root.page }
    Binding { target: IslandApi; property: "expanded"; value: root.expanded }
    Binding { target: IslandApi; property: "widget"; value: root.widget }

    Connections {
        target: root
        function onPagesChanged() {
            IslandApi.setAvailablePages(root.pages)
        }
    }

    Component.onCompleted: {
        // Publish the offered pages so IslandApi.ListPages() is truthful from
        // the start (subsequent changes flow through onPagesChanged).
        IslandApi.setAvailablePages(root.pages)

        // Adopt whatever the media backend already knows at startup.
        if (media.available && media.title !== "")
            root.showMedia()
        if (media.playing)
            root.expandBriefly(Config.mediaExpandTimeout)

        // Dev/test hook: force the selected agenda date, so screenshots can
        // target a specific day. Ignored when unset or malformed.
        if (Debug.date !== "" && isValidIsoDate(Debug.date))
            root.selectedDate = Debug.date

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
