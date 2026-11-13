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
// Actions: focusWindow(address), switchWorkspace(monitor, id). Live images come from toplevelFor(address).
Singleton {
    id: root

    property var monitors: []
    property var workspaces: []
    property var clients: []
    property bool animationsEnabled: true
    property bool loaded: false          // the first refresh has landed
    property int generation: 0           // counts finished refreshes (failed ones too)
    property bool hidden: true           // set by the shell: refresh less eagerly while hidden

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
