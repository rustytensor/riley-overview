// SPDX-License-Identifier: GPL-3.0-or-later
//
// Spread layout gate inputs, with every expected value worked out by hand before any run.
// MC (2026-11-13): the spread follows the even-size rule of docs/design.md "Spread layout: even sizes" (Marc's new
// spec), which replaced M1's one common scale. In short, with n windows, a_i = w_i*h_i and S = area.w*area.h:
//   A = S/n; t_i = min(maxScale, sqrt(A/a_i)); with b_i = t_i^2*a_i, t_i = min(t_i, sqrt(CAP*min(b)/a_i)), CAP = 9;
//   then M1's row packing on the pre-scaled sizes t_i*w_i x t_i*h_i (real centres for the order):
//   sort by (centre y, centre x, id); for r = 1..n split greedily into at most r rows by pre-scaled width
//   (ideal = sum/r; a window joins while the row is empty, or the row plus it fits the ideal, or adding it brings
//   the row closer: |1 - new/ideal| < |1 - old/ideal|; the last row takes the rest; empty rows dropped); per
//   candidate f = min(1, min over rows of (area.w - (k-1)*spacing)/sum(w'), (area.h - (rows-1)*spacing)/
//   sum(tallest h' per row)); the largest f wins, a tie keeps the smaller r. Rows stacked, block centred
//   vertically, each row centred, ordered by (centre x, centre y, id), each tile centred vertically in its row.
//   Window i is drawn s_i = t_i*f times its size. Spacing is not scaled.
// Expected values that M1's rule gave and this rule changes are replaced here, each with its derivation; the
// equal-size cases keep M1's numbers (with one t for all, the result is M1's when M1's scale <= t; shown per case).
//
// Safe areas (config defaults, docs/design.md "Geometry"): margin 24, strip height 120, section gap 16, search
// height 40. Top of the area = 24 + 120 + 16 + 40 + 16 = 216; bottom margin 24.
//   A 3440x1440 (DP-1, scale 1):              {x 24, y 216, w 3440-48 = 3392, h 1440-216-24 = 1200}  S = 4070400
//   B 1440x2560 (HDMI-A-1, transform 3):      {x 24, y 216, w 1392,           h 2560-240 = 2320}     S = 3229440
//   C 2752x1152 (3440x1440 device at 1.25):   {x 24, y 216, w 2704,           h 1152-240 = 912}      S = 2466048
//   D 1152x2048 (1440x2560 device at 1.25):   {x 24, y 216, w 1104,           h 2048-240 = 1808}     S = 1996032
// Window spacing 24, max scale 1.0 unless a case says otherwise.

export const AREA = {
    A: { x: 24, y: 216, w: 3392, h: 1200 },
    B: { x: 24, y: 216, w: 1392, h: 2320 },
    C: { x: 24, y: 216, w: 2704, h: 912 },
    D: { x: 24, y: 216, w: 1104, h: 1808 },
};
export const OPTS = { spacing: 24, maxScale: 1.0 };
// The ratio cap of docs/design.md, on tile areas (largest / smallest), equality allowed when the cap binds.
export const CAP = 9;

const SA = 3392 * 1200, SB = 1392 * 2320, SC = 2704 * 912, SD = 1104 * 1808;
const sqrt = Math.sqrt;

function W(id, x, y, w, h) { return { id: id, x: x, y: y, w: w, h: h }; }
function R(x, y, w, h) { return { x: x, y: y, w: w, h: h }; }
function same(ids, s) { const o = {}; for (const id of ids) o[id] = s; return o; }

// ---- Two-window values that need the even-out step (computed once, used below) ----------------------------------
// B 2 stacked: w1 1420x1240 (a 1760800), w2 1420x1250 (a 1775000); A = SB/2 = 1614720, both above A.
//   t1 = sqrt(1614720/1760800) = 0.957621, t2 = sqrt(1614720/1775000) = 0.953783. Both tiles area A: ratio 1.
//   Pre-scaled w1' 1359.82 x 1187.45, w2' 1354.37 x 1192.23. Sorted w1 (cy 670), w2 (cy 1925).
//   r=1: (1392-24)/2714.19 = 0.50402.
//   r=2: ideal 1357.10; w1 alone (adding w2 gives |1-2.0| = 1 > 0.002); rows [w1],[w2]: horizontal 1392/1359.82 =
//        1.0237, 1392/1354.37 = 1.0278; vertical (2320-24)/(1187.45+1192.23) = 0.964836 -> f = 0.964836. Wins.
//   f = 2296/(1240 t1 + 1250 t2); s1 = t1 f = 0.923947, s2 = t2 f = 0.920244.
//   Each row centred: x_i = 24 + (1392 - 1420 s_i)/2. Block 1240 s1 + 24 + 1250 s2 = 2296 + 24 = 2320 -> top 216.
//   y1 = 216, y2 = 216 + 1240 s1 + 24.
const B2t1 = sqrt(SB / 2 / (1420 * 1240)), B2t2 = sqrt(SB / 2 / (1420 * 1250));
const B2f = 2296 / (1240 * B2t1 + 1250 * B2t2), B2s1 = B2t1 * B2f, B2s2 = B2t2 * B2f;
// D 2 stacked: w1 1136x992 (a 1126912), w2 1136x1000 (a 1136000); A = SD/2 = 998016.
//   t1 = sqrt(998016/1126912) = 0.941074, t2 = sqrt(998016/1136000) = 0.937302.
//   r=1: (1104-24)/(1136 (t1+t2)) = 0.506. r=2: rows [w1],[w2] (as B); horizontal 1104/1069.06 = 1.0327;
//   vertical (1808-24)/(992 t1 + 1000 t2) = 1784/1870.85 = 0.953579 -> f. s1 = t1 f = 0.897391, s2 = t2 f = 0.893794.
//   x_i = 24 + (1104 - 1136 s_i)/2; y1 = 216, y2 = 216 + 992 s1 + 24 (block = 1808, top 216).
const D2t1 = sqrt(SD / 2 / (1136 * 992)), D2t2 = sqrt(SD / 2 / (1136 * 1000));
const D2f = 1784 / (992 * D2t1 + 1000 * D2t2), D2s1 = D2t1 * D2f, D2s2 = D2t2 * D2f;

