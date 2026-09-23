pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import ".."

// The visible pill: a dark container that morphs in size (driven by the
// window) and cross-fades between views. The compact state keeps a full pill
// (radius = height / 2); the expanded card uses a small radius so it reads as
// a square-ish card. When expanded and more than one page is available,
// chevrons and a dot indicator let the user switch pages.
Rectangle {
    id: pill

    property string mode: "idle"
    property bool expanded: false
    property string page: "calendar"
    property var pages: []
    property var media
    property var notification

    readonly property bool hovered: hoverHandler.hovered
    // Navigation is only meaningful while expanded with somewhere to go.
    readonly property bool showNavigation: expanded && pages.length > 1

    // Which view is on screen: the selected page while expanded, otherwise the
    // compact view for the current mode.
    readonly property string activeView: expanded ? page : mode

    signal toggleRequested()
    signal nextPageRequested()
    signal previousPageRequested()

    anchors.top: parent.top
    anchors.topMargin: Config.topPadding
    anchors.horizontalCenter: parent.horizontalCenter
    width: parent.width
    height: parent.height - Config.topPadding
    radius: expanded ? Config.expandedRadius : height / 2
    color: Config.pillColor
    border.color: Config.pillBorderColor
    border.width: 1
    clip: true

    // Animate the radius in step with the window size animation so the
    // pill-to-card morph stays smooth.
    Behavior on radius {
        NumberAnimation { duration: Config.sizeDuration; easing.type: Easing.OutCubic }
    }

    HoverHandler {
        id: hoverHandler
    }

    // Background click surface, kept below the views so their buttons win.
    MouseArea {
        anchors.fill: parent
        onClicked: pill.toggleRequested()
    }

    IdleView {
        anchors.fill: parent
        opacity: pill.activeView === "idle" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Config.fadeDuration } }
    }

    MediaView {
        anchors.fill: parent
        media: pill.media
        expanded: pill.expanded && pill.activeView === "media"
        opacity: pill.activeView === "media" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Config.fadeDuration } }
    }

    CalendarView {
        anchors.fill: parent
        opacity: pill.activeView === "calendar" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Config.fadeDuration } }
    }

    NotificationView {
        anchors.fill: parent
        notification: pill.notification
        expanded: pill.expanded && pill.activeView === "notification"
        opacity: pill.activeView === "notification" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Config.fadeDuration } }
    }

    // ---- page navigation (expanded only) ----------------------------------
    Item {
        id: prevButton
        anchors.left: parent.left
        anchors.leftMargin: 0
        anchors.verticalCenter: parent.verticalCenter
        width: 22
        height: 40
        visible: pill.showNavigation
        opacity: pill.showNavigation ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Config.fadeDuration } }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: prevButtonHover.hovered ? Config.controlHoverColor : "transparent"
            Behavior on color { ColorAnimation { duration: Config.fadeDuration } }
        }

        Kirigami.Icon {
            anchors.centerIn: parent
            width: 16
            height: 16
            source: "arrow-left"
            color: Config.textColor
        }

        HoverHandler {
            id: prevButtonHover
        }

        // Consumes the click so the card body does not toggle collapse.
        MouseArea {
            anchors.fill: parent
            onClicked: pill.previousPageRequested()
        }
    }

    Item {
        id: nextButton
        anchors.right: parent.right
        anchors.rightMargin: 0
        anchors.verticalCenter: parent.verticalCenter
        width: 22
        height: 40
        visible: pill.showNavigation
        opacity: pill.showNavigation ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Config.fadeDuration } }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: nextButtonHover.hovered ? Config.controlHoverColor : "transparent"
            Behavior on color { ColorAnimation { duration: Config.fadeDuration } }
        }

        Kirigami.Icon {
            anchors.centerIn: parent
            width: 16
            height: 16
            source: "arrow-right"
            color: Config.textColor
        }

        HoverHandler {
            id: nextButtonHover
        }

        MouseArea {
            anchors.fill: parent
            onClicked: pill.nextPageRequested()
        }
    }

    Row {
        id: pageDots
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        spacing: 5
        visible: pill.showNavigation
        opacity: pill.showNavigation ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Config.fadeDuration } }

        Repeater {
            model: pill.pages
            delegate: Rectangle {
                required property string modelData
                width: modelData === pill.page ? 6 : 5
                height: width
                radius: width / 2
                color: modelData === pill.page ? Config.accentColor : Config.progressTrackColor
                Behavior on color { ColorAnimation { duration: Config.fadeDuration } }
            }
        }
    }
}
