# SwiftBorders

Colored window borders for macOS 15+ (built and tested on macOS 26 Tahoe),
written in Swift. SwiftBorders highlights the focused window and outlines the
rest, and is designed around one goal: **keep working across macOS releases**.
It is built exclusively on public, contractual APIs — the Accessibility API
for tracking windows and AppKit overlays for drawing — so OS updates that
change private window-server internals don't break it.

## Design

- **Well-behaved overlays.** Each border is a click-through `NSPanel` with
  `.transient` + `.ignoresCycle` collection behavior, so macOS window tiling,
  Mission Control, and Cmd-Tab ignore borders by construction — they never
  get tiled, listed, or focused like real windows.
- **Idle means idle.** Borders are static `CAShapeLayer`s with implicit
  animations disabled: zero CPU/GPU work while nothing on screen moves.
  During an actual window drag, a short-lived 90 Hz poll keeps the border
  glued to the window, then everything goes quiet again.
- **Native corner rounding.** macOS 26 gives different windows different
  corner radii; SwiftBorders detects each window's style through the
  accessibility hierarchy and matches it (~26 pt for toolbar windows, ~16 pt
  for titlebar-only ones). Override with a fixed `radius=N` if you prefer.
- **Self-healing.** A `CGWindowList` reconciliation pass every 2 seconds
  corrects border visibility, frames, and dead windows — so a missed event
  never leaves a stale border on screen.
- **Correct stacking.** Every border is ordered directly against its own
  window, so unrelated windows layer correctly in between.

The one non-public symbol used is `_AXUIElementGetWindow` (AX element →
window ID), which has been stable for a decade and is relied on by many
well-known window utilities. Everything else is public API.

## Install

```sh
brew tap albibenni/swiftborders
brew install swiftborders
```

On first launch macOS asks for the **Accessibility** permission
(System Settings → Privacy & Security → Accessibility). The process waits and
starts automatically once you grant it. The permission persists across
updates.

## Usage

```sh
swiftborders active_color=0xffe1e3e4 inactive_color=0xff494d64 width=5.0
```

To start it at login and keep it running:

```sh
brew services start swiftborders
```

## Configuration

Options are `key=value` pairs, given as CLI arguments or in
`~/.config/swiftborders/swiftbordersrc` (one per line, `#` comments). The file
is watched and live-reloaded — edit it and running borders update instantly,
no restart needed. CLI arguments override the file.

| Key              | Default      | Meaning                                                     |
| ---------------- | ------------ | ----------------------------------------------------------- |
| `active_color`   | `0xffe1e3e4` | Focused window border, `0xAARRGGBB`                         |
| `inactive_color` | `0xff494d64` | Unfocused window border                                     |
| `width`          | `5.0`        | Border width in points                                      |
| `style`          | `round`      | `round` or `square`                                         |
| `radius`         | `auto`       | Inner corner radius; `auto` matches the OS per window style |
| `order`          | `below`      | Stack border `below` or `above` its window                  |
| `blacklist`      | —            | Comma-separated app names to skip                           |
| `whitelist`      | —            | If set, border only these apps                              |

A few extra keys (`hidpi`, `background_color`, `ax_focus`, `blur_radius`) are
accepted and ignored, so an existing JankyBorders config keeps working as a
drop-in.

## AeroSpace integration

Start SwiftBorders from `~/.config/aerospace/aerospace.toml`:

```toml
after-startup-command = [
    'exec-and-forget swiftborders active_color=0xffe1e3e4 inactive_color=0xff494d64 width=5.0'
]
```

If you already have `after-startup-command` entries, append this one to the
array. Because the config file is live-reloaded, you can also leave the
arguments out of the TOML and tune everything in
`~/.config/swiftborders/swiftbordersrc` without restarting AeroSpace.

For yabai, the equivalent line at the end of `~/.config/yabai/yabairc`:

```sh
swiftborders active_color=0xffe1e3e4 inactive_color=0xff494d64 width=5.0 &
```

Only run one border tool at a time — stop any other one before starting
SwiftBorders.

## Building from source

```sh
swift build -c release    # binary at .build/release/swiftborders
swift test
```

Note: an unsigned local build gets a new ad-hoc code signature on every
rebuild, so macOS may ask you to re-grant the Accessibility permission after
rebuilding. Release builds installed via Homebrew don't have this problem.

## Architecture

- `Sources/SwiftBordersCore` — pure logic, fully unit tested: config parsing
  (`Config`), coordinate conversion, overlay/ring geometry, fullscreen
  detection (`BorderGeometry`).
- `Sources/SwiftBorders` — the AppKit shell:
  - `WindowTracker` — per-app `AXObserver`s (create/destroy/move/resize/focus),
    `NSWorkspace` app & space notifications, a 90 Hz micro-poll that runs only
    while a window is actually being dragged, and the 2 s reconciliation pass.
  - `BorderWindow` — one click-through `NSPanel` per window, stacked directly
    against its target via `NSWindow.order(_:relativeTo:)` so unrelated windows
    layer correctly in between.
  - `BorderManager` — glues tracker events to border windows, applies config
    and live reloads.
