pragma ComponentBehavior: Bound

import QtQuick
import Island 1.0
import ".."

// Agenda page for the expanded card: the events of one selected day, with an
// inline create form.
//
// The day comes from main.qml (`selectedDate`); clicking a day in the calendar
// switches it and shows this page. The list is scrollable; each row shows the
// time (or "All day"), the title and a small delete button. `+ New` opens the
// create form, which asks for a title, a time, and a reminder lead, then saves
// the event into `EventStore`.
//
// While the form is open the page reports `formOpen`, so main.qml can switch
// the layer-shell surface to `keyboardInteractivity: OnDemand` and request
// activation. `interacting` keeps the card from collapsing mid-press.
Item {
    id: view

    property string selectedDate: ""
    // Mirrored from main.qml so the page (and its key handling) knows whether
    // the agenda is the visible page.
    property bool active: false

    // True while the user is pressing a control; forwarded through Island.qml
    // so the card never collapses during the interaction.
    property bool interacting: newButton.pressed || saveButton.pressed
                              || cancelButton.pressed || reminderButton.pressed
                              || titleInput.activeFocus || timeInput.activeFocus
    // The create form owns the keyboard: main.qml watches this to switch the
    // layer-shell keyboard interactivity on and off.
    property bool formOpen: false

    signal dateChanged(string isoDate)

    // Reading `revision` registers the dependency on every mutation: a bare
    // eventsForDate() call would register none, so the list would only refresh
    // after re-entering the page.
    readonly property var events: {
        EventStore.revision
        return EventStore.eventsForDate(selectedDate)
    }
    readonly property string headerText: {
        if (selectedDate === "")
            return ""
        return new Date(selectedDate + "T00:00:00")
            .toLocaleDateString(Qt.locale(), "dddd, MMM d")
    }
    readonly property bool isToday: selectedDate === Qt.formatDate(new Date(), "yyyy-MM-dd")

    // Reminder lead options cycled by the form button.
    readonly property var reminderOptions: [-1, 5, 10, 30, 60]
    property int reminderIndex: 0
    property string draftTime: ""

    function reminderLabel(minutes) {
        return minutes < 0 ? "Off" : minutes + " min"
    }

    function nextFullHour() {
        var now = new Date()
        var hour = now.getHours() + 1
        if (hour > 23)
            hour = 23
        return (hour < 10 ? "0" + hour : "" + hour) + ":00"
    }

    // The default lead comes from the persisted config, mapped to the nearest
    // option so the cycle button starts on the user's preference.
    function defaultReminderIndex() {
        var lead = IslandConfig ? IslandConfig.reminderLeadMinutes : 10
        var best = 0
        var bestDelta = -1
        for (var i = 0; i < reminderOptions.length; i++) {
            var delta = Math.abs(reminderOptions[i] - lead)
            if (reminderOptions[i] >= 0 && (bestDelta < 0 || delta < bestDelta)) {
                bestDelta = delta
                best = i
            }
        }
        return best
    }

    function openForm() {
        reminderIndex = defaultReminderIndex()
        draftTime = nextFullHour()
        titleInput.text = ""
        formOpen = true
        // `formOpen` drives main.qml's layer-shell keyboardInteractivity
        // switch; the title input still has to be told to take focus.
        titleInput.forceActiveFocus()
    }

    function closeForm() {
        // Clear focus explicitly and let main.qml return the surface to
        // keyboardInteractivity: None via `formOpen`.
        titleInput.focus = false
        formOpen = false
    }

    function saveForm() {
        var title = titleInput.text.trim()
        if (title === "")
            return
        EventStore.addEvent(title, selectedDate, draftTime,
                            reminderOptions[reminderIndex])
        closeForm()
    }

    Connections {
        target: EventStore
        function onEventsChanged() {
            // The list binds to `view.events`, which re-evaluates when the
            // store emits; nothing else to do here.
        }
    }

    anchors.fill: parent
    anchors.margins: Config.contentMargin

    // ---- header -------------------------------------------------------------
    Item {
        id: headerRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.round(20 * Config.scale)

        Text {
            id: headerLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - todayButton.width - newButton.width - 16
            elide: Text.ElideRight
            text: view.headerText
            color: Config.textColor
            font.pixelSize: Config.smallSize
            font.bold: true
        }

        // `Today` jumps the selected date back to today (only when needed).
        Item {
            id: todayButton
            anchors.right: newButton.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: todayLabel.implicitWidth + 14
            implicitHeight: Math.round(20 * Config.scale)
            visible: !view.isToday
            readonly property bool pressed: todayMouse.pressed

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: todayButton.pressed ? Config.controlHoverColor
                                            : Config.progressTrackColor
                border.color: Config.pillBorderColor
                border.width: 1
            }

            Text {
                id: todayLabel
                anchors.centerIn: parent
                text: "Today"
                color: Config.textColor
                font.pixelSize: Config.microSize
            }

            MouseArea {
                id: todayMouse
                anchors.fill: parent
                onClicked: view.dateChanged(Qt.formatDate(new Date(), "yyyy-MM-dd"))
            }
        }

        Item {
            id: newButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: newLabel.implicitWidth + 18
            implicitHeight: Math.round(20 * Config.scale)
            visible: !view.formOpen
            readonly property bool pressed: newMouse.pressed

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: newButton.pressed ? Config.controlHoverColor
                                         : Config.progressTrackColor
                border.color: Config.pillBorderColor
                border.width: 1
            }

            Text {
                id: newLabel
                anchors.centerIn: parent
                text: "+ New"
                color: Config.textColor
                font.pixelSize: Config.microSize
            }

            MouseArea {
                id: newMouse
                anchors.fill: parent
                onClicked: view.openForm()
            }
        }
    }

    // ---- event list ---------------------------------------------------------
    ListView {
        id: eventList
        anchors.top: headerRow.bottom
        anchors.topMargin: 6
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: formArea.visible ? formArea.top : parent.bottom
        anchors.bottomMargin: formArea.visible ? 6 : 0
        visible: !view.formOpen
        clip: true
        model: view.events
        spacing: Math.round(3 * Config.scale)

        delegate: Item {
            id: row
            required property var modelData
            width: eventList.width
            height: Math.round(19 * Config.scale)

            Text {
                id: timeLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(46 * Config.scale)
                text: row.modelData.time === "" ? "All day" : row.modelData.time
                color: Config.secondaryTextColor
                font.pixelSize: Config.microSize
                elide: Text.ElideRight
            }

            Text {
                id: titleLabel
                anchors.left: timeLabel.right
                anchors.leftMargin: 6
                anchors.right: deleteButton.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.title
                color: Config.textColor
                font.pixelSize: Config.smallSize
                elide: Text.ElideRight
            }

            Item {
                id: deleteButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(16 * Config.scale)
                height: width
                readonly property bool pressed: deleteMouse.pressed

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: deleteButton.pressed || deleteHover.hovered
                           ? Config.controlHoverColor : "transparent"
                }

                Text {
                    anchors.centerIn: parent
                    text: "\u00d7" // multiplication sign as a delete glyph
                    color: Config.secondaryTextColor
                    font.pixelSize: Math.round(13 * Config.scale)
                }

                HoverHandler {
                    id: deleteHover
                }

                MouseArea {
                    id: deleteMouse
                    anchors.fill: parent
                    onClicked: EventStore.removeEvent(row.modelData.id)
                }
            }
        }

        // Empty state.
        Text {
            anchors.centerIn: parent
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: eventList.count === 0
            text: "No events"
            color: Config.secondaryTextColor
            font.pixelSize: Config.smallSize
        }
    }

    // ---- create form --------------------------------------------------------
    Item {
        id: formArea
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.round(62 * Config.scale)
        visible: view.formOpen

        TextInput {
            id: titleInput
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.round(22 * Config.scale)
            color: Config.textColor
            font.pixelSize: Config.smallSize
            selectionColor: Config.accentColor
            selectedTextColor: Config.pillColor
            clip: true
            verticalAlignment: TextInput.AlignVCenter

            // A subtle underline so the empty field still reads as an input.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: titleInput.activeFocus ? Config.accentColor
                                              : Config.progressTrackColor
            }

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: titleInput.text === ""
                text: "Title"
                color: Config.secondaryTextColor
                font.pixelSize: Config.smallSize
            }

            Keys.onReturnPressed: view.saveForm()
            Keys.onEnterPressed: view.saveForm()
            Keys.onEscapePressed: view.closeForm()
        }

        Row {
            anchors.top: titleInput.bottom
            anchors.topMargin: 6
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 6

            // Time field: "HH:MM", validated on save by EventStore.
            TextInput {
                id: timeInput
                width: Math.round(52 * Config.scale)
                height: Math.round(20 * Config.scale)
                text: view.draftTime
                color: Config.textColor
                font.pixelSize: Config.smallSize
                horizontalAlignment: TextInput.AlignHCenter
                selectionColor: Config.accentColor
                selectedTextColor: Config.pillColor
                onTextEdited: view.draftTime = text
                Keys.onReturnPressed: view.saveForm()
                Keys.onEnterPressed: view.saveForm()
                Keys.onEscapePressed: view.closeForm()

                Rectangle {
                    anchors.fill: parent
                    z: -1
                    radius: Math.round(5 * Config.scale)
                    color: Config.progressTrackColor
                }
            }

            // Reminder cycle: Off / 5 / 10 / 30 / 60 min.
            Item {
                id: reminderButton
                width: reminderLabelText.implicitWidth + 18
                height: Math.round(20 * Config.scale)
                readonly property bool pressed: reminderMouse.pressed

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: reminderButton.pressed ? Config.controlHoverColor
                                                  : Config.progressTrackColor
                    border.color: Config.pillBorderColor
                    border.width: 1
                }

                Text {
                    id: reminderLabelText
                    anchors.centerIn: parent
                    text: "\u23f0 " + view.reminderLabel(
                              view.reminderOptions[view.reminderIndex])
                    color: Config.textColor
                    font.pixelSize: Config.microSize
                }

                MouseArea {
                    id: reminderMouse
                    anchors.fill: parent
                    onClicked: view.reminderIndex =
                        (view.reminderIndex + 1) % view.reminderOptions.length
                }
            }

            Item { width: 1; height: 1 } // spacer

            Item {
                id: saveButton
                width: saveLabel.implicitWidth + 18
                height: Math.round(20 * Config.scale)
                readonly property bool pressed: saveMouse.pressed

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Config.accentColor
                }

                Text {
                    id: saveLabel
                    anchors.centerIn: parent
                    text: "Save"
                    color: Config.pillColor
                    font.pixelSize: Config.microSize
                }

                MouseArea {
                    id: saveMouse
                    anchors.fill: parent
                    onClicked: view.saveForm()
                }
            }

            Item {
                id: cancelButton
                width: cancelLabel.implicitWidth + 14
                height: Math.round(20 * Config.scale)
                readonly property bool pressed: cancelMouse.pressed

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: cancelButton.pressed ? Config.controlHoverColor
                                                : Config.progressTrackColor
                    border.color: Config.pillBorderColor
                    border.width: 1
                }

                Text {
                    id: cancelLabel
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: Config.textColor
                    font.pixelSize: Config.microSize
                }

                MouseArea {
                    id: cancelMouse
                    anchors.fill: parent
                    onClicked: view.closeForm()
                }
            }
        }
    }
}
