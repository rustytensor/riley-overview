// SPDX-License-Identifier: GPL-3.0-or-later
// M1 gate: spread layout (shell/lib/spread.mjs). Inputs and hand-worked expected values: cases.mjs.
import QtQuick
import QtTest
import "../lib/spread.mjs" as Spread
import "checks.mjs" as Checks
import "cases.mjs" as Cases

TestCase {
    name: "spread"

    function all() { return Cases.exactCases.concat(Cases.propCases); }
    function rows(list) { return list.map((c, i) => ({ tag: c.tag, i: i })); }
    function run(c) {
        const input = JSON.parse(JSON.stringify(c.windows));
        const out = Spread.spreadLayout(input, Cases.AREA[c.mon], Cases.OPTS);
        compare(JSON.stringify(input), JSON.stringify(c.windows), "spreadLayout modified its input");
        return out;
    }
    function ok(msg) { verify(msg === null, msg === null ? "" : msg); }

    // Exact rects, scale and rows for the 1- and 2-window cases.
    function test_exact_data() { return rows(Cases.exactCases); }
    function test_exact(d) {
        const c = Cases.exactCases[d.i], out = run(c);
        ok(Checks.sameWindows(c.windows, out));
        verify(Checks.near(out.scale, c.scale, 1e-6), "scale " + out.scale + ", want " + c.scale);
        compare(out.rows, c.rows, "rows");
        ok(Checks.rectsEqual(out, c.rects));
    }

    // Expected scale and row count, all cases (hand-worked in cases.mjs).
    function test_scale_rows_data() { return rows(all()); }
    function test_scale_rows(d) {
        const c = all()[d.i], out = run(c);
        verify(Checks.near(out.scale, c.scale, 1e-6), "scale " + out.scale + ", want " + c.scale);
        compare(out.rows, c.rows, "rows");
    }

    function test_windows_data() { return rows(all()); }
    function test_windows(d) { const c = all()[d.i]; ok(Checks.sameWindows(c.windows, run(c))); }

    function test_no_overlap_data() { return rows(all()); }
    function test_no_overlap(d) { const c = all()[d.i]; ok(Checks.noOverlap(run(c), Cases.OPTS.spacing)); }

    function test_inside_data() { return rows(all()); }
    function test_inside(d) { const c = all()[d.i]; ok(Checks.inside(run(c), Cases.AREA[c.mon])); }

    function test_aspect_data() { return rows(all()); }
    function test_aspect(d) { const c = all()[d.i]; ok(Checks.aspectKept(c.windows, run(c))); }

    function test_not_larger_data() { return rows(all()); }
    function test_not_larger(d) { const c = all()[d.i]; ok(Checks.notLarger(c.windows, run(c))); }

    function test_one_scale_data() { return rows(all()); }
    function test_one_scale(d) { const c = all()[d.i]; ok(Checks.uniformScale(c.windows, run(c), Cases.OPTS.maxScale)); }

    function test_order_data() { return rows(all()); }
    function test_order(d) { const c = all()[d.i]; ok(Checks.orderKept(c.windows, run(c))); }

    // No windows: no rects, zero rows.
    function test_empty() {
        const out = Spread.spreadLayout([], Cases.AREA.A, Cases.OPTS);
        compare(out.rects.length, 0);
        compare(out.rows, 0);
    }
}
