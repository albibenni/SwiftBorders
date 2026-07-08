# SwiftBorders

Window borders for macOS 15+ (built and tested on macOS 26 Tahoe), written in
Swift. A reliability-focused reimplementation of
[JankyBorders](https://github.com/FelixKratz/JankyBorders): same idea, same
config style, but built on **public APIs only** so it doesn't break when Apple
changes the private SkyLight framework.

## Why it's more reliable than JankyBorders

| JankyBorders failure mode | SwiftBorders design |
|---|---|
| Private SkyLight APIs change between macOS releases | Accessibility API + AppKit overlays — public, contractual APIs |
| Sequoia window tiling tries to tile the border windows ([#115](https://github.com/FelixKratz/JankyBorders/issues/115)) | Borders are `NSPanel`s with `.transient` + `.ignoresCycle` collection behavior — tiling, Mission Control and Cmd-Tab ignore them by construction |
| High GPU usage on Tahoe ([#188](https://github.com/FelixKratz/JankyBorders/issues/188)) | Static `CAShapeLayer` with implicit animations disabled; zero redraw while nothing moves |
| Wrong corner radii on Tahoe's new Liquid Glass windows | Per-window radius: toolbar windows get ~26 pt, titlebar-only windows ~16 pt (Tahoe's own values), detected via the accessibility hierarchy |
| Missed events leave stale borders | Self-healing loop: a `CGWindowList` reconciliation pass every 2 s corrects visibility, frames, and dead windows regardless of which event was missed |

The one non-public symbol used is `_AXUIElementGetWindow` (AX element → window
ID), which has been stable for a decade and is what Rectangle, AltTab, Loop,
etc. use. Everything else is public API.

## Build & run

```sh
swift build -c release
.build/release/swiftborders active_color=0xffe1e3e4 inactive_color=0xff494d64 width=5.0
```

On first launch macOS asks for the **Accessibility** permission
(System Settings → Privacy & Security → Accessibility); the process waits and
starts automatically once granted. Note: rebuilding the binary changes its
ad-hoc code signature, so after a rebuild you may need to remove and re-add it
in the Accessibility list.

## Configuration

Options are `key=value` pairs, given as CLI arguments or in
`~/.config/swiftborders/swiftbordersrc` (one per line, `#` comments). The file
is watched and live-reloaded — no restart or IPC needed. CLI arguments override
the file.

| Key | Default | Meaning |
|---|---|---|
| `active_color` | `0xffe1e3e4` | Focused window border, `0xAARRGGBB` |
| `inactive_color` | `0xff494d64` | Unfocused window border |
| `width` | `5.0` | Border width in points |
| `style` | `round` | `round` or `square` |
| `radius` | `auto` | Inner corner radius; `auto` matches the OS per window style |
| `order` | `below` | Stack border `below` or `above` its window |
| `blacklist` | — | Comma-separated app names to skip |
| `whitelist` | — | If set, border only these apps |

`hidpi`, `background_color`, `ax_focus` and `blur_radius` are accepted (and
ignored) for drop-in compatibility with a JankyBorders `bordersrc`.

### Start at login

```sh
cp .build/release/swiftborders /usr/local/bin/
cat > ~/Library/LaunchAgents/com.swiftborders.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.swiftborders</string>
  <key>ProgramArguments</key><array><string>/usr/local/bin/swiftborders</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict></plist>
EOF
launchctl load ~/Library/LaunchAgents/com.swiftborders.plist
```

With yabai or AeroSpace, instead just launch it from their config like
JankyBorders (`swiftborders &`).

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

Run tests with `swift test`.
