# Linux Dynamic Island

An Apple-style **Dynamic Island for KDE Plasma 6 on Wayland**: a standalone,
always-on-top overlay with one compact pill anchored to the top-center of the
screen that morphs in place to show notifications, media playback, a calendar
and system settings (volume, brightness, bluetooth), then collapses back
automatically. It is a layer-shell surface, not a
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
| `settings` | At least one of its backends is available (see below) — placed after `calendar` |
| `customize` | Always — placed after `settings`, before `notification`. Configures the island itself |
| `notification` | A notification is active |

A notification arrival forces the `notification` page and auto-expands;
hover-expanding shows the default page (notification if active, else media if
available, else calendar); after an auto-collapse the card settles back to that
default. Chevron clicks are consumed, so clicking anywhere else on the card
still toggles collapse.

### Settings page

The `settings` page shows three rows — volume, brightness and bluetooth — with
hand-rolled sliders and a pill toggle that match the dark card. Each row is
hidden when its backend is unavailable, and the page itself is absent from the
rotation when none of them can be reached, so the island degrades quietly on
machines without an audio server, a backlight or a bluetooth adapter. Volume and
brightness are applied to the system the moment a slider is released (the value
label tracks the handle live); the bluetooth toggle powers the adapter on or
off, and its status text reports the connected-device count (`On · 1 connected`,
`On`, or `Off`).

| Row | Icon | Backend |
|-----|------|---------|
| Volume + mute | `audio-volume-high` / `audio-volume-muted` | WirePlumber via `wpctl` (`get-volume`, `set-volume`, `set-mute` on `@DEFAULT_AUDIO_SINK@`) |
| Brightness | `brightness-high` | PowerDevil `org.kde.Solid.PowerManagement.Actions.BrightnessControl` (`brightness`/`brightnessMax`/`brightnessMin`, `setBrightness`) |
| Bluetooth | `bluetooth` | BlueZ on the system bus: `GetManagedObjects` to find the adapter and count connected devices, `Properties.Set` on `org.bluez.Adapter1` `Powered` to toggle |

The three backends poll only while the settings page is visible in an expanded
card (`active` property); brightness also subscribes to `brightnessChanged` so
brightness keys stay in sync, and bluetooth subscribes to the adapter's
`PropertiesChanged`. While a slider or toggle is pressed the card will not
collapse (`Island.interacting`).

### Customize page

The `customize` page configures the island itself. It lays its rows out in two
columns so the card stays compact, and every change is applied **live**: the
island resizes, moves, fades or re-times as you drag. Like the settings page,
the card will not collapse while a control is pressed (`Island.interacting`).

| Row | Control | Range / options | Default |
|-----|---------|-----------------|---------|
| Alignment | Cycle | `Left` / `Center` / `Right` | `Center` |
| Top offset | Slider | 0–40 px | `6` |
| Scale | Slider | 75–150 % | `100 %` |
| Opacity | Slider | 50–100 % | `92 %` |
| Animation | Slider | 0–600 ms (`Off` at 0) | `300 ms` |
| Easing | Cycle | `Back` / `Cubic` / `Quad` | `Back` |
| Screen | Cycle | `Default` → `Active` → each connected screen name | `Default` |
| Reset | Button | Restore every default above | — |

- **Alignment** picks which screen edge the pill is pinned to. `Left` and
  `Right` anchor to that edge with no margin; `Center` leaves the horizontal
  axis unanchored, which KWin centers.
- **Scale** multiplies every size and font size; the window, the card and the
  text grow together.
- **Animation** `0` disables the size morph and the content cross-fades; the
  island still resizes, just instantly.
- **Screen** selects the monitor. `Default` leaves the surface unpinned, so the
  compositor places it exactly as before the customize page existed; `Active`
  asks the compositor to place the surface on the focused screen
  (`wantsToBeOnActiveScreen`); a screen name pins it to that monitor. If the
  chosen monitor is disconnected, the island falls back to the primary one.

