// SPDX-License-Identifier: GPL-3.0-or-later
//
// riley-overview: the Quickshell config. Resident and hidden; `riley-overview toggle` (IPC target "overview") shows
// one overview surface per screen (Overlay.qml). docs/overlay.md has the interfaces, docs/design.md the reasons.
import QtQuick
import Quickshell
import Quickshell.Io
import "lib/model.mjs" as Model
import "lib/wallpaper.mjs" as Wallpaper

ShellRoot {
    id: root

    property bool shown: false
    property bool closing: false             // the close animation runs; the surfaces are still mapped
    readonly property bool mapped: shown || closing
    property bool tilesOpen: false           // WindowTile.open: false at the real rects, true at the spread rects
    property int seq: 0                      // shows since start
    property var ipcAt: null
    property string hovered: ""
    property var hoverSource: null
    property string pendingFocus: ""

    property var records: ({})               // hypr-minimize's minimized.json
    property var wallBlocks: []              // hyprpaper.conf, parsed
    property var model: []                   // Model.overviewModel(...)

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

    function setHover(source, address): void {
        if (address !== "") {
            hovered = address;
            hoverSource = source;
        } else if (hoverSource === source) {
            hovered = "";
            hoverSource = null;
        }
    }

    function show(viaIpc): void {
        if (shown) return;
        const t = Date.now();
        if (closing) {
            closeTimer.stop();
            closing = false;
            pendingFocus = "";
        }
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
        tilesOpen = animationMs === 0;
        shown = true;
        if (!tilesOpen) Qt.callLater(() => { if (root.shown) root.tilesOpen = true; });
    }

    // focusAddress: a window to focus once the surfaces are gone ("" for none).
    function hide(focusAddress): void {
        if (!shown) return;
        shown = false;
        tilesOpen = false;
        hovered = "";
        hoverSource = null;
        hookPending = false;
        hookTimer.stop();
        HyprModel.hidden = true;
        pendingFocus = focusAddress || "";
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
        if (a !== "") HyprModel.focusWindow(a);
    }

    function toggle(viaIpc): void {
        if (shown) hide("");
        else show(viaIpc);
    }

    // Every surface has drawn its first frame and the refresh started by the show has landed: wait out the open
    // animation, then write the state file.
    function checkHook(): void {
        if (!hookPending || !hook.enabled) return;
        if (HyprModel.generation <= showGeneration) return;
        const surfaces = overlays.instances;
        for (let i = 0; i < surfaces.length; i++)
            if (!(surfaces[i].firstFrameAt > 0)) return;
        hookPending = false;
        hookTimer.interval = Math.max(1, animationMs);
        hookTimer.restart();
    }

    function stateFile() {
        const surfaces = overlays.instances;
        const out = [];
        for (let i = 0; i < surfaces.length; i++) out.push(surfaces[i].describe());
        return {
            seq: seq, shown: shown, ipcAt: ipcAt, animationMs: animationMs,
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
            return JSON.stringify({ ready: root.ready, shown: root.shown, seq: root.seq, hovered: root.hovered });
        }
        function click(x: real, y: real): string {
            if (!hook.enabled) return "disabled";
            return JSON.stringify(root.clickAt(x, y));
        }
    }
}
