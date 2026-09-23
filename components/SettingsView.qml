pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import ".."

// Settings page for the expanded card: volume, brightness and bluetooth.
// Each row is only visible when its backend reports `available`, so the page
// degrades gracefully on machines without an audio server, a backlight or a
// bluetooth adapter. All controls are hand-rolled (no QtQuick.Controls) to
// match the dark card look.
Item {
    id: view

    property var volume
    property var brightness
    property var bluetooth

    // True while the user is dragging a slider or pressing a toggle. main.qml
    // reads it (through Island.qml) to keep the card from collapsing while the
    // user is interacting.
    property bool interacting: volumeSlider.pressed || brightnessSlider.pressed
                              || bluetoothToggle.pressed

    anchors.fill: parent
    anchors.margins: 16

    Column {
        anchors.fill: parent
        spacing: 7
        // Positioner skips invisible children, so hidden rows leave no gap.

        // ---- volume --------------------------------------------------------
        Item {
            id: volumeRow
            width: parent.width
            height: 38
            visible: view.volume && view.volume.available

            Kirigami.Icon {
                id: volumeIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18
                color: Config.textColor
                source: (view.volume && view.volume.muted) ? "audio-volume-muted"
                                                           : "audio-volume-high"
            }

            IconButton {
                id: muteButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: 22
                implicitHeight: 22
                iconSize: 15
                icon: (view.volume && view.volume.muted) ? "audio-volume-muted"
                                                         : "audio-volume-high"
                onClicked: if (view.volume) view.volume.toggleMute()
            }

            Text {
                id: volumeLabel
                anchors.right: muteButton.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                horizontalAlignment: Text.AlignRight
                text: Math.round(volumeSlider.displayValue * 100) + "%"
                color: Config.textColor
                font.pixelSize: Config.smallSize
            }

            SettingSlider {
                id: volumeSlider
                anchors.left: volumeIcon.right
                anchors.leftMargin: 10
                anchors.right: volumeLabel.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                height: 18
                value: view.volume ? view.volume.volume : 0
                onCommitted: function(v) { if (view.volume) view.volume.setVolume(v) }
            }
        }

        // ---- brightness ----------------------------------------------------
        Item {
            id: brightnessRow
            width: parent.width
            height: 38
            visible: view.brightness && view.brightness.available

            Kirigami.Icon {
                id: brightnessIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18
                source: "brightness-high"
                color: Config.textColor
            }

            Text {
                id: brightnessLabel
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                horizontalAlignment: Text.AlignRight
                text: Math.round(brightnessSlider.displayValue * 100) + "%"
                color: Config.textColor
                font.pixelSize: Config.smallSize
            }

            SettingSlider {
                id: brightnessSlider
                anchors.left: brightnessIcon.right
                anchors.leftMargin: 10
                anchors.right: brightnessLabel.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                height: 18
                value: view.brightness ? view.brightness.percent / 100 : 0
                onCommitted: function(v) {
                    if (view.brightness)
                        view.brightness.setPercent(Math.round(v * 100))
                }
            }
        }

        // ---- bluetooth -----------------------------------------------------
        Item {
            id: bluetoothRow
            width: parent.width
            height: 38
            visible: view.bluetooth && view.bluetooth.available

            Kirigami.Icon {
                id: bluetoothIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18
                source: "bluetooth"
                color: Config.textColor
            }

            SettingToggle {
                id: bluetoothToggle
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: view.bluetooth ? view.bluetooth.powered : false
                onToggled: if (view.bluetooth) view.bluetooth.togglePower()
            }

            Text {
                anchors.left: bluetoothIcon.right
                anchors.leftMargin: 10
                anchors.right: bluetoothToggle.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: {
                    if (!view.bluetooth || !view.bluetooth.powered)
                        return "Off"
                    return view.bluetooth.connectedCount > 0
                        ? "On \u00b7 " + view.bluetooth.connectedCount + " connected"
                        : "On"
                }
                color: Config.secondaryTextColor
                font.pixelSize: Config.smallSize
            }
        }
    }

    // Hand-rolled slider: track + filled portion + draggable handle. While the
    // handle is pressed the local `dragValue` is shown; the change is applied
    // to the backend on release.
    component SettingSlider: Item {
        id: slider

        property real value: 0       // 0..1, bound to the backend
        property real dragValue: 0   // 0..1, live value while pressed
        property bool pressed: false

        readonly property real displayValue: pressed ? dragValue : value

        signal committed(real value)

        implicitHeight: 18

        function valueFromX(x) {
            if (width <= 0)
                return 0
            return Math.max(0, Math.min(1, x / width))
        }

        Rectangle {
            id: sliderTrack
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 4
            radius: 2
            color: Config.progressTrackColor
        }

        Rectangle {
            anchors.left: sliderTrack.left
            anchors.verticalCenter: sliderTrack.verticalCenter
            height: 4
            radius: 2
            color: Config.accentColor
            width: sliderTrack.width * slider.displayValue
        }

        Rectangle {
            id: sliderHandle
            width: 12
            height: 12
            radius: width / 2
            color: Config.accentColor
            anchors.verticalCenter: parent.verticalCenter
            x: (slider.width - width) * slider.displayValue
        }

        MouseArea {
            anchors.fill: parent
            anchors.topMargin: -5
            anchors.bottomMargin: -5
            onPressed: function(mouse) {
                slider.pressed = true
                slider.dragValue = slider.valueFromX(mouse.x)
            }
            onPositionChanged: function(mouse) {
                if (slider.pressed)
                    slider.dragValue = slider.valueFromX(mouse.x)
            }
            onReleased: {
                if (!slider.pressed)
                    return
                slider.pressed = false
                slider.committed(slider.dragValue)
            }
            onCanceled: slider.pressed = false
        }
    }

    // Hand-rolled toggle: pill track with a sliding knob.
    component SettingToggle: Item {
        id: toggle

        property bool checked: false
        property bool pressed: mouseArea.pressed

        signal toggled()

        implicitWidth: 40
        implicitHeight: 22

        Rectangle {
            id: toggleTrack
            anchors.fill: parent
            radius: height / 2
            color: toggle.checked ? Config.accentColor : Config.progressTrackColor
            Behavior on color { ColorAnimation { duration: Config.fadeDuration } }
        }

        Rectangle {
            id: toggleKnob
            width: 16
            height: 16
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: toggle.checked ? toggleTrack.width - width - 3 : 3
            color: toggle.checked ? Config.pillColor : Config.textColor
            Behavior on x {
                NumberAnimation { duration: Config.fadeDuration; easing.type: Easing.OutCubic }
            }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            onClicked: toggle.toggled()
        }
    }
}
