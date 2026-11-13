# The overlay (M2): interfaces and test hooks

What the M2 gate (`tests/run-overlay.sh`) drives and checks. The gate was written first; the code implements this.
Coordinates follow `docs/design.md`: the pure modules work in the monitor's logical pixels, relative to its top-left
corner; device pixels are logical times the monitor's scale.

## Files and owners

| Path | What | Owner |
| --- | --- | --- |
| `shell/shell.qml` | Root: `IpcHandler` target `overview`, one `Overlay` per screen (`Variants` over `Quickshell.screens`), shown/hidden state, test hook wiring. | A |
| `shell/Overlay.qml` | One `PanelWindow` per screen (below). Lays out with `lib/model.mjs`, composes B's components, one `MouseArea` for the whole surface, keys. | A |
| `shell/HyprModel.qml` | Monitors, workspaces, clients (`hyprctl -j` through `Process`, refreshed on show and on Hyprland events), the `animations:enabled` option, minimized records; `focusWindow(address)`, `switchWorkspace(monitor, id)`. | A |
| `shell/Config.qml` | Loads `$XDG_CONFIG_HOME/riley-overview/config.xml` (xmllint against the XSD, then `config.mjs`), notifies on a broken file. | A |
| `shell/Theme.qml` | Colours and font from `$XDG_CONFIG_HOME/riley/bar.json` (default `~/.config`), as Riley's `bar/Theme.qml`. | A |
| `shell/TestHook.qml` | Writes the state files below when `RILEYOVERVIEW_TEST_DIR` is set; nothing otherwise. | A |
| `shell/lib/model.mjs` | Pure: the model and the per-monitor layout (below). | A |
| `bin/riley-overview` | Unchanged interface: `run`, `toggle`, `show`, `hide`. | A |
| `docs/design.md` | The M2 sections (stack notes, code layout). | A |
| `shell/components/WindowTile.qml` | One window: live `ScreencopyView`, icon, title under it, hover highlight, close button stub, the open/close animation. | B |
| `shell/components/Backdrop.qml` | The dimmed, blurred wallpaper (or a dimmed solid colour). | B |
| `shell/components/WorkspaceStrip.qml` | The strip of workspace previews, the current one marked, the empty one at the end. | B |
| `shell/components/MinimizedRow.qml` | The row of minimized windows. | B |
| `shell/lib/wallpaper.mjs` | Pure: Riley's wallpaper for a monitor from hyprpaper's config (below). | B |
| `tests/overlay/*`, `tests/run-overlay.sh`, `tests/faults/*`, this file | The gate. | gate writer / integrator |

A never edits B's files and B never edits A's; anything that needs both goes through the component APIs below.

## `shell/lib/model.mjs` (A)

ES module, no Quickshell imports; may import `./spread.mjs`, `./strip.mjs`, `./config.mjs`. Inputs are shaped like
`hyprctl monitors -j`, `workspaces -j`, `clients -j`; inputs are never modified. Hyprland 0.57 gives a special
workspace no `id` at all (a client there has `workspace: {address, type: "special", name}`), so special workspaces
are told by name (`special:` prefix) or a missing or negative id.

