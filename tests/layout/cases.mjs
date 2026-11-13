// SPDX-License-Identifier: GPL-3.0-or-later
//
// M1 gate inputs for the spread layout, with every expected value worked out by hand before any run.
// The algorithm these numbers follow is specified in docs/design.md, section "Spread layout"; in short:
//   sort windows by (centre y, centre x, id); for r = 1..n split them greedily into at most r rows by width
//   (ideal row width = sum of widths / r; a window joins the current row while the row is empty, or the row plus it
//   still fits the ideal, or adding it brings the row closer to the ideal: |1 - new/ideal| < |1 - old/ideal|; the last
//   row takes the rest; empty rows are dropped); per candidate the scale is
//     s = min(maxScale, min over rows of (area.w - (k-1)*spacing) / sum(widths in row),
//                       (area.h - (rows-1)*spacing) / sum(tallest window per row))
//   the largest s wins, a tie keeps the smaller r. Rows are stacked top to bottom, the block centred vertically in
//   the area; each row centred horizontally, its windows ordered by (centre x, centre y, id), each window centred
//   vertically in its row. Spacing is in screen pixels and is not scaled.
//
// Safe areas (config defaults, docs/design.md "Geometry"): margin 24, strip height 120, section gap 16, search
// height 40. Top of the area = 24 + 120 + 16 + 40 + 16 = 216; bottom margin 24.
//   A 3440x1440 (DP-1, scale 1):              {x 24, y 216, w 3440-48 = 3392, h 1440-216-24 = 1200}
//   B 1440x2560 (HDMI-A-1, transform 3):      {x 24, y 216, w 1392,           h 2560-240 = 2320}
//   C 2752x1152 (3440x1440 device at 1.25):   {x 24, y 216, w 2704,           h 1152-240 = 912}
//   D 1152x2048 (1440x2560 device at 1.25):   {x 24, y 216, w 1104,           h 2048-240 = 1808}
// Window spacing 24, max scale 1.0 throughout.

export const AREA = {
    A: { x: 24, y: 216, w: 3392, h: 1200 },
    B: { x: 24, y: 216, w: 1392, h: 2320 },
    C: { x: 24, y: 216, w: 2704, h: 912 },
    D: { x: 24, y: 216, w: 1104, h: 1808 },
};
export const OPTS = { spacing: 24, maxScale: 1.0 };

function W(id, x, y, w, h) { return { id: id, x: x, y: y, w: w, h: h }; }

