// SPDX-License-Identifier: GPL-3.0-or-later
// M3 gate: drag threshold, drop target (shell/lib/drop.mjs) and the close button's hit area (shell/lib/hittest.mjs).
// Rules in docs/interact.md; expected values by hand below.
import QtQuick
import QtTest
import "../lib/drop.mjs" as Drop
import "../lib/hittest.mjs" as Hit

TestCase {
    name: "drop"

    // Strips from M1 (tests/layout/tst_strip.qml), each with 3 entries: the current workspace, the last real one,
    // the empty new one at the end (id 1 + the largest id = 7 on every monitor).
    //   A 3440x1440: x 1274, 1576.6667, 1879.3333 (step 908/3); w 860/3 = 286.6667; y 24; h 120. Ends at 2166.
    //   C 2752x1152: x 930, 1232.6667, 1535.3333; same size. Ends at 1822.
    //   B 1440x2560 (rotated): x 602.75, 686.25, 769.75 (step 83.5); w 67.5; y 24; h 120.
    function strip3(x0, step, w, ids) {
        return ids.map((id, i) => ({ index: i, id: id, x: x0 + i * step, y: 24, w: w, h: 120 }));
    }
    // Monitors at their global logical positions: A at 0,0; C (3440x1440 at 1.25 -> 2752x1152) at 3440,0;
    // B (2560x1440, transform 1 -> 1440x2560) at 6192,0.
    readonly property var surfaces: [
        { monitor: "RO-A", x: 0, y: 0, w: 3440, h: 1440, workspace: 1, strip: strip3(1274, 908 / 3, 860 / 3, [1, 4, 7]) },
        { monitor: "RO-C", x: 3440, y: 0, w: 2752, h: 1152, workspace: 2, strip: strip3(930, 908 / 3, 860 / 3, [2, 5, 7]) },
        { monitor: "RO-B", x: 6192, y: 0, w: 1440, h: 2560, workspace: 3, strip: strip3(602.75, 83.5, 67.5, [3, 6, 7]) },
    ]
    readonly property var fromA1: ({ monitor: "RO-A", workspace: 1 })
    readonly property var fromA4: ({ monitor: "RO-A", workspace: 4 })
    readonly property var fromC2: ({ monitor: "RO-C", workspace: 2 })

    function test_target_data() {
        const ws = (m, id, i) => ({ kind: "workspace", monitor: m, id: id, index: i });
        const mon = (m, id) => ({ kind: "monitor", monitor: m, id: id });
        const none = { kind: "none" };
        return [
            { tag: "A first entry, top-left corner inclusive", p: [1274, 24], src: fromA4, want: ws("RO-A", 1, 0) },
            { tag: "A first entry is the source's own workspace", p: [1300, 50], src: fromA1, want: none },
            { tag: "A last real entry", p: [1700, 100], src: fromA1, want: ws("RO-A", 4, 1) },
            { tag: "A empty new entry, just above its bottom", p: [2000, 143.9], src: fromA1, want: ws("RO-A", 7, 2) },
            { tag: "A empty entry's right edge excluded: same monitor, nothing", p: [2166, 80], src: fromA1, want: none },
            // gap between entry 0 (ends 1560.6667) and entry 1 (starts 1576.6667)
            { tag: "A strip gap", p: [1568, 80], src: fromA1, want: none },
            { tag: "A spread area, same monitor", p: [1720, 700], src: fromA1, want: none },
            { tag: "A right edge, still A", p: [3439.9, 600], src: fromA1, want: none },
            { tag: "C left edge inclusive: C's workspace", p: [3440, 600], src: fromA1, want: mon("RO-C", 2) },
            // local x 4740 - 3440 = 1300, in entry 1 (1232.6667 .. 1519.3333)
            { tag: "C strip middle entry", p: [4740, 80], src: fromA1, want: ws("RO-C", 5, 1) },
            // local x 1600, in entry 2 (1535.3333 .. 1822)
            { tag: "C strip empty entry", p: [5040, 30], src: fromA1, want: ws("RO-C", 7, 2) },
            // C is 1152 high; x 4000 is not in A (0 .. 3440) or B
            { tag: "below C: no surface", p: [4000, 1200], src: fromA1, want: none },
            // local x 6888.25 - 6192 = 696.25, in entry 1 (686.25 .. 753.75)
            { tag: "B (rotated) strip second entry", p: [6888.25, 30], src: fromA1, want: ws("RO-B", 6, 1) },
            { tag: "B spread area, far down", p: [6892, 2000], src: fromA1, want: mon("RO-B", 3) },
            { tag: "left of every surface", p: [-1, 600], src: fromA1, want: none },
            { tag: "right of every surface", p: [7632, 600], src: fromA1, want: none },
            { tag: "from C onto A's spread: A's workspace", p: [100, 600], src: fromC2, want: mon("RO-A", 1) },
            // local x 1000 in C's entry 0 (930 .. 1216.6667) = id 2, the source's own workspace
            { tag: "from C onto its own workspace in C's strip", p: [4440, 80], src: fromC2, want: none },
            { tag: "from C onto A's strip", p: [1700, 100], src: fromC2, want: ws("RO-A", 4, 1) },
            { tag: "from C onto C's spread: nothing", p: [4816, 700], src: fromC2, want: none },
        ];
    }
    function test_target(d) {
        const r = Drop.dropTarget(d.p[0], d.p[1], surfaces, d.src);
        compare(r.kind, d.want.kind, "kind " + JSON.stringify(r));
        if (d.want.kind !== "none") {
            compare(r.monitor, d.want.monitor, "monitor");
            compare(r.id, d.want.id, "id");
        }
        if (d.want.kind === "workspace") compare(r.index, d.want.index, "index");
    }

    function test_threshold_data() {
        return [
            { tag: "8 right: started", dx: 8, dy: 0, want: true },
            { tag: "8 up: started", dx: 0, dy: -8, want: true },
            { tag: "5,6 = 7.81: not yet", dx: 5, dy: 6, want: false },
            { tag: "6,6 = 8.49: started", dx: 6, dy: -6, want: true },
            { tag: "7.9 left: not yet", dx: -7.9, dy: 0, want: false },
            { tag: "no motion", dx: 0, dy: 0, want: false },
        ];
    }
    function test_threshold(d) {
        compare(Drop.DRAG_THRESHOLD, 8);
        compare(Drop.dragStarted(d.dx, d.dy), d.want);
    }

    // ---- close button: closeRect and hitTestOverlay ------------------------------------------------------------
    // Strip of A with 3 entries as above; tiles of M1 "A 2 tiles": w1 x 225.3913 .. 1708 (w 1482.6087), w2 1732 ..
    // 3214.6087, both y 216 .. 1416. closeRect(w1) = {1708 - 12, 216 - 12, 24, 24} = {1696, 204, 24, 24};
    // closeRect(w2) = {3202.6087, 204, 24, 24}.
    readonly property var tiles: [
        { id: "w1", x: 225.3913, y: 216, w: 1482.6087, h: 1200 },
        { id: "w2", x: 1732, y: 216, w: 1482.6087, h: 1200 },
    ]
    function test_close_rect() {
        compare(Hit.CLOSE_SIZE, 24);
        const r = Hit.closeRect(tiles[0]);
        verify(Math.abs(r.x - 1696) < 1e-4 && r.y === 204 && r.w === 24 && r.h === 24, JSON.stringify(r));
        const q = Hit.closeRect({ x: 10, y: 20, w: 100, h: 50 });
        compare(JSON.stringify(q), JSON.stringify({ x: 98, y: 8, w: 24, h: 24 }));
    }
    function test_overlay_hit_data() {
        return [
            { tag: "w1's button, outside the tile, w1 highlighted", p: [1700, 210], hl: "w1", want: { kind: "close", id: "w1" } },
            { tag: "same point, nothing highlighted", p: [1700, 210], hl: "", want: { kind: "none" } },
            { tag: "same point, w2 highlighted", p: [1700, 210], hl: "w2", want: { kind: "none" } },
            { tag: "button over the tile wins", p: [1700, 220], hl: "w1", want: { kind: "close", id: "w1" } },
            { tag: "w1's corner without its highlight is the tile", p: [1700, 220], hl: "w2", want: { kind: "window", id: "w1" } },
            { tag: "button top-left corner inclusive", p: [1696, 204], hl: "w1", want: { kind: "close", id: "w1" } },
            { tag: "button right edge excluded, spacing gap", p: [1720, 220], hl: "w1", want: { kind: "none" } },
            { tag: "button bottom edge excluded: the tile", p: [1700, 228], hl: "w1", want: { kind: "window", id: "w1" } },
            { tag: "w2's button", p: [3210, 210], hl: "w2", want: { kind: "close", id: "w2" } },
            { tag: "strip before everything", p: [1300, 50], hl: "w1", want: { kind: "workspace", index: 0 } },
            { tag: "unknown highlight: windows as usual", p: [300, 300], hl: "zz", want: { kind: "window", id: "w1" } },
            { tag: "nothing", p: [100, 1430], hl: "w1", want: { kind: "none" } },
        ];
    }
    function test_overlay_hit(d) {
        const r = Hit.hitTestOverlay(d.p[0], d.p[1], tiles, surfaces[0].strip, d.hl);
        compare(r.kind, d.want.kind, "kind " + JSON.stringify(r));
        if (d.want.id !== undefined) compare(r.id, d.want.id, "id");
        if (d.want.index !== undefined) compare(r.index, d.want.index, "index");
    }
}
