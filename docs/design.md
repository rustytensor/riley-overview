# riley-overview design

## Stack: a Quickshell config, no C++ for now

riley-overview is a Quickshell config (QML plus ES modules), run as its own resident Quickshell instance
(`qs -p <prefix>/share/riley-overview/shell`). The reasons:

- Quickshell already has everything the overview shows: `ScreencopyView` gives live images of Hyprland toplevels
  and of whole outputs (the workspace strip); `PanelWindow` gives one layer-shell surface per screen
  (`WlrLayershell` overlay layer, exclusive keyboard focus while shown); `Quickshell.Hyprland` gives the monitors,
  workspaces and toplevels with their geometry, plus `Hyprland.dispatch()` for focus, move-to-workspace and close;
  `IpcHandler` gives the `toggle` call. Riley's bar is built the same way (`~/git/riley/bar`), so colours and font
  come from `~/.config/riley/bar.json` exactly as the bar's `Theme.qml` reads them.
- A resident instance that only flips visibility keeps the first frame well under the 100 ms target (measured in M2).
- No plugin in Hyprland and no compositor change: the overview is a client like the bar.

What Quickshell does not give, and how it is covered:

- XSD validation (Qt 6 has no XML Schema support). The config is checked with `xmllint --noout --schema` (libxml2,
  installed with the system) run through Quickshell's `Process`, then read by `shell/lib/config.mjs`, which applies
  the same ranges itself so an unchecked value is never used. If xmllint is missing or rejects the file, the
  defaults are used and `notify-send` says why. A small C++ helper is the fallback only if this proves too slow or
  unreliable in M2; none is planned.
- Nothing else is missing for M1 to M3. If M2 finds a gap (for example a toplevel without a usable image), a small
  C++ Qt plugin is allowed and will be described here.

## Code layout

| Path | What |
| --- | --- |
| `shell/shell.qml` | The Quickshell root: IPC target `overview`, show/hide state, one `Overlay` per screen, the test hook. |
| `shell/Overlay.qml` | One layer-shell surface per screen: lays out with `lib/model.mjs`, composes the components, one `MouseArea`, keys. |
| `shell/HyprModel.qml` | Singleton: monitors, workspaces, clients and `animations:enabled` from `hyprctl -j`; focus and workspace switch. |
| `shell/Config.qml`, `shell/Theme.qml` | Singletons: the config (xmllint, then `config.mjs`) and the bar's colours and font. |
| `shell/TestHook.qml` | The state files of `docs/overlay.md`, only with `RILEYOVERVIEW_TEST_DIR` set. |
| `shell/components/*.qml` | `WindowTile`, `Backdrop`, `WorkspaceStrip`, `MinimizedRow`: drawing only, no input. |
| `shell/lib/*.mjs` | Pure logic, no Quickshell imports: `spread.mjs`, `strip.mjs`, `hittest.mjs`, `config.mjs`, `model.mjs`, `wallpaper.mjs`. Tested offscreen. |
| `data/config.xsd` | The config schema; `data/config.example.xml` spells out the defaults. |
| `bin/riley-overview` | `riley-overview [run\|toggle\|show\|hide]`. |
| `tests/run-layout.sh` | M1 gate (Qt Quick Test with `qmltestrunner-qt6`, `QT_QPA_PLATFORM=offscreen`, plus xmllint). |

Installed layout (M4, `RILEYOVERVIEW_PREFIX` in the gates): `$PREFIX/bin/riley-overview`,
`$PREFIX/share/riley-overview/shell/` (the whole `shell/` tree), `$PREFIX/share/riley-overview/config.xsd`,
`$PREFIX/share/riley-overview/config.example.xml`.

The pure modules are ES modules (`.mjs`), imported in QML with `import "lib/spread.mjs" as Spread`; they may import
each other with relative paths. The tests are Qt Quick Test files and nothing else; there is no second test runner.

## The overlay (M2)

