import QtQuick
import org.kde.kirigami as Kirigami
import ".."

// Small round, theme-icon button used by the media controls.
// When `icon` is empty the `glyph` text is rendered instead.
Item {
    id: control

    property string icon: ""
    property string glyph: ""
    property int iconSize: 18
    property bool hovered: hoverHandler.hovered

    signal clicked()

    implicitWidth: 32
    implicitHeight: 32
    opacity: enabled ? 1.0 : 0.35

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: control.hovered && control.enabled ? Config.controlHoverColor : "transparent"
        Behavior on color { ColorAnimation { duration: Config.fadeDuration } }
    }

    Kirigami.Icon {
        anchors.centerIn: parent
        width: control.iconSize
        height: control.iconSize
        source: control.icon
        color: Config.textColor
        visible: control.icon !== ""
    }

    Text {
        anchors.centerIn: parent
        text: control.glyph
        visible: control.icon === ""
        color: Config.textColor
        font.pixelSize: 15
    }

    HoverHandler {
        id: hoverHandler
        enabled: control.enabled
    }

    MouseArea {
        anchors.fill: parent
        enabled: control.enabled
        onClicked: control.clicked()
    }
}
