// SPDX-License-Identifier: GPL-3.0-or-later
//
// riley-overview: the Quickshell config. Resident and hidden; `riley-overview toggle` (IPC target "overview") shows
// one overview surface per screen (Overlay.qml). docs/overlay.md and docs/interact.md have the interfaces,
// docs/design.md the reasons.
//
// The shell holds what all surfaces share: the highlight (one for the whole overview, set by the pointer and the
// arrows), the search query and the windows it leaves visible, the drag in progress and the open animation's
// bookkeeping for the test hook.
import QtQuick
import Quickshell
import Quickshell.Io
import "lib/model.mjs" as Model
import "lib/wallpaper.mjs" as Wallpaper
import "lib/navigate.mjs" as Nav
import "lib/search.mjs" as Search
import "lib/drop.mjs" as Drop

ShellRoot {
    id: root

    property bool shown: false
    property bool closing: false             // the close animation runs; the surfaces are still mapped
    readonly property bool mapped: shown || closing
    property bool tilesOpen: false           // WindowTile.open: false at the real rects, true at the spread rects
    property int seq: 0                      // shows since start
    property var ipcAt: null
    property string highlighted: ""          // an address or ""
    readonly property string hovered: highlighted   // the M2 name, kept for its gate
    property var hoverSource: null           // the surface whose pointer set the highlight; null: the keys did
    property string overClose: ""            // the window whose close button the pointer is on
    property var overCloseSource: null
    property string query: ""
    property var drag: null                  // { address, monitor, workspace, target, gx, gy, over, w, h } or null
    property var anim: ({ startedAt: null, doneAt: null, frames: 0 })
    property string pendingFocus: ""
    // The window that had the focus when the overview opened: given back when it closes without focusing another
    // (Hyprland leaves nothing focused when an exclusive-keyboard layer goes away; seen in the nest).
    property string previousFocus: ""
    property var pendingLaunch: null         // argv to run once the surfaces are gone

    property var records: ({})               // hypr-minimize's minimized.json
    property var wallBlocks: []              // hyprpaper.conf, parsed
    property var model: []                   // Model.overviewModel(...)

    // The search: every surface's spread windows that match the query.
    readonly property var visibleList: {
        const all = [];
        for (const e of model) for (const w of e.windows) all.push(w);
        return Search.filterWindows(all, query);
    }
    readonly property var visibleSet: {
        const o = {};
        for (const a of visibleList) o[a] = true;
        return o;
    }

    readonly property int animationMs: HyprModel.animationsEnabled ? Math.max(0, Math.min(Config.values.animationMs, 200)) : 0
    readonly property bool ready: Config.loaded && Theme.loaded && HyprModel.loaded

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
    readonly property string minimizedFile: Quickshell.env("RILEYOVERVIEW_MINIMIZED_FILE")
        || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/riley/minimized.json")

    // the test hook's bookkeeping for the current show
    property bool hookPending: false
    property int showGeneration: 0

    function entryFor(name) {
        for (const e of model) if (e.monitor === name) return e;
        return null;
    }

    function wallpaperFor(entry): string {
        return Wallpaper.wallpaperFor(wallBlocks, entry.monitor, entry.description, home);
    }

    function rebuild(): void {
        const next = Model.overviewModel(HyprModel.monitors, HyprModel.workspaces, HyprModel.clients, records);
        if (JSON.stringify(next) !== JSON.stringify(model)) model = next;
        // a highlight, close button or drag of a window that is gone goes with it
        if (highlighted !== "" && !hasWindow(highlighted)) { highlighted = ""; hoverSource = null; }
        if (overClose !== "" && !hasWindow(overClose)) { overClose = ""; overCloseSource = null; }
        if (drag && !hasWindow(drag.address)) drag = null;
    }

    function hasWindow(address): bool {
        for (const e of model) for (const w of e.windows) if (w.address === address) return true;
        return false;
    }

    function isVisible(address): bool {
        return visibleSet[address] === true;
    }

    function surfaceFor(name) {
        const surfaces = overlays.instances;
        for (let i = 0; i < surfaces.length; i++) if (surfaces[i].monitorName === name) return surfaces[i];
        return null;
    }

    function surfaceHolding(address) {
        const surfaces = overlays.instances;
        for (let i = 0; i < surfaces.length; i++) if (surfaces[i].holds(address)) return surfaces[i];
        return null;
    }

    // The surface the arrows work on: the one holding the highlighted window, else Hyprland's focused monitor's,
    // else the first.
    function navigationSurface() {
        const surfaces = overlays.instances;
        if (surfaces.length === 0) return null;
        return (highlighted !== "" ? surfaceHolding(highlighted) : null) || surfaceFor(HyprModel.focusedMonitor) || surfaces[0];
    }

    function readRecords(): void {
        recordsFile.reload();
        let r = {};
        try {
            const t = recordsFile.text();
            if (t && t.trim() !== "") {
                const o = JSON.parse(t);
                if (o && typeof o === "object" && !Array.isArray(o)) r = o;
            }
        } catch (e) {}
        records = r;
    }

    function readWallpapers(): void {
        wallFile.reload();
        let b = [];
        try {
            b = Wallpaper.parseHyprpaper(wallFile.text() || "");
        } catch (e) {}
        if (JSON.stringify(b) !== JSON.stringify(wallBlocks)) wallBlocks = b;
    }

    // The pointer over a window (address) or over nothing of it (""): a highlight the keys set stays.
    function setHover(source, address): void {
        if (address !== "") {
            highlighted = address;
            hoverSource = source;
        } else if (hoverSource === source) {
            highlighted = "";
            hoverSource = null;
        }
    }

    function setOverClose(source, address): void {
        if (address !== "") {
            overClose = address;
            overCloseSource = source;
        } else if (overCloseSource === source) {
            overClose = "";
            overCloseSource = null;
        }
    }

    function setKeyHighlight(address): void {
        highlighted = address;
        hoverSource = null;
    }

    function navigateKey(dir): void {
        const s = navigationSurface();
        if (!s) return;
        const rects = s.visibleRects();
        const from = s.holds(highlighted) ? highlighted : "";
        const next = Nav.navigate(rects, from, dir);
        if (next !== "") setKeyHighlight(next);
    }

    function setQuery(q): void {
        query = q;
        if (q === "" || (highlighted !== "" && isVisible(highlighted) && surfaceHolding(highlighted))) return;
        let pick = "";
        const s = navigationSurface();
        if (s) pick = Nav.readingOrder(s.visibleRects())[0] || "";
        if (pick === "") {
            const surfaces = overlays.instances;
            for (let i = 0; i < surfaces.length && pick === ""; i++)
                pick = Nav.readingOrder(surfaces[i].visibleRects())[0] || "";
        }
        setKeyHighlight(pick);
    }

    // Return or Enter: focus the visible highlighted window, or hand a query with no match to the launcher.
    function activateHighlight(): void {
        if (highlighted !== "" && isVisible(highlighted) && surfaceHolding(highlighted)) {
            hide(highlighted);
        } else if (query !== "" && visibleList.length === 0) {
            hide("", Search.launcherArgv(Config.values.launcher, query));
        }
    }

    function printable(t): bool {
        if (!t) return false;
        for (let i = 0; i < t.length; i++) {
            const c = t.charCodeAt(i);
            if (c < 0x20 || c === 0x7f) return false;
        }
        return true;
    }

    // A key on any surface. True when it was used.
    function handleKey(event): bool {
        if (!shown) return false;
        switch (event.key) {
        case Qt.Key_Left: navigateKey("left"); return true;
        case Qt.Key_Right: navigateKey("right"); return true;
        case Qt.Key_Up: navigateKey("up"); return true;
        case Qt.Key_Down: navigateKey("down"); return true;
        case Qt.Key_Return:
        case Qt.Key_Enter: activateHighlight(); return true;
        case Qt.Key_Escape:
            if (query !== "") setQuery("");
            else hide("");
            return true;
        case Qt.Key_Backspace:
            if (query !== "") setQuery(Array.from(query).slice(0, -1).join(""));
            return true;
        }
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return false;
        if (!printable(event.text)) return false;
        setQuery(query + event.text);
        return true;
    }

    // ---- drag and drop: global logical pointer positions --------------------------------------------------------
    function dropSurfaces() {
        const out = [];
        for (const e of model) {
            const s = surfaceFor(e.monitor);
            out.push({ monitor: e.monitor, x: e.x, y: e.y, w: e.logical.w, h: e.logical.h, workspace: e.workspace.id,
                       strip: s && s.layout ? s.layout.strip : [] });
        }
        return out;
    }

    function monitorAt(gx, gy): string {
        for (const e of model)
            if (e.x <= gx && gx < e.x + e.logical.w && e.y <= gy && gy < e.y + e.logical.h) return e.monitor;
        return "";
    }

    // source: the surface the press was on; w, h: the proxy's size.
    function startDrag(source, address, gx, gy, w, h): void {
        if (!shown || !source || !source.entry) return;
        drag = { address: address, monitor: source.monitorName, workspace: source.entry.workspace.id,
                 target: { kind: "none" }, gx: gx, gy: gy, over: source.monitorName, w: w, h: h };
        updateDrag(gx, gy);
    }

    function updateDrag(gx, gy): void {
        if (!drag) return;
        const d = drag;
        const t = Drop.dropTarget(gx, gy, dropSurfaces(), { monitor: d.monitor, workspace: d.workspace });
        drag = { address: d.address, monitor: d.monitor, workspace: d.workspace, target: t, gx: gx, gy: gy,
                 over: monitorAt(gx, gy), w: d.w, h: d.h };
    }

    function endDrag(): void {
        const d = drag;
        drag = null;
        if (!d || !shown) return;
        const t = d.target || {};
        if (t.kind === "workspace" || t.kind === "monitor") HyprModel.moveToWorkspace(d.address, t.id, t.monitor);
    }

    function liveState() {
        return { ready: ready, shown: shown, seq: seq, hovered: hovered, highlighted: highlighted, query: query,
                 visible: visibleList, overClose: overClose,
                 drag: drag ? { address: drag.address, target: drag.target } : null };
    }

    // ---- the open animation, for the test hook --------------------------------------------------------------------
    function startOpen(): void {
        if (!shown && !showing) return;
        anim = { startedAt: Date.now(), doneAt: null, frames: 0 };
        tilesOpen = true;
        Qt.callLater(root.checkAnim);
    }

    // Every tile has sent openAnimationDone since open went true: note the time and the tiles' steps.
    function checkAnim(): void {
        if (!shown || !tilesOpen || anim.startedAt === null || anim.doneAt !== null) return;
        let frames = 0;
        const surfaces = overlays.instances;
        for (let i = 0; i < surfaces.length; i++) {
            const ts = surfaces[i].tileStates();
            for (const t of ts) {
                if (!t.done) return;
                frames += t.steps;
            }
        }
        anim = { startedAt: anim.startedAt, doneAt: Date.now(), frames: frames };
        checkHook();
    }

    property bool showing: false             // inside show(), before shown goes true

    function show(viaIpc): void {
        if (shown) return;
        const t = Date.now();
        if (closing) {
            closeTimer.stop();
            closing = false;
            pendingFocus = "";
            pendingLaunch = null;
        }
        showing = true;
        previousFocus = HyprModel.activeAddress();
        query = "";
        highlighted = "";
        hoverSource = null;
        overClose = "";
        overCloseSource = null;
        drag = null;
        anim = { startedAt: null, doneAt: null, frames: 0 };
        seq++;
        ipcAt = viaIpc ? t : null;
        readRecords();
        readWallpapers();
        rebuild();
        const surfaces = overlays.instances;
        for (let i = 0; i < surfaces.length; i++) surfaces[i].prepareShow();
        showGeneration = HyprModel.generation;
        hookPending = true;
        HyprModel.hidden = false;
        HyprModel.refresh();
        if (animationMs === 0) startOpen();
        showing = false;
        shown = true;
        if (!tilesOpen) Qt.callLater(() => { if (root.shown && !root.tilesOpen) root.startOpen(); });
    }

    // focusAddress: a window to focus once the surfaces are gone ("" for none); launch: argv to run then (or none).
    function hide(focusAddress, launch): void {
        if (!shown) return;
        shown = false;
        tilesOpen = false;
        highlighted = "";
        hoverSource = null;
        overClose = "";
        overCloseSource = null;
        drag = null;
        hookPending = false;
        hookTimer.stop();
        HyprModel.hidden = true;
        pendingFocus = focusAddress || (launch && launch.length > 0 ? "" : previousFocus);
        previousFocus = "";
        pendingLaunch = launch && launch.length > 0 ? launch : null;
        if (animationMs > 0) {
            closing = true;
            closeTimer.interval = animationMs + 16;
            closeTimer.restart();
        } else {
            finishHide();
        }
    }

    function finishHide(): void {
        closing = false;
        const a = pendingFocus;
        pendingFocus = "";
        if (a !== "" && HyprModel.onShownWorkspace(a)) HyprModel.focusWindow(a);
        const argv = pendingLaunch;
        pendingLaunch = null;
        if (argv) Quickshell.execDetached(argv);
    }

    function toggle(viaIpc): void {
        if (shown) hide("");
        else show(viaIpc);
    }

    // Every surface has drawn its first frame, the refresh started by the show has landed and the open animation
    // is done (anim.doneAt): write the state file.
    function checkHook(): void {
        if (!hookPending || !hook.enabled) return;
        if (HyprModel.generation <= showGeneration) return;
        if (anim.doneAt === null) return;
        const surfaces = overlays.instances;
        for (let i = 0; i < surfaces.length; i++)
            if (!(surfaces[i].firstFrameAt > 0)) return;
        hookPending = false;
        hookTimer.interval = 1;
        hookTimer.restart();
    }

    function stateFile() {
        const surfaces = overlays.instances;
        const out = [];
        for (let i = 0; i < surfaces.length; i++) out.push(surfaces[i].describe());
        return {
            seq: seq, shown: shown, ipcAt: ipcAt, animationMs: animationMs,
            query: query, highlighted: highlighted,
            anim: { startedAt: anim.startedAt, doneAt: anim.doneAt, frames: anim.frames },
            configOk: Config.ok, config: Config.values,
            theme: { base: String(Theme.base), accent: String(Theme.accent), font: Theme.font },
            surfaces: out,
        };
    }

    // x, y global logical: the screen holding the point gets activateAt(x - its x, y - its y).
    function clickAt(x, y) {
        for (const e of model) {
            if (x < e.x || y < e.y || x >= e.x + e.logical.w || y >= e.y + e.logical.h) continue;
            const surfaces = overlays.instances;
            for (let i = 0; i < surfaces.length; i++)
                if (surfaces[i].monitorName === e.monitor)
                    return surfaces[i].activateAt(x - e.x, y - e.y, Qt.LeftButton);
            return { kind: "no surface", monitor: e.monitor };
        }
        return { kind: "no screen" };
    }

    Component.onCompleted: rebuild()

    Connections {
        target: HyprModel
        function onRefreshed(ok) {
            root.rebuild();
            root.checkAnim();
            root.checkHook();
        }
    }

    Variants {
        id: overlays
        model: Quickshell.screens
        delegate: Overlay {
            overview: root
            onFramed: root.checkHook()
        }
    }

    TestHook { id: hook }

    Timer {
        id: closeTimer
        onTriggered: root.finishHide()
    }

    Timer {
        id: hookTimer
        onTriggered: if (root.shown) hook.write(root.seq, root.stateFile())
    }

    FileView {
        id: recordsFile
        path: root.minimizedFile
        blockAllReads: true
        printErrors: false
    }

    FileView {
        id: wallFile
        path: root.configHome + "/hypr/hyprpaper.conf"
        blockAllReads: true
        printErrors: false
    }

    IpcHandler {
        target: "overview"
        function toggle(): void { root.toggle(true); }
        function show(): void { root.show(true); }
        function hide(): void { root.hide(""); }
        // test only: answer "disabled" unless RILEYOVERVIEW_TEST_DIR is set
        function state(): string {
            if (!hook.enabled) return "disabled";
            return JSON.stringify(root.liveState());
        }
        // test only: the state file's object for this moment, with state() under "live"
        function snapshot(): string {
            if (!hook.enabled) return "disabled";
            const o = root.stateFile();
            o.live = root.liveState();
            return JSON.stringify(o);
        }
        function click(x: real, y: real): string {
            if (!hook.enabled) return "disabled";
            return JSON.stringify(root.clickAt(x, y));
        }
    }
}