The interfaces are in `docs/overlay.md`; this is how the code meets them.

- **Resident, hidden, unmapped.** Quickshell starts with the session and loads the whole scene once. Each screen's
  `PanelWindow` is only made visible on a show, so a hidden overview has no layer surface at all. A show maps the
  surfaces and draws from what is already known; nothing is fetched first.
- **Hyprland data is kept current while hidden.** `HyprModel` runs `hyprctl -j monitors`, `workspaces`, `clients`
  and `getoption animations:enabled` in one `sh` (the replies split on a record-separator line) at start, on every
  Hyprland event (debounced: 150 ms while hidden, 30 ms while shown; our own `openlayer`/`closelayer` events are
  ignored) and on each show. The `hyprctl` shapes go straight into `lib/model.mjs`.
- **Read on each show:** hypr-minimize's `minimized.json` and hyprpaper's config, both small, read synchronously.
  The config and `bar.json` are watched and reloaded when they change.
- **Model to pixels.** `overviewModel` gives one entry per monitor; each `Overlay` takes its own by screen name and
  `layoutMonitor` gives the rects it draws and hit-tests. The model is replaced only when it really changed, so a
  refresh that brings nothing new does not rebuild the tiles.
- **Input.** One `MouseArea` per surface: hover sets the highlighted window; a left click on a window closes the
  overview and then focuses the window (after the surfaces are gone, so the layer's keyboard grab cannot undo the
  focus); a click on a strip workspace focuses that monitor, then that workspace (a new workspace opens on the
  focused monitor), and the overview stays open; a click on nothing closes. Escape closes and leaves the focus.
- **Animations.** `animationMs` is 0 when `animations:enabled` is false, else the config value capped at 200. A
  show sets the tiles' `open` one event-loop turn after mapping (at once with 0); a hide sets it false and unmaps
  after `animationMs`.
- **First frame.** Each surface records the first `frameSwapped` of its window after the show and reads the
  window's `devicePixelRatio` then (not earlier: before the first frame the surface has no output yet). The state
  file is written once every surface has a first frame, the refresh started by the show has landed, and the open
  animation's time has passed.

## Coordinates

Everything in the pure modules is in the monitor's logical pixels, relative to the monitor's top-left corner:
device size divided by the monitor's scale, after its transform. Marc's monitors: HDMI-A-1 2560x1440 with
transform 3 is 1440x2560; DP-1 and DP-3 are 3440x1440; DP-2 2560x1600 at 1.25 is 2048x1280. Window geometry from
Hyprland (`at`, `size`, global logical) is turned into monitor-relative by subtracting the monitor's `x, y`.

## Config

`$XDG_CONFIG_HOME/riley-overview/config.xml`, root `<overview xmlns="urn:riley-overview:config" version="1">`.
Every element optional. A file that does not validate is not used at all.