- `monitorLogical(m) -> {w, h}`: `m.width x m.height` (device), swapped when `m.transform` is odd, divided by `m.scale`.
- `nextEmptyWorkspace(workspaces) -> int`: 1 + the largest id > 0 (1 when there is none).
- `overviewModel(monitors, workspaces, clients, records) -> [entry]`, one per monitor with `disabled` not true, in
  input order:
  `{monitor, description, x, y, scale, logical: {w, h}, workspace: {id, name},
    windows: [{address, class, title, x, y, w, h}], minimized: [{address, class, title, w, h}],
    strip: [{id, name, current, empty}]}`.
  - `windows`: clients with `mapped` not false and `hidden` not true on `monitor.activeWorkspace.id`, in input
    order, `x, y` = `at` minus the monitor's `x, y`; `w, h` = `size`.
  - `minimized`: clients on the workspace named `special:minimized` (hypr-minimize's hidden workspace). Each goes to
    the monitor named by `records[address].monitor` when that monitor is in the list, else to the monitor whose `id`
    is `client.monitor`. `records` is hypr-minimize's `minimized.json` (`{address: {workspace, monitor}}`), `{}` if
    missing.
  - `strip`: the workspaces with `id > 0` whose `monitor` is this monitor's name, by id, `current` when it is the
    active one, `empty` false; then `{id: nextEmptyWorkspace(workspaces), name: String(id), current: false,
    empty: true}`. Special workspaces (id < 0) never appear.
- `minimizedRow(W, H, windows, cfg) -> {band, rects: [{address, x, y, w, h}]}`: band `{margin, H - margin -
  stripHeight, W - 2*margin, stripHeight}`; each window `stripHeight` high and `stripHeight * w/h` wide,
  `stripSpacing` apart, in input order; a row wider than the band is scaled down as a whole by
  `(band.w - (n-1)*stripSpacing) / (sum of widths)`; the row is centred in the band both ways.
- `layoutMonitor(entry, cfg) -> {area, scale, rows, windows: [{address, x, y, w, h}], strip: [{index, id, name,
  current, empty, x, y, w, h}], minimized: [{address, x, y, w, h}]}`: `area` = `safeArea(W, H, cfg)`, its `h`
  reduced by `stripHeight + sectionGap` when `entry.minimized` is not empty; `windows` = `spreadLayout` of the
  entry's windows (id = address) in that area with `{spacing: windowSpacing, maxScale}`, in the entry's order;
  `strip` = `stripGeometry(W, H, entry.strip.length, cfg)` rects merged with the entry's strip items;
  `minimized` = `minimizedRow`.

## `shell/lib/wallpaper.mjs` (B)

- `parseHyprpaper(text) -> [{monitor, path, fitMode}]`, in file order. Block form (what Riley's `hypr-theme.py`
  writes to `~/.config/hypr/hyprpaper.conf`): `wallpaper { monitor = X  path = P  fit_mode = F }`, one key per
  line; one-line form `wallpaper = X,P`. Lines starting with `#` (after spaces) are comments; keys and values
  trimmed; everything else ignored. `fitMode` is `""` when absent.
- `wallpaperFor(blocks, name, description, home) -> path`: a block whose `monitor` is `name` or `"desc:" +
  description` wins over a block with an empty `monitor`; among equals the last one wins; `""` when none fits. A
  path starting with `~/` gets `home` in front.

The overlay reads `$XDG_CONFIG_HOME/hypr/hyprpaper.conf` (default `~/.config`) on each show.

## Overlay window (A, `shell/Overlay.qml`)

- `PanelWindow` per screen, `WlrLayershell.layer: WlrLayer.Overlay`, `WlrLayershell.namespace: "riley-overview"`,
  `WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive` while shown, anchored to all four edges, exclusion
  mode ignore, so the surface is the monitor's logical size and Qt renders it at the monitor's scale (device px).
- Hidden means unmapped: no `riley-overview` layer surface in `hyprctl layers` while hidden (the gate checks this).
  The QML scene stays loaded (resident), only the windows' `visible` flips.
- Input: one `MouseArea` over the surface, `hoverEnabled`. `onPositionChanged` -> `hoverAt(x, y)`; `onClicked` ->
  `activateAt(x, y, button)`. Both use `hittest.mjs` on the current tile rects (window rects bottom to top) and
  strip rects. A window hit: `HyprModel.focusWindow(address)` then close the overview. A strip hit:
  `HyprModel.switchWorkspace(monitor, id)` (the overview may stay open). Nothing hit: close.
- Keys: Escape closes. (Arrows, Enter, search: M3.)
- Animations: `animationMs` = 0 when Hyprland's `animations:enabled` is false (Riley Settings' animations switch
  writes that option), else `min(config animationMs, 200)`.

## Components (B): QML APIs A composes

All sizes in the surface's logical px; all rects are `{x, y, w, h}` objects relative to the surface.

`WindowTile.qml`
```
property var toplevel            // the Quickshell Toplevel / HyprlandToplevel.wayland for ScreencopyView
property string address
property string appClass         // icon lookup (Quickshell.iconPath(appClass, true), fallback icon)
property string title            // drawn under the tile, elided
property var realRect            // where the window really is (monitor-relative logical)
property var spreadRect          // where it goes in the overview
property int animationMs         // 0 = jump
property bool highlighted        // hover / keyboard highlight (set by the Overlay)
property bool open               // true: animate realRect -> spreadRect; false: back to realRect
signal closeAnimationDone()      // after open went false and the move back finished (at once when animationMs 0)
signal closeRequested(string address)   // close button (stub in M2: emits only)
```
The live image fills `spreadRect` exactly, at full opacity, without tint when not highlighted (the gate samples
its colour at 20/50/80 % of the rect). The highlight is drawn as a frame around the rect, not over it. The icon
and title go below the rect, inside the spacing.