## Details

| Topic | Decision |
|-------|----------|
| Windowing | `zwlr_layer_shell_v1` via `org.kde.layershell`; overlay layer, `AnchorTop`, no focus, exclusion zone 0 |
| Placement | The horizontal anchors follow the customize page's alignment (`Top\|Left` / `Top` / `Top\|Right`); KWin centers the unanchored axis, so `Center` keeps the pill top-center at any width |
| Screen | `LayerShell.Window.screen` is bound to `IslandConfig.targetScreen` (`null` for the `default` mode, so the compositor chooses the output); `wantsToBeOnActiveScreen` is set for the `active` mode. Verified on KWin 6.7: a named screen pins the island, and `active` follows the compositor's active output |
| Vertical offset | Transparent internal padding (`Config.topPadding`, from `topOffset`). Layer-shell `margins` is writable (`setMargins`), but QML cannot construct a `QMargins` value, so the property is unusable from QML |
| Settings | The `IslandConfig` C++ singleton persists to `~/.config/dynamic-island/config.ini` via `QSettings` (debounced); `Config.qml` is a read-only projection of it |
| Notifications | `dbus-monitor` subprocess observing `org.freedesktop.Notifications` (passive, never replies) |
| Media | MPRIS over `QDBus`; `PropertiesChanged` subscription + 1 s `Position` poll |
| D-Bus in QML | No QtDBus QML module exists, so D-Bus lives in the C++ plugin (`imports/Island`) |
| Animations | Window `width`/`height` with the configured easing (`OutBack` / `OutCubic` / `OutQuad`) and duration; content cross-fades at up to 150 ms. Both follow the customize page's animation knob (`0` disables them) |

## Configuration

User settings live in a persisted config file, written by the `IslandConfig`
C++ singleton (registered as the `IslandConfig` QML singleton):

```
~/.config/dynamic-island/config.ini
```

The file is created lazily: it appears only after the first change on the
customize page (or a programmatic `IslandConfig` write), is written through
`QSettings` with a ~300 ms debounce so a slider drag produces one write on
release, and is never placed inside the repository. Editing it while the island
is stopped is supported; unknown/missing keys fall back to the defaults below.

| Key | Values | Default |
|-----|--------|---------|
| `alignment` | `left` / `center` / `right` | `center` |
| `topOffset` | 0–40 px | `6` |
| `scale` | 0.75–1.5 | `1.0` |
| `opacity` | 0.5–1.0 | `0.92` |
| `animationDuration` | 0–600 ms (0 = animations off) | `300` |
| `easing` | `back` / `cubic` / `quad` | `back` |
| `screenMode` | `default` / `active` / a screen name (`HDMI-A-1`, `eDP-1`, …) | `default` |

A legacy stored value of `primary` is read back as `default`, so an existing
`config.ini` cannot keep the island pinned to Qt's primary screen.

`Config.qml` is the single place the components read from, but it is now a
read-only projection: every geometry value is derived from `IslandConfig`
(multiplied by `scale`), the vertical offset comes from `topOffset`, the fill
color composes `opacity`, the size morph duration/easing come from
`animationDuration`/`easing`, and the card sizes are the base values below
scaled. The most useful base values:

