import QtQuick
import ".."

// Collapsed resting state: a quiet pill with a gently pulsing dot.
Item {
    id: view

    Item {
        anchors.centerIn: parent
        width: Math.round(10 * Config.scale)
        height: width

        Rectangle {
            anchors.centerIn: parent
            width: Math.round(7 * Config.scale)
            height: width
            radius: width / 2
            color: Config.textColor
            opacity: 0.85

            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: true
                NumberAnimation { to: 0.35; duration: 1400; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.85; duration: 1400; easing.type: Easing.InOutSine }
            }
        }
    }
}