// Exact cases: expected scale, rows and every rect. Rects are given by the formula that produced them.
export const exactCases = [
    // A, one maximised window 3420x1380. s = min(1, 3392/3420 = 0.99181, 1200/1380 = 20/23 = 0.869565) = 20/23.
    // w = 3420*20/23 = 2973.9130, h = 1200; x = 24 + (3392 - w)/2 = 233.0435; y = 216 + (1200 - 1200)/2 = 216.
    { tag: "A 1 big", mon: "A", windows: [W("w1", 10, 50, 3420, 1380)], scale: 20 / 23, rows: 1,
      rects: { w1: { x: 24 + (3392 - 3420 * 20 / 23) / 2, y: 216, w: 3420 * 20 / 23, h: 1200 } } },
    // A, one small window 1200x800: s = min(1, 3392/1200, 1200/800) = 1 (never enlarged).
    // x = 24 + (3392-1200)/2 = 1120; y = 216 + (1200-800)/2 = 416.
    { tag: "A 1 small", mon: "A", windows: [W("w1", 1000, 400, 1200, 800)], scale: 1, rows: 1,
      rects: { w1: { x: 1120, y: 416, w: 1200, h: 800 } } },
    // B, one maximised window 1420x2500. s = min(1, 1392/1420 = 0.98028, 2320/2500 = 0.928) = 0.928.
    // w = 1420*0.928 = 1317.76, h = 2320; x = 24 + (1392 - 1317.76)/2 = 61.12; y = 216.
    { tag: "B 1 big", mon: "B", windows: [W("w1", 10, 50, 1420, 2500)], scale: 0.928, rows: 1,
      rects: { w1: { x: 61.12, y: 216, w: 1317.76, h: 2320 } } },
    // B, one small window 800x600: s = 1. x = 24 + (1392-800)/2 = 320; y = 216 + (2320-600)/2 = 1076.
    { tag: "B 1 small", mon: "B", windows: [W("w1", 300, 800, 800, 600)], scale: 1, rows: 1,
      rects: { w1: { x: 320, y: 1076, w: 800, h: 600 } } },
    // C, A's big window times 0.8: 2736x1104. s = min(1, 2704/2736 = 0.98830, 912/1104 = 19/23 = 0.826087) = 19/23.
    // w = 2736*19/23 = 2260.1739, h = 912; x = 24 + (2704 - w)/2 = 245.9130; y = 216.
    { tag: "C 1 big", mon: "C", windows: [W("w1", 8, 40, 2736, 1104)], scale: 19 / 23, rows: 1,
      rects: { w1: { x: 24 + (2704 - 2736 * 19 / 23) / 2, y: 216, w: 2736 * 19 / 23, h: 912 } } },
    // C, one small window 960x640: s = 1. x = 24 + (2704-960)/2 = 896; y = 216 + (912-640)/2 = 352.
    { tag: "C 1 small", mon: "C", windows: [W("w1", 800, 320, 960, 640)], scale: 1, rows: 1,
      rects: { w1: { x: 896, y: 352, w: 960, h: 640 } } },
    // D, one maximised window 1136x2000. s = min(1, 1104/1136 = 0.97183, 1808/2000 = 0.904) = 0.904.
    // w = 1136*0.904 = 1026.944, h = 1808; x = 24 + (1104 - 1026.944)/2 = 62.528; y = 216.
    { tag: "D 1 big", mon: "D", windows: [W("w1", 8, 40, 1136, 2000)], scale: 0.904, rows: 1,
      rects: { w1: { x: 62.528, y: 216, w: 1026.944, h: 1808 } } },
    // D, one small window 640x480: s = 1. x = 24 + (1104-640)/2 = 256; y = 216 + (1808-480)/2 = 880.
    { tag: "D 1 small", mon: "D", windows: [W("w1", 240, 640, 640, 480)], scale: 1, rows: 1,
      rects: { w1: { x: 256, y: 880, w: 640, h: 480 } } },

    // A, two side-by-side tiles 1705x1380 (input order reversed on purpose). Sorted: w1 (cx 862.5), w2 (cx 2577.5),
    // same cy 740.
    //   r=1: horizontal (3392-24)/3410 = 0.98768; vertical 1200/1380 = 20/23 = 0.869565 -> s1 = 20/23.
    //   r=2: ideal 1705; w1 fills row 0 (adding w2 moves |1-ratio| from 0 to 1, so it breaks); rows [w1],[w2];
    //        vertical (1200-24)/(1380+1380) = 0.42609 -> smaller. Winner r=1, s = 20/23.
    //   w = 1705*20/23 = 1482.6087, h = 1200. Row width = 2w + 24 = 2989.2174; x(w1) = 24 + (3392 - 2989.2174)/2
    //   = 225.3913; x(w2) = x(w1) + w + 24 = 1732.0000. y = 216 for both (row height 1200 fills the area).
    { tag: "A 2 tiles", mon: "A", windows: [W("w2", 1725, 50, 1705, 1380), W("w1", 10, 50, 1705, 1380)],
      scale: 20 / 23, rows: 1,
      rects: { w1: { x: 24 + (3392 - (2 * 1705 * 20 / 23 + 24)) / 2, y: 216, w: 1705 * 20 / 23, h: 1200 },
               w2: { x: 1732, y: 216, w: 1705 * 20 / 23, h: 1200 } } },
    // A, two floating windows a 800x600 at (200,300) (cy 600) and b 600x400 at (2000,500) (cy 700).
    //   r=1: horizontal (3392-24)/1400 = 2.4, vertical 1200/600 = 2 -> capped at maxScale 1.
    //   r=2: also capped at 1 -> tie, smaller r kept. Row [a, b] (cx 600 < 2300). s = 1.
    //   Row width 800+600+24 = 1424; x(a) = 24 + (3392-1424)/2 = 1008; x(b) = 1008+800+24 = 1832.
    //   Row height 600; row top = 216 + (1200-600)/2 = 516; y(a) = 516; y(b) = 516 + (600-400)/2 = 616.
    { tag: "A 2 floating", mon: "A", windows: [W("b", 2000, 500, 600, 400), W("a", 200, 300, 800, 600)],
      scale: 1, rows: 1,
      rects: { a: { x: 1008, y: 516, w: 800, h: 600 }, b: { x: 1832, y: 616, w: 600, h: 400 } } },
    // B, two stacked windows w1 1420x1240 (cy 670) over w2 1420x1250 (cy 1925).
    //   r=1: horizontal (1392-24)/2840 = 0.48169.
    //   r=2: ideal 1420; rows [w1],[w2]; horizontal 1392/1420 = 0.98028; vertical (2320-24)/(1240+1250) = 2296/2490
    //        = 0.922088 -> s2 = 2296/2490. Winner r=2.
    //   w = 1420*s = 1309.3655; x = 24 + (1392 - w)/2 = 65.3173 for both. h1 = 1240*s = 1143.3896, h2 = 1250*s =
    //   1152.6104; block height h1 + h2 + 24 = 2320 -> top 216. y(w1) = 216; y(w2) = 216 + h1 + 24 = 1383.3896.
    { tag: "B 2 stacked", mon: "B", windows: [W("w2", 10, 1300, 1420, 1250), W("w1", 10, 50, 1420, 1240)],
      scale: 2296 / 2490, rows: 2,
      rects: { w1: { x: 24 + (1392 - 1420 * 2296 / 2490) / 2, y: 216, w: 1420 * 2296 / 2490, h: 1240 * 2296 / 2490 },
               w2: { x: 24 + (1392 - 1420 * 2296 / 2490) / 2, y: 216 + 1240 * 2296 / 2490 + 24,
                     w: 1420 * 2296 / 2490, h: 1250 * 2296 / 2490 } } },
    // C, A's tiles times 0.8: 1364x1104 each.
    //   r=1: horizontal (2704-24)/2728 = 0.98240; vertical 912/1104 = 19/23 = 0.826087 -> s = 19/23.
    //   r=2: vertical (912-24)/2208 = 0.40217 -> smaller. Winner r=1.
    //   w = 1364*19/23 = 1126.7826, h = 912. Row width 2w+24 = 2277.5652; x(w1) = 24 + (2704 - 2277.5652)/2
    //   = 237.2174; x(w2) = x(w1) + w + 24 = 1388.0000; y = 216.
    { tag: "C 2 tiles", mon: "C", windows: [W("w2", 1380, 40, 1364, 1104), W("w1", 8, 40, 1364, 1104)],
      scale: 19 / 23, rows: 1,
      rects: { w1: { x: 24 + (2704 - (2 * 1364 * 19 / 23 + 24)) / 2, y: 216, w: 1364 * 19 / 23, h: 912 },
               w2: { x: 1388, y: 216, w: 1364 * 19 / 23, h: 912 } } },
    // D, B's stack times 0.8: w1 1136x992 (cy 536) over w2 1136x1000 (cy 1540).
    //   r=1: horizontal (1104-24)/2272 = 0.47535.
    //   r=2: horizontal 1104/1136 = 0.97183; vertical (1808-24)/(992+1000) = 1784/1992 = 0.895582 -> winner.
    //   w = 1136*s = 1017.3815; x = 24 + (1104 - w)/2 = 67.3092. h1 = 992*s = 888.4177, h2 = 1000*s = 895.5823;
    //   block 1808 -> top 216; y(w2) = 216 + h1 + 24 = 1128.4177.
    { tag: "D 2 stacked", mon: "D", windows: [W("w2", 8, 1040, 1136, 1000), W("w1", 8, 40, 1136, 992)],
      scale: 1784 / 1992, rows: 2,
      rects: { w1: { x: 24 + (1104 - 1136 * 1784 / 1992) / 2, y: 216, w: 1136 * 1784 / 1992, h: 992 * 1784 / 1992 },
               w2: { x: 24 + (1104 - 1136 * 1784 / 1992) / 2, y: 216 + 992 * 1784 / 1992 + 24,
                     w: 1136 * 1784 / 1992, h: 1000 * 1784 / 1992 } } },
];

