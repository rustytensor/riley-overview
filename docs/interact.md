# Interaction (M3): interfaces and test hooks

What the M3 gate (`tests/run-interact.sh`) drives and checks. The gate was written first; the code implements this.
Coordinates follow `docs/design.md`: the pure modules work in logical pixels; a surface's rects are relative to its
top-left corner; "global" means Hyprland layout coordinates (logical).

## Files and owners

| Path | What | Owner |
| --- | --- | --- |
| `shell/lib/navigate.mjs` | Pure: arrow-key navigation order (below). New. | A |
| `shell/lib/search.mjs` | Pure: the window search and the launcher command line (below). New. | A |
| `shell/lib/drop.mjs` | Pure: drag threshold and drop target (below). New. | A |
| `shell/lib/hittest.mjs` | Add `CLOSE_SIZE`, `closeRect`, `hitTestOverlay` (below); `hitTest` unchanged. | A |
| `shell/Overlay.qml` | Pointer (hover, close button, middle click, drag and drop), keys, search field, drag proxy wiring. | A |
| `shell/shell.qml` | Highlight, query, visible set, drag state, launcher handoff, the new IPC calls and state fields. | A |
| `shell/HyprModel.qml` | `moveToWorkspace(address, id, monitor)`, `closeWindow(address)`, `focusedMonitor`. | A |
| `shell/TestHook.qml`, `shell/Config.qml` | Only if needed for the fields below. | A |
| `docs/design.md` | An M3 section: how the code meets this file. | A |
| `shell/components/WindowTile.qml` | Close button at `closeRect`, highlight look, dragged look, `openAnimationDone`, `steps`. | B |
| `shell/components/WorkspaceStrip.qml` | `dropIndex`: the drop-target highlight. | B |
| `shell/components/SearchField.qml` | The search field. New. | B |
| `shell/components/DragProxy.qml` | The image that follows the pointer during a drag. New. | B |
| `tests/run-interact.sh`, `tests/interact/*`, `tests/overlay/vpointer.c`, `tests/faults/*`, this file | The gate. | gate writer / integrator |

A never edits B's files and B never edits A's; anything that needs both goes through the APIs below. M1 and M2
interfaces (`docs/design.md`, `docs/overlay.md`) are unchanged and their gates must still pass.

## `shell/lib/navigate.mjs` (A)

ES module, no imports needed. `rects` are `[{id, x, y, w, h}]` (the visible tiles of one surface), never modified;
the centre of a rect is `(x + w/2, y + h/2)`; ids compare as plain strings (`a < b`).

- `readingOrder(rects) -> [id]`: the ids sorted by (centre y, centre x, id).
- `navigate(rects, fromId, dir) -> id`, `dir` one of `"left" "right" "up" "down"`:
  1. No rects: `""`.
  2. `fromId` is `""` or not among the rects: `readingOrder(rects)[0]` (the first press only selects; it does not
     move).
  3. Candidates are the other rects whose centre is strictly beyond the from-centre in `dir` (right: centre x
     greater; left: smaller; down: centre y greater; up: smaller). An equal coordinate is not a candidate.
  4. A candidate is *in the beam* when it overlaps the from-rect on the other axis (left/right: `c.y < f.y + f.h`
     and `f.y < c.y + c.h`; up/down: the same with x and w). Touching edges do not overlap.
  5. The winner: in-beam candidates before the others; then the smaller Euclidean distance between centres; then
     the smaller id. No candidate: `fromId` (the highlight stays).

## `shell/lib/search.mjs` (A)

Windows are shaped like the model's: `{address, class, title}`; a missing `class` or `title` counts as `""`.

- `terms(query) -> [string]`: the query lower-cased (`toLowerCase()`), split on runs of white space (`/\s+/`),
  empty pieces dropped.
- `matches(win, query) -> bool`: true when every term is a substring of the lower-cased title or of the lower-cased
  class (each term on its own; one may be in the title and another in the class). No terms: true. Plain substring,
  never a pattern.
