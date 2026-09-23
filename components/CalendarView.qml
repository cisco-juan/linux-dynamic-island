pragma ComponentBehavior: Bound

import QtQuick
import ".."

// Current-month calendar grid for the expanded card. Locale-aware month and
// weekday names come from Qt.locale(); the week starts on Monday. Today is
// marked with an accent circle. The small month arrows let the user page
// through months and consume their own clicks, so clicking elsewhere on the
// card still toggles collapse.
Item {
    id: view

    // Month currently displayed (defaults to today's month).
    property int viewYear: new Date().getFullYear()
    property int viewMonth: new Date().getMonth() // 0-11

    readonly property string monthHeader: new Date(viewYear, viewMonth, 1)
                                          .toLocaleDateString(Qt.locale(), "MMMM yyyy")
    readonly property real cellWidth: grid.width / 7
    readonly property real cellHeight: 15

    // Builds one cell per grid slot: leading blanks, then the days of the
    // month with a `today` flag for the accent circle.
    function buildModel(year, month) {
        var cells = []
        var firstDow = new Date(year, month, 1).getDay() // 0=Sun .. 6=Sat
        var leading = (firstDow + 6) % 7                 // Monday-first offset
        var daysInMonth = new Date(year, month + 1, 0).getDate()
        var now = new Date()
        var isCurrentMonth = (now.getFullYear() === year && now.getMonth() === month)
        for (var i = 0; i < leading; i++)
            cells.push({ "day": 0, "today": false })
        for (var d = 1; d <= daysInMonth; d++)
            cells.push({ "day": d, "today": isCurrentMonth && d === now.getDate() })
        return cells
    }

    function shiftMonth(step) {
        var m = viewMonth + step
        var y = viewYear
        if (m < 0) {
            m = 11
            y--
        } else if (m > 11) {
            m = 0
            y++
        }
        viewMonth = m
        viewYear = y
    }

    anchors.fill: parent
    anchors.margins: 10

    Text {
        id: header
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        text: view.monthHeader
        color: Config.textColor
        font.pixelSize: Config.smallSize
        font.bold: true
    }

    Text {
        id: prevMonth
        anchors.left: parent.left
        anchors.verticalCenter: header.verticalCenter
        text: "\u2039" // single left angle quote
        color: prevHover.hovered ? Config.textColor : Config.secondaryTextColor
        font.pixelSize: 16
        Behavior on color { ColorAnimation { duration: Config.fadeDuration } }

        HoverHandler {
            id: prevHover
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            onClicked: view.shiftMonth(-1)
        }
    }

    Text {
        id: nextMonth
        anchors.right: parent.right
        anchors.verticalCenter: header.verticalCenter
        text: "\u203a" // single right angle quote
        color: nextHover.hovered ? Config.textColor : Config.secondaryTextColor
        font.pixelSize: 16
        Behavior on color { ColorAnimation { duration: Config.fadeDuration } }

        HoverHandler {
            id: nextHover
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            onClicked: view.shiftMonth(1)
        }
    }

    Row {
        id: weekdays
        anchors.top: header.bottom
        anchors.topMargin: 4
        anchors.left: parent.left
        anchors.right: parent.right

        Repeater {
            model: 7
            delegate: Text {
                required property int index
                width: view.cellWidth
                horizontalAlignment: Text.AlignHCenter
                text: Qt.locale().dayName(index + 1, Locale.ShortFormat)
                color: Config.secondaryTextColor
                font.pixelSize: 9
            }
        }
    }

    Grid {
        id: grid
        anchors.top: weekdays.bottom
        anchors.topMargin: 2
        anchors.left: parent.left
        anchors.right: parent.right
        columns: 7
        columnSpacing: 0
        rowSpacing: 0

        Repeater {
            model: view.buildModel(view.viewYear, view.viewMonth)
            delegate: Item {
                id: dayCell
                required property var modelData
                width: view.cellWidth
                height: view.cellHeight

                Rectangle {
                    anchors.centerIn: parent
                    width: 14
                    height: 14
                    radius: width / 2
                    color: dayCell.modelData.today ? Config.accentColor : "transparent"
                }

                Text {
                    anchors.centerIn: parent
                    text: dayCell.modelData.day > 0 ? dayCell.modelData.day : ""
                    color: dayCell.modelData.today ? "#0f0f10" : Config.textColor
                    font.pixelSize: 9
                }
            }
        }
    }
}
