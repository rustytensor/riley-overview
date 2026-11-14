// SPDX-License-Identifier: GPL-3.0-or-later
// Layout gate: spread layout (shell/lib/spread.mjs), the even-size rule of MC (docs/design.md "Spread layout: even
// sizes"). Inputs and hand-worked expected values: cases.mjs.
import QtQuick
import QtTest
import "../lib/spread.mjs" as Spread
import "checks.mjs" as Checks
import "cases.mjs" as Cases

TestCase {
    name: "spread"

    function all() { return Cases.exactCases.concat(Cases.propCases); }
    function rows(list) { return list.map((c, i) => ({ tag: c.tag, i: i })); }
    function opts(c) { return c.opts || Cases.OPTS; }
    function run(c) {
        const input = JSON.parse(JSON.stringify(c.windows));
        const out = Spread.spreadLayout(input, Cases.AREA[c.mon], opts(c));
        compare(JSON.stringify(input), JSON.stringify(c.windows), "spreadLayout modified its input");
        return out;
    }
    function ok(msg) { verify(msg === null, msg === null ? "" : msg); }

    // Exact rects for the 1-window, 2-window, full-screen + 2 small and cap cases.
    function test_exact_data() { return rows(Cases.exactCases); }
    function test_exact(d) {
        const c = Cases.exactCases[d.i], out = run(c);
        ok(Checks.sameWindows(c.windows, out));
        ok(Checks.rectsEqual(out, c.rects));
    }

    // Expected rows and every window's scale, all cases (hand-worked in cases.mjs).
    function test_scales_rows_data() { return rows(all()); }
    function test_scales_rows(d) {
        const c = all()[d.i], out = run(c);
        compare(out.rows, c.rows, "rows");
        ok(Checks.scalesEqual(out, c.scales));
    }

    function test_windows_data() { return rows(all()); }
    function test_windows(d) { const c = all()[d.i]; ok(Checks.sameWindows(c.windows, run(c))); }

    function test_no_overlap_data() { return rows(all()); }
    function test_no_overlap(d) { const c = all()[d.i]; ok(Checks.noOverlap(run(c), opts(c).spacing)); }

    function test_inside_data() { return rows(all()); }
    function test_inside(d) { const c = all()[d.i]; ok(Checks.inside(run(c), Cases.AREA[c.mon])); }

    function test_aspect_data() { return rows(all()); }
    function test_aspect(d) { const c = all()[d.i]; ok(Checks.aspectKept(c.windows, run(c))); }

    // Never above 1.0 of the window (no upscaled live image).
    function test_not_larger_data() { return rows(all()); }
    function test_not_larger(d) { const c = all()[d.i]; ok(Checks.notLarger(c.windows, run(c))); }

    // Each rect is its window times its own reported scale, at most maxScale; top-level scale = the largest.
    function test_own_scale_data() { return rows(all()); }
    function test_own_scale(d) { const c = all()[d.i]; ok(Checks.ownScale(c.windows, run(c), opts(c).maxScale)); }

    // Largest / smallest tile area at most the cap (9, docs/design.md).
    function test_area_ratio_data() { return rows(all()); }
    function test_area_ratio(d) { const c = all()[d.i]; ok(Checks.areaRatio(run(c), Cases.CAP)); }

    function test_order_data() { return rows(all()); }
    function test_order(d) { const c = all()[d.i]; ok(Checks.orderKept(c.windows, run(c))); }

    // No windows: no rects, zero rows, scale maxScale, fit 1.
    function test_empty() {
        const out = Spread.spreadLayout([], Cases.AREA.A, Cases.OPTS);
        compare(out.rects.length, 0);
        compare(out.rows, 0);
        compare(out.scale, 1);
        compare(out.fit, 1);
    }
}
