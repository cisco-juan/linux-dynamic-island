# Writing custom widgets

The island can render your own QML on a dedicated `widget` page. Widgets are
plain `.qml` files discovered at startup and re-scanned on demand, so no build
step and no plugin is involved.

> **Security:** a widget is arbitrary QML executed with the island's full
> privileges (filesystem, network, other D-Bus services). **Install only
> widgets you trust.** There is no sandbox.

## Directory layout

Widgets live under the user data directory:

```text
~/.local/share/dynamic-island/widgets/
├── hello-world/
│   ├── widget.qml          # required entry point
│   └── metadata.json       # optional
└── clock/
    ├── widget.qml
    └── metadata.json
```

- The **directory name is the widget id** (`hello-world`, `clock`).
- `widget.qml` is required. A directory without it is skipped with a warning.
- `metadata.json` is optional. An invalid JSON file is ignored with a warning
  and the defaults are used.

The base directory follows `QStandardPaths::GenericDataLocation`, i.e. it
respects `XDG_DATA_HOME` (default `~/.local/share`). This is the same location
the island uses for custom widgets; nothing is installed system-wide.

### `metadata.json`

```json
{
  "name": "Hello World",
  "icon": "dialog-information"
}
```

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `name` | string | the widget id | Human-readable name (used by listing tools). |
| `icon` | string | `""` | A themed icon name, for listing tools. |

## The `island` context object

After loading `widget.qml`, the island assigns a context object to the root
item's **`island` property**. Declare it on your root item:

```qml
Item {
    property var island
    // ...
}
```

The property is assigned after the file loads, so it may be `undefined` for the
first frame — always guard reads (see the example below). It is the **only**
supported way for a widget to talk back to the island; do not reach into other
objects.

### Actions

| Member | Signature | Effect |
|--------|-----------|--------|
| `island.showCard(appName, title, body, icon, urgency, timeoutMs)` | function | Shows an island card through the same path notifications use. `icon` is a themed icon name or an absolute path; `urgency` is accepted for compatibility; `timeoutMs <= 0` uses the island default (~4 s), otherwise clamped to 500–60000 ms. |
| `island.dismiss()` | function | Hides this widget and returns the island to its default page. It does **not** dismiss a card raised by `showCard`; that card follows its own timeout. |
| `island.expand()` | function | Expands the card. |
| `island.collapse()` | function | Collapses the card. |

### Values

| Member | Type | Meaning |
|--------|------|---------|
| `island.widgetId` | string | The id of the running widget (its directory name). |
| `island.cardWidth` | int | Content width in logical pixels (card width minus the page margins). |
| `island.cardHeight` | int | Content height in logical pixels. |
| `island.scale` | real | The island's current scale factor (`0.75`–`1.5`); multiply your own pixel sizes by it. |
| `island.pillColor` | color | Card fill color (composited from the configured opacity). |
| `island.textColor` | color | Primary text color. |
| `island.accentColor` | color | Accent color (matches the island's accent). |

## Sizing and scale

The island loads your widget into a `Loader` that fills the card minus the page
margins. The loaded item is resized to that area, so:

- Root your widget in an `Item` and lay out with `anchors` (or read
  `width`/`height`). Do not hard-code the card size.
- The available content area is reported as `island.cardWidth` ×
  `island.cardHeight` (at the default scale: `388 × 188` logical pixels for the
  `widget` page).
- The card sizes come from `Config.qml` (`widgetWidth`/`widgetHeight`, base
  `420 × 220`), multiplied by the user's `scale`. Text and pixel sizes should be
  multiplied by `island.scale` so the widget grows with the island.
- The island may be animating its size when your widget loads, so never assume
  a fixed size at load time; use anchors and reflow.

## A complete minimal example

`~/.local/share/dynamic-island/widgets/hello-world/widget.qml`:

```qml
import QtQuick

Item {
    id: root

    // Required: the island assigns its context object here after loading.
    property var island

    // Guard reads: `island` is undefined for the first frame.
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

    MouseArea {
        anchors.fill: parent
        onClicked: if (root.island)
            root.island.showCard("Hello World", "Widget clicked",
                                 "This card was raised by the hello-world widget.",
                                 "dialog-information", 0, 3000)
    }
}
```

`metadata.json` next to it:

```json
{ "name": "Hello World", "icon": "dialog-information" }
```

Two runnable examples are committed in
[`examples/widgets/`](../examples/widgets): `hello-world` (shows a card on click)
and `clock` (a pure-QML clock).

## Loading, reloading and hiding

Widgets are **only** shown on request; they are never started automatically:

```bash
IFACE=io.github.cisco_juan.DynamicIsland

# List discovered widgets
busctl --user call $IFACE /Island $IFACE ListWidgets

# Show one (expands the card on the widget page)
busctl --user call $IFACE /Island $IFACE ShowWidget s hello-world

# Hide it
busctl --user call $IFACE /Island $IFACE HideWidget

# Re-scan after adding or editing a widget
busctl --user call $IFACE /Island $IFACE ReloadWidgets
```

`ReloadWidgets()` re-scans the directory and reloads the widget currently on
screen. Copy a widget directory into place, call `ReloadWidgets()`, then
`ShowWidget`.

## Interaction and collapse

The widget page keeps the island's existing hover/collapse behavior: hovering
the card keeps it expanded, moving the pointer away collapses it, and the
island never collapses mid-interaction with the settings/customize/agenda
controls. Your widget's own controls receive clicks normally (the page's
background click still toggles the card, but your controls sit above it), so you
can add buttons, sliders, and inputs without special handling.
