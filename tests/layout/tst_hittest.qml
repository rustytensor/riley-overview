// SPDX-License-Identifier: GPL-3.0-or-later
// M1 gate: hit-testing (shell/lib/hittest.mjs). Points picked by hand against literal rects.
//
// Rules (docs/design.md "Hit-testing"): a rect holds a point when x <= px < x+w and y <= py < y+h. The strip is drawn
// above the windows, so strip rects are tested first; a point in a strip gap falls through to the windows. Window
// rects are listed bottom to top: the last one holding the point wins.
import QtQuick
import QtTest
import "../lib/hittest.mjs" as Hit

TestCase {
    name: "hittest"

    // Strip of A with 3 workspaces (tst_strip.qml): x 1274, 1576.6667, 1879.3333; w 286.6667; y 24; h 120.
    readonly property var strip: [
        { index: 0, x: 1274, y: 24, w: 860 / 3, h: 120 },
        { index: 1, x: 1274 + 908 / 3, y: 24, w: 860 / 3, h: 120 },
        { index: 2, x: 1274 + 2 * 908 / 3, y: 24, w: 860 / 3, h: 120 },
    ]
    // Spread of "A 2 tiles" (cases.mjs): w1 x 225.3913..1708.0000, w2 x 1732.0000..3214.6087, y 216..1416.
    readonly property var tiles: [
        { id: "w1", x: 225.3913, y: 216, w: 1482.6087, h: 1200 },
        { id: "w2", x: 1732, y: 216, w: 1482.6087, h: 1200 },
    ]
    // Two overlapping rects (as during the open animation): a under b. Overlap x 300..500, y 400..600.
    readonly property var stacked: [
        { id: "a", x: 100, y: 300, w: 400, h: 300 },
        { id: "b", x: 300, y: 400, w: 400, h: 300 },
    ]
    readonly property var big: [{ id: "big", x: 0, y: 0, w: 3440, h: 1440 }]

    function test_hit_data() {
        return [
            { tag: "strip ws0 inside", px: 1300, py: 50, win: tiles, e: { kind: "workspace", index: 0 } },
            { tag: "strip ws0 left top corner", px: 1274, py: 24, win: tiles, e: { kind: "workspace", index: 0 } },
            { tag: "strip ws0 just above bottom", px: 1274, py: 143.9, win: tiles, e: { kind: "workspace", index: 0 } },
            { tag: "strip ws0 bottom edge excluded", px: 1274, py: 144, win: tiles, e: { kind: "none" } },
            // gap between ws0 (ends 1560.6667) and ws1 (starts 1576.6667)
            { tag: "strip gap 0-1", px: 1568, py: 80, win: tiles, e: { kind: "none" } },
            { tag: "strip ws1", px: 1700, py: 100, win: tiles, e: { kind: "workspace", index: 1 } },
            { tag: "strip ws2 top edge", px: 1880, py: 24, win: tiles, e: { kind: "workspace", index: 2 } },
            // ws2 ends at 1274 + 2*908/3 + 860/3 = 2166
            { tag: "strip ws2 right edge excluded", px: 2166, py: 80, win: tiles, e: { kind: "none" } },
            { tag: "left of strip", px: 100, py: 80, win: tiles, e: { kind: "none" } },
            { tag: "window w1", px: 300, py: 300, win: tiles, e: { kind: "window", id: "w1" } },
            { tag: "window w1 near bottom", px: 1000, py: 1415.9, win: tiles, e: { kind: "window", id: "w1" } },
            { tag: "below w1", px: 1000, py: 1416, win: tiles, e: { kind: "none" } },
            // spacing gap between w1 (ends 1708.0000) and w2 (starts 1732)
            { tag: "spacing gap w1-w2", px: 1720, py: 600, win: tiles, e: { kind: "none" } },
            { tag: "window w2 top left", px: 1732, py: 216, win: tiles, e: { kind: "window", id: "w2" } },
            { tag: "right of w2", px: 3300, py: 600, win: tiles, e: { kind: "none" } },
            { tag: "outside monitor", px: -5, py: 600, win: tiles, e: { kind: "none" } },
            { tag: "overlap goes to topmost b", px: 350, py: 450, win: stacked, e: { kind: "window", id: "b" } },
            { tag: "a only", px: 150, py: 350, win: stacked, e: { kind: "window", id: "a" } },
            { tag: "b only", px: 650, py: 650, win: stacked, e: { kind: "window", id: "b" } },
            { tag: "beside a, above b", px: 600, py: 350, win: stacked, e: { kind: "none" } },
            { tag: "strip above a window", px: 1300, py: 50, win: big, e: { kind: "workspace", index: 0 } },
            { tag: "strip gap falls to window", px: 1568, py: 80, win: big, e: { kind: "window", id: "big" } },
        ];
    }
    function test_hit(d) {
        const r = Hit.hitTest(d.px, d.py, d.win, strip);
        compare(r.kind, d.e.kind, "kind");
        if (d.e.kind === "window") compare(r.id, d.e.id, "id");
        if (d.e.kind === "workspace") compare(r.index, d.e.index, "index");
    }

    // An empty strip and no windows: nothing is hit.
    function test_empty() {
        compare(Hit.hitTest(10, 10, [], []).kind, "none");
    }
}
