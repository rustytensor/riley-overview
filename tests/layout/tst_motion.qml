// SPDX-License-Identifier: GPL-3.0-or-later
// MC layout gate: the open/close zoom (shell/lib/motion.mjs). Expected values worked out by hand below.
//
// Rules (docs/design.md "Motion"): easeOutCubic(p) = 1 - (1 - p)^3, p clamped to [0, 1];
// zoomRect(from, to, p) = from + easeOutCubic(p) * (to - from), per field x, y, w, h.
//   p 0.25: 1 - 0.75^3 = 1 - 0.421875 = 0.578125.   p 0.5: 1 - 0.125 = 0.875.   p 0.75: 1 - 0.015625 = 0.984375.
//   from {0, 0, 1720, 1440} (a tiled window's real rect), to {440, 216, 1280, 1064}:
//   p 0.5: x = 0.875*440 = 385, y = 0.875*216 = 189, w = 1720 - 0.875*440 = 1335, h = 1440 - 0.875*376 = 1111.
//   (A linear move would give x 220 at p 0.5: a fault there is caught.)
import QtQuick
import QtTest
import "../lib/motion.mjs" as Motion

TestCase {
    name: "motion"

    function test_ease_data() {
        return [
            { tag: "0", p: 0, want: 0 }, { tag: "0.25", p: 0.25, want: 0.578125 }, { tag: "0.5", p: 0.5, want: 0.875 },
            { tag: "0.75", p: 0.75, want: 0.984375 }, { tag: "1", p: 1, want: 1 },
            { tag: "below 0 clamps", p: -0.5, want: 0 }, { tag: "above 1 clamps", p: 1.5, want: 1 },
        ];
    }
    function test_ease(d) {
        const got = Motion.easeOutCubic(d.p);
        verify(Math.abs(got - d.want) <= 1e-9, "easeOutCubic(" + d.p + ") = " + got + ", want " + d.want);
    }

    function test_zoom_data() {
        return [
            { tag: "start", p: 0, want: { x: 0, y: 0, w: 1720, h: 1440 } },
            { tag: "half", p: 0.5, want: { x: 385, y: 189, w: 1335, h: 1111 } },
            { tag: "end", p: 1, want: { x: 440, y: 216, w: 1280, h: 1064 } },
        ];
    }
    function test_zoom(d) {
        const from = { x: 0, y: 0, w: 1720, h: 1440 }, to = { x: 440, y: 216, w: 1280, h: 1064 };
        const got = Motion.zoomRect(from, to, d.p);
        for (const k of ["x", "y", "w", "h"])
            verify(Math.abs(got[k] - d.want[k]) <= 1e-6, k + " = " + got[k] + ", want " + d.want[k]);
        compare(JSON.stringify(from), JSON.stringify({ x: 0, y: 0, w: 1720, h: 1440 }), "zoomRect modified from");
    }
}
