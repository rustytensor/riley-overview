// SPDX-License-Identifier: GPL-3.0-or-later
// MC layout gate: the Spaces-style desktops bar (shell/lib/desktops.mjs) and the drop target on its previews
// (shell/lib/drop.mjs). Expected values worked out by hand below, before any run.
//
// Rules (docs/design.md "Desktops bar"), config defaults: margin 24, strip height 120, strip spacing 16.
//   band = {margin, margin, W - 2*margin, stripHeight}; zone = band in both states.
//   expanded: rects = stripGeometry's (tst_strip.qml): thumbnail h = 120, w = 120*W/H, shrunk to fit the band
//             when the row is too wide, the row centred in the band both ways.
//   collapsed: the same x and w, y = band.y = 24, h = min(NAMES_HEIGHT = 28, stripHeight) = 28.
//   plus: true only for the last entry (index count-1: the empty workspace, drawn as "+").
//   barExpanded(px, py, band, dragging) = dragging || band holds the point (x <= px < x+w, y <= py < y+h).
import QtQuick
import QtTest
import "../lib/desktops.mjs" as Desk
import "../lib/drop.mjs" as Drop
import "checks.mjs" as Checks

TestCase {
    name: "desktops"

    readonly property var cfg: ({ margin: 24, stripHeight: 120, stripSpacing: 16, sectionGap: 16, searchHeight: 40 })

    // A 3440x1440, 3 entries: w = 860/3 = 286.6667; row 892; x0 = 24 + (3392-892)/2 = 1274; step 908/3.
    // B 1440x2560, 3 entries: w = 67.5; row 234.5; x0 = 24 + (1392-234.5)/2 = 602.75; step 83.5.
    // C 2752x1152, 2 entries: w = 286.6667; row 589.3333; x0 = 24 + (2704-589.3333)/2 = 1081.3333; x1 = 1384.
    // D 1152x2048, 20 entries: 20*67.5 + 19*16 = 1654 > 1104 -> w = (1104-304)/20 = 40, h = 40*2048/1152 = 71.1111,
    //   x0 = 24, step 56, expanded y = 24 + (120-71.1111)/2 = 48.4444.
    // A 3440x1440, 1 entry (only "+"): x = 24 + (3392 - 286.6667)/2 = 1576.6667.
    function cases() {
        return [
            { tag: "A 3", W: 3440, H: 1440, n: 3, x0: 1274, step: 908 / 3, w: 860 / 3, h: 120, y: 24 },
            { tag: "B 3", W: 1440, H: 2560, n: 3, x0: 602.75, step: 83.5, w: 67.5, h: 120, y: 24 },
            { tag: "C 2", W: 2752, H: 1152, n: 2, x0: 24 + (2704 - (1720 / 3 + 16)) / 2, step: 908 / 3, w: 860 / 3, h: 120, y: 24 },
            { tag: "D 20", W: 1152, H: 2048, n: 20, x0: 24, step: 56, w: 40, h: 40 * 2048 / 1152, y: 24 + (120 - 40 * 2048 / 1152) / 2 },
            { tag: "A 1", W: 3440, H: 1440, n: 1, x0: 24 + (3392 - 860 / 3) / 2, step: 0, w: 860 / 3, h: 120, y: 24 },
        ];
    }
    function rows(list) { return list.map((c, i) => ({ tag: c.tag, i: i })); }
    function near(a, b) { return Math.abs(a - b) <= 1e-4; }
    function checkRects(out, c, expanded) {
        compare(out.rects.length, c.n, "rect count");
        compare(out.expanded, expanded, "expanded flag");
        for (let i = 0; i < c.n; i++) {
            const r = out.rects[i];
            const want = expanded ? { x: c.x0 + i * c.step, y: c.y, w: c.w, h: c.h }
                                  : { x: c.x0 + i * c.step, y: 24, w: c.w, h: 28 };
            compare(r.index, i, "index");
            for (const k of ["x", "y", "w", "h"])
                verify(near(r[k], want[k]), (expanded ? "expanded" : "collapsed") + " rect " + i + "." + k + " = " +
                       r[k] + ", want " + want[k]);
            compare(r.plus, i === c.n - 1, "plus on rect " + i);
        }
        const b = { x: 24, y: 24, w: c.W - 48, h: 120 };
        for (const k of ["x", "y", "w", "h"]) {
            verify(near(out.band[k], b[k]), "band." + k + " = " + out.band[k] + ", want " + b[k]);
            verify(near(out.zone[k], b[k]), "zone." + k + " = " + out.zone[k] + ", want " + b[k]);
        }
    }

    function test_names_height() { compare(Desk.NAMES_HEIGHT, 28); }

    function test_expanded_data() { return rows(cases()); }
    function test_expanded(d) {
        const c = cases()[d.i];
        checkRects(Desk.desktopsBar(c.W, c.H, c.n, cfg, true), c, true);
    }

    function test_collapsed_data() { return rows(cases()); }
    function test_collapsed(d) {
        const c = cases()[d.i];
        checkRects(Desk.desktopsBar(c.W, c.H, c.n, cfg, false), c, false);
    }

    // Band A {24, 24, 3392, 120}: x in [24, 3416), y in [24, 144).
    function test_bar_expanded_data() {
        return [
            { tag: "top-left corner", px: 24, py: 24, drag: false, want: true },
            { tag: "inside near bottom-right", px: 3415.9, py: 143.9, drag: false, want: true },
            { tag: "names row", px: 1700, py: 40, drag: false, want: true },
            { tag: "right edge excluded", px: 3416, py: 50, drag: false, want: false },
            { tag: "bottom edge excluded", px: 100, py: 144, drag: false, want: false },
            { tag: "above the band", px: 100, py: 23.9, drag: false, want: false },
            { tag: "spread, no drag", px: 2000, py: 600, drag: false, want: false },
            { tag: "spread, dragging", px: 2000, py: 600, drag: true, want: true },
        ];
    }
    function test_bar_expanded(d) {
        compare(Desk.barExpanded(d.px, d.py, { x: 24, y: 24, w: 3392, h: 120 }, d.drag), d.want);
    }

    // Drop on a preview. Surfaces built from desktopsBar(expanded) with ids merged in strip order:
    //   RO-A at 0,0, 3440x1440, current workspace 1, entries ids [1, 2, 3] (3 = "+"): x 1274, 1576.6667, 1879.3333,
    //        y 24..144, w 286.6667.
    //   RO-C at 3440,0, 2752x1152, current workspace 4, entries [4, 5]: x 1081.3333, 1384, y 24..144.
    //   The dragged window is on RO-A, workspace 1.
    //   (1700, 80): 1576.6667 <= 1700 < 1863.3333 -> RO-A id 2 index 1.
    //   (1700, 140): below the names row (24..52) but in the preview (24..144) -> RO-A id 2 index 1.
    //   (1880, 100): 1879.3333 <= 1880 -> the "+" entry, RO-A id 3 index 2.
    //   (1870, 80): the gap 1863.3333..1879.3333 on the source monitor -> none.
    //   (1300, 80): the source's own workspace 1 -> none.
    //   (3440 + 1400, 50): RO-C local (1400, 50), 1384 <= 1400 < 1670.6667 -> RO-C id 5 index 1.
    //   (3440 + 1000, 600): RO-C away from its bar -> monitor RO-C, its workspace 4.
    function surfaces() {
        const a = Desk.desktopsBar(3440, 1440, 3, cfg, true).rects, c = Desk.desktopsBar(2752, 1152, 2, cfg, true).rects;
        const ids = (rs, list) => rs.map((r, i) => ({ index: r.index, id: list[i], x: r.x, y: r.y, w: r.w, h: r.h }));
        return [
            { monitor: "RO-A", x: 0, y: 0, w: 3440, h: 1440, workspace: 1, strip: ids(a, [1, 2, 3]) },
            { monitor: "RO-C", x: 3440, y: 0, w: 2752, h: 1152, workspace: 4, strip: ids(c, [4, 5]) },
        ];
    }
    function test_drop_data() {
        return [
            { tag: "preview 2", px: 1700, py: 80, want: { kind: "workspace", monitor: "RO-A", id: 2, index: 1 } },
            { tag: "preview 2 below the names row", px: 1700, py: 140,
              want: { kind: "workspace", monitor: "RO-A", id: 2, index: 1 } },
            { tag: "plus", px: 1880, py: 100, want: { kind: "workspace", monitor: "RO-A", id: 3, index: 2 } },
            { tag: "gap", px: 1870, py: 80, want: { kind: "none" } },
            { tag: "own workspace", px: 1300, py: 80, want: { kind: "none" } },
            { tag: "RO-C preview 5", px: 4840, py: 50, want: { kind: "workspace", monitor: "RO-C", id: 5, index: 1 } },
            { tag: "RO-C spread", px: 4440, py: 600, want: { kind: "monitor", monitor: "RO-C", id: 4 } },
        ];
    }
    function test_drop(d) {
        const got = Drop.dropTarget(d.px, d.py, surfaces(), { monitor: "RO-A", workspace: 1 });
        compare(JSON.stringify(got), JSON.stringify(d.want));
    }
}
