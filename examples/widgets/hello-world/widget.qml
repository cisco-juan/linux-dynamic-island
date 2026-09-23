import QtQuick

// Minimal Dynamic Island widget example.
//
// The island loads this file and assigns its context object to the `island`
// property below. Everything this widget needs — theme colors, the content
// size, and the actions it can trigger — comes from that object. See
// docs/widgets.md for the full contract.
Item {
    id: root

    // Required by the widget contract: the island assigns its context object
    // here right after loading this file.
    property var island

    // The theme can be missing for a frame while the island assigns it, so
    // every read falls back to a safe default.
    readonly property color textColor: island ? island.textColor : "#ffffff"
    readonly property color accentColor: island ? island.accentColor : "#ffffff"
    readonly property real uiScale: island ? island.scale : 1.0

    Rectangle {
        anchors.fill: parent
        radius: Math.round(10 * root.uiScale)
        color: "transparent"
        border.color: root.accentColor
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: "Hello from a widget!"
            color: root.textColor
            font.pixelSize: Math.round(14 * root.uiScale)
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        text: "Click me to raise a card"
        color: root.textColor
        opacity: 0.7
        font.pixelSize: Math.round(10 * root.uiScale)
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (!root.island)
                return
            root.island.showCard("Hello World", "Widget clicked",
                                 "This card was raised by the hello-world widget.",
                                 "dialog-information", 0, 3000)
        }
    }
}
