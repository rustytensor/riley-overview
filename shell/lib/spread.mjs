// SPDX-License-Identifier: GPL-3.0-or-later
//
// Spread layout: places one workspace's windows so none overlap, near their real places, with their sizes evened
// out (Mission Control): each window is first scaled towards an equal share of the safe area (never above
// maxScale, with a cap on the largest-to-smallest tile area), then the pre-scaled set is packed in rows (GNOME's
// natural layout, row form) with one common fit factor. Pure logic, no Quickshell. Specified in docs/design.md
// "Spread layout".
//
//   spreadLayout(windows, area, opts) -> { scale, fit, rows, rects }
//     windows: [{ id, x, y, w, h }] in the monitor's logical pixels, relative to the monitor. Not modified.
//     area:    { x, y, w, h } the safe area (strip.mjs safeArea()).
//     opts:    { spacing, maxScale } spacing in logical px (not scaled), maxScale <= 1.
//     scale:   the largest window factor; fit: the common fit factor (<= 1); rows: number of non-empty rows
//              (0 for no windows).
//     rects:   [{ id, x, y, w, h, scale }] one per window, in input order; scale = tile width / window width.

// The cap on tile areas: the largest tile is at most CAP times the area of the smallest.
export const CAP = 9;

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

// Packing step 3: the candidate's common factor (at most 1: the sizes are already pre-scaled).
function rowsScale(rows, area, opts) {
    let s = 1;
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

// Steps 1 to 3 of the size rule: each window's pre-scale t_i.
function preScales(windows, area, maxScale) {
    const n = windows.length;
    const A = area.w * area.h / n;
    const t = windows.map(win => {
        const a = win.w * win.h;
        return a > 0 ? Math.min(maxScale, Math.sqrt(A / a)) : maxScale;
    });
    let bmin = Infinity;
    windows.forEach((win, i) => {
        const a = win.w * win.h;
        if (a > 0) bmin = Math.min(bmin, t[i] * t[i] * a);
    });
    if (isFinite(bmin))
        windows.forEach((win, i) => {
            const a = win.w * win.h;
            if (a > 0) t[i] = Math.min(t[i], Math.sqrt(CAP * bmin / a));
        });
    return t;
}

export function spreadLayout(windows, area, opts) {
    if (!windows || windows.length === 0)
        return { scale: opts.maxScale, fit: 1, rows: 0, rects: [] };

    const t = preScales(windows, area, opts.maxScale);

    // Work on copies so the caller's objects are never touched. Sizes are pre-scaled; centres are the real ones.
    const entries = windows.map((win, index) => {
        const c = centre(win);
        return { index: index, id: win.id, t: t[index], w: t[index] * win.w, h: t[index] * win.h, cx: c.cx, cy: c.cy };
    });

    // Packing step 1: reading order.
    const sorted = entries.slice().sort((a, b) => cmp(a.cy, b.cy) || cmp(a.cx, b.cx) || cmp(a.id, b.id));

    // Packing steps 2-4: the largest factor wins; a tie keeps the smaller r.
    let best = null;
    let bestFit = -Infinity;
    for (let r = 1; r <= sorted.length; ++r) {
        const rows = splitRows(sorted, r);
        const f = rowsScale(rows, area, opts);
        if (f > bestFit) {
            bestFit = f;
            best = rows;
        }
    }

    // Packing step 5: place. Spacing is not scaled.
    const f = bestFit;
    const heights = best.map(row => f * Math.max(...row.map(e => e.h)));
    let blockH = (best.length - 1) * opts.spacing;
    for (const h of heights)
        blockH += h;

    const rects = new Array(windows.length);
    let top = 0;
    let y = area.y + (area.h - blockH) / 2;
    best.forEach((row, ri) => {
        const ordered = row.slice().sort((a, b) => cmp(a.cx, b.cx) || cmp(a.cy, b.cy) || cmp(a.id, b.id));
        let rowW = (ordered.length - 1) * opts.spacing;
        for (const e of ordered)
            rowW += f * e.w;
        let x = area.x + (area.w - rowW) / 2;
        const rowH = heights[ri];
        for (const e of ordered) {
            const w = f * e.w;
            const h = f * e.h;
            // Step 5 of the size rule: s_i = t_i * f.
            const scale = e.t * f;
            rects[e.index] = { id: e.id, x: x, y: y + (rowH - h) / 2, w: w, h: h, scale: scale };
            top = Math.max(top, scale);
            x += w + opts.spacing;
        }
        y += rowH + opts.spacing;
    });

    return { scale: top, fit: f, rows: best.length, rects: rects };
}