// ---- One full-screen window and two small ones (where M1's one scale was worst) ---------------------------------
// The small ones s1 640x480 (a 307200) and s2 800x600 (a 480000) are below every A here, so t = 1 for both; the
// full-screen one shrinks to area A. Tile area ratio = A / 307200 (cap 9 not reached). M1's one scale gave the real
// ratio a_F / 307200: A 15.36, B 11.56, C 9.83 (all above the cap: the planted fault is caught there), D 7.40.
//
// A: F 3420x1380 at (10,50) (cx 1720, cy 740), s1 at (200,300) (cx 520, cy 540), s2 at (2200,700) (cx 2600, cy 1000).
//   A = SA/3 = 1356800; tF = sqrt(1356800/4719600) = 0.536173; F' = 1833.713 x 739.919. Ratio 1356800/307200 = 4.417.
//   Sorted s1 (540), F (740), s2 (1000). Sum of widths 3273.713.
//   r=1: horizontal (3392-48)/3273.713 = 1.02147, vertical 1200/739.919 = 1.622 -> f = 1 (capped).
//   r=2: ideal 1636.86; s1, then F (|1-1.511| = 0.511 < |1-0.391| = 0.609) joins, s2 would not; rows [s1 F],[s2]:
//        vertical (1200-24)/(739.919+600) = 0.8777 < 1. r=3 smaller still. Winner r=1, f = 1.
//   Row by cx: s1, F, s2. Row width 640 + 1833.713 + 800 + 48 = 3321.713; x0 = 24 + (3392 - 3321.713)/2 = 59.1434.
//   Row height 739.919; top = 216 + (1200 - 739.919)/2 = 446.0403; each tile centred vertically in the row.
const FAt = sqrt(SA / 3 / (3420 * 1380));
const FAx0 = 24 + (3392 - (640 + 3420 * FAt + 800 + 48)) / 2, FArh = 1380 * FAt, FAtop = 216 + (1200 - FArh) / 2;
// B: F 1420x2500 at (10,50) (cx 720, cy 1300), s1 at (100,300) (cx 420, cy 540), s2 at (500,1800) (cx 900, cy 2100).
//   A = SB/3 = 1076480; tF = sqrt(1076480/3550000) = 0.550667; F' = 781.947 x 1376.667. Ratio 3.504.
//   Sorted s1 (540), F (1300), s2 (2100); widths 640, 781.947, 800, sum 2221.947.
//   r=1: (1392-48)/2221.947 = 0.60487.
//   r=2: ideal 1110.97; s1, F joins (|1-1.2799| = 0.280 < |1-0.5761| = 0.424), s2 not (|1-2| = 1); rows [s1 F],[s2]:
//        horizontal (1392-24)/1421.947 = 0.962061, 1392/800; vertical (2320-24)/(1376.667+600) = 1.1616 -> 0.962061.
//   r=3: ideal 740.65; three single rows; vertical (2320-48)/(480+1376.667+600) = 0.92483. Winner r=2.
//   f = 1368/(640 + 1420 tF) = 0.962061. Row 0 (by cx: s1, F) width 1368 + 24 = 1392 -> x0 = 24; height
//   2500 tF f = 1324.43. Row 1: s2, height 600 f = 577.24, x = 24 + (1392 - 800 f)/2.
//   Block 2500 tF f + 24 + 600 f; top = 216 + (2320 - block)/2 = 413.17.
const FBt = sqrt(SB / 3 / (1420 * 2500)), FBf = 1368 / (640 + 1420 * FBt);
const FBh0 = 2500 * FBt * FBf, FBtop = 216 + (2320 - (FBh0 + 24 + 600 * FBf)) / 2;
// C: F 2736x1104 at (8,40) (cx 1376, cy 592), s1 at (160,240) (cx 480, cy 480), s2 at (1760,500) (cx 2160, cy 800).
//   A = SC/3 = 822016; tF = sqrt(822016/3020544) = 0.521672; F' = 1427.295 x 575.926. Ratio 2.676.
//   Sorted s1 (480), F (592), s2 (800); sum of widths 2867.295.
//   r=1: horizontal (2704-48)/2867.295 = 0.926309; vertical 912/600 = 1.52 -> 0.926309.
//   r=2: ideal 1433.65; s1, F joins (0.442 < 0.554), s2 not; vertical (912-24)/(575.926+600) = 0.75515 -> smaller.
//   r=3: vertical (912-48)/(480+575.926+600) = 0.5218. Winner r=1, f = 2656/(1440 + 2736 tF) = 0.926309.
//   One row s1, F, s2, width 2656 + 48 = 2704 -> x0 = 24. Height = the tallest = s2's 600 f (F's 575.926 f is less);
//   top = 216 + (912 - 600 f)/2. s1 y = top + 60 f; F y = top + (600 f - 1104 tF f)/2; s2 y = top.
const FCt = sqrt(SC / 3 / (2736 * 1104)), FCf = 2656 / (1440 + 2736 * FCt), FCtop = 216 + (912 - 600 * FCf) / 2;
// D: F 1136x2000 at (8,40) (cx 576, cy 1040), s1 at (80,200) (cx 400, cy 440), s2 at (300,1500) (cx 700, cy 1800).
//   A = SD/3 = 665344; tF = sqrt(665344/2272000) = 0.541152; F' = 614.748 x 1082.303. Ratio 2.166.
//   Sorted s1 (440), F (1040), s2 (1800); sum 2054.748.
//   r=1: (1104-48)/2054.748 = 0.51393.
//   r=2: ideal 1027.37; s1, F joins (0.221 < 0.377), s2 not; rows [s1 F],[s2]: horizontal (1104-24)/1254.748 =
//        0.860730, 1104/800; vertical (1808-24)/(1082.303+600) = 1.0605 -> 0.860730.
//   r=3: three single rows: vertical (1808-48)/(480+1082.303+600) = 0.81395. Winner r=2.
//   f = 1080/(640 + 1136 tF). Row 0 (s1, F) width 1104 -> x0 = 24, height 2000 tF f; row 1 s2 at
//   x = 24 + (1104 - 800 f)/2. Block 2000 tF f + 24 + 600 f; top = 216 + (1808 - block)/2.
const FDt = sqrt(SD / 3 / (1136 * 2000)), FDf = 1080 / (640 + 1136 * FDt);
const FDh0 = 2000 * FDt * FDf, FDtop = 216 + (1808 - (FDh0 + 24 + 600 * FDf)) / 2;

