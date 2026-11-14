// SPDX-License-Identifier: GPL-3.0-or-later
// MC layout gate: what layoutMonitor (shell/lib/model.mjs) hands the QML from MC on: each window's own scale and the
// collapsed names row. Expected values worked out by hand below.
//
// Entry: RO-A, logical 3440x1440, the two tiles of cases.mjs "A 2 tiles" (0xa at 10,50 and 0xb at 1725,50, both
// 1705x1380), no minimized window, strip items [1 (current), 2 (empty)]. Config defaults.
//   Safe area {24, 216, 3392, 1200}; spread as "A 2 tiles": both scale 20/23, 0xa x = 225.3913, 0xb x = 1732, y 216,
//   w = 1705*20/23 = 1482.6087, h 1200.
//   Strip (2 entries, docs/overlay.md and the M2 gate): w 286.6667, x 1425.3333 and 1728, y 24, h 120.
//   names (desktopsBar collapsed): the same x and w, y 24, h 28, with the items' id, name, current, empty.
import QtQuick
import QtTest
import "../lib/model.mjs" as Model

TestCase {
    name: "layoutmonitor"

    readonly property var cfg: ({ margin: 24, stripHeight: 120, stripSpacing: 16, searchHeight: 40, sectionGap: 16,
                                  windowSpacing: 24, maxScale: 1.0, animationMs: 200, launcher: "fuzzel" })
    readonly property var entry: ({
        monitor: "RO-A", description: "", x: 0, y: 0, scale: 1, logical: { w: 3440, h: 1440 },
        workspace: { id: 1, name: "1" },
        windows: [{ address: "0xa", class: "a", title: "a", x: 10, y: 50, w: 1705, h: 1380 },
                  { address: "0xb", class: "b", title: "b", x: 1725, y: 50, w: 1705, h: 1380 }],
        minimized: [],
        strip: [{ id: 1, name: "1", current: true, empty: false }, { id: 2, name: "2", current: false, empty: true }],
    })
    function near(a, b) { return Math.abs(a - b) <= 1e-4; }

    function test_window_scales() {
        const L = Model.layoutMonitor(entry, cfg);
        compare(L.windows.length, 2);
        const want = { "0xa": 24 + (3392 - (2 * 1705 * 20 / 23 + 24)) / 2, "0xb": 1732 };
        for (const w of L.windows) {
            verify(near(w.scale, 20 / 23), w.address + " scale " + w.scale + ", want " + 20 / 23);
            verify(near(w.x, want[w.address]), w.address + " x " + w.x + ", want " + want[w.address]);
        }
        verify(near(L.scale, 20 / 23), "scale " + L.scale);
    }

    function test_names() {
        const L = Model.layoutMonitor(entry, cfg);
        verify(Array.isArray(L.names), "layoutMonitor gives names");
        compare(L.names.length, 2);
        const xs = [24 + (3392 - (1720 / 3 + 16)) / 2, 1728];
        for (let i = 0; i < 2; i++) {
            const n = L.names[i], it = entry.strip[i];
            compare(n.index, i); compare(n.id, it.id); compare(n.name, it.name);
            compare(n.current, it.current); compare(n.empty, it.empty);
            verify(near(n.x, xs[i]) && near(n.y, 24) && near(n.w, 860 / 3) && near(n.h, 28),
                   "names[" + i + "] " + JSON.stringify(n));
            const s = L.strip[i];
            verify(near(s.x, xs[i]) && near(s.y, 24) && near(s.w, 860 / 3) && near(s.h, 120),
                   "strip[" + i + "] " + JSON.stringify(s));
        }
    }
}
