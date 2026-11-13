// SPDX-License-Identifier: GPL-3.0-or-later
//
// Spread layout: places one workspace's windows so none overlap, scaled down by one common factor, near their real
// places (GNOME's natural layout, row form). Pure logic, no Quickshell. Specified in docs/design.md "Spread layout".
//
//   spreadLayout(windows, area, opts) -> { scale, rows, rects }
//     windows: [{ id, x, y, w, h }] in the monitor's logical pixels, relative to the monitor. Not modified.
//     area:    { x, y, w, h } the safe area (strip.mjs safeArea()).
//     opts:    { spacing, maxScale } spacing in logical px (not scaled), maxScale <= 1.
//     scale:   the factor applied to every window; rows: number of non-empty rows (0 for no windows).
//     rects:   [{ id, x, y, w, h }] one per window, in input order.

function cmp(a, b) {
    return a < b ? -1 : (a > b ? 1 : 0);
}

function centre(win) {
    return { cx: win.x + win.w / 2, cy: win.y + win.h / 2 };
}

// Step 2: split the sorted windows into at most r rows, greedily by width. Empty rows are dropped.
function splitRows(sorted, r) {
    let sumW = 0;
    for (const e of sorted)
        sumW += e.w;
    const ideal = sumW / r;
    const rows = [];
    let i = 0;
    for (let row = 0; row < r && i < sorted.length; ++row) {
        const cur = [];
        if (row === r - 1) {
            while (i < sorted.length)
                cur.push(sorted[i++]);
        } else {
            let rowW = 0;
            while (i < sorted.length) {
                const w = sorted[i].w;
                const take = cur.length === 0
                    || rowW + w <= ideal
                    || Math.abs(1 - (rowW + w) / ideal) < Math.abs(1 - rowW / ideal);
                if (!take)
                    break;
                cur.push(sorted[i++]);
                rowW += w;
            }
        }
        if (cur.length > 0)
            rows.push(cur);
    }
    return rows;
}

// Step 3: the candidate's common scale.
function rowsScale(rows, area, opts) {
    let s = opts.maxScale;
    let sumTall = 0;
    for (const row of rows) {
        let rowW = 0;
        let tall = 0;
        for (const e of row) {
            rowW += e.w;
            tall = Math.max(tall, e.h);
        }
        s = Math.min(s, (area.w - (row.length - 1) * opts.spacing) / rowW);
        sumTall += tall;
    }
    return Math.min(s, (area.h - (rows.length - 1) * opts.spacing) / sumTall);
}

export function spreadLayout(windows, area, opts) {
    if (!windows || windows.length === 0)
        return { scale: opts.maxScale, rows: 0, rects: [] };

    // Work on copies so the caller's objects are never touched.
    const entries = windows.map((win, index) => {
        const c = centre(win);
        return { index: index, id: win.id, w: win.w, h: win.h, cx: c.cx, cy: c.cy };
    });

    // Step 1: reading order.
    const sorted = entries.slice().sort((a, b) => cmp(a.cy, b.cy) || cmp(a.cx, b.cx) || cmp(a.id, b.id));

    // Steps 2-4: the largest scale wins; a tie keeps the smaller r.
    let best = null;
    let bestScale = -Infinity;
    for (let r = 1; r <= sorted.length; ++r) {
        const rows = splitRows(sorted, r);
        const s = rowsScale(rows, area, opts);
        if (s > bestScale) {
            bestScale = s;
            best = rows;
        }
    }

    // Step 5: place. Spacing is not scaled.
    const s = bestScale;
    const heights = best.map(row => s * Math.max(...row.map(e => e.h)));
    let blockH = (best.length - 1) * opts.spacing;
    for (const h of heights)
        blockH += h;

    const rects = new Array(windows.length);
    let y = area.y + (area.h - blockH) / 2;
    best.forEach((row, ri) => {
        const ordered = row.slice().sort((a, b) => cmp(a.cx, b.cx) || cmp(a.cy, b.cy) || cmp(a.id, b.id));
        let rowW = (ordered.length - 1) * opts.spacing;
        for (const e of ordered)
            rowW += s * e.w;
        let x = area.x + (area.w - rowW) / 2;
        const rowH = heights[ri];
        for (const e of ordered) {
            const w = s * e.w;
            const h = s * e.h;
            rects[e.index] = { id: e.id, x: x, y: y + (rowH - h) / 2, w: w, h: h };
            x += w + opts.spacing;
        }
        y += rowH + opts.spacing;
    });

    return { scale: s, rows: best.length, rects: rects };
}
