// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Quickshell

// Test hooks (docs/overlay.md "State file"): on when $RILEYOVERVIEW_TEST_DIR is set, nothing otherwise.
// write(seq, state) puts the state into <dir>/show-<seq>.json through a temporary file and a rename, so a reader
// never sees half a file.
QtObject {
    id: hook
    readonly property string dir: Quickshell.env("RILEYOVERVIEW_TEST_DIR") || ""
    readonly property bool enabled: dir !== ""

    function write(seq, state): void {
        if (!enabled) return;
        const target = dir + "/show-" + seq + ".json";
        Quickshell.execDetached(["sh", "-c", 'printf "%s\\n" "$1" > "$2.tmp" && mv -f "$2.tmp" "$2"', "sh",
                                 JSON.stringify(state), target]);
    }
}
