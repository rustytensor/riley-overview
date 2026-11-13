// SPDX-License-Identifier: GPL-3.0-or-later
// M1 gate: safe area and workspace strip geometry (shell/lib/strip.mjs). Expected values worked out by hand below.
//
// Geometry (docs/design.md "Geometry"), config defaults: margin 24, strip height 120, strip spacing 16, section gap
// 16, search height 40.
//   band = {x: margin, y: margin, w: W - 2*margin, h: stripHeight}
//   thumbnail: h = stripHeight, w = h * W/H (the monitor's aspect); if count*w + (count-1)*spacing > band.w, then
//   w = (band.w - (count-1)*spacing)/count and h = w * H/W. The row of thumbnails is centred in the band both ways.
//   count = the monitor's workspaces plus one empty one at the end (the caller passes the total).
import QtQuick
import QtTest
import "../lib/strip.mjs" as Strip
import "../lib/config.mjs" as Config
import "checks.mjs" as Checks

TestCase {
    name: "strip"

    readonly property var cfg: ({ margin: 24, stripHeight: 120, stripSpacing: 16, sectionGap: 16, searchHeight: 40 })

    // A 3440x1440: thumbnail 120 * 3440/1440 = 860/3 = 286.6667 wide, 120 high; band.w = 3392.
    //   3: row 3*860/3 + 2*16 = 892; x0 = 24 + (3392-892)/2 = 1274; step 860/3 + 16 = 302.6667.
    //   5: row 4300/3 + 64 = 1497.3333; x0 = 24 + (3392 - 1497.3333)/2 = 971.3333.
    // B 1440x2560: thumbnail 120 * 1440/2560 = 67.5 wide; band.w = 1392; step 83.5.
    //   3: row 202.5 + 32 = 234.5; x0 = 24 + (1392-234.5)/2 = 602.75.
    //   5: row 337.5 + 64 = 401.5; x0 = 24 + (1392-401.5)/2 = 519.25.
    // C 2752x1152 (same aspect as A): thumbnail 286.6667; band.w = 2704.
    //   3: x0 = 24 + (2704-892)/2 = 930.   5: x0 = 24 + (2704-1497.3333)/2 = 627.3333.
    // D 1152x2048 (same aspect as B): thumbnail 67.5; band.w = 1104.
    //   3: x0 = 24 + (1104-234.5)/2 = 458.75.   5: x0 = 24 + (1104-401.5)/2 = 375.25.
    // D with 20 workspaces: 20*67.5 + 19*16 = 1654 > 1104, so w = (1104 - 304)/20 = 40, h = 40*2048/1152 =
    //   71.1111; row 800+304 = 1104 -> x0 = 24; y = 24 + (120 - 71.1111)/2 = 48.4444; step 56.
    function stripCases() {
        return [
            { tag: "A 3", W: 3440, H: 1440, n: 3, x0: 1274, step: 860 / 3 + 16, w: 860 / 3, h: 120, y: 24 },
            { tag: "A 5", W: 3440, H: 1440, n: 5, x0: 24 + (3392 - (4300 / 3 + 64)) / 2, step: 860 / 3 + 16, w: 860 / 3, h: 120, y: 24 },
            { tag: "B 3", W: 1440, H: 2560, n: 3, x0: 602.75, step: 83.5, w: 67.5, h: 120, y: 24 },
            { tag: "B 5", W: 1440, H: 2560, n: 5, x0: 519.25, step: 83.5, w: 67.5, h: 120, y: 24 },
            { tag: "C 3", W: 2752, H: 1152, n: 3, x0: 930, step: 860 / 3 + 16, w: 860 / 3, h: 120, y: 24 },
            { tag: "C 5", W: 2752, H: 1152, n: 5, x0: 24 + (2704 - (4300 / 3 + 64)) / 2, step: 860 / 3 + 16, w: 860 / 3, h: 120, y: 24 },
            { tag: "D 3", W: 1152, H: 2048, n: 3, x0: 458.75, step: 83.5, w: 67.5, h: 120, y: 24 },
            { tag: "D 5", W: 1152, H: 2048, n: 5, x0: 375.25, step: 83.5, w: 67.5, h: 120, y: 24 },
            { tag: "D 20 shrunk", W: 1152, H: 2048, n: 20, x0: 24, step: 56, w: 40, h: 40 * 2048 / 1152, y: 24 + (120 - 40 * 2048 / 1152) / 2 },
        ];
    }

    function test_strip_data() { return stripCases().map((c, i) => ({ tag: c.tag, i: i })); }
    function test_strip(d) {
        const c = stripCases()[d.i];
        const g = Strip.stripGeometry(c.W, c.H, c.n, cfg);
        compare(g.rects.length, c.n, "rect count");
        verify(Checks.near(g.band.x, 24) && Checks.near(g.band.y, 24) && Checks.near(g.band.w, c.W - 48) &&
               Checks.near(g.band.h, 120), "band " + JSON.stringify(g.band));
        verify(Checks.near(g.thumbW, c.w) && Checks.near(g.thumbH, c.h), "thumb " + g.thumbW + "x" + g.thumbH);
        for (let i = 0; i < c.n; i++) {
            const r = g.rects[i];
            compare(r.index, i, "index");
            verify(Checks.near(r.x, c.x0 + i * c.step), "rect " + i + " x " + r.x + ", want " + (c.x0 + i * c.step));
            verify(Checks.near(r.y, c.y), "rect " + i + " y " + r.y + ", want " + c.y);
            verify(Checks.near(r.w, c.w) && Checks.near(r.h, c.h), "rect " + i + " size " + r.w + "x" + r.h);
        }
    }

    // Safe area = monitor minus margins, strip, search field and gaps: y = 24 + 120 + 16 + 40 + 16 = 216.
    //   A {24, 216, 3392, 1200}; B {24, 216, 1392, 2320}; C {24, 216, 2704, 912}; D {24, 216, 1104, 1808}.
    // With tests/layout/data/valid.xml (margin 32, strip 100, gap 20, search 44) on A:
    //   y = 32 + 100 + 20 + 44 + 20 = 216, x = 32, w = 3440 - 64 = 3376, h = 1440 - 216 - 32 = 1192.
    function test_safe_area_data() {
        return [
            { tag: "A", W: 3440, H: 1440, c: cfg, e: [24, 216, 3392, 1200] },
            { tag: "B", W: 1440, H: 2560, c: cfg, e: [24, 216, 1392, 2320] },
            { tag: "C", W: 2752, H: 1152, c: cfg, e: [24, 216, 2704, 912] },
            { tag: "D", W: 1152, H: 2048, c: cfg, e: [24, 216, 1104, 1808] },
            { tag: "A defaults object", W: 3440, H: 1440, c: Config.DEFAULTS, e: [24, 216, 3392, 1200] },
            { tag: "A valid.xml values", W: 3440, H: 1440,
              c: { margin: 32, stripHeight: 100, stripSpacing: 12, sectionGap: 20, searchHeight: 44 }, e: [32, 216, 3376, 1192] },
        ];
    }
    function test_safe_area(d) {
        const a = Strip.safeArea(d.W, d.H, d.c);
        compare([a.x, a.y, a.w, a.h], d.e);
    }
}
