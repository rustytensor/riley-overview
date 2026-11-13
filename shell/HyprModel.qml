// SPDX-License-Identifier: GPL-3.0-or-later
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// What Hyprland has: monitors, workspaces and clients exactly as `hyprctl -j` gives them (the shapes lib/model.mjs
// takes), and whether animations are on (animations:enabled, the option Riley Settings' animations switch writes).
// Kept current while hidden, so a show draws at once from what is here: refreshed on start, on every Hyprland
// event (debounced) and on each show. One `sh` runs the four hyprctl calls; the replies are split on a record
// separator line.
//
// Actions: focusWindow(address), switchWorkspace(monitor, id), closeWindow(address), moveToWorkspace(address, id,
// monitor). Live images come from toplevelFor(address). focusedMonitor: the name of the monitor with focused true.
Singleton {
    id: root

    property var monitors: []
    property var workspaces: []
    property var clients: []
    property bool animationsEnabled: true
    property bool loaded: false          // the first refresh has landed
    property int generation: 0           // counts finished refreshes (failed ones too)
    property bool hidden: true           // set by the shell: refresh less eagerly while hidden

    readonly property string focusedMonitor: {
        for (const m of monitors) if (m && m.focused === true) return String(m.name);
        return "";
    }

    signal refreshed(bool ok)

    function refresh(): void {
        if (proc.running) {
            proc.again = true;
            return;
        }
        proc.running = true;
    }

    function luaStr(s): string {
        return "\"" + String(s).replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\"";
    }

    function focusWindow(address): void {
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ window = " + luaStr("address:" + address) + " })"]);
    }

    // The monitor first, then the workspace: a workspace that does not exist yet opens on the focused monitor.
    function switchWorkspace(monitor, id): void {
        Quickshell.execDetached(["sh", "-c", 'hyprctl dispatch "$1" >/dev/null && hyprctl dispatch "$2" >/dev/null', "sh",
                                 "hl.dsp.focus({ monitor = " + luaStr(monitor) + " })",
                                 "hl.dsp.focus({ workspace = " + luaStr(String(id)) + " })"]);
    }

    // The focused window, "" for none: Quickshell's live active toplevel (kept by Hyprland's events, so never a
    // refresh behind), else the last refresh's focusHistoryID 0.
    function activeAddress(): string {
        const t = Hyprland.activeToplevel;
        const a = t ? norm(t.address) : "";
        if (a !== "") return "0x" + a;
        for (const c of clients) if (c && c.focusHistoryID === 0) return String(c.address || "");
        return "";
    }

    // The window still exists and sits on a workspace some monitor shows: focusing it switches nothing.
    function onShownWorkspace(address): bool {
        const want = norm(address);
        if (want === "") return false;
        const c = clients.find(c => c && norm(c.address) === want);
        if (!c || !c.workspace) return false;
        return monitors.some(m => m && m.activeWorkspace && m.activeWorkspace.id === c.workspace.id);
    }

    function closeWindow(address): void {
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.close({ window = " + luaStr("address:" + address) + " })"]);
    }

    function workspaceExists(id): bool {
        for (const w of workspaces) if (w && w.id === id) return true;
        return false;
    }

    // Hyprland 0.57's movetoworkspacesilent. A workspace that does not exist yet (the empty entry at the end of a
    // strip) is created on the focused monitor, so that monitor is focused first: the new workspace then lands on
    // the strip's monitor.
    function moveToWorkspace(address, id, monitor): void {
        const move = "hl.dsp.window.move({ workspace = " + luaStr(String(id)) + ", follow = false, window = " +
                     luaStr("address:" + address) + " })";
        if (monitor && !workspaceExists(Number(id))) {
            Quickshell.execDetached(["sh", "-c", 'hyprctl dispatch "$1" >/dev/null && hyprctl dispatch "$2" >/dev/null', "sh",
                                     "hl.dsp.focus({ monitor = " + luaStr(monitor) + " })", move]);
        } else {
            Quickshell.execDetached(["hyprctl", "dispatch", move]);
        }
    }

    function norm(address): string {
        return String(address || "").toLowerCase().replace(/^0x/, "");
    }

    // The Quickshell toplevel (for ScreencopyView) of a window, null until Quickshell knows it.
    function toplevelFor(address) {
        const want = norm(address);
        const all = Hyprland.toplevels.values;
        for (let i = 0; i < all.length; i++)
            if (norm(all[i].address) === want) return all[i].wayland || null;
        return null;
    }

    function parse(text): bool {
        const parts = String(text).split("\n\x1e\n");
        if (parts.length < 4) return false;
        try {
            const mons = JSON.parse(parts[0]);
            const wss = JSON.parse(parts[1]);
            const cls = JSON.parse(parts[2]);
            if (!Array.isArray(mons) || !Array.isArray(wss) || !Array.isArray(cls)) return false;
            let anim = root.animationsEnabled;
            try {
                const o = JSON.parse(parts[3]);
                if (typeof o.bool === "boolean") anim = o.bool;
                else if (typeof o.int === "number") anim = o.int !== 0;
                else if (o.value !== undefined) anim = !(o.value === false || o.value === 0 || o.value === "false" || o.value === "0");
            } catch (e) {}
            root.monitors = mons;
            root.workspaces = wss;
            root.clients = cls;
            root.animationsEnabled = anim;
            return true;
        } catch (e) {
            console.warn("riley-overview: cannot read hyprctl output: " + e);
            return false;
        }
    }

    // The stream end and the exit can come in either order: finish once both are in.
    Process {
        id: proc
        property bool again: false
        property bool ok: false
        property bool streamDone: false
        property bool exitDone: false
        running: true
        command: ["sh", "-c",
                  "hyprctl -j monitors; printf '\\n\\036\\n'; hyprctl -j workspaces; printf '\\n\\036\\n'; " +
                  "hyprctl -j clients; printf '\\n\\036\\n'; hyprctl -j getoption animations:enabled"]
        onStarted: { streamDone = false; exitDone = false; ok = false; }
        stdout: StdioCollector {
            onStreamFinished: {
                proc.ok = root.parse(text);
                proc.streamDone = true;
                proc.finish();
            }
        }
        onExited: { exitDone = true; finish(); }

        function finish() {
            if (!streamDone || !exitDone) return;
            streamDone = false;
            exitDone = false;
            const ok = proc.ok;
            if (ok) root.loaded = true;
            root.generation++;
            root.refreshed(ok);
            if (again) {
                again = false;
                Qt.callLater(root.refresh);
            }
        }
    }

    Timer {
        id: debounce
        interval: root.hidden ? 150 : 30
        onTriggered: root.refresh()
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // our own surfaces mapping and unmapping change nothing we show
            if (event.name === "openlayer" || event.name === "closelayer") return;
            if (!debounce.running) debounce.start();
        }
    }
}
