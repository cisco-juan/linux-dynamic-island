import QtQuick
import org.kde.kirigami as Kirigami
import ".."

// Notification view. Compact shows the summary; expanded adds the app name and
// the wrapped body. Absolute-path icons render through Image, themed names
// through Kirigami.Icon.
Item {
    id: view

    property var notification
    property bool expanded: false

    readonly property string appName: notification && notification.appName ? notification.appName : ""
    readonly property string appIcon: notification && notification.appIcon ? notification.appIcon : ""
    readonly property string imagePath: notification && notification.imagePath ? notification.imagePath : ""
    // Prefer the explicit app_icon; fall back to the image-path hint that
    // notify-send -i and many apps use instead.
    readonly property string iconName: appIcon !== "" ? appIcon : imagePath
    readonly property string summary: notification && notification.summary ? notification.summary : ""
    readonly property string body: notification && notification.body ? notification.body : ""
    readonly property bool iconIsPath: iconName.indexOf("/") === 0

    function iconSource() {
        if (!iconIsPath)
            return ""
        return iconName.indexOf("file:") === 0 ? iconName : "file://" + iconName
    }

    // ---------------------------------------------------------------- compact
    Item {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        opacity: view.expanded ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Config.fadeDuration } }

        Image {
            id: compactPathIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            height: 20
            sourceSize.width: 40
            sourceSize.height: 40
            source: view.iconSource()
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            visible: view.iconIsPath && status === Image.Ready
        }

        Kirigami.Icon {
            id: compactThemedIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            height: 20
            source: view.iconIsPath ? "" : view.iconName
            color: Config.textColor
            visible: !view.iconIsPath && view.iconName !== ""
        }

        Text {
            anchors.left: (view.iconIsPath || view.iconName !== "") ? compactThemedIcon.right : parent.left
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: view.summary !== "" ? view.summary : view.body
            color: Config.textColor
            font.pixelSize: Config.smallSize
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    // --------------------------------------------------------------- expanded
    Item {
        anchors.fill: parent
        anchors.margins: 14
        opacity: view.expanded ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Config.fadeDuration } }

        Image {
            id: pathIcon
            anchors.left: parent.left
            anchors.top: parent.top
            width: 30
            height: 30
            sourceSize.width: 60
            sourceSize.height: 60
            source: view.iconSource()
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            visible: view.iconIsPath && status === Image.Ready
        }

        Kirigami.Icon {
            id: themedIcon
            anchors.left: parent.left
            anchors.top: parent.top
            width: 30
            height: 30
            source: view.iconIsPath ? "" : view.iconName
            color: Config.textColor
            visible: !view.iconIsPath && view.iconName !== ""
        }

        Column {
            anchors.left: (view.iconIsPath || view.iconName !== "") ? themedIcon.right : parent.left
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 3

            Text {
                width: parent.width
                text: view.appName
                color: Config.secondaryTextColor
                font.pixelSize: Config.smallSize
                elide: Text.ElideRight
                maximumLineCount: 1
                visible: text !== ""
            }

            Text {
                width: parent.width
                text: view.summary
                color: Config.textColor
                font.pixelSize: Config.titleSize
                font.bold: true
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                width: parent.width
                text: view.body
                color: Config.secondaryTextColor
                font.pixelSize: Config.bodySize
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
        }
    }
}
