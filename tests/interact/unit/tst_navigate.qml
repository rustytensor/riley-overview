// SPDX-License-Identifier: GPL-3.0-or-later
// M3 gate: arrow-key navigation (shell/lib/navigate.mjs). Rules in docs/interact.md; expected values by hand below.
//
// navigate(rects, fromId, dir): no rects -> ""; fromId "" or unknown -> readingOrder first (by centre y, centre x,
// id); else candidates have their centre strictly beyond in dir; in-beam (overlap on the other axis, touching does
// not count) first, then the smaller centre distance, then the smaller id; no candidate -> fromId.
import QtQuick
import QtTest
import "../lib/navigate.mjs" as Nav
import "../lib/spread.mjs" as Spread
import "cases.mjs" as Cases

TestCase {
    name: "navigate"

    function rc(id, x, y, w, h) { return { id: id, x: x, y: y, w: w, h: h }; }

    // ---- "A 5" (tests/layout/cases.mjs) spread on A {24, 216, 3392, 1200}, spacing 24, MC even-size rule ---------
    // (docs/design.md "Spread layout: even sizes"; replaces M1's one common scale 1176/1370, which no longer holds
    // for windows of different sizes.) S = 3392*1200 = 4070400, A = S/5 = 814080. w1, w2 (1130x685, a 774050) and
    // w3 (1140x685, a 780900) are below A: t = 1. w4, w5 (1705x685, a 1167925): t4 = sqrt(814080/1167925) =
    // 0.834884. Cap: bmin = 774050, 9*bmin far above every tile, no change. Rows [w1 w2 w3], [w4 w5] (cases.mjs),
    // f = 1176/(685 + 685 t4) = 0.935639 (the vertical limit). Row 0: s = f, tiles 1057.2717 (w1, w2), 1066.6281
    // (w3) x 640.9125; width 3181.1715 + 48, x0 = 24 + (3392 - 3229.1715)/2 = 105.4142, x(w2) = 1186.6859,
    // x(w3) = 2267.9577, y 216. Row 1: s = t4 f = 0.781150, tiles 1331.8601 x 535.0875; width 2687.7202,
    // x0 = 24 + (3392 - 2687.7202)/2 = 376.1399, x(w5) = 1732, y = 216 + 640.9125 + 24 = 880.9125 (block ends 1416).
    // Centres: w1 (634.0501, 536.4562), w2 (1715.3218, 536.4562), w3 (2801.2717, 536.4562), w4 (1042.0699,
    // 1148.4562), w5 (2397.9301, 1148.4562).
    // x ranges: w1 105.41..1162.69, w2 1186.69..2243.96, w3 2267.96..3334.59, w4 376.14..1708.00, w5 1732..3063.86.
    readonly property real f5: 1176 / (685 + 685 * Math.sqrt(814080 / 1167925))
    readonly property var a5: {
        const f = f5, t4 = Math.sqrt(814080 / 1167925);
        const w12 = 1130 * f, w3 = 1140 * f, h0 = 685 * f, w45 = 1705 * t4 * f, h1 = 685 * t4 * f;
        const x0 = 24 + (3392 - (2 * w12 + w3 + 48)) / 2;
        const x1 = 24 + (3392 - (2 * w45 + 24)) / 2;   // row 1
        const y1 = 216 + h0 + 24;
        return [rc("w1", x0, 216, w12, h0), rc("w2", x0 + w12 + 24, 216, w12, h0),
                rc("w3", x0 + 2 * (w12 + 24), 216, w3, h0),
                rc("w4", x1, y1, w45, h1), rc("w5", x1 + w45 + 24, y1, w45, h1)];
    }
    // ---- M1 "A 12": 4x3 grid of 845x453 -> s = 1152/1359, tiles 716.2914 x 384 ---------------------------------
    // Row width 4*716.2914 + 72 = 2937.1656, x0 = 24 + (3392 - 2937.1656)/2 = 251.4172, column step 740.2914;
    // block 3*384 + 48 = 1200 -> row tops 216, 624, 1032. Ids g<row><col> as cases.mjs's grid().
    readonly property var a12: {
        const s = 1152 / 1359, w = 845 * s, h = 453 * s;
        const x0 = 24 + (3392 - (4 * w + 72)) / 2;
        const out = [];
        for (let r = 0; r < 3; r++)
            for (let c = 0; c < 4; c++)
                out.push(rc("g" + r + c, x0 + c * (w + 24), 216 + r * (h + 24), w, h));
        return out;
    }

    // The hand-worked rects above are the real spread of the M1 cases (spread.mjs is M1-gated): a slip in the
    // arithmetic here would show up as a mismatch, not as a navigation failure.
    function test_rects_are_the_m1_spreads_data() {
        return [{ tag: "A 5", c: "A 5", want: a5 }, { tag: "A 12", c: "A 12", want: a12 }];
    }
    function test_rects_are_the_m1_spreads(d) {
        const pc = Cases.propCases.find(c => c.tag === d.c);
        const out = Spread.spreadLayout(pc.windows, Cases.AREA.A, Cases.OPTS);
        for (const e of d.want) {
            const r = out.rects.find(q => q.id === e.id);
            verify(r, "no rect for " + e.id);
            for (const k of ["x", "y", "w", "h"])
                verify(Math.abs(r[k] - e[k]) < 1e-4, e.id + "." + k + " " + r[k] + " vs hand " + e[k]);
        }
    }

    // ---- key sequences: the highlight after each key, from no highlight ----------------------------------------
    // A 5 (centres and x ranges above; the same sequence as M1, worked again on the MC rects):
    //   down  -> w1   start: reading order w1 (cy 536.46, smallest cx)
    //   right -> w2   in beam (same row) w2 1081.27 away, w3 2167.22; w4, w5 out of beam
    //   down  -> w4   both in beam (x overlap with 1186.69..2243.96); w4 909.84 away, w5 916.79
    //   right -> w5   w5 in beam; w2, w3 (cx > 1042.07) out of beam
    //   up    -> w3   in beam w2 (916.79) and w3 (dx 403.34, dy 612 -> 732.96); w1 out of beam
    //   left  -> w2   w2 (1085.95) before w1 (in beam too, farther)
    //   left  -> w1
    //   left  -> w1   nothing left of w1
    //   up    -> w1   nothing above
    //   down  -> w4   in beam w4 (x 376.14..1708 overlaps 105.41..1162.69); w5 out
    //   down  -> w4   nothing below
    //   left  -> w1   no rect left in beam; w1 (cx 634.05 < 1042.07) is the only candidate, out of beam
    // A 12 (a full grid: the in-beam neighbour is always the next tile in the row or column):
    //   up -> g00 (start), right g01, right g02, right g03, right g03 (edge), down g13, down g23, down g23 (edge),
    //   left g22, up g12, left g11, up g01, left g00
    function test_sequence_data() {
        return [
            { tag: "A 5", rects: a5,
              keys: ["down", "right", "down", "right", "up", "left", "left", "left", "up", "down", "down", "left"],
              want: ["w1", "w2", "w4", "w5", "w3", "w2", "w1", "w1", "w1", "w4", "w4", "w1"] },
            { tag: "A 12", rects: a12,
              keys: ["up", "right", "right", "right", "right", "down", "down", "down", "left", "up", "left", "up", "left"],
              want: ["g00", "g01", "g02", "g03", "g03", "g13", "g23", "g23", "g22", "g12", "g11", "g01", "g00"] },
        ];
    }
    function test_sequence(d) {
        let cur = "";
        const got = [];
        for (const k of d.keys) {
            cur = Nav.navigate(d.rects, cur, k);
            got.push(cur);
        }
        compare(JSON.stringify(got), JSON.stringify(d.want));
    }

    // ---- the rules one at a time, on literal rects -------------------------------------------------------------
    // m {400, 400, 100, 100}: centre (450, 450), y and x ranges 400..500.
    readonly property var m: rc("m", 400, 400, 100, 100)
    function test_rules_data() {
        return [
            // out of beam both (y 100..200 and 700..800), centres (650, 150) and (650, 750): equal distance
            // sqrt(200^2 + 300^2) -> the smaller id
            { tag: "tie out of beam: smaller id", rects: [m, rc("zz", 600, 100, 100, 100), rc("aa", 600, 700, 100, 100)],
              from: "m", dir: "right", want: "aa" },
            // far: centre (1050, 470), y 420..520 in beam, 600.33 away; near: centre (650, 650), y 600..700, 282.84 away
            { tag: "in beam beats nearer", rects: [m, rc("near", 600, 600, 100, 100), rc("far", 1000, 420, 100, 100)],
              from: "m", dir: "right", want: "far" },
            // t: y 500..600 only touches m's 400..500 -> out of beam (316.23 away) -> far (in beam) wins
            { tag: "touching edges are not in beam", rects: [m, rc("t", 700, 500, 100, 100), rc("far", 1000, 420, 100, 100)],
              from: "m", dir: "right", want: "far" },
            // b1 centre (750, 500), b2 (750, 400): both in beam, both sqrt(300^2 + 50^2) away -> b1
            { tag: "tie in beam: smaller id", rects: [m, rc("b2", 700, 350, 100, 100), rc("b1", 700, 450, 100, 100)],
              from: "m", dir: "right", want: "b1" },
            // s centre (450, 750): same centre x as m -> no candidate to the right; below it is
            { tag: "equal centre x is not to the right", rects: [m, rc("s", 400, 700, 100, 100)], from: "m", dir: "right", want: "m" },
            { tag: "but it is below", rects: [m, rc("s", 400, 700, 100, 100)], from: "m", dir: "down", want: "s" },
            { tag: "up from m to s? no: s is below", rects: [m, rc("s", 400, 700, 100, 100)], from: "m", dir: "up", want: "m" },
            // left: l centre (150, 450) in beam, 300 away; u centre (450, 150) is above, not left
            { tag: "left", rects: [m, rc("l", 100, 400, 100, 100), rc("u", 400, 100, 100, 100)], from: "m", dir: "left", want: "l" },
            { tag: "up", rects: [m, rc("l", 100, 400, 100, 100), rc("u", 400, 100, 100, 100)], from: "m", dir: "up", want: "u" },
            // start rule: centres q (550, 50), p (50, 50), r (50, 50): cy 50 all, cx 50 for p and r, id p < r
            { tag: "start: reading order, ties by id", rects: [rc("q", 500, 0, 100, 100), rc("r", 0, 10, 100, 80), rc("p", 0, 0, 100, 100)],
              from: "", dir: "down", want: "p" },
            { tag: "start from an unknown id", rects: [rc("q", 500, 0, 100, 100), rc("p", 0, 0, 100, 100)],
              from: "gone", dir: "left", want: "p" },
            { tag: "no rects", rects: [], from: "", dir: "right", want: "" },
            { tag: "no rects, stale id", rects: [], from: "gone", dir: "right", want: "" },
            { tag: "alone: stays", rects: [m], from: "m", dir: "right", want: "m" },
        ];
    }
    function test_rules(d) {
        compare(Nav.navigate(d.rects, d.from, d.dir), d.want);
    }

    function test_reading_order() {
        // centres: c (150, 350), a (650, 150), b (150, 150), d (150, 150) -> by cy: a, b, d (cy 150), then c;
        // among cy 150 by cx: b and d (150) before a (650); b < d by id
        const rs = [rc("c", 100, 300, 100, 100), rc("a", 600, 100, 100, 100), rc("d", 100, 100, 100, 100), rc("b", 50, 50, 200, 200)];
        compare(JSON.stringify(Nav.readingOrder(rs)), JSON.stringify(["b", "d", "a", "c"]));
        compare(JSON.stringify(Nav.readingOrder([])), "[]");
    }

    function test_input_not_modified() {
        const rs = [rc("x", 0, 0, 10, 10), rc("y", 20, 0, 10, 10)];
        const before = JSON.stringify(rs);
        Nav.navigate(rs, "x", "right");
        Nav.readingOrder(rs);
        compare(JSON.stringify(rs), before);
    }
}
