# Dynamic Island D-Bus API

Other applications can drive the island and read its live state over the session
bus. The service is provided by the C++ `IslandApi` object
([`imports/Island/islandapi.cpp`](../imports/Island/islandapi.cpp)) and fulfilled
by the QML bridge in [`main.qml`](../main.qml).

| | |
|---|---|
| Bus | Session bus (`--user`) |
| Bus name | `io.github.cisco_juan.DynamicIsland` |
| Object path | `/Island` |
| Interface | `io.github.cisco_juan.DynamicIsland` |
| Interface version | `1` (`Version` property) |

The service never touches the UI directly. Methods only emit request signals
that the QML bridge fulfils, and the island writes its state back into the
`mode`/`page`/`expanded`/`widget` properties, so `GetStatus()` and the
state-change signals are always truthful.

> **This document must match the running service.** The authoritative list is
> `busctl --user introspect io.github.cisco_juan.DynamicIsland /Island`. If you
> change the interface, update this file in the same change.

## Quick start

```bash
IFACE=io.github.cisco_juan.DynamicIsland

# Show a card and capture the returned id
busctl --user call $IFACE /Island $IFACE ShowCard \
  ssssii "My App" "Build finished" "All tests passed." "dialog-information" 1 4000
# → u 1

# Read the island state
busctl --user call $IFACE /Island $IFACE GetStatus
# → a{sv} 7 "expanded" b true "mode" s "notification" ...

# Expand / collapse
busctl --user call $IFACE /Island $IFACE Expand
busctl --user call $IFACE /Island $IFACE Collapse
```

```bash
# Same call with gdbus
gdbus call --session --dest io.github.cisco_juan.DynamicIsland \
  --object-path /Island --method io.github.cisco_juan.DynamicIsland.ShowCard \
  "My App" "Build finished" "All tests passed." "dialog-information" 1 4000
```

```python
#!/usr/bin/env python3
"""Minimal client using only the standard library (python-dbus / Gio not required)."""
import subprocess

IFACE = "io.github.cisco_juan.DynamicIsland"
BASE = ["busctl", "--user", "call", IFACE, "/Island", IFACE]


def show_card(app, title, body, icon="dialog-information", urgency=1, timeout_ms=4000):
    out = subprocess.check_output(
        BASE + ["ShowCard", "ssssii", app, title, body, icon, str(urgency), str(timeout_ms)],
        text=True,
    )
    return int(out.split()[1])  # "u 1" -> 1


def get_status():
    out = subprocess.check_output(BASE + ["GetStatus"], text=True)
    return out.strip()


if __name__ == "__main__":
    print("card id:", show_card("Python", "Hello", "Sent over D-Bus"))
    print(get_status())
```

A ready-made set of shell scripts lives in
[`examples/dbus/`](../examples/dbus).

## Methods

All arguments and return values use D-Bus types. `ShowCard` returns the card id
**synchronously** (the id is allocated before the request is emitted).

| Method | In | Out | Effect |
|--------|----|-----|--------|
| `ShowCard(appName, title, body, icon, urgency, timeoutMs)` | `ssssii` | `u` | Shows a card through the same path as a notification. `icon` is a themed icon name or an absolute path; `urgency` is accepted for compatibility (the card styling is uniform); `timeoutMs <= 0` uses the island default (~4 s), otherwise it is clamped to 500–60000 ms. Returns the new card id. |
| `DismissCard(id)` | `u` | — | Dismisses the card with that id. |
| `DismissAll()` | — | — | Dismisses the current card. |
| `Expand()` | — | — | Expands the card. |
| `Collapse()` | — | — | Collapses the card. |
| `Toggle()` | — | — | Expands if collapsed, collapses if expanded (based on the reported `expanded` state). |
| `ShowPage(pageId)` | `s` | — | Switches to `pageId` and expands. The id is validated against the pages the island currently offers; an unknown id is ignored. |
| `ListPages()` | — | `as` | The pages the island currently offers (see below). |
| `ShowWidget(widgetId)` | `s` | — | Shows the custom widget `widgetId` on the `widget` page and expands. Unknown ids are ignored by the bridge. |
| `HideWidget()` | — | — | Hides the widget and returns to the default page. |
| `ListWidgets()` | — | `as` | The ids of the discovered custom widgets. |
| `ReloadWidgets()` | — | — | Re-scans the widget directory; emits `widgetsChanged`. |
| `GetStatus()` | — | `a{sv}` | A snapshot of the island state (see below). |

### `ListPages()` values

The pages the island offers change at runtime. As of v1.5:

| Page id | Present when |
|---------|--------------|
| `media` | An MPRIS player is available with a non-empty title |
| `calendar` | Always |
| `agenda` | Always |
| `settings` | At least one settings backend (volume, brightness, bluetooth) is available |
| `customize` | Always |
| `widget` | A widget is currently shown (`ShowWidget`) |
| `notification` | A card is currently active |

### `GetStatus()` keys

| Key | Type | Meaning |
|-----|------|---------|
| `mode` | `s` | `idle` / `media` / `notification` |
| `page` | `s` | Current page id (or `""` before the first render) |
| `expanded` | `b` | Whether the card is expanded |
| `widget` | `s` | Shown widget id (`""` = none) |
| `version` | `u` | Interface version (`1`) |
| `widgets` | `as` | Same as `ListWidgets()` |
| `pages` | `as` | Same as `ListPages()` |

## Properties

