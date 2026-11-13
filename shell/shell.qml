// SPDX-License-Identifier: GPL-3.0-or-later
//
// riley-overview: the Quickshell config. M1 placeholder: the IPC target exists so the launcher can be wired;
// the overlay arrives in M2 (docs/design.md).
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    property bool shown: false

    IpcHandler {
        target: "overview"
        function toggle(): void { root.shown = !root.shown; }
        function show(): void { root.shown = true; }
        function hide(): void { root.shown = false; }
    }
}
