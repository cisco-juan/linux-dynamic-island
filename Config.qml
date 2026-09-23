pragma Singleton

import QtQuick
import Island 1.0

// Central tuning knobs for the island. All sizes are in logical pixels.
//
// Every value here is a read-only projection of `IslandConfig`, the persisted
// C++ singleton that backs the customize page: `IslandConfig` owns the state
// (alignment, scale, opacity, timing, target screen) and Config.qml derives the
// concrete pixel sizes the components consume. Components keep reading a single
// `Config` object, and live edits on the customize page flow through here
// automatically.
//
// The window height always equals the pill height plus `topPadding`, which
// pushes the visible pill down from the top screen edge. Layer-shell `margins`
// is writable (`write: "setMargins"`), but QML cannot construct a `QMargins`
// value (`margins { }` fails at runtime; qmllint: "margins was not found"), so
// the internal padding is used instead.
QtObject {
    id: config

    // ---- User knobs ---------------------------------------------------------
    // Mirrored from IslandConfig so components can read one object.
    readonly property real scale: IslandConfig.scale

    // ---- Geometry -----------------------------------------------------------
    // Transparent gap above the pill; from the customize page's top-offset knob.
    readonly property int topPadding: IslandConfig.topOffset

    // Idle pill
    readonly property int idleWidth: Math.round(180 * scale)
    readonly property int idleHeight: Math.round(32 * scale)

    // Compact states
    readonly property int mediaCompactWidth: Math.round(240 * scale)
    readonly property int mediaCompactHeight: Math.round(32 * scale)
    readonly property int notificationCompactWidth: Math.round(340 * scale)
    readonly property int notificationCompactHeight: Math.round(32 * scale)

    // Expanded states
    readonly property int mediaExpandedWidth: Math.round(420 * scale)
    readonly property int mediaExpandedHeight: Math.round(164 * scale)
    readonly property int notificationExpandedWidth: Math.round(420 * scale)
    readonly property int notificationExpandedHeight: Math.round(116 * scale)

    // Customize page card. Wider and taller than the other pages because it
    // lays its rows out in two columns.
    readonly property int customizeWidth: Math.round(470 * scale)
    readonly property int customizeHeight: Math.round(222 * scale)

    // Agenda page card: a day header, a scrollable event list and the inline
    // create form.
    readonly property int agendaWidth: Math.round(420 * scale)
    readonly property int agendaHeight: Math.round(220 * scale)

    // Custom-widget page card. A third-party widget is rendered inside it; the
    // content area is this size minus two `contentMargin` insets (reported to
    // the widget as `cardWidth` / `cardHeight`).
    readonly property int widgetWidth: Math.round(420 * scale)
    readonly property int widgetHeight: Math.round(220 * scale)

    // Corner radius of the expanded card. The compact pill always keeps
    // `height / 2` (a full pill); the expanded card uses this small radius so
    // it reads as a square-ish card instead of an oversized pill.
    readonly property int expandedRadius: Math.round(14 * scale)

    // Small inset kept between the pill and the window bounds.
    readonly property int sideInset: 0

    // ---- Timing (ms) --------------------------------------------------------
    readonly property int sizeDuration: IslandConfig.animationDuration
    // Fades never outlast the size animation, so turning animations off
    // (`animationDuration` 0) turns the cross-fades off too.
    readonly property int fadeDuration: Math.min(150, IslandConfig.animationDuration)
    readonly property int notificationTimeout: 4000
    readonly property int mediaExpandTimeout: 3000
    readonly property int positionPollInterval: 1000

    // Easing curve of the size morph, selected on the customize page.
    readonly property int sizeEasing: {
        switch (IslandConfig.easing) {
        case "cubic":
            return Easing.OutCubic
        case "quad":
            return Easing.OutQuad
        default:
            return Easing.OutBack
        }
    }

    // ---- Scaled geometry helpers -------------------------------------------
    // Shared sizes so the internal layout scales with the island instead of
    // drifting from the font sizes below at extreme scale factors.
    readonly property int iconSize: Math.round(18 * scale)
    readonly property int glyphSize: Math.round(16 * scale)
    readonly property int contentMargin: Math.round(16 * scale)
    readonly property int rowHeight: Math.round(38 * scale)
    readonly property int sliderHeight: Math.round(18 * scale)
    readonly property int compactArtSize: Math.round(22 * scale)
    readonly property int expandedArtSize: Math.round(96 * scale)
    readonly property int notificationIconSize: Math.round(20 * scale)
    readonly property int notificationLargeIconSize: Math.round(30 * scale)
    readonly property int navButtonWidth: Math.round(22 * scale)
    readonly property int navButtonHeight: Math.round(40 * scale)
    readonly property int navIconSize: Math.round(16 * scale)

    // ---- Colors -------------------------------------------------------------
    // Pill fill is composited from the configured opacity so the customize
    // page's opacity slider takes effect live. RGB is #0f0f10.
    readonly property color pillColor: Qt.rgba(15 / 255, 15 / 255, 16 / 255,
                                               IslandConfig.opacity)
    readonly property color pillBorderColor: "#26ffffff"
    readonly property color textColor: "#ffffff"
    readonly property color secondaryTextColor: "#b3ffffff"
    readonly property color accentColor: "#ffffff"
    readonly property color progressTrackColor: "#33ffffff"
    readonly property color controlHoverColor: "#22ffffff"

    // ---- Type ---------------------------------------------------------------
    readonly property int titleSize: Math.round(14 * scale)
    readonly property int bodySize: Math.round(12 * scale)
    readonly property int smallSize: Math.round(11 * scale)
    readonly property int microSize: Math.round(9 * scale)
}