// ---- The cap binding: a maximised window and a tiny dialog ------------------------------------------------------
// A: F 3420x1380 at (10,50) (cx 1720, cy 740), dialog 300x200 at (1500,600) (cx 1650, cy 700).
//   A = SA/2 = 2035200; step 2: tF = sqrt(2035200/4719600) = 0.656676 (area 2035200), dialog t = 1 (area 60000):
//   ratio 33.92 > 9. Step 3: tF = sqrt(9*60000/4719600) = 0.338255; F' = 1156.832 x 466.792, area 540000: ratio 9.
//   r=1: horizontal (3392-24)/1456.832 = 2.31, vertical 1200/466.792 = 2.57 -> f = 1; r=2 at most 1: tie, r=1.
//   Row by cx: dialog (1650), F (1720). Width 300 + 1156.832 + 24 = 1480.832; x0 = 24 + (3392 - 1480.832)/2 =
//   979.584. Height 466.792; top = 216 + (1200 - 466.792)/2 = 582.604; dialog y = top + (466.792 - 200)/2.
const CPt = sqrt(9 * 60000 / (3420 * 1380));
const CPx0 = 24 + (3392 - (300 + 3420 * CPt + 24)) / 2, CPrh = 1380 * CPt, CPtop = 216 + (1200 - CPrh) / 2;

