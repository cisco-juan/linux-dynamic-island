pragma ComponentBehavior: Bound

import QtQuick
import Island 1.0
import ".."

// Customize page for the expanded card: every knob of the island itself, split
// into two columns so the card does not become a tall list. Each control writes
// straight to the persisted `IslandConfig` singleton, so changes apply live
// (the island resizes, moves, fades or re-times as you drag).
//
// The visual language mirrors SettingsView.qml: hand-rolled slider, cycle
// buttons and a small action button, all in the dark card style. `interacting`
// is forwarded through Island.qml so the card never collapses mid-drag.
Item {
    id: view

    // True while the user is pressing any control. main.qml reads it (through
    // Island.qml) to keep the card from collapsing during the interaction.
    property bool interacting: offsetSlider.pressed || scaleSlider.pressed
                              || opacitySlider.pressed || durationSlider.pressed
                              || alignButton.pressed || easingButton.pressed
                              || screenButton.pressed || resetButton.pressed

    anchors.fill: parent
    anchors.margins: Config.contentMargin

    // A completed interaction is persisted right away: the 300 ms debounce only
    // covers the updates produced while a control is still being dragged, so a
    // change cannot be lost to a quit or a kill right after the drag ends.
    onInteractingChanged: if (!view.interacting) IslandConfig.flush()

    property int gridSpacing: Math.round(14 * Config.scale)

    function capitalize(value) {
        return value.length > 0 ? value.charAt(0).toUpperCase() + value.slice(1) : value
    }

    function screenLabel(mode) {
        if (mode === "default")
            return "Default"
        if (mode === "active")
            return "Active screen"
        return mode
    }

    function cycleFrom(list, current) {
        var index = list.indexOf(current)
        return list[(index + 1 + list.length) % list.length]
    }

    function cycleAlignment() {
        IslandConfig.alignment = view.cycleFrom(["left", "center", "right"],
                                                 IslandConfig.alignment)
    }

    function cycleEasing() {
        IslandConfig.easing = view.cycleFrom(["back", "cubic", "quad"],
                                              IslandConfig.easing)
    }

    function cycleScreen() {
        var list = ["default", "active"].concat(IslandConfig.screenNames)
        IslandConfig.screenMode = view.cycleFrom(list, IslandConfig.screenMode)
    }

    Grid {
        id: grid
        anchors.fill: parent
        columns: 2
        columnSpacing: view.gridSpacing
        rowSpacing: Math.round(8 * Config.scale)

        // ---- alignment ------------------------------------------------------
        RowBase {
            label: "Alignment"
            availableWidth: view.width
            CycleButton {
                id: alignButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: view.capitalize(IslandConfig.alignment)
                onClicked: view.cycleAlignment()
            }
        }

        // ---- top offset -----------------------------------------------------
        RowBase {
            label: "Top offset"
            availableWidth: view.width
            LiveSlider {
                id: offsetSlider
                anchors.left: parent.left
                anchors.right: offsetValue.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                height: Config.sliderHeight
                value: IslandConfig.topOffset / 40
                onEdited: function(v) { IslandConfig.topOffset = Math.round(v * 40) }
            }
            Text {
                id: offsetValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(34 * Config.scale)
                horizontalAlignment: Text.AlignRight
                text: IslandConfig.topOffset + " px"
                color: Config.textColor
                font.pixelSize: Config.smallSize
            }
        }

        // ---- scale ----------------------------------------------------------
        RowBase {
            label: "Scale"
            availableWidth: view.width
            LiveSlider {
                id: scaleSlider
                anchors.left: parent.left
                anchors.right: scaleValue.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                height: Config.sliderHeight
                value: (IslandConfig.scale - 0.75) / 0.75
                onEdited: function(v) { IslandConfig.scale = 0.75 + v * 0.75 }
            }
            Text {
                id: scaleValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(34 * Config.scale)
                horizontalAlignment: Text.AlignRight
                text: Math.round(IslandConfig.scale * 100) + "%"
                color: Config.textColor
                font.pixelSize: Config.smallSize
            }
        }

        // ---- opacity --------------------------------------------------------
        RowBase {
            label: "Opacity"
            availableWidth: view.width
            LiveSlider {
                id: opacitySlider
                anchors.left: parent.left
                anchors.right: opacityValue.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                height: Config.sliderHeight
                value: (IslandConfig.opacity - 0.5) / 0.5
                onEdited: function(v) { IslandConfig.opacity = 0.5 + v * 0.5 }
            }
            Text {
                id: opacityValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(34 * Config.scale)
                horizontalAlignment: Text.AlignRight
                text: Math.round(IslandConfig.opacity * 100) + "%"
                color: Config.textColor
                font.pixelSize: Config.smallSize
            }
        }

        // ---- animation duration --------------------------------------------
        RowBase {
            label: "Animation"
            availableWidth: view.width
            LiveSlider {
                id: durationSlider
                anchors.left: parent.left
                anchors.right: durationValue.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                height: Config.sliderHeight
                value: IslandConfig.animationDuration / 600
                onEdited: function(v) {
                    IslandConfig.animationDuration = Math.round(v * 600)
                }
            }
            Text {
                id: durationValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(40 * Config.scale)
                horizontalAlignment: Text.AlignRight
                text: IslandConfig.animationDuration === 0
                      ? "Off" : IslandConfig.animationDuration + " ms"
                color: Config.textColor
                font.pixelSize: Config.smallSize
            }
        }

        // ---- easing ---------------------------------------------------------
        RowBase {
            label: "Easing"
            availableWidth: view.width
            CycleButton {
                id: easingButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: view.capitalize(IslandConfig.easing)
                onClicked: view.cycleEasing()
            }
        }

        // ---- screen ---------------------------------------------------------
        RowBase {
            label: "Screen"
            availableWidth: view.width
            CycleButton {
                id: screenButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: Math.min(parent.width, Math.round(120 * Config.scale))
                text: view.screenLabel(IslandConfig.screenMode)
                onClicked: view.cycleScreen()
            }
        }

        // ---- reset ----------------------------------------------------------
        RowBase {
            label: "Reset"
            availableWidth: view.width
            ActionButton {
                id: resetButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "Restore defaults"
                onClicked: IslandConfig.reset()
            }
        }
    }

    // A labelled row: fixed label column on the left, a content slot on the
    // right. Children declared on a RowBase land in the slot and anchor to it.
    component RowBase: Item {
        id: row

        property string label: ""
        property real availableWidth: 0
        default property alias content: slot.data

        width: Math.max(0, (availableWidth - Math.round(14 * Config.scale)) / 2)
        height: Config.rowHeight

        Text {
            id: rowLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(70 * Config.scale)
            text: row.label
            color: Config.secondaryTextColor
            font.pixelSize: Config.smallSize
            elide: Text.ElideRight
        }

        Item {
            id: slot
            anchors.left: rowLabel.right
            anchors.leftMargin: 6
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
        }
    }

    // Hand-rolled pill button that cycles through a short list of values.
    component CycleButton: Item {
        id: button

        property string text: ""
        readonly property bool pressed: mouseArea.pressed

        signal clicked()

        implicitWidth: Math.max(Math.round(72 * Config.scale), buttonText.implicitWidth + 16)
        implicitHeight: Math.round(24 * Config.scale)

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: button.pressed || hoverHandler.hovered ? Config.controlHoverColor
                                                          : Config.progressTrackColor
            border.color: Config.pillBorderColor
            border.width: 1
            Behavior on color { ColorAnimation { duration: Config.fadeDuration } }
        }

        Text {
            id: buttonText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, button.width - 8)
            horizontalAlignment: Text.AlignHCenter
            text: button.text
            color: Config.textColor
            font.pixelSize: Config.smallSize
            elide: Text.ElideRight
        }

        HoverHandler {
            id: hoverHandler
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            onClicked: button.clicked()
        }
    }

    // Small filled button used for the reset action.
    component ActionButton: Item {
        id: button

        property string text: ""
        readonly property bool pressed: mouseArea.pressed

        signal clicked()

        implicitWidth: buttonLabel.implicitWidth + 18
        implicitHeight: Math.round(24 * Config.scale)

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: button.pressed ? Config.controlHoverColor : Config.progressTrackColor
            border.color: Config.pillBorderColor
            border.width: 1
            Behavior on color { ColorAnimation { duration: Config.fadeDuration } }
        }

        Text {
            id: buttonLabel
            anchors.centerIn: parent
            text: button.text
            color: Config.textColor
            font.pixelSize: Config.smallSize
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            onClicked: button.clicked()
        }
    }

    // Live slider: applies continuously while dragging. The value is anchored
    // at press time so the layout shifting under the pointer (the card grows
    // and moves as scale changes) cannot feed back into the value.
    component LiveSlider: Item {
        id: slider

        property real value: 0       // 0..1, bound to the backing property
        property real dragValue: 0   // 0..1, live value while pressed
        property bool pressed: false
        readonly property real displayValue: pressed ? dragValue : value

        property real pressValue: 0
        property real pressSceneX: 0
        property real pressWidth: 1

        signal edited(real value)
        signal committed(real value)

        implicitHeight: 18

        function clamp01(v) {
            return Math.max(0, Math.min(1, v))
        }

        function valueFromX(x) {
            return width <= 0 ? 0 : clamp01(x / width)
        }

        function sceneX(mouse) {
            return slider.mapToItem(null, mouse.x, 0).x
        }

        Rectangle {
            id: sliderTrack
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: Math.max(2, Math.round(4 * Config.scale))
            radius: height / 2
            color: Config.progressTrackColor
        }

        Rectangle {
            anchors.left: sliderTrack.left
            anchors.verticalCenter: sliderTrack.verticalCenter
            height: sliderTrack.height
            radius: sliderTrack.radius
            color: Config.accentColor
            width: sliderTrack.width * slider.displayValue
        }

        Rectangle {
            id: sliderHandle
            width: Math.round(12 * Config.scale)
            height: width
            radius: width / 2
            color: Config.accentColor
            anchors.verticalCenter: parent.verticalCenter
            x: (slider.width - width) * slider.displayValue
        }

        MouseArea {
            anchors.fill: parent
            anchors.topMargin: -6
            anchors.bottomMargin: -6
            onPressed: function(mouse) {
                slider.pressed = true
                slider.dragValue = slider.valueFromX(mouse.x)
                slider.pressValue = slider.dragValue
                slider.pressSceneX = slider.sceneX(mouse)
                slider.pressWidth = Math.max(1, slider.width)
                slider.edited(slider.dragValue)
            }
            onPositionChanged: function(mouse) {
                if (!slider.pressed)
                    return
                var dx = slider.sceneX(mouse) - slider.pressSceneX
                slider.dragValue = slider.clamp01(slider.pressValue
                                                  + dx / slider.pressWidth)
                slider.edited(slider.dragValue)
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
}
