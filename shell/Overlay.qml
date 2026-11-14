// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"
import "lib/model.mjs" as Model
import "lib/hittest.mjs" as Hit
import "lib/drop.mjs" as Drop
import "lib/strip.mjs" as Strip
import "lib/desktops.mjs" as Desk

// One overview surface per screen (docs/overlay.md "Overlay window"): a full-screen layer-shell surface on the
// overlay layer with the keyboard while shown. Hidden means unmapped; the scene stays loaded. One MouseArea takes
// all input and hit-tests the same rects the components draw (lib/hittest.mjs). Pointer, keys, search and drag and
// drop: docs/interact.md; the state they share lives in the shell (shell.qml).
PanelWindow {
    id: win

    required property var modelData          // the ShellScreen (Variants)
    property var overview                    // the shell root: state, show/hide, the model

    readonly property string monitorName: modelData ? modelData.name : ""
    readonly property var entry: overview ? overview.entryFor(monitorName) : null
    readonly property var layout: entry ? Model.layoutMonitor(entry, Config.values) : null
    readonly property string wallpaper: overview && entry ? overview.wallpaperFor(entry) : ""

    // The desktops bar (docs/design.md "Desktops bar"): expanded while the pointer is in its band or any drag runs
    // (on every surface). Hit-testing always uses the expanded rects (layout.strip): a point in a preview is in the
    // band, so the bar is expanded whenever such a point is tested.
    property real pointerX: -1               // the pointer over this surface, local logical; -1 when not over it
    property real pointerY: -1
    property int stripHover: -1              // the strip entry under the pointer, -1 for none
    readonly property var barBand: entry ? Desk.desktopsBar(entry.logical.w, entry.logical.h, (entry.strip || []).length,
                                                            Config.values, false).band
                                         : ({ x: 0, y: 0, w: 0, h: 0 })
    readonly property bool barExpanded: {
        const dragging = overview ? overview.drag !== null : false;
        return Desk.barExpanded(pointerX, pointerY, barBand, dragging);
    }
    // Per workspace id of this monitor's strip: its windows as fractions of the monitor, back to front, for the
    // bar's live previews.
    readonly property var previews: {
        const e = entry;
        const out = {};
        if (!e || !(e.logical.w > 0) || !(e.logical.h > 0)) return out;
        const ids = {};
        for (const s of e.strip || []) if (!s.empty) ids[s.id] = true;
        const cls = HyprModel.clients.filter(c => c && c.workspace && ids[c.workspace.id] === true && c.mapped !== false
                                                  && c.hidden !== true && Array.isArray(c.at) && Array.isArray(c.size))
                                     .slice()
                                     .sort((a, b) => (b.focusHistoryID || 0) - (a.focusHistoryID || 0));
        for (const c of cls) {
            const list = out[c.workspace.id] || (out[c.workspace.id] = []);
            list.push({ toplevel: HyprModel.toplevelFor(c.address),
                        x: (c.at[0] - e.x) / e.logical.w, y: (c.at[1] - e.y) / e.logical.h,
                        w: c.size[0] / e.logical.w, h: c.size[1] / e.logical.h });
        }
        return out;
    }

    // the first frame after a show (test hook and timing)
    property bool awaitingFrame: false
    property real firstFrameAt: 0
    property real frameDpr: 1
    signal framed()

    screen: modelData
    visible: overview ? overview.mapped : false
    color: "black"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "riley-overview"
    WlrLayershell.keyboardFocus: overview && overview.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Called by the shell just before it maps the surfaces.
    function prepareShow(): void {
        firstFrameAt = 0;
        awaitingFrame = true;
        press = null;
        dragOwner = false;
        stripHover = -1;
        pointerX = -1;
        pointerY = -1;
        scene.forceActiveFocus();
        if (typeof strip.capture === "function") strip.capture();
    }

    // The spread windows that match the search: the only ones drawn, hit-tested and navigated.
    function visibleRects() {
        if (!layout || !overview) return [];
        return layout.windows.filter(w => overview.isVisible(w.address))
                             .map(w => ({ id: w.address, x: w.x, y: w.y, w: w.w, h: w.h }));
    }

    function windowRects() {
        return visibleRects();
    }

    // This surface's spread holds the window (visible or not).
    function holds(address): bool {
        if (!layout || !address) return false;
        for (const w of layout.windows) if (w.address === address) return true;
        return false;
    }

    function hitAt(x, y) {
        if (!layout) return { kind: "none" };
        return Hit.hitTestOverlay(x, y, windowRects(), layout.strip, overview ? overview.highlighted : "");
    }

    function hoverAt(x, y): void {
        pointerX = x;
        pointerY = y;
        if (!overview || !overview.shown) return;
        const h = hitAt(x, y);
        stripHover = h.kind === "workspace" ? h.index : -1;
        if (h.kind === "close") {
            overview.setHover(win, h.id);
            overview.setOverClose(win, h.id);
        } else {
            overview.setHover(win, h.kind === "window" ? h.id : "");
            overview.setOverClose(win, "");
        }
    }

    // The tiles' open-animation state, for the shell's anim bookkeeping.
    function tileStates() {
        const out = [];
        for (let i = 0; i < tiles.count; i++) {
            const t = tiles.itemAt(i);
            if (t) out.push({ done: t.doneSeen, steps: t.steps });
        }
        // the backdrop's fade ends on the same frame as the moves; the state file waits for it too
        out.push({ done: backdrop.doneSeen, steps: 0 });
        return out;
    }

    // ---- the pointer: press, motion (hover or drag), release (click or drop) ------------------------------------
    property var press: null                 // { x, y, button, address } of the button held down
    property bool dragOwner: false           // this surface started the drag in progress

    function pointerPressed(x, y, button): void {
        if (!overview || !overview.shown) { press = null; return; }
        const h = hitAt(x, y);
        press = { x: x, y: y, button: button, address: button === Qt.LeftButton && h.kind === "window" ? h.id : "" };
    }

    // x, y local; the compositor keeps sending motion to the pressed surface outside it, so the global position is
    // this monitor's position plus the local one.
    function pointerMoved(x, y): void {
        if (!overview || !overview.shown) return;
        const gx = (entry ? entry.x : 0) + x;
        const gy = (entry ? entry.y : 0) + y;
        pointerX = x;
        pointerY = y;
        if (dragOwner && overview.drag) {
            overview.updateDrag(gx, gy);
            return;
        }
        if (press && press.address !== "" && Drop.dragStarted(x - press.x, y - press.y)) {
            const r = layout ? layout.windows.find(w => w.address === press.address) : null;
            const pw = r && r.w > 0 ? Math.min(r.w, 300) : 0;
            const ph = r && r.w > 0 ? r.h * pw / r.w : 0;
            dragOwner = true;
            overview.setOverClose(win, "");
            overview.startDrag(win, press.address, gx, gy, pw, ph);
            press = null;
            return;
        }
        hoverAt(x, y);
    }

    function pointerReleased(x, y, button): void {
        const p = press;
        press = null;
        if (dragOwner) {
            dragOwner = false;
            if (overview) overview.endDrag();
            if (x >= 0 && y >= 0 && x < width && y < height) hoverAt(x, y);
            return;
        }
        if (!p || p.button !== button) return;
        if (x < 0 || y < 0 || x >= width || y >= height) return;
        activateAt(x, y, button);
    }

    function pointerCanceled(): void {
        press = null;
        if (dragOwner) {
            dragOwner = false;
            if (overview && overview.drag) overview.drag = null;
        }
    }

    // A click at x, y (surface logical px). Returns what was hit, as the IPC click call reports it.
    function activateAt(x, y, button) {
        if (!overview || !overview.shown) return { kind: "hidden" };
        const h = hitAt(x, y);
        if (h.kind === "close") {
            if (button === Qt.LeftButton || button === Qt.MiddleButton) HyprModel.closeWindow(h.id);
            return { kind: "close", address: h.id, monitor: monitorName };
        }
        if (h.kind === "window") {
            if (button === Qt.LeftButton) overview.hide(h.id);
            else if (button === Qt.MiddleButton) HyprModel.closeWindow(h.id);
            return { kind: "window", address: h.id, monitor: monitorName };
        }
        if (h.kind === "workspace") {
            const s = layout.strip[h.index];
            if (button === Qt.LeftButton && s) HyprModel.switchWorkspace(monitorName, s.id);
            return { kind: "workspace", index: h.index, id: s ? s.id : null, monitor: monitorName };
        }
        if (button === Qt.LeftButton) overview.hide("");
        return { kind: "none", monitor: monitorName };
    }

    function r4(r, k) {
        return { x: r.x * k, y: r.y * k, w: r.w * k, h: r.h * k };
    }

    // This surface for the test hook's state file.
    function describe() {
        const dpr = frameDpr;
        const L = layout;
        const e = entry;
        const real = {};
        const info = {};
        if (e) {
            for (const w of e.windows) { real[w.address] = { x: w.x, y: w.y, w: w.w, h: w.h }; info[w.address] = w; }
            for (const w of e.minimized) info[w.address] = w;
        }
        return {
            monitor: monitorName,
            logical: { w: win.width, h: win.height },
            dpr: dpr,
            device: { w: win.width * dpr, h: win.height * dpr },
            firstFrameAt: firstFrameAt,
            workspace: e ? { id: e.workspace.id, name: e.workspace.name } : null,
            windows: L ? L.windows.map(w => ({
                address: w.address, class: info[w.address].class, title: info[w.address].title,
                visible: overview ? overview.isVisible(w.address) : true, scale: w.scale,
                real: real[w.address], logical: r4(w, 1), device: r4(w, dpr) })) : [],
            minimized: L ? L.minimized.map(w => ({
                address: w.address, class: info[w.address].class, title: info[w.address].title,
                logical: r4(w, 1), device: r4(w, dpr) })) : [],
            strip: L ? L.strip.map(s => ({ index: s.index, id: s.id, name: s.name, current: s.current, empty: s.empty,
                                           logical: r4(s, 1) })) : [],
            bar: { expanded: barExpanded,
                   names: L && L.names ? L.names.map(n => ({ index: n.index, id: n.id, name: n.name, current: n.current,
                                                             empty: n.empty,
                                                             plus: n.plus !== undefined ? n.plus === true : n.empty === true,
                                                             logical: r4(n, 1) })) : [] },
        };
    }

    Item {
        id: scene
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            if (win.overview && win.overview.handleKey(event)) event.accepted = true;
        }

        // The first frame after a show: frameSwapped of the backing window (render thread, delivered queued).
        Connections {
            target: scene.Window.window
            ignoreUnknownSignals: true
            function onFrameSwapped() {
                if (!win.awaitingFrame) return;
                win.awaitingFrame = false;
                win.firstFrameAt = Date.now();
                win.frameDpr = win.devicePixelRatio > 0 ? win.devicePixelRatio : 1;
                win.framed();
            }
        }

        Backdrop {
            id: backdrop
            // openAnimationDone seen since open last went true (the shell's anim bookkeeping)
            property bool doneSeen: false
            wallpaper: win.wallpaper
            fallbackColor: Theme.base
            open: win.overview ? win.overview.tilesOpen : false
            animationMs: win.overview ? win.overview.animationMs : 0
            onOpenAnimationDone: {
                doneSeen = true;
                if (win.overview) win.overview.checkAnim();
            }
            onOpenChanged: if (!open) doneSeen = false
        }

        WorkspaceStrip {
            id: strip
            entries: win.layout ? win.layout.strip : []
            names: win.layout && win.layout.names ? win.layout.names : []
            expanded: win.barExpanded
            previews: win.barExpanded ? win.previews : ({})
            wallpaper: win.wallpaper
            screen: win.modelData
            accent: Theme.accent
            textColor: Theme.text
            panelColor: Theme.surface0
            fontFamily: Theme.font
            animationMs: win.overview ? win.overview.animationMs : 0
            hoveredIndex: win.stripHover
            dropIndex: {
                const d = win.overview ? win.overview.drag : null;
                return d && d.target && d.target.kind === "workspace" && d.target.monitor === win.monitorName
                    ? d.target.index : -1;
            }
        }

        SearchField {
            rect: win.entry ? Strip.searchArea(win.entry.logical.w, win.entry.logical.h, Config.values)
                            : ({ x: 0, y: 0, w: 0, h: 0 })
            query: win.overview ? win.overview.query : ""
            noMatch: win.overview ? win.overview.query !== "" && win.overview.visibleList.length === 0 : false
            accent: Theme.accent
            textColor: Theme.text
            panelColor: Theme.surface0
            fontFamily: Theme.font
        }

        Repeater {
            id: tiles
            model: win.layout ? win.layout.windows : []
            delegate: WindowTile {
                required property var modelData
                // openAnimationDone seen since open last went true (the shell's anim bookkeeping)
                property bool doneSeen: false
                onOpenAnimationDone: {
                    doneSeen = true;
                    if (win.overview) win.overview.checkAnim();
                }
                onOpenChanged: if (!open) doneSeen = false
                visible: win.overview ? win.overview.isVisible(modelData.address) : true
                dragging: win.overview && win.overview.drag ? win.overview.drag.address === modelData.address : false
                readonly property var src: win.entry ? win.entry.windows.find(w => w.address === modelData.address) : null
                toplevel: HyprModel.toplevelFor(modelData.address)
                address: modelData.address
                appClass: src ? src.class : ""
                title: src ? src.title : ""
                realRect: src ? { x: src.x, y: src.y, w: src.w, h: src.h } : modelData
                spreadRect: ({ x: modelData.x, y: modelData.y, w: modelData.w, h: modelData.h })
                tileScale: isFinite(modelData.scale) ? modelData.scale : (src && src.w > 0 ? modelData.w / src.w : 1)
                animationMs: win.overview ? win.overview.animationMs : 0
                highlighted: win.overview ? win.overview.highlighted === modelData.address : false
                open: win.overview ? win.overview.tilesOpen : false
                accent: Theme.accent
                textColor: Theme.text
                panelColor: Theme.surface0
                fontFamily: Theme.font
            }
        }

        MinimizedRow {
            entries: {
                const L = win.layout;
                const e = win.entry;
                if (!L || !e) return [];
                return L.minimized.map(r => {
                    const m = e.minimized.find(w => w.address === r.address) || {};
                    return { address: r.address, x: r.x, y: r.y, w: r.w, h: r.h, appClass: m.class || "",
                             title: m.title || "", toplevel: HyprModel.toplevelFor(r.address) };
                });
            }
            accent: Theme.accent
            textColor: Theme.text
            fontFamily: Theme.font
            highlightedAddress: win.overview ? win.overview.hovered : ""
        }

        // The window being dragged, under the pointer, on the surface the pointer is over.
        DragProxy {
            readonly property var d: win.overview ? win.overview.drag : null
            visible: d !== null && d.over === win.monitorName
            toplevel: d ? HyprModel.toplevelFor(d.address) : null
            appClass: {
                if (!d) return "";
                for (const e of win.overview.model)
                    for (const w of e.windows) if (w.address === d.address) return w.class;
                return "";
            }
            px: d && win.entry ? d.gx - win.entry.x : 0
            py: d && win.entry ? d.gy - win.entry.y : 0
            w: d ? d.w : 0
            h: d ? d.h : 0
            accent: Theme.accent
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            onEntered: if (!win.dragOwner) win.hoverAt(mouseX, mouseY)
            onPositionChanged: mouse => win.pointerMoved(mouse.x, mouse.y)
            onExited: {
                if (win.dragOwner) return;
                win.pointerX = -1;
                win.pointerY = -1;
                win.stripHover = -1;
                if (win.overview) {
                    win.overview.setHover(win, "");
                    win.overview.setOverClose(win, "");
                }
            }
            onPressed: mouse => win.pointerPressed(mouse.x, mouse.y, mouse.button)
            onReleased: mouse => win.pointerReleased(mouse.x, mouse.y, mouse.button)
            onCanceled: win.pointerCanceled()
        }
    }
}