`Backdrop.qml`
```
property string wallpaper        // file path, "" for none
property color fallbackColor     // Theme.base
property real dim: 0.5           // black over the picture at this opacity (fixed: the gate expects 50 %)
property int blurRadius: 48
```
Fills its parent. With a wallpaper: the picture (cover fit), blurred, under black at `dim`. Without: `fallbackColor`
under black at `dim`.

`WorkspaceStrip.qml`
```
property var entries             // layoutMonitor(...).strip
property var screen              // ShellScreen: ScreencopyView of the output for the current workspace
property color accent            // current marker
```
Draws each entry at its rect; the current one gets the accent frame, the empty one a plain "+" placeholder. No input
handling (the Overlay hit-tests the same rects).

`MinimizedRow.qml`
```
property var entries             // layoutMonitor(...).minimized merged with {toplevel, appClass, title}
```

## IPC (`IpcHandler { target: "overview" }`)

| Call | Always | What |
| --- | --- | --- |
| `toggle(): void` | yes | show if hidden, hide if shown |
| `show(): void` / `hide(): void` | yes | |
| `state(): string` | test only | JSON `{ready, shown, seq, hovered}`; `ready` once config, theme and the model have loaded |
| `click(x: real, y: real): string` | test only | `x, y` global logical (Hyprland layout coordinates); finds the screen holding the point and calls that Overlay's `activateAt(x - screen.x, y - screen.y, Qt.LeftButton)`, the MouseArea's own handler; returns JSON of the hit |

"Test only" calls answer `"disabled"` unless `RILEYOVERVIEW_TEST_DIR` is set. `hovered` is the address of the
window under the pointer, `""` for none.

## Environment

| Variable | Default | Use |
| --- | --- | --- |
| `XDG_CONFIG_HOME` | `~/.config` | `riley-overview/config.xml`, `riley/bar.json`, `hypr/hyprpaper.conf` |
| `RILEYOVERVIEW_XSD` | `<shell>/../config.xsd`, else `<shell>/../data/config.xsd` | the schema |
| `RILEYOVERVIEW_NOTIFY` | `notify-send` | called as `CMD SUMMARY BODY` for a broken config (once per load) |
| `RILEYOVERVIEW_MINIMIZED_FILE` | `$XDG_RUNTIME_DIR/riley/minimized.json` | hypr-minimize's records, read on each show |
| `RILEYOVERVIEW_TEST_DIR` | unset | test hooks on; state files go here |

## State file (test hook)

On every show, once every surface has swapped its first frame after the show and the open animation has finished
(at once with animations off), `TestHook` writes `$RILEYOVERVIEW_TEST_DIR/show-<seq>.json` (temp file, then
rename; `seq` counts shows from 1 per instance). Times are `Date.now()` (ms since the epoch).

```
{ "seq": 1, "shown": true,
  "ipcAt": 1794594750123,            // when the IPC call reached the handler (null if shown otherwise)
  "animationMs": 0,
  "configOk": false, "config": { ...config.mjs keys, the values in use... },
  "theme": { "base": "#rrggbb", "accent": "#rrggbb", "font": "..." },
  "surfaces": [ {
      "monitor": "RO-A",
      "logical": { "w": 3440, "h": 1440 },          // the window's width/height
      "dpr": 1.0,                                    // the window's device pixel ratio
      "device": { "w": 3440, "h": 1440 },            // logical * dpr, measured from the window, not the monitor
      "firstFrameAt": 1794594750160,                 // first frameSwapped of this window after the show
      "workspace": { "id": 1, "name": "1" },
      "windows":   [ { "address", "class", "title", "real": {x,y,w,h}, "logical": {x,y,w,h}, "device": {x,y,w,h} } ],
      "minimized": [ { "address", "class", "title", "logical": {x,y,w,h}, "device": {x,y,w,h} } ],
      "strip":     [ { "index", "id", "name", "current", "empty", "logical": {x,y,w,h} } ]
  } ] }
```
`logical` rects are the tiles' final (spread) rects as drawn; `device` = `logical` times `dpr`. The first frame comes
from the window's `frameSwapped` (for example `Connections { target: someItem.Window.window; function
onFrameSwapped() {...} }`).

Seen in the nest while writing the gate (Quickshell 0.2.1, Hyprland 0.57.2): `Screen.devicePixelRatio` read in
`Component.onCompleted` of a `PanelWindow`'s content is 1 even on the 1.25 output, because the surface has no output
yet; read the ratio once the window is exposed (first frame). `hyprctl layers` reports global `x, y` and the logical
size (RO-C: 3440,0 2752x1152). `hl.dsp.cursor.move` sends real pointer motion (hover works) and `wtype -k Escape`
reaches the surface that has exclusive keyboard focus.