- `filterWindows(windows, query) -> [address]`: the matching windows' addresses in input order.
- `launcherArgv(launcher, text) -> [string]`: `launcher` (the config value) trimmed and split on runs of white space
  (no shell, no quoting). If any word contains `{query}`, every `{query}` in every word is replaced by `text` (the
  text is never split) and nothing is appended; otherwise `"--search=" + text` is appended (fuzzel's option for an
  initial search). A blank launcher gives `[]`.

## `shell/lib/drop.mjs` (A)

- `DRAG_THRESHOLD = 8`; `dragStarted(dx, dy) -> bool`: `Math.hypot(dx, dy) >= DRAG_THRESHOLD` (logical px since the
  press).
- `dropTarget(px, py, surfaces, source)`: `px, py` global; `surfaces` `[{monitor, x, y, w, h, workspace, strip}]`
  (`x, y` the monitor's global logical position, `w, h` its logical size, `workspace` its current workspace id,
  `strip` the `layoutMonitor(...).strip` entries `{index, id, x, y, w, h}` relative to the surface); `source`
  `{monitor, workspace}` of the dragged window. Rects hold a point half-open (`x <= p < x + w`). Result:
  1. no surface holds the point: `{kind: "none"}`;
  2. a strip entry of that surface holds the point (surface-relative): `{kind: "workspace", monitor, id, index}`,
     or `{kind: "none"}` when `id` is `source.workspace`;
  3. else, on another monitor than `source.monitor`: `{kind: "monitor", monitor, id: surface.workspace}`;
  4. else `{kind: "none"}`.

## `shell/lib/hittest.mjs` additions (A)

- `CLOSE_SIZE = 24`; `closeRect(r) -> {x: r.x + r.w - 12, y: r.y - 12, w: 24, h: 24}`: the close button, centred on
  the tile's top-right corner.
- `hitTestOverlay(px, py, windowRects, stripRects, highlightedId)`: the strip first (as `hitTest`); then the
  `closeRect` of the window whose id is `highlightedId` (only that one; none when it is `""` or not among the rects):
  `{kind: "close", id}`; then the windows as `hitTest` (last holding rect wins); else `{kind: "none"}`.

## Behaviour (A)

One highlight for the whole overview, `highlighted` (an address or `""`), set by the pointer and by the arrows;
`hovered` in the IPC state stays as an alias of it (the M2 gate reads `hovered`). Every show starts with an empty
query, no highlight and no drag.

- **Pointer motion** (`hitTestOverlay` with the current highlight): over a window it highlights that window; over
  the highlighted window's close button it keeps the highlight; over anything else it clears a highlight the pointer
  set (a highlight set by the keys stays).
- **Close**: a left click on the close button of the highlighted window, or a middle click on any window, closes
  it with `HyprModel.closeWindow(address)`. The overview stays open and re-lays out when Hyprland reports the change.
- **Drag and drop**: a left press on a window and a motion with `dragStarted` true starts a drag (no click is
  delivered then). While dragging, every motion computes `dropTarget` from the global pointer position (the surface's
  position plus the local one: the compositor keeps sending motion to the pressed surface even outside it, with
  local coordinates beyond its size). On release: `workspace` and `monitor` targets call
  `HyprModel.moveToWorkspace(address, id, monitor)`; `none` does nothing. The overview stays open and re-lays out.
  A drop on the empty workspace at the end of a strip must leave the new workspace on that strip's monitor (Hyprland
  opens a new workspace on the focused monitor; seen in the nest).
- **Keys** (on whichever surface has the keyboard): arrows call `navigate` on the visible rects of the surface that
  holds the highlighted window, else of the surface on Hyprland's focused monitor, else the first surface; the
  highlight never crosses surfaces. Return or Enter: a visible highlighted window is focused and the overview closes
  (as a click); else, with a non-empty query and no visible window, the overview closes and
  `launcherArgv(Config.values.launcher, query)` runs detached; else nothing. Escape: clears a non-empty query
  (the overview stays), else closes. Backspace removes the last character of the query. A key whose text is not
  empty, has no character below U+0020 or U+007F, and comes without Ctrl, Alt or Super, appends its text.
