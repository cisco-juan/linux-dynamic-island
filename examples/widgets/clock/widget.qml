import QtQuick

// A pure-QML widget example: a live clock. It only reads from the island
// context, so it works with no external dependency. See docs/widgets.md.
Item {
    id: root

    // Required by the widget contract.
    property var island

    readonly property color textColor: island ? island.textColor : "#ffffff"
    readonly property color accentColor: island ? island.accentColor : "#ffffff"
    readonly property real uiScale: island ? island.scale : 1.0

    Text {
        id: timeLabel
        anchors.centerIn: parent
        color: root.textColor
        font.pixelSize: Math.round(34 * root.uiScale)
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: timeLabel.bottom
        anchors.topMargin: Math.round(2 * root.uiScale)
        text: Qt.formatDate(new Date(), "dddd, MMM d")
        color: root.accentColor
        opacity: 0.8
        font.pixelSize: Math.round(11 * root.uiScale)
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: timeLabel.text = Qt.formatTime(new Date(), "HH:mm:ss")
    }
}