function grid(cols, rows, x0, y0, dx, dy, w, h) {
    const out = [];
    for (let r = 0; r < rows; r++)
        for (let c = 0; c < cols; c++)
            out.push(W("g" + r + c, x0 + dx * c, y0 + dy * r, w, h));
    return out;
}

// Property cases: checked for no overlap with spacing, inside the area, aspect kept, never enlarged, one scale,
// order by position; plus the expected scale and row count worked out here.
export const propCases = [
    // A, master and stack: w1 1705x1380 left; w2, w3 1705x685 stacked on the right. Sum of widths 5115.
    //   r=1: horizontal (3392-48)/5115 = 0.653763; vertical 1200/1380 = 0.8696 -> 0.653763.
    //   r=2: ideal 2557.5; sorted w2 (cy 392.5), w1 (740), w3 (1087.5). Either way the tie at |1-ratio| = 1/3
    //        falls, two rows of total tallest height 1380+685 = 2065: vertical (1200-24)/2065 = 0.56949.
    //   r=3: vertical (1200-48)/2750 = 0.41891. Winner r=1, s = 3344/5115.
    { tag: "A 3", mon: "A", scale: 3344 / 5115, rows: 1,
      windows: [W("w1", 10, 50, 1705, 1380), W("w2", 1725, 50, 1705, 685), W("w3", 1725, 745, 1705, 685)] },
    // A, three tiles on top (1130, 1130, 1140 wide), two below (1705 each), all 685 high. Sum 6810.
    //   r=1: (3392-96)/6810 = 0.48399.
    //   r=2: ideal 3405; row 0 w1+w2+w3 = 3400 <= 3405, w4 would make 5105 (worse) -> rows [w1 w2 w3],[w4 w5].
    //        horizontal 3344/3400 = 0.98353, 3368/3410 = 0.98768; vertical (1200-24)/1370 = 0.858394 -> 0.858394.
    //   r=3: ideal 2270: rows [w1 w2],[w3 w4],[w5]; vertical (1200-48)/2055 = 0.56058.
    //   r=4: ideal 1702.5: rows [w1 w2],[w3],[w4],[w5]; vertical (1200-72)/2740 = 0.41168. r=5 smaller still.
    //   Winner r=2, s = 1176/1370.
    { tag: "A 5", mon: "A", scale: 1176 / 1370, rows: 2,
      windows: [W("w1", 10, 50, 1130, 685), W("w2", 1150, 50, 1130, 685), W("w3", 2290, 50, 1140, 685),
                W("w4", 10, 745, 1705, 685), W("w5", 1725, 745, 1705, 685)] },
    // A, 4x3 grid of 845x453 tiles. Sum 10140.
    //   r=1: 3128/10140 = 0.30848. r=2: ideal 5070, 6 per row: (3392-120)/5070 = 0.64536.
    //   r=3: ideal 3380, 4 per row: horizontal 3320/3380 = 0.98225, vertical (1200-48)/1359 = 0.847682.
    //   r=4: 3 per row: vertical (1200-72)/1812 = 0.62252. r>=5: vertical <= (1200-96)/2265 = 0.48742.
    //   Winner r=3, s = 1152/1359.
    { tag: "A 12", mon: "A", scale: 1152 / 1359, rows: 3, windows: grid(4, 3, 10, 50, 855, 463, 845, 453) },
    // B, master on top w1 1420x1240, two side by side below (705x1250 each). Sum 2830.
    //   r=1: (1392-48)/2830 = 0.47491.
    //   r=2: ideal 1415; row 0 w1 (1420; adding w2 -> 2125 is worse), row 1 [w2 w3]. horizontal 1392/1420 =
    //        0.98028, (1392-24)/1410 = 0.97021; vertical (2320-24)/(1240+1250) = 0.922088 -> 0.922088.
    //   r=3: rows [w1],[w2],[w3]; vertical (2320-48)/3740 = 0.60749. Winner r=2, s = 2296/2490.
    { tag: "B 3", mon: "B", scale: 2296 / 2490, rows: 2,
      windows: [W("w1", 10, 50, 1420, 1240), W("w2", 10, 1300, 705, 1250), W("w3", 725, 1300, 705, 1250)] },
    // B, master on top 1420x1240 and a 2x2 grid of 705x620 below. Sum 4240.
    //   r=1: 1296/4240 = 0.30566.
    //   r=2: ideal 2120; row 0 w1 + w2 = 2125 (|1-ratio| 0.0024 < 0.330) then w3 would be worse; rows [w1 w2],
    //        [w3 w4 w5]: horizontal (1392-48)/2115 = 0.63546 -> 0.63546.
    //   r=3: ideal 1413.33; rows [w1],[w2 w3],[w4 w5]; horizontal 0.98028, 1368/1410 = 0.97021; vertical
    //        (2320-48)/(1240+620+620) = 2272/2480 = 0.916129 -> 0.916129.
    //   r=4: ideal 1060 gives the same three rows (the fourth is empty and dropped): same s, tie keeps r=3.
    //   r=5: five rows, vertical (2320-96)/3720 = 0.59785. Winner: 3 rows, s = 2272/2480.
    { tag: "B 5", mon: "B", scale: 2272 / 2480, rows: 3,
      windows: [W("w1", 10, 50, 1420, 1240), W("w2", 10, 1300, 705, 620), W("w3", 725, 1300, 705, 620),
                W("w4", 10, 1930, 705, 620), W("w5", 725, 1930, 705, 620)] },
    // B, 2x6 grid of 705x405 tiles. Sum 8460.
    //   r=1: 0.13333; r=2: 1272/4230 = 0.30071; r=3: 1320/2820 = 0.46809; r=4: 1344/2115 = 0.63546;
    //   r=5: 2 per row, last row 4 wide: <= 0.46809.
    //   r=6: ideal 1410, 2 per row: horizontal 1368/1410 = 0.97021; vertical (2320-120)/2430 = 0.905350.
    //   r=7: same 6 rows (tie). r=8: either 6 rows (tie) or a 5-wide last row (worse). r>=9: <= 0.6.
    //   Winner 6 rows, s = 2200/2430.
    { tag: "B 12", mon: "B", scale: 2200 / 2430, rows: 6, windows: grid(2, 6, 10, 50, 715, 415, 705, 405) },
    // C, A 3 times 0.8: w1 1364x1104, w2 and w3 1364x548. Sum 4092.
    //   r=1: (2704-48)/4092 = 0.649071; vertical 912/1104 = 0.826 -> 0.649071.
    //   r=2: two rows of tallest 1104 + 548: vertical (912-24)/1652 = 0.53753. Winner r=1, s = 2656/4092.
    { tag: "C 3", mon: "C", scale: 2656 / 4092, rows: 1,
      windows: [W("w1", 8, 40, 1364, 1104), W("w2", 1380, 40, 1364, 548), W("w3", 1380, 596, 1364, 548)] },
    // C, A 5 times 0.8: 904, 904, 912 on top, 1364, 1364 below, all 548 high. Sum 5448.
    //   r=1: 2608/5448 = 0.47871.
    //   r=2: ideal 2724; rows [w1 w2 w3] (2720), [w4 w5]; horizontal 2656/2720 = 0.97647, 2680/2728 = 0.98240;
    //        vertical (912-24)/1096 = 0.810219.
    //   r=3: rows [w1 w2],[w3 w4],[w5]; vertical 864/1644 = 0.52555. Winner r=2, s = 888/1096.
    { tag: "C 5", mon: "C", scale: 888 / 1096, rows: 2,
      windows: [W("w1", 8, 40, 904, 548), W("w2", 920, 40, 904, 548), W("w3", 1832, 40, 912, 548),
                W("w4", 8, 596, 1364, 548), W("w5", 1380, 596, 1364, 548)] },
    // C, 4x3 grid of 676x362 tiles. Sum 8112.
    //   r=2: 2584/4056 = 0.63708. r=3: ideal 2704, 4 per row: horizontal 2632/2704 = 0.97337, vertical
    //   (912-48)/1086 = 0.795580. r=4: vertical 840/1448 = 0.58011. Winner r=3, s = 864/1086.
    { tag: "C 12", mon: "C", scale: 864 / 1086, rows: 3, windows: grid(4, 3, 8, 40, 684, 370, 676, 362) },
    // D, B 3 times 0.8: w1 1136x992, w2 and w3 564x1000. Sum 2264.
    //   r=1: 1056/2264 = 0.46643.
    //   r=2: ideal 1132; rows [w1],[w2 w3]; horizontal 0.97183, 1080/1128 = 0.95745; vertical (1808-24)/1992
    //        = 0.895582. r=3: vertical 1760/2992 = 0.58824. Winner r=2, s = 1784/1992.
    { tag: "D 3", mon: "D", scale: 1784 / 1992, rows: 2,
      windows: [W("w1", 8, 40, 1136, 992), W("w2", 8, 1040, 564, 1000), W("w3", 580, 1040, 564, 1000)] },
    // D, B 5 times 0.8: w1 1136x992, 2x2 grid of 564x496. Sum 3392.
    //   r=2: rows [w1 w2] (1700), [w3 w4 w5]: horizontal 1056/1692 = 0.62411.
    //   r=3: ideal 1130.67; rows [w1],[w2 w3],[w4 w5]; horizontal 0.97183, 1080/1128 = 0.95745; vertical
    //        (1808-48)/1984 = 0.887097. r=4: same rows, tie. r=5: 1712/2976 = 0.57527. Winner 3 rows, s = 1760/1984.
    { tag: "D 5", mon: "D", scale: 1760 / 1984, rows: 3,
      windows: [W("w1", 8, 40, 1136, 992), W("w2", 8, 1040, 564, 496), W("w3", 580, 1040, 564, 496),
                W("w4", 8, 1544, 564, 496), W("w5", 580, 1544, 564, 496)] },
    // D, 2x6 grid of 564x324 tiles. Sum 6768.
    //   r=4: 1056/1692 = 0.62411. r=6: ideal 1128, 2 per row: horizontal 1080/1128 = 0.95745; vertical
    //   (1808-120)/1944 = 0.868313. r=7: same 6 rows (tie); r=8 tie or worse; r>=9 worse. Winner 6 rows,
    //   s = 1688/1944.
    { tag: "D 12", mon: "D", scale: 1688 / 1944, rows: 6, windows: grid(2, 6, 8, 40, 572, 332, 564, 324) },
];