| Property | Base default | Purpose |
|----------|--------------|---------|
| `topPadding` | `6` (from `topOffset`) | Transparent gap above the pill; increase to clear a top panel |
| `idleWidth` / `idleHeight` | `180` / `32` | Idle pill size (× `scale`) |
| `mediaCompactWidth` / `mediaExpandedHeight` | `240` / `164` | Media pill sizes (× `scale`) |
| `notificationCompactWidth` / `notificationExpandedHeight` | `340` / `116` | Notification pill sizes (× `scale`) |
| `customizeWidth` / `customizeHeight` | `470` / `222` | Customize page card size (× `scale`) |
| `expandedRadius` | `14` | Corner radius of the expanded card. The compact pill always keeps `height / 2` (a full pill); the expanded card uses this small radius so it reads as a square-ish card. The radius animates together with the size morph |
| `sizeDuration` | from `animationDuration` | Pill resize animation (ms) |
| `fadeDuration` | `min(150, animationDuration)` | Content cross-fade (ms); `0` when animations are off |
| `notificationTimeout` | `4000` | How long a notification stays expanded (ms) |
| `mediaExpandTimeout` | `3000` | How long media expands on playback start (ms) |
| `pillColor` | `#0f0f10` × `opacity` | Pill fill; `#eb0f0f10` at the default `0.92` opacity |

## Dev/test hook

Two environment variables force the initial state and are read once at startup
by the app. They have no effect unless set, and exist purely as a development
aid for screenshot verification of the expanded card.

| Variable | Effect |
|----------|--------|
| `ISLAND_DEBUG_EXPAND=1` | Start expanded |
| `ISLAND_DEBUG_PAGE=<media\|calendar\|settings\|customize\|notification>` | Force the initial page. For `notification`, a placeholder notification is seeded when none exists so the page renders |

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
│   ├── SettingsView.qml       # volume/brightness sliders + bluetooth toggle
│   ├── CustomizeView.qml      # alignment/scale/opacity/timing/screen controls
│   ├── NotificationView.qml   # app icon, app name, summary, body
│   └── IconButton.qml
└── imports/Island/            # C++ QML plugin, module "Island"
    ├── Island.pro
    ├── island_plugin.cpp/.h         # registers the types + the `Debug`/`IslandConfig` singletons
    ├── islandconfig.cpp/.h          # persisted settings (QSettings) + target screen resolution
    ├── mediacontroller.cpp/.h       # MPRIS over QDBus
    ├── notificationmonitor.cpp/.h   # dbus-monitor subprocess + parser
    ├── volumecontrol.cpp/.h         # WirePlumber `wpctl` volume/mute
    ├── brightnesscontrol.cpp/.h     # PowerDevil backlight brightness
    ├── bluetoothcontrol.cpp/.h      # BlueZ adapter power + connected devices
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
| Island is on the wrong monitor | Set the `Screen` row on the customize page (or `screenMode` in `~/.config/dynamic-island/config.ini`). `Default` lets the compositor choose (the behavior before the customize page); pick the monitor by name to pin it explicitly. |
| Settings will not reset | Delete `~/.config/dynamic-island/config.ini` (or press `Reset` on the customize page) to return to the defaults. |

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

ISLAND_DEBUG_EXPAND=1 ISLAND_DEBUG_PAGE=settings ./run.sh &
sleep 2.5 && spectacle -b -n -f -o /tmp/opencode/island-settings.png
kill %1

ISLAND_DEBUG_EXPAND=1 ISLAND_DEBUG_PAGE=customize ./run.sh &
sleep 2.5 && spectacle -b -n -f -o /tmp/opencode/island-customize.png
kill %1

# Start from clean defaults (drops the persisted settings)
rm -f ~/.config/dynamic-island/config.ini

# Shell syntax
bash -n run.sh install.sh
```

## Checklist

- [ ] `./run.sh` shows a compact pill at top-center.
- [ ] `notify-send -a "Dynamic Island" "Test" "Hello island"` expands the pill.
- [ ] Playing media in a browser/player shows title, artist and progress.
- [ ] Play/pause/next/previous buttons control the active player.
- [ ] The `customize` page changes alignment, scale, opacity, timing and screen live, and the values survive a restart (`~/.config/dynamic-island/config.ini`).
- [ ] `./install.sh` writes the autostart entry; `./install.sh --uninstall` removes it.

## Out of scope (v1)

Click-to-invoke notification actions, notification stacking/history, and
packaging are intentionally deferred.