// Exact cases: expected rows, every window's scale and every rect. The top-level scale must be the largest scale.
// One window: t = min(1, sqrt(S/a)) >= min(1, W/w, H/h), so s = t*f = min(1, area.w/w, area.h/h): M1's values hold.
export const exactCases = [
    // A, one maximised window 3420x1380: t = sqrt(4070400/4719600) = 0.928680, f = 1200/(1380 t); s = 20/23.
    // w = 3420*20/23 = 2973.9130, h = 1200; x = 24 + (3392 - w)/2 = 233.0435; y = 216.
    { tag: "A 1 big", mon: "A", windows: [W("w1", 10, 50, 3420, 1380)], rows: 1, scales: { w1: 20 / 23 },
      rects: { w1: R(24 + (3392 - 3420 * 20 / 23) / 2, 216, 3420 * 20 / 23, 1200) } },
    // A, one small window 1200x800 (a 960000 < S): t = 1, f = 1. x = 24 + (3392-1200)/2 = 1120; y = 216 + 200 = 416.
    { tag: "A 1 small", mon: "A", windows: [W("w1", 1000, 400, 1200, 800)], rows: 1, scales: { w1: 1 },
      rects: { w1: R(1120, 416, 1200, 800) } },
    // B, one maximised window 1420x2500: s = min(1, 1392/1420, 2320/2500) = 0.928. w 1317.76, x 61.12, y 216.
    { tag: "B 1 big", mon: "B", windows: [W("w1", 10, 50, 1420, 2500)], rows: 1, scales: { w1: 0.928 },
      rects: { w1: R(61.12, 216, 1317.76, 2320) } },
    // B, one small window 800x600: s = 1. x = 24 + (1392-800)/2 = 320; y = 216 + (2320-600)/2 = 1076.
    { tag: "B 1 small", mon: "B", windows: [W("w1", 300, 800, 800, 600)], rows: 1, scales: { w1: 1 },
      rects: { w1: R(320, 1076, 800, 600) } },
    // C, 2736x1104: s = min(1, 2704/2736, 912/1104 = 19/23) = 19/23; w = 2260.1739, x = 245.9130, y = 216.
    { tag: "C 1 big", mon: "C", windows: [W("w1", 8, 40, 2736, 1104)], rows: 1, scales: { w1: 19 / 23 },
      rects: { w1: R(24 + (2704 - 2736 * 19 / 23) / 2, 216, 2736 * 19 / 23, 912) } },
    // C, 960x640: s = 1. x = 24 + (2704-960)/2 = 896; y = 216 + (912-640)/2 = 352.
    { tag: "C 1 small", mon: "C", windows: [W("w1", 800, 320, 960, 640)], rows: 1, scales: { w1: 1 },
      rects: { w1: R(896, 352, 960, 640) } },
    // D, 1136x2000: s = min(1, 1104/1136, 1808/2000) = 0.904. w = 1026.944, x = 62.528, y = 216.
    { tag: "D 1 big", mon: "D", windows: [W("w1", 8, 40, 1136, 2000)], rows: 1, scales: { w1: 0.904 },
      rects: { w1: R(62.528, 216, 1026.944, 1808) } },
    // D, 640x480: s = 1. x = 24 + (1104-640)/2 = 256; y = 216 + (1808-480)/2 = 880.
    { tag: "D 1 small", mon: "D", windows: [W("w1", 240, 640, 640, 480)], rows: 1, scales: { w1: 1 },
      rects: { w1: R(256, 880, 640, 480) } },

    // A, two side-by-side tiles 1705x1380 (input order reversed on purpose). A = SA/2 = 2035200;
    //   t = sqrt(2035200/2352900) = 0.930040 for both; M1's scale 20/23 = 0.869565 <= t, so M1's result holds:
    //   r=1: f = min(1, 3368/(3410 t) = 1.062, 1200/(1380 t) = 0.934972) -> s = t f = 20/23; r=2 vertical smaller.
    //   w = 1705*20/23 = 1482.6087, h = 1200; x(w1) = 24 + (3392 - (2w + 24))/2 = 225.3913; x(w2) = 1732; y = 216.
    { tag: "A 2 tiles", mon: "A", windows: [W("w2", 1725, 50, 1705, 1380), W("w1", 10, 50, 1705, 1380)],
      rows: 1, scales: same(["w1", "w2"], 20 / 23),
      rects: { w1: R(24 + (3392 - (2 * 1705 * 20 / 23 + 24)) / 2, 216, 1705 * 20 / 23, 1200),
               w2: R(1732, 216, 1705 * 20 / 23, 1200) } },
    // A, the same two tiles with max scale 0.5: t = min(0.5, 0.930040) = 0.5; pre-scaled 852.5 x 690.
    //   r=1: horizontal 3368/1705 = 1.975, vertical 1200/690 = 1.739 -> f = 1; r=2 at most 1 (tie keeps r=1).
    //   s = 0.5. Row width 1705 + 24 = 1729; x(w1) = 24 + (3392-1729)/2 = 855.5; x(w2) = 855.5 + 852.5 + 24 = 1732;
    //   y = 216 + (1200-690)/2 = 471.
    { tag: "A 2 tiles max 0.5", mon: "A", opts: { spacing: 24, maxScale: 0.5 },
      windows: [W("w2", 1725, 50, 1705, 1380), W("w1", 10, 50, 1705, 1380)],
      rows: 1, scales: same(["w1", "w2"], 0.5),
      rects: { w1: R(855.5, 471, 852.5, 690), w2: R(1732, 471, 852.5, 690) } },
    // A, two floating windows a 800x600 at (200,300) (cy 600), b 600x400 at (2000,500) (cy 700). Both below
    //   A = 2035200: t = 1; ratio 480000/240000 = 2. As M1: f capped at 1 for r=1 and r=2, tie keeps r=1.
    //   Row [a, b]: width 1424; x(a) = 1008; x(b) = 1832; row top 516; y(a) = 516; y(b) = 516 + 100 = 616.
    { tag: "A 2 floating", mon: "A", windows: [W("b", 2000, 500, 600, 400), W("a", 200, 300, 800, 600)],
      rows: 1, scales: same(["a", "b"], 1),
      rects: { a: R(1008, 516, 800, 600), b: R(1832, 616, 600, 400) } },
    // B, two stacked windows (derivation at B2 above). Replaces M1's one scale 2296/2490.
    { tag: "B 2 stacked", mon: "B", windows: [W("w2", 10, 1300, 1420, 1250), W("w1", 10, 50, 1420, 1240)],
      rows: 2, scales: { w1: B2s1, w2: B2s2 },
      rects: { w1: R(24 + (1392 - 1420 * B2s1) / 2, 216, 1420 * B2s1, 1240 * B2s1),
               w2: R(24 + (1392 - 1420 * B2s2) / 2, 216 + 1240 * B2s1 + 24, 1420 * B2s2, 1250 * B2s2) } },
    // C, two tiles 1364x1104: A = SC/2 = 1233024, t = sqrt(1233024/1505856) = 0.904886 for both; M1's 19/23 =
    //   0.826087 <= t: M1's result holds (f = 912/(1104 t)). w = 1126.7826, h = 912; x(w1) = 237.2174,
    //   x(w2) = 1388; y = 216. (The M2 gate's RO-C case: unchanged.)
    { tag: "C 2 tiles", mon: "C", windows: [W("w2", 1380, 40, 1364, 1104), W("w1", 8, 40, 1364, 1104)],
      rows: 1, scales: same(["w1", "w2"], 19 / 23),
      rects: { w1: R(24 + (2704 - (2 * 1364 * 19 / 23 + 24)) / 2, 216, 1364 * 19 / 23, 912),
               w2: R(1388, 216, 1364 * 19 / 23, 912) } },
    // D, two stacked windows (derivation at D2 above). Replaces M1's one scale 1784/1992.
    { tag: "D 2 stacked", mon: "D", windows: [W("w2", 8, 1040, 1136, 1000), W("w1", 8, 40, 1136, 992)],
      rows: 2, scales: { w1: D2s1, w2: D2s2 },
      rects: { w1: R(24 + (1104 - 1136 * D2s1) / 2, 216, 1136 * D2s1, 992 * D2s1),
               w2: R(24 + (1104 - 1136 * D2s2) / 2, 216 + 992 * D2s1 + 24, 1136 * D2s2, 1000 * D2s2) } },

    // One full-screen window and two small ones (derivations above, FA..FD).
    { tag: "A full + 2 small", mon: "A",
      windows: [W("F", 10, 50, 3420, 1380), W("s1", 200, 300, 640, 480), W("s2", 2200, 700, 800, 600)],
      rows: 1, scales: { F: FAt, s1: 1, s2: 1 },
      rects: { s1: R(FAx0, FAtop + (FArh - 480) / 2, 640, 480),
               F: R(FAx0 + 664, FAtop, 3420 * FAt, FArh),
               s2: R(FAx0 + 664 + 3420 * FAt + 24, FAtop + (FArh - 600) / 2, 800, 600) } },
    { tag: "B full + 2 small", mon: "B",
      windows: [W("F", 10, 50, 1420, 2500), W("s1", 100, 300, 640, 480), W("s2", 500, 1800, 800, 600)],
      rows: 2, scales: { F: FBt * FBf, s1: FBf, s2: FBf },
      rects: { s1: R(24, FBtop + (FBh0 - 480 * FBf) / 2, 640 * FBf, 480 * FBf),
               F: R(24 + 640 * FBf + 24, FBtop, 1420 * FBt * FBf, FBh0),
               s2: R(24 + (1392 - 800 * FBf) / 2, FBtop + FBh0 + 24, 800 * FBf, 600 * FBf) } },
    { tag: "C full + 2 small", mon: "C",
      windows: [W("F", 8, 40, 2736, 1104), W("s1", 160, 240, 640, 480), W("s2", 1760, 500, 800, 600)],
      rows: 1, scales: { F: FCt * FCf, s1: FCf, s2: FCf },
      rects: { s1: R(24, FCtop + 60 * FCf, 640 * FCf, 480 * FCf),
               F: R(24 + 640 * FCf + 24, FCtop + (600 * FCf - 1104 * FCt * FCf) / 2, 2736 * FCt * FCf, 1104 * FCt * FCf),
               s2: R(24 + 640 * FCf + 24 + 2736 * FCt * FCf + 24, FCtop, 800 * FCf, 600 * FCf) } },
    { tag: "D full + 2 small", mon: "D",
      windows: [W("F", 8, 40, 1136, 2000), W("s1", 80, 200, 640, 480), W("s2", 300, 1500, 800, 600)],
      rows: 2, scales: { F: FDt * FDf, s1: FDf, s2: FDf },
      rects: { s1: R(24, FDtop + (FDh0 - 480 * FDf) / 2, 640 * FDf, 480 * FDf),
               F: R(24 + 640 * FDf + 24, FDtop, 1136 * FDt * FDf, FDh0),
               s2: R(24 + (1104 - 800 * FDf) / 2, FDtop + FDh0 + 24, 800 * FDf, 600 * FDf) } },

    // The ratio cap binding (derivation at CP above): tile area ratio exactly 9.
    { tag: "A full + tiny dialog (cap)", mon: "A",
      windows: [W("F", 10, 50, 3420, 1380), W("dlg", 1500, 600, 300, 200)],
      rows: 1, scales: { F: CPt, dlg: 1 },
      rects: { dlg: R(CPx0, CPtop + (CPrh - 200) / 2, 300, 200),
               F: R(CPx0 + 324, CPtop, 3420 * CPt, CPrh) } },
];

