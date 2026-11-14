// SPDX-License-Identifier: GPL-3.0-or-later
//
// The gate's own property checks for a spread result. Each returns null when the property holds, or a message.
// EPS absorbs floating point only; it is far below a pixel.

export const EPS = 1e-6;

function byId(rects) {
    const m = {};
    for (const r of rects) m[r.id] = r;
    return m;
}

// Every input window has exactly one rect, in input order, with the same id.
export function sameWindows(windows, out) {
    if (!out || !Array.isArray(out.rects)) return "result has no rects array";
    if (out.rects.length !== windows.length) return "rects " + out.rects.length + " != windows " + windows.length;
    for (let i = 0; i < windows.length; i++)
        if (out.rects[i].id !== windows[i].id) return "rect " + i + " is " + out.rects[i].id + ", want " + windows[i].id;
    return null;
}

// No two rects closer than the spacing: for every pair the horizontal or the vertical gap is >= spacing.
export function noOverlap(out, spacing) {
    const r = out.rects;
    for (let i = 0; i < r.length; i++)
        for (let j = i + 1; j < r.length; j++) {
            const a = r[i], b = r[j];
            const hgap = Math.max(b.x - (a.x + a.w), a.x - (b.x + b.w));
            const vgap = Math.max(b.y - (a.y + a.h), a.y - (b.y + b.h));
            if (Math.max(hgap, vgap) < spacing - EPS)
                return a.id + " and " + b.id + ": gap " + Math.max(hgap, vgap).toFixed(4) + " < spacing " + spacing;
        }
    return null;
}

export function inside(out, area) {
    for (const r of out.rects)
        if (r.x < area.x - EPS || r.y < area.y - EPS || r.x + r.w > area.x + area.w + EPS ||
            r.y + r.h > area.y + area.h + EPS)
            return r.id + " " + JSON.stringify(r) + " leaves area " + JSON.stringify(area);
    return null;
}

// |w/h - w0/h0| < 0.01 * w0/h0.
export function aspectKept(windows, out) {
    const m = byId(out.rects);
    for (const w of windows) {
        const r = m[w.id], a0 = w.w / w.h;
        if (!r || !(r.h > 0)) return w.id + ": no rect or zero height";
        if (Math.abs(r.w / r.h - a0) >= 0.01 * a0) return w.id + ": aspect " + (r.w / r.h) + " vs " + a0;
    }
    return null;
}

export function notLarger(windows, out) {
    const m = byId(out.rects);
    for (const w of windows) {
        const r = m[w.id];
        if (r.w > w.w + EPS || r.h > w.h + EPS) return w.id + ": " + r.w + "x" + r.h + " larger than " + w.w + "x" + w.h;
    }
    return null;
}

// MC: each rect is its window times the rect's own scale (aspect kept exactly), that scale is in (0, maxScale], and
// the top-level scale is the largest of them.
export function ownScale(windows, out, maxScale) {
    const m = byId(out.rects);
    let top = 0;
    for (const w of windows) {
        const r = m[w.id];
        if (!r) return w.id + ": no rect";
        if (typeof r.scale !== "number" || !(r.scale > 0) || r.scale > maxScale + EPS)
            return w.id + ": rect scale " + r.scale + " outside (0, " + maxScale + "]";
        if (Math.abs(r.w - w.w * r.scale) > 1e-4 || Math.abs(r.h - w.h * r.scale) > 1e-4)
            return w.id + ": " + r.w + "x" + r.h + " is not its scale " + r.scale + " of " + w.w + "x" + w.h;
        top = Math.max(top, r.scale);
    }
    if (!(Math.abs(out.scale - top) <= 1e-9)) return "top-level scale " + out.scale + " is not the largest " + top;
    return null;
}

// MC: largest tile area / smallest tile area <= cap (equality allowed: the cap binds exactly).
export function areaRatio(out, cap) {
    let lo = Infinity, hi = 0;
    for (const r of out.rects) {
        const a = r.w * r.h;
        lo = Math.min(lo, a);
        hi = Math.max(hi, a);
    }
    if (out.rects.length === 0) return null;
    if (!(lo > 0)) return "a tile has no area";
    const q = hi / lo;
    return q <= cap * (1 + 1e-9) ? null : "tile area ratio " + q.toFixed(4) + " > cap " + cap;
}

// MC: the expected scale of every window (hand-worked in cases.mjs), tolerance 1e-6.
export function scalesEqual(out, expected) {
    const m = byId(out.rects);
    for (const id in expected) {
        const r = m[id];
        if (!r) return "no rect for " + id;
        if (!(Math.abs(r.scale - expected[id]) <= 1e-6)) return id + ".scale = " + r.scale + ", want " + expected[id];
    }
    return null;
}

// Order by position, GNOME reading order. Two spread rects share a row when their vertical extents overlap.
// For every pair (a, b) with a before b in reality by (centre y, then centre x) or, within one spread row,
// by (centre x, then centre y):
//   - same spread row: a's spread centre is left of b's;
//   - different rows: a's row is above b's.
// So side-by-side tiles that stay in one row keep left/right, stacked tiles keep above/below, and a column that is
// laid out in one row reads top to bottom as left to right.
export function orderKept(windows, out) {
    const m = byId(out.rects);
    const c = w => ({ x: w.x + w.w / 2, y: w.y + w.h / 2 });
    for (const a of windows)
        for (const b of windows) {
            if (a === b) continue;
            const ra = m[a.id], rb = m[b.id], ca = c(a), cb = c(b), sa = c(ra), sb = c(rb);
            const sameRow = ra.y < rb.y + rb.h - EPS && rb.y < ra.y + ra.h - EPS;
            if (sameRow) {
                const before = ca.x < cb.x - EPS || (Math.abs(ca.x - cb.x) <= EPS && ca.y < cb.y - EPS);
                if (before && !(sa.x < sb.x - EPS))
                    return a.id + " is left of " + b.id + " in reality but not in the spread row";
            } else {
                const before = ca.y < cb.y - EPS || (Math.abs(ca.y - cb.y) <= EPS && ca.x < cb.x - EPS);
                if (before && !(ra.y < rb.y))
                    return a.id + " is above " + b.id + " in reality but its spread row is not above";
            }
        }
    return null;
}

// Exact rect comparison, tolerance 1e-4 logical px.
export function rectsEqual(out, expected) {
    const m = byId(out.rects);
    for (const id in expected) {
        const r = m[id], e = expected[id];
        if (!r) return "no rect for " + id;
        for (const k of ["x", "y", "w", "h"])
            if (!(Math.abs(r[k] - e[k]) <= 1e-4)) return id + "." + k + " = " + r[k] + ", want " + e[k];
    }
    return null;
}

export function near(a, b, tol) { return Math.abs(a - b) <= (tol === undefined ? 1e-4 : tol); }