- **Search**: `visible` is `filterWindows` over every surface's spread windows. Tiles that do not match are not drawn,
  hit-tested or navigated; the spread is not recomputed for a search. When the query changes to a non-empty one and
  the highlight is not visible, the highlight becomes `readingOrder` of the navigation surface's visible rects, else
  of the first surface (in `Quickshell.screens` order) with a visible window, else `""`. When it is cleared, a still
  valid highlight stays.
- **HyprModel**: `moveToWorkspace` dispatches `hl.dsp.window.move({ workspace = "<id>", follow = false, window =
  "address:<address>" })` (Hyprland 0.57's form of `movetoworkspacesilent`); `closeWindow` dispatches
  `hl.dsp.window.close({ window = "address:<address>" })`; `focusedMonitor` is the name of the monitor with
  `focused` true.

## Components (B): QML APIs A composes

`WindowTile.qml`, in addition to M2's API:
```
property bool dragging           // this window is being dragged: draw the tile dimmed at its spread rect
signal openAnimationDone()       // open went true and the move reached the spread rect (at once when animationMs 0)
readonly property int steps      // progress values strictly between 0 and 1 seen since open last changed
```
The close button is a 24x24 disc of `accent` exactly at `closeRect(spreadRect)` (relative to the tile: x `w - 12`,
y `-12`), drawn above the image, visible while `highlighted && open && settled`; its glyph stays inside the middle
12x12 (the gate samples the disc 9 px from its centre). The highlight stays a frame outside the rect (M2).

`WorkspaceStrip.qml`: `property int dropIndex: -1`: the entry under a drag gets a drop-target highlight (distinct
from the current marker).

`SearchField.qml` (drawing only; A's keys handle input):
```
property var rect                // searchArea(W, H, cfg) of strip.mjs, surface-relative
property string query
property bool noMatch            // query not empty and nothing visible: show "Enter: search in the launcher"
property color accent
property color textColor
property color panelColor
property string fontFamily
```

`DragProxy.qml`: a small live image under the pointer during a drag, on the surface the pointer is over.
```
property var toplevel
property string appClass
property real px                 // pointer, surface-relative logical
property real py
property real w                  // proxy size (A passes the tile size scaled to at most 300 wide)
property real h
```

## IPC additions (`IpcHandler { target: "overview" }`, test only)

`state(): string` gains fields: `{ready, shown, seq, hovered, highlighted, query, visible: [address], overClose,
drag}`. `overClose` is the address whose close button the pointer is on (`""` otherwise); `drag` is `null` or
`{address, target}` with `target` the current `dropTarget` result.

`snapshot(): string`: the state file's object (below) for this moment, with the `state()` fields under `live`.

## State file additions

Top level: `query`, `highlighted`, and
```
"anim": { "startedAt": ms, "doneAt": ms, "frames": n }
```
`startedAt` when the tiles' `open` went true; `doneAt` when the last tile sent `openAnimationDone` (= `startedAt`
with no tiles); `frames` the sum of the tiles' `steps` at `doneAt`. The file is written once `doneAt` is set, in
addition to M2's conditions. Each window entry gains `"visible": bool` (matches the query).

## Seen in the nest while writing the gate (Quickshell 0.2.1, Hyprland 0.57.2)

- A headless output with `transform = 1` on a 2560x1440 mode reports `width 2560, height 1440, transform 1`; its
  layer surface is 1440x2560 and `grim -o` gives a 1440x2560 picture in the rotated orientation.
- While a button is held, the pressed layer surface gets every motion, also over another output, in its own
  coordinates (RO-A got x 4924 for a pointer on RO-C); the release goes to it too; the other surface gets `entered`
  only after the release.
- Relative virtual-pointer motion moves the cursor 1:1 in logical px (`hyprctl cursorpos`).
- The keyboard goes to the surface on the monitor that has the pointer.
- `hl.dsp.window.close` makes a `colour.qml` window's process exit within 0.1 s.
- `hyprctl eval 'hl.config({ animations = { enabled = true } })'` turns the option on (`getoption` shows it).