function grid(cols, rows, x0, y0, dx, dy, w, h) {
    const out = [];
    for (let r = 0; r < rows; r++)
        for (let c = 0; c < cols; c++)
            out.push(W("g" + r + c, x0 + dx * c, y0 + dy * r, w, h));
    return out;
}
function gridIds(cols, rows) {
    const out = [];
    for (let r = 0; r < rows; r++)
        for (let c = 0; c < cols; c++)
            out.push("g" + r + c);
    return out;
}

// Property cases: no overlap with spacing, inside the area, aspect kept, never above max scale, each rect its
// window times its own scale, tile area ratio <= CAP, order by position; plus the expected rows and every scale
// worked out here. Windows below their share A keep t = 1. Replaces M1's one scale for every case with unequal
// windows; the 12-window grids (one size) keep M1's numbers because M1's scale <= t there.
const A3t = sqrt(SA / 3 / (1705 * 1380)), A3f = 3344 / (1705 * A3t + 3410);
const A5t = sqrt(SA / 5 / (1705 * 685)), A5f = 1176 / (685 + 685 * A5t);
const B3t = sqrt(SB / 3 / (1420 * 1240)), B3f = 1368 / 1410;
const B5t = sqrt(SB / 5 / (1420 * 1240)), B5f = 1368 / (1420 * B5t + 705);
const C3t = sqrt(SC / 3 / (1364 * 1104)), C3f = 2656 / (1364 * C3t + 2728);
const C5t1 = sqrt(SC / 5 / (904 * 548)), C5t3 = sqrt(SC / 5 / (912 * 548)), C5t4 = sqrt(SC / 5 / (1364 * 548));
const C5f = 888 / (548 * C5t1 + 548 * C5t4);
const D3t = sqrt(SD / 3 / (1136 * 992)), D3f = 1080 / 1128;
const D5t = sqrt(SD / 5 / (1136 * 992)), D5f = 1080 / (1136 * D5t + 564);