Properties are read/write so the island can publish its state; the four live
state properties are written by QML, not by clients. **To change the island,
call the methods above** — writing a state property directly does not emit a
request and therefore does not drive the UI.

| Property | Type | Access | Notes |
|----------|------|--------|-------|
| `Version` | `u` | read | Interface version, `1`. |
| `mode` | `s` | read/write | Live state, written by QML. |
| `page` | `s` | read/write | Live state, written by QML. |
| `expanded` | `b` | read/write | Live state, written by QML. |
| `widget` | `s` | read/write | Live state, written by QML. |
| `widgets` | `as` | read | Discovered widget ids. |
| `widgetList` | `av` | read | Discovered widgets with metadata: `{ "id", "name", "icon", "path" }`. |
| `widgetsRevision` | `i` | read | Increments on every scan; useful to detect a rescan. |

Every property is exported with `emits-change`, so standard
`org.freedesktop.DBus.Properties.PropertiesChanged` signals are emitted when a
value changes.

## Signals

### Public notifications

These are emitted once the island has actually changed.

| Signal | Signature | Emitted when |
|--------|-----------|--------------|
| `CardShown` | `uss` | A card requested through `ShowCard` is displayed. `(id, appName, title)`. Cards raised internally by a widget (`island.showCard`) have no API id and do not emit this signal. |
| `CardDismissed` | `u` | A card is dismissed or expires. |
| `ExpansionChanged` | `b` | The card expands (`true`) or collapses (`false`). |
| `PageChanged` | `s` | The active page changes. |
| `WidgetShown` | `s` | A widget becomes visible. |

### Request signals

These mirror the methods and are consumed by the QML bridge. They are listed
because they appear in the introspection output; clients normally call the
methods instead of listening to them.

| Signal | Signature |
|--------|-----------|
| `cardRequested` | `ussssii` |
| `cardDismissRequested` | `u` |
| `dismissAllRequested` | — |
| `expandRequested` | `b` |
| `pageRequested` | `s` |
| `widgetRequested` | `s` |
| `hideWidgetRequested` | — |

### Property-change signals

Exported because the properties use `NOTIFY`. They carry no arguments and are
the D-Bus side of the property change: `modeChanged`, `pageChanged`,
`expandedChanged`, `widgetChanged`, `widgetsChanged`.

## Watching signals

```bash
# Observe every public notification
dbus-monitor --session "type='signal',interface='io.github.cisco_juan.DynamicIsland',member='CardShown'"
dbus-monitor --session "type='signal',interface='io.github.cisco_juan.DynamicIsland',member='ExpansionChanged'"
```

```bash
# Show a card and watch CardShown arrive
dbus-monitor --session "interface='io.github.cisco_juan.DynamicIsland'" &
busctl --user call io.github.cisco_juan.DynamicIsland /Island \
  io.github.cisco_juan.DynamicIsland ShowCard \
  ssssii "Demo" "Signals" "Look at dbus-monitor." "dialog-information" 0 4000
```

## Graceful degradation

The service is optional and never blocks the UI:

- If the session bus is unavailable, the app logs one warning and runs without
  the service.
- If the bus name is already owned (a second island instance), the app logs one
  warning and runs without the service — it does not crash and does not hang.

The service is created when the island starts, because `main.qml` references the
`IslandApi` singleton.

## Introspection snapshot

```text
$ busctl --user introspect io.github.cisco_juan.DynamicIsland /Island
NAME                                TYPE      SIGNATURE RESULT/VALUE   FLAGS
io.github.cisco_juan.DynamicIsland  interface -         -              -
.Collapse                           method    -         -              -
.DismissAll                         method    -         -              -
.DismissCard                        method    u         -              -
.Expand                             method    -         -              -
.GetStatus                          method    -         a{sv}          -
.HideWidget                         method    -         -              -
.ListPages                          method    -         as             -
.ListWidgets                        method    -         as             -
.ReloadWidgets                      method    -         -              -
.ShowCard                           method    ssssii    u              -
.ShowPage                           method    s         -              -
.ShowWidget                         method    s         -              -
.Toggle                             method    -         -              -
.Version                            property  u         1              emits-change
.expanded                           property  b         false          emits-change writable
.mode                               property  s         "media"        emits-change writable
.page                               property  s         "calendar"     emits-change writable
.widget                             property  s         ""             emits-change writable
.widgetList                         property  av        …              emits-change
.widgets                            property  as        …              emits-change
.widgetsRevision                    property  i         1              emits-change
.CardDismissed                      signal    u         -              -
.CardShown                          signal    uss       -              -
.ExpansionChanged                   signal    b         -              -
.PageChanged                        signal    s         -              -
.WidgetShown                        signal    s         -              -
.cardDismissRequested               signal    u         -              -
.cardRequested                      signal    ussssii   -              -
.dismissAllRequested                signal    -         -              -
.expandRequested                    signal    b         -              -
.expandedChanged                    signal    -         -              -
.hideWidgetRequested                signal    -         -              -
.modeChanged                        signal    -         -              -
.pageChanged                        signal    -         -              -
.pageRequested                      signal    s         -              -
.widgetChanged                      signal    -         -              -
.widgetRequested                    signal    s         -              -
.widgetsChanged                     signal    -         -              -
```

(The listing above is trimmed to the island interface; `busctl` also prints the
standard `org.freedesktop.DBus.Introspectable`, `Peer` and `Properties`
interfaces.)
