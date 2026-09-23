# Linux Dynamic Island

An Apple-style **Dynamic Island for KDE Plasma 6 on Wayland**: a standalone,
always-on-top overlay with one compact pill anchored to the top-center of the
screen that morphs in place to show notifications, media playback and a
calendar, then collapses back automatically. It is a layer-shell surface, not a
Plasma applet, so it never steals focus and leaves no taskbar entry.

<div align="center">

[![Built with Gentle-AI](https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/docs/assets/brand/built-with-gentle-ai.png)](https://github.com/Gentleman-Programming/gentle-ai)

</div>

## Requirements

| Requirement | Why |
|-------------|-----|
| KDE Plasma 6 on Wayland (KWin 6.x) | The overlay is a `zwlr_layer_shell_v1` surface; KWin implements it |
| Qt 6 (`qml6`, QtQuick, QtDBus) | Runtime and the small C++ QML plugin — tested with Qt 6.11 |
| `qmake6`, `make`, `g++` | Build the plugin (the first `./run.sh` does it for you) |
| `dbus-monitor` (dbus package) | Notification capture |
| Kirigami QML module (`org.kde.kirigami`) | Themed app icons |
| `spectacle` (optional) | Only for the screenshot recipes below |

`run.sh` and `install.sh` never install system packages.

## Quick path

1. Run it from the project directory:

   ```bash
   ./run.sh
   ```

   `run.sh` builds the C++ QML plugin on first use, then starts the overlay.

2. Trigger a notification to see it expand:

   ```bash
   notify-send -a "Dynamic Island" "Test" "Hello island"
   ```

3. Start it automatically on login (optional):

   ```bash
   ./install.sh              # writes ~/.config/autostart/dynamic-island.desktop
   ./install.sh --uninstall  # removes it
   ```

## What you get

| State | Trigger | Behavior |
|-------|---------|----------|
| Idle | No media, no notification | Compact pill (~180×32) with a pulsing dot |
| Media | An MPRIS player has a track | Compact now-playing pill; expands briefly on playback start |
| Notification | `Notify` on `org.freedesktop.Notifications` | Expands for ~4 s, then collapses |

Interaction: hover expands, click toggles, and events auto-expand then
auto-collapse. Media controls (play/pause, previous, next) are live and wired
straight to the active MPRIS player.

### Pages in the expanded card

While expanded, the card can show several pages; left/right chevrons at the
card edges cycle through them (wrapping around) and a small dot indicator at the
bottom marks the current one. The chevrons only appear when more than one page
is available.

| Page | Shown when |
|------|------------|
| `media` | An MPRIS player is available with a non-empty title |
| `calendar` | Always (current-month grid, today circled) |
| `notification` | A notification is active |

A notification arrival forces the `notification` page and auto-expands;
hover-expanding shows the default page (notification if active, else media if
available, else calendar); after an auto-collapse the card settles back to that
default. Chevron clicks are consumed, so clicking anywhere else on the card
still toggles collapse.

## Details

| Topic | Decision |
|-------|----------|
| Windowing | `zwlr_layer_shell_v1` via `org.kde.layershell`; overlay layer, `AnchorTop`, no focus, exclusion zone 0 |
| Placement | KWin centers the unanchored axis, so the pill stays top-center at any width |
| Vertical offset | Transparent internal padding (`Config.topPadding`). Layer-shell `margins` is writable (`setMargins`), but QML cannot construct a `QMargins` value, so the property is unusable from QML |
| Notifications | `dbus-monitor` subprocess observing `org.freedesktop.Notifications` (passive, never replies) |
| Media | MPRIS over `QDBus`; `PropertiesChanged` subscription + 1 s `Position` poll |
| D-Bus in QML | No QtDBus QML module exists, so D-Bus lives in the C++ plugin (`imports/Island`) |
| Animations | Window `width`/`height` with `OutBack`; content cross-fades at ~150 ms |

## Configuration

All knobs live in `Config.qml` (a QML singleton). The most useful ones:

| Property | Default | Purpose |
|----------|---------|---------|
| `topPadding` | `6` | Transparent gap above the pill; increase to clear a top panel |
| `idleWidth` / `idleHeight` | `180` / `32` | Idle pill size |
| `mediaCompactWidth` / `mediaExpandedHeight` | `240` / `164` | Media pill sizes |
| `notificationCompactWidth` / `notificationExpandedHeight` | `340` / `116` | Notification pill sizes |
| `expandedRadius` | `14` | Corner radius of the expanded card. The compact pill always keeps `height / 2` (a full pill); the expanded card uses this small radius so it reads as a square-ish card. The radius animates together with the size morph |
| `sizeDuration` | `300` | Pill resize animation (ms) |
| `fadeDuration` | `150` | Content cross-fade (ms) |
| `notificationTimeout` | `4000` | How long a notification stays expanded (ms) |
| `mediaExpandTimeout` | `3000` | How long media expands on playback start (ms) |
| `pillColor` | `#eb0f0f10` | Pill fill (`#0f0f10` at ~0.92 alpha) |

## Dev/test hook

Two environment variables force the initial state and are read once at startup
by the app. They have no effect unless set, and exist purely as a development
aid for screenshot verification of the expanded card.

| Variable | Effect |
|----------|--------|
| `ISLAND_DEBUG_EXPAND=1` | Start expanded |
| `ISLAND_DEBUG_PAGE=<media\|calendar\|notification>` | Force the initial page. For `notification`, a placeholder notification is seeded when none exists so the page renders |

```bash
# Capture a specific page (e.g. for visual review)
ISLAND_DEBUG_EXPAND=1 ISLAND_DEBUG_PAGE=calendar ./run.sh &
sleep 2.5
spectacle -b -n -f -o /tmp/opencode/island-calendar.png
kill %1
```

Qt Quick has no built-in environment access, so these values are exposed to QML
by a small read-only `Debug` singleton in the C++ plugin (`imports/Island`).

## Project layout

```
dynamic-island/
├── run.sh                     # build plugin if needed + start the overlay
├── install.sh                 # autostart desktop entry (not run automatically)
├── main.qml                   # layer-shell window + state machine + page navigation
├── Config.qml                 # QML singleton: sizes, timing, colors
├── components/
│   ├── Island.qml             # pill/card container, view cross-fade, hover/click, page nav
│   ├── IdleView.qml
│   ├── MediaView.qml          # art, title/artist, progress, transport controls
│   ├── CalendarView.qml       # locale-aware current-month grid, today circled
│   ├── NotificationView.qml   # app icon, app name, summary, body
│   └── IconButton.qml
└── imports/Island/            # C++ QML plugin, module "Island"
    ├── Island.pro
    ├── island_plugin.cpp/.h         # registers the types + the `Debug` singleton
    ├── mediacontroller.cpp/.h       # MPRIS over QDBus
    ├── notificationmonitor.cpp/.h   # dbus-monitor subprocess + parser
    └── qmldir
```

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `Did not load any objects, exiting.` | `org.kde.layershell` must be imported with an alias: `import org.kde.layershell as LayerShell`. Without it, the module's non-creatable `Window` shadows QtQuick's `Window`. |
| Nothing appears on screen | The overlay needs Wayland. `run.sh` exports `QT_QPA_PLATFORM=wayland`; confirm you are in a Plasma Wayland session. |
| Pill sits under the top panel | Increase `Config.topPadding`. |
| Notifications do not expand | The notification daemon must be running (`plasmashell`). Verify capture manually with `dbus-monitor "interface='org.freedesktop.Notifications'"`. |
| Media view stays idle | Check for a player: `busctl --user list | grep -i mpris`. Only players exposing MPRIS are visible. |
| Plugin fails to load | Rebuild it: `cd imports/Island && qmake6 && make -j$(nproc)`. |

## Verifying

```bash
# Build the plugin
cd imports/Island && qmake6 && make -j$(nproc)

# Lint the QML (warnings are acceptable; errors are not)
/usr/lib/qt6/bin/qmllint main.qml Config.qml components/*.qml

# Smoke test: should stay alive for 6 s (exit 124)
timeout 6 ./run.sh

# Per-page screenshots of the expanded card (dev hook)
ISLAND_DEBUG_EXPAND=1 ISLAND_DEBUG_PAGE=calendar ./run.sh &
sleep 2.5 && spectacle -b -n -f -o /tmp/opencode/island-calendar.png
kill %1

# Shell syntax
bash -n run.sh install.sh
```

## Checklist

- [ ] `./run.sh` shows a compact pill at top-center.
- [ ] `notify-send -a "Dynamic Island" "Test" "Hello island"` expands the pill.
- [ ] Playing media in a browser/player shows title, artist and progress.
- [ ] Play/pause/next/previous buttons control the active player.
- [ ] `./install.sh` writes the autostart entry; `./install.sh --uninstall` removes it.

## Out of scope (v1)

Volume/brightness HUD, click-to-invoke notification actions, notification
stacking/history, a config file, and packaging are intentionally deferred.