export const propCases = [
    // A, master and stack: w1 1705x1380 (a 2352900) left; w2, w3 1705x685 (a 1167925) stacked right.
    //   A = SA/3 = 1356800: t1 = sqrt(1356800/2352900) = 0.759375 (w1' 1294.73 x 1047.94); t2 = t3 = 1.
    //   Ratio 1356800/1167925 = 1.162. Sorted w2 (cy 392.5), w1 (740), w3 (1087.5); sum of widths 4704.73.
    //   r=1: horizontal (3392-48)/4704.73 = 0.710773; vertical 1200/1047.94 -> 0.710773.
    //   r=2: ideal 2352.37; w2 then w1 is an exact tie (|1-ratio| = 0.2752 both ways, w2 = w3 wide), but both
    //        splits give tallest heights 685 + 1047.94: vertical (1200-24)/1732.94 = 0.67862 -> smaller.
    //   r=3: (1200-48)/2417.94 = 0.4764. Winner r=1, f = 3344/(1705 t1 + 3410). s1 = t1 f = 0.53974, s2 = s3 = f.
    { tag: "A 3", mon: "A", rows: 1, scales: { w1: A3t * A3f, w2: A3f, w3: A3f },
      windows: [W("w1", 10, 50, 1705, 1380), W("w2", 1725, 50, 1705, 685), W("w3", 1725, 745, 1705, 685)] },
    // A, three tiles on top (1130, 1130, 1140 wide), two below (1705 each), all 685 high.
    //   A = SA/5 = 814080: w1, w2 (a 774050) and w3 (a 780900) keep t = 1; w4, w5 (a 1167925) t4 =
    //   sqrt(814080/1167925) = 0.834884 (1423.48 x 571.90). Ratio 814080/774050 = 1.052. Sum of widths 6246.97.
    //   r=1: (3392-96)/6246.97 = 0.52762.
    //   r=2: ideal 3123.48; w1, w2 (2260 <= ideal), w3 (3400: 0.0885 < 0.2765), not w4; rows [w1 w2 w3],[w4 w5]:
    //        horizontal 3344/3400 = 0.98353, 3368/2846.97 = 1.183; vertical (1200-24)/(685 + 571.90) = 0.935639.
    //   r=3: rows [w1 w2],[w3 w4],[w5]: vertical (1200-48)/(685+685+571.90) = 0.59323. r>=4 smaller.
    //   Winner r=2, f = 1176/(685 + 685 t4). s1..s3 = f, s4 = s5 = t4 f = 0.78114.
    { tag: "A 5", mon: "A", rows: 2,
      scales: { w1: A5f, w2: A5f, w3: A5f, w4: A5t * A5f, w5: A5t * A5f },
      windows: [W("w1", 10, 50, 1130, 685), W("w2", 1150, 50, 1130, 685), W("w3", 2290, 50, 1140, 685),
                W("w4", 10, 745, 1705, 685), W("w5", 1725, 745, 1705, 685)] },
    // A, 4x3 grid of 845x453 (a 382785): A = SA/12 = 339200, t = 0.941349 for all. M1: r=3, 1152/1359 = 0.847682
    //   <= t, so M1's result holds (f = 0.847682/t = 0.9005 < 1). Rows 3, every s = 1152/1359.
    { tag: "A 12", mon: "A", rows: 3, scales: same(gridIds(4, 3), 1152 / 1359),
      windows: grid(4, 3, 10, 50, 855, 463, 845, 453) },
    // B, master on top w1 1420x1240 (a 1760800), two side by side below, 705x1250 (a 881250).
    //   A = SB/3 = 1076480: t1 = sqrt(1076480/1760800) = 0.781894 (1110.29 x 969.55); t2 = t3 = 1. Ratio 1.222.
    //   Sorted w1 (670), w2, w3 (1925). Sum 2520.29.
    //   r=1: (1392-48)/2520.29 = 0.53328.
    //   r=2: ideal 1260.15; w1 alone (adding w2: 0.4405 > 0.1189); rows [w1],[w2 w3]: horizontal 1392/1110.29,
    //        (1392-24)/1410 = 0.970213; vertical (2320-24)/(969.55+1250) = 1.0344 -> 0.970213.
    //   r=3: (2320-48)/(969.55+2500) = 0.6548. Winner r=2, f = 1368/1410. s1 = t1 f = 0.75861, s2 = s3 = f.
    { tag: "B 3", mon: "B", rows: 2, scales: { w1: B3t * B3f, w2: B3f, w3: B3f },
      windows: [W("w1", 10, 50, 1420, 1240), W("w2", 10, 1300, 705, 1250), W("w3", 725, 1300, 705, 1250)] },
    // B, master on top 1420x1240 and a 2x2 grid of 705x620 (a 437100) below.
    //   A = SB/5 = 645888: t1 = sqrt(645888/1760800) = 0.605653 (860.03 x 751.01); others 1. Ratio 1.478.
    //   Sorted w1 (670), w2 w3 (1610), w4 w5 (2240). Sum 3680.03.
    //   r=1: (1392-96)/3680.03 = 0.35217.
    //   r=2: ideal 1840.01; w1, w2 (1565.03 <= ideal), not w3 (0.2337 > 0.1494); rows [w1 w2],[w3 w4 w5]:
    //        horizontal (1392-48)/2115 = 0.63546 -> at most 0.63546.
    //   r=3: ideal 1226.68; w1, w2 joins (|1-1.27583| = 0.2758 < |1-0.70110| = 0.2989), not w3; w3, w4 (0.1495 <
    //        0.4253), not w5; rows [w1 w2],[w3 w4],[w5]: horizontal 1368/1565.03 = 0.874106, 1368/1410 = 0.97021;
    //        vertical (2320-48)/(751.01+620+620) = 1.1411 -> 0.874106.
    //   r=4: rows [w1],[w2],[w3],[w4 w5]: horizontal 0.97021; vertical (2320-72)/(751.01+1860) = 0.860970.
    //   r=5: (2320-96)/(751.01+2480) = 0.6883. Winner r=3, f = 1368/(1420 t1 + 705). s1 = t1 f = 0.52940, rest f.
    { tag: "B 5", mon: "B", rows: 3,
      scales: { w1: B5t * B5f, w2: B5f, w3: B5f, w4: B5f, w5: B5f },
      windows: [W("w1", 10, 50, 1420, 1240), W("w2", 10, 1300, 705, 620), W("w3", 725, 1300, 705, 620),
                W("w4", 10, 1930, 705, 620), W("w5", 725, 1930, 705, 620)] },
    // B, 2x6 grid of 705x405 (a 285525): A = SB/12 = 269120, t = 0.970847. M1: 6 rows, 2200/2430 = 0.905350 <= t:
    //   M1's result holds (f = 0.9325). Rows 6, s = 2200/2430.
    { tag: "B 12", mon: "B", rows: 6, scales: same(gridIds(2, 6), 2200 / 2430),
      windows: grid(2, 6, 10, 50, 715, 415, 705, 405) },
    // C, w1 1364x1104 (a 1505856), w2, w3 1364x548 (a 747472).
    //   A = SC/3 = 822016: t1 = sqrt(822016/1505856) = 0.738837 (1007.77 x 815.68); t2 = t3 = 1. Ratio 1.100.
    //   Sorted w2 (314), w1 (592), w3 (870). Sum 3735.77.
    //   r=1: (2704-48)/3735.77 = 0.710964; vertical 912/815.68 -> 0.710964.
    //   r=2: the same exact tie as "A 3", either split: vertical (912-24)/(815.68+548) = 0.65118 -> smaller.
    //   Winner r=1, f = 2656/(1364 t1 + 2728). s1 = t1 f = 0.52529, s2 = s3 = f.
    { tag: "C 3", mon: "C", rows: 1, scales: { w1: C3t * C3f, w2: C3f, w3: C3f },
      windows: [W("w1", 8, 40, 1364, 1104), W("w2", 1380, 40, 1364, 548), W("w3", 1380, 596, 1364, 548)] },
    // C, 904, 904, 912 wide on top, 1364, 1364 below, all 548 high. A = SC/5 = 493209.6, every window above it:
    //   t1 = t2 = sqrt(493209.6/495392) = 0.997795, t3 = sqrt(493209.6/499776) = 0.993409, t4 = t5 =
    //   sqrt(493209.6/747472) = 0.812303. All tiles area A: ratio 1. Pre-scaled widths 902.01, 902.01, 905.99,
    //   1107.98, 1107.98 (sum 4925.97); heights 546.79, 546.79, 544.39, 445.14, 445.14.
    //   r=1: (2704-96)/4925.97 = 0.52944.
    //   r=2: ideal 2462.99; w1, w2, w3 (2710.01: 0.1003 < 0.2675), not w4; rows [w1 w2 w3],[w4 w5]: horizontal
    //        2656/2710.01 = 0.98007, 2680/2215.96; vertical (912-24)/(546.79+445.14) = 0.895221.
    //   r=3: rows [w1 w2],[w3 w4],[w5]: vertical (912-48)/(546.79+544.39+445.14) = 0.56238.
    //   Winner r=2, f = 888/(548 t1 + 548 t4). s1 = s2 = t1 f, s3 = t3 f, s4 = s5 = t4 f.
    { tag: "C 5", mon: "C", rows: 2,
      scales: { w1: C5t1 * C5f, w2: C5t1 * C5f, w3: C5t3 * C5f, w4: C5t4 * C5f, w5: C5t4 * C5f },
      windows: [W("w1", 8, 40, 904, 548), W("w2", 920, 40, 904, 548), W("w3", 1832, 40, 912, 548),
                W("w4", 8, 596, 1364, 548), W("w5", 1380, 596, 1364, 548)] },
    // C, 4x3 grid of 676x362 (a 244712): A = SC/12 = 205504, t = 0.916394; M1: r=3, 864/1086 = 0.795580 <= t.
    //   Rows 3, s = 864/1086.
    { tag: "C 12", mon: "C", rows: 3, scales: same(gridIds(4, 3), 864 / 1086),
      windows: grid(4, 3, 8, 40, 684, 370, 676, 362) },
    // D, w1 1136x992 (a 1126912), w2, w3 564x1000 (a 564000).
    //   A = SD/3 = 665344: t1 = sqrt(665344/1126912) = 0.768384 (872.88 x 762.24); t2 = t3 = 1. Ratio 1.180.
    //   r=1: (1104-48)/2000.88 = 0.52776.
    //   r=2: ideal 1000.44; w1 alone (0.4363 > 0.1275); rows [w1],[w2 w3]: horizontal 1104/872.88, 1080/1128 =
    //        0.957447; vertical (1808-24)/(762.24+1000) = 1.0123 -> 0.957447.
    //   r=3: (1808-48)/2762.24 = 0.6372. Winner r=2, f = 1080/1128. s1 = t1 f = 0.73569, s2 = s3 = f.
    { tag: "D 3", mon: "D", rows: 2, scales: { w1: D3t * D3f, w2: D3f, w3: D3f },
      windows: [W("w1", 8, 40, 1136, 992), W("w2", 8, 1040, 564, 1000), W("w3", 580, 1040, 564, 1000)] },
    // D, w1 1136x992 and a 2x2 grid of 564x496 (a 279744).
    //   A = SD/5 = 399206.4: t1 = sqrt(399206.4/1126912) = 0.595187 (676.13 x 590.43); others 1. Ratio 1.427.
    //   Sorted w1 (536), w2 w3 (1288), w4 w5 (1792). Sum 2932.13.
    //   r=1: 0.34378. r=2: rows [w1 w2],[w3 w4 w5] (w3 would be 0.2306 > 0.1541): 1056/1692 = 0.62411.
    //   r=3: ideal 977.38; w1, w2 joins (0.2688 < 0.3082); w3, w4 (0.1541 < 0.4230); w5: rows [w1 w2],[w3 w4],[w5]:
    //        horizontal 1080/1240.13 = 0.870874, 1080/1128; vertical (1808-48)/(590.43+496+496) = 1.112 -> 0.870874.
    //   r=4: rows [w1],[w2],[w3],[w4 w5]: vertical (1808-72)/(590.43+1488) = 0.835247. r=5: 0.6650.
    //   Winner r=3, f = 1080/(1136 t1 + 564). s1 = t1 f = 0.51834, rest f.
    { tag: "D 5", mon: "D", rows: 3,
      scales: { w1: D5t * D5f, w2: D5f, w3: D5f, w4: D5f, w5: D5f },
      windows: [W("w1", 8, 40, 1136, 992), W("w2", 8, 1040, 564, 496), W("w3", 580, 1040, 564, 496),
                W("w4", 8, 1544, 564, 496), W("w5", 580, 1544, 564, 496)] },
    // D, 2x6 grid of 564x324 (a 182736): A = SD/12 = 166336, t = 0.954072; M1: 6 rows, 1688/1944 = 0.868313 <= t.
    //   Rows 6, s = 1688/1944.
    { tag: "D 12", mon: "D", rows: 6, scales: same(gridIds(2, 6), 1688 / 1944),
      windows: grid(2, 6, 8, 40, 572, 332, 564, 324) },
];
