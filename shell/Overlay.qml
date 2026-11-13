// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"
import "lib/model.mjs" as Model
import "lib/hittest.mjs" as Hit

// One overview surface per screen (docs/overlay.md "Overlay window"): a full-screen layer-shell surface on the
// overlay layer with the keyboard while shown. Hidden means unmapped; the scene stays loaded. One MouseArea takes
// all input and hit-tests the same rects the components draw (lib/hittest.mjs).
PanelWindow {
    id: win

    required property var modelData          // the ShellScreen (Variants)
    property var overview                    // the shell root: state, show/hide, the model

    readonly property string monitorName: modelData ? modelData.name : ""
    readonly property var entry: overview ? overview.entryFor(monitorName) : null
    readonly property var layout: entry ? Model.layoutMonitor(entry, Config.values) : null
    readonly property string wallpaper: overview && entry ? overview.wallpaperFor(entry) : ""

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
        scene.forceActiveFocus();
        if (typeof strip.capture === "function") strip.capture();
    }

    function windowRects() {
        return layout ? layout.windows.map(w => ({ id: w.address, x: w.x, y: w.y, w: w.w, h: w.h })) : [];
    }

    function hitAt(x, y) {
        if (!layout) return { kind: "none" };
        return Hit.hitTest(x, y, windowRects(), layout.strip);
    }

    function hoverAt(x, y): void {
        if (!overview || !overview.shown) return;
        const h = hitAt(x, y);
        overview.setHover(win, h.kind === "window" ? h.id : "");
    }

    // A click at x, y (surface logical px). Returns what was hit, as the IPC click call reports it.
    function activateAt(x, y, button) {
        if (!overview || !overview.shown) return { kind: "hidden" };
        const h = hitAt(x, y);
        if (h.kind === "window") {
            if (button === Qt.LeftButton) overview.hide(h.id);
            // middle click and the close button: M3
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
                real: real[w.address], logical: r4(w, 1), device: r4(w, dpr) })) : [],
            minimized: L ? L.minimized.map(w => ({
                address: w.address, class: info[w.address].class, title: info[w.address].title,
                logical: r4(w, 1), device: r4(w, dpr) })) : [],
            strip: L ? L.strip.map(s => ({ index: s.index, id: s.id, name: s.name, current: s.current, empty: s.empty,
                                           logical: r4(s, 1) })) : [],
        };
    }

    Item {
        id: scene
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                win.overview.hide("");
                event.accepted = true;
            }
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
            wallpaper: win.wallpaper
            fallbackColor: Theme.base
        }

        WorkspaceStrip {
            id: strip
            entries: win.layout ? win.layout.strip : []
            screen: win.modelData
            accent: Theme.accent
            textColor: Theme.text
            panelColor: Theme.surface0
            fontFamily: Theme.font
        }

        Repeater {
            model: win.layout ? win.layout.windows : []
            delegate: WindowTile {
                required property var modelData
                readonly property var src: win.entry ? win.entry.windows.find(w => w.address === modelData.address) : null
                toplevel: HyprModel.toplevelFor(modelData.address)
                address: modelData.address
                appClass: src ? src.class : ""
                title: src ? src.title : ""
                realRect: src ? { x: src.x, y: src.y, w: src.w, h: src.h } : modelData
                spreadRect: ({ x: modelData.x, y: modelData.y, w: modelData.w, h: modelData.h })
                animationMs: win.overview ? win.overview.animationMs : 0
                highlighted: win.overview ? win.overview.hovered === modelData.address : false
                open: win.overview ? win.overview.tilesOpen : false
                accent: Theme.accent
                textColor: Theme.text
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

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            onEntered: win.hoverAt(mouseX, mouseY)
            onPositionChanged: mouse => win.hoverAt(mouse.x, mouse.y)
            onExited: if (win.overview) win.overview.setHover(win, "")
            onClicked: mouse => win.activateAt(mouse.x, mouse.y, mouse.button)
        }
    }
}