| Element | Key in `config.mjs` | Default | Range |
| --- | --- | --- | --- |
| `margin` | `margin` | 24 | 0 to 400 |
| `strip-height` | `stripHeight` | 120 | 40 to 400 |
| `strip-spacing` | `stripSpacing` | 16 | 0 to 200 |
| `search-height` | `searchHeight` | 40 | 20 to 200 |
| `section-gap` | `sectionGap` | 16 | 0 to 200 |
| `window-spacing` | `windowSpacing` | 24 | 0 to 200 |
| `max-scale` | `maxScale` | 1.0 | above 0, at most 1 |
| `animation-ms` | `animationMs` | 200 | 0 to 200 (Riley's animations off wins) |
| `launcher` | `launcher` | `fuzzel` | one line, not blank |

`parseConfig(text) -> { ok, config, errors }`: `ok` true gives the file's values with defaults for missing
elements and `errors` empty; `ok` false gives a fresh copy of `DEFAULTS` and at least one error string. Numbers may
have surrounding whitespace (XSD whitespace collapse); the five XML entities are decoded; the launcher is trimmed.
Unknown elements, duplicates, values out of range, a wrong root, namespace or version, or text that is not the
config at all give `ok` false.

## Geometry (`strip.mjs`)

For a monitor of logical size W x H and config `cfg`:

- **Safe area** for the spread: `x = margin`, `y = margin + stripHeight + sectionGap + searchHeight + sectionGap`,
  `w = W - 2*margin`, `h = H - y - margin`. With the defaults: `{24, 216, W-48, H-240}`.
- **Search field**: `{margin, margin + stripHeight + sectionGap, W - 2*margin, searchHeight}` (used from M2).
- **Strip band**: `{margin, margin, W - 2*margin, stripHeight}`.
- **Strip thumbnails** for `count` workspaces (the monitor's ones plus one empty one at the end; the caller passes
  the total): height `stripHeight`, width `stripHeight * W/H`. If `count*w + (count-1)*stripSpacing` is wider
  than the band, `w = (band.w - (count-1)*stripSpacing)/count` and `h = w*H/W`. The row is centred in the band in
  both directions. `stripGeometry(W, H, count, cfg) -> { band, thumbW, thumbH, rects: [{index, x, y, w, h}] }`,
  `index` 0 to count-1, left to right. Mapping an index to a Hyprland workspace id is the overlay's job (M2).

No rounding in the modules; the overlay rounds when it draws.

## Spread layout (`spread.mjs`)

GNOME's natural layout in its row form: windows keep their reading order and stay roughly where they are.

`spreadLayout(windows, area, opts) -> { scale, rows, rects }`, with `windows` `[{id, x, y, w, h}]`
(not modified), `area` the safe area, `opts` `{spacing, maxScale}`. `rects` holds one `{id, x, y, w, h}` per
window in input order; `scale` is the one factor applied to every window; `rows` the number of non-empty rows. No
windows: `{scale: maxScale, rows: 0, rects: []}`.

1. Sort the windows by (centre y, centre x, id).
2. For each r from 1 to n, split the sorted list into at most r rows. `ideal = (sum of widths) / r`. For every row
   but the last, take windows in order while the row is empty, or `rowWidth + w <= ideal`, or
   `|1 - (rowWidth + w)/ideal| < |1 - rowWidth/ideal|`; the last row takes the rest. Drop empty rows.
3. The candidate's scale is `min(maxScale, min over rows of (area.w - (k-1)*spacing) / (sum of widths in the row),
   (area.h - (rows-1)*spacing) / (sum over rows of the tallest height in the row))`, k the row's window count.
4. Keep the candidate with the largest scale; on a tie keep the smaller r (strictly greater replaces).
5. Place: the rows, each `scale * tallest` high, stacked with `spacing` between them, the block centred vertically
   in the area. In each row the windows are ordered by (centre x, centre y, id), `scale*w` by `scale*h`, with
   `spacing` between them, the row centred horizontally, each window centred vertically in its row.

Spacing is in screen pixels and never scaled. Windows are never enlarged (`maxScale <= 1`).

## Hit-testing (`hittest.mjs`)

`hitTest(px, py, windowRects, stripRects) -> {kind: "workspace", index} | {kind: "window", id} | {kind: "none"}`.
A rect holds a point when `x <= px < x+w` and `y <= py < y+h`. The strip is drawn above the windows, so its rects
are tested first; a point in a gap of the strip falls through to the windows. `windowRects` are bottom to top: the
last rect that holds the point wins (it matters while windows animate and overlap). The result's `index` is the
strip rect's `index`.

## Gates

- M1 `tests/run-layout.sh` (this milestone): 274 checks on hand-worked values (`tests/layout/cases.mjs` and the
  comments in each `tst_*.qml`). `--plant` applies `tests/faults/m1-*.patch` to a copy and expects the gate to fail.
- M2 `tests/run-overlay.sh`, M3 `tests/run-interact.sh`: nested Hyprland on DP-2 under `dp2-lock`; see the brief.
