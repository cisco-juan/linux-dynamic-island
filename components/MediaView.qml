pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import ".."

// Media playback view. Shows a compact now-playing row when collapsed and a
// full card (art, title/artist, progress, transport controls) when expanded.
Item {
    id: view

    property var media
    property bool expanded: false

    readonly property real progress: (media && media.duration > 0)
                                     ? Math.max(0, Math.min(1, media.position / media.duration))
                                     : 0

    function artSource(url) {
        if (!url)
            return ""
        if (url.indexOf("/") === 0)
            return "file://" + url
        return url
    }

    function formatTime(ms) {
        if (!ms || ms < 0)
            return "0:00"
        var total = Math.floor(ms / 1000)
        var minutes = Math.floor(total / 60)
        var seconds = total % 60
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
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
            id: compactArt
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22
            sourceSize.width: 44
            sourceSize.height: 44
            source: view.artSource(view.media ? view.media.albumArt : "")
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: status === Image.Ready
        }

        Rectangle {
            anchors.fill: compactArt
            radius: 5
            color: "#1a1a1c"
            visible: compactArt.status !== Image.Ready

            Kirigami.Icon {
                anchors.centerIn: parent
                width: 14
                height: 14
                source: "audio-x-generic"
                color: Config.secondaryTextColor
            }
        }

        Text {
            anchors.left: compactArt.right
            anchors.leftMargin: 8
            anchors.right: compactIndicator.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: view.media ? view.media.title : ""
            color: Config.textColor
            font.pixelSize: Config.smallSize
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Item {
            id: compactIndicator
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14

            Repeater {
                model: 3
                Rectangle {
                    id: bar
                    required property int index
                    x: index * 5
                    width: 3
                    radius: 1.5
                    color: Config.textColor
                    height: view.media && view.media.playing ? 5 : 12
                    y: (compactIndicator.height - height) / 2

                    SequentialAnimation on height {
                        running: view.media ? view.media.playing : false
                        loops: Animation.Infinite
                        NumberAnimation { to: 13; duration: 320 + bar.index * 130; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 4; duration: 320 + bar.index * 130; easing.type: Easing.InOutSine }
                    }
                }
            }
        }
    }

    // --------------------------------------------------------------- expanded
    Item {
        anchors.fill: parent
        anchors.margins: 16
        opacity: view.expanded ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Config.fadeDuration } }

        Image {
            id: art
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 96
            height: 96
            sourceSize.width: 192
            sourceSize.height: 192
            source: view.artSource(view.media ? view.media.albumArt : "")
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: status === Image.Ready
        }

        Rectangle {
            anchors.fill: art
            radius: 12
            color: "#1a1a1c"
            visible: art.status !== Image.Ready

            Kirigami.Icon {
                anchors.centerIn: parent
                width: 40
                height: 40
                source: "audio-x-generic"
                color: Config.secondaryTextColor
            }
        }

        Column {
            anchors.left: art.right
            anchors.leftMargin: 16
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7

            Text {
                width: parent.width
                text: view.media ? view.media.title : ""
                color: Config.textColor
                font.pixelSize: Config.titleSize
                font.bold: true
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                width: parent.width
                text: view.media ? view.media.artist : ""
                color: Config.secondaryTextColor
                font.pixelSize: Config.bodySize
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Item {
                width: parent.width
                height: 14

                Rectangle {
                    id: track
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 3
                    radius: 1.5
                    color: Config.progressTrackColor
                }

                Rectangle {
                    anchors.left: track.left
                    anchors.verticalCenter: track.verticalCenter
                    width: track.width * view.progress
                    height: 3
                    radius: 1.5
                    color: Config.accentColor
                }

                Text {
                    anchors.left: parent.left
                    anchors.top: track.bottom
                    anchors.topMargin: 1
                    text: view.formatTime(view.media ? view.media.position : 0)
                    color: Config.secondaryTextColor
                    font.pixelSize: 9
                }

                Text {
                    anchors.right: parent.right
                    anchors.top: track.bottom
                    anchors.topMargin: 1
                    text: view.formatTime(view.media ? view.media.duration : 0)
                    color: Config.secondaryTextColor
                    font.pixelSize: 9
                }
            }

            Row {
                spacing: 4

                IconButton {
                    icon: "media-skip-backward"
                    enabled: view.media ? view.media.canGoPrevious : false
                    onClicked: view.media.previous()
                }

                IconButton {
                    icon: (view.media && view.media.playing) ? "media-playback-pause" : "media-playback-start"
                    iconSize: 22
                    enabled: view.media ? view.media.available : false
                    onClicked: view.media.playPause()
                }

                IconButton {
                    icon: "media-skip-forward"
                    enabled: view.media ? view.media.canGoNext : false
                    onClicked: view.media.next()
                }
            }
        }
    }
}
