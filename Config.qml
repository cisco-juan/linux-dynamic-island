pragma Singleton

import QtQuick

// Central tuning knobs for the island. All sizes are in logical pixels.
// The window height always equals the pill height plus `topPadding`, which
// pushes the visible pill down from the top screen edge. Layer-shell `margins`
// is writable (`write: "setMargins"`), but QML cannot construct a `QMargins`
// value (`margins { }` fails at runtime; qmllint: "margins was not found"), so
// the internal padding is used instead.
QtObject {
    id: config

    // ---- Geometry -----------------------------------------------------------
    // Transparent gap above the pill. Increase to clear a top panel.
    readonly property int topPadding: 6

    // Idle pill
    readonly property int idleWidth: 180
    readonly property int idleHeight: 32

    // Compact states
    readonly property int mediaCompactWidth: 240
    readonly property int mediaCompactHeight: 32
    readonly property int notificationCompactWidth: 340
    readonly property int notificationCompactHeight: 32

    // Expanded states
    readonly property int mediaExpandedWidth: 420
    readonly property int mediaExpandedHeight: 164
    readonly property int notificationExpandedWidth: 420
    readonly property int notificationExpandedHeight: 116

    // Corner radius of the expanded card. The compact pill always keeps
    // `height / 2` (a full pill); the expanded card uses this small radius so
    // it reads as a square-ish card instead of an oversized pill.
    readonly property int expandedRadius: 14

    // Small inset kept between the pill and the window bounds.
    readonly property int sideInset: 0

    // ---- Timing (ms) --------------------------------------------------------
    readonly property int sizeDuration: 300
    readonly property int fadeDuration: 150
    readonly property int notificationTimeout: 4000
    readonly property int mediaExpandTimeout: 3000
    readonly property int positionPollInterval: 1000

    // ---- Colors -------------------------------------------------------------
    readonly property color pillColor: "#eb0f0f10"     // #0f0f10 @ ~0.92
    readonly property color pillBorderColor: "#26ffffff"
    readonly property color textColor: "#ffffff"
    readonly property color secondaryTextColor: "#b3ffffff"
    readonly property color accentColor: "#ffffff"
    readonly property color progressTrackColor: "#33ffffff"
    readonly property color controlHoverColor: "#22ffffff"

    // ---- Type ---------------------------------------------------------------
    readonly property int titleSize: 14
    readonly property int bodySize: 12
    readonly property int smallSize: 11
}
