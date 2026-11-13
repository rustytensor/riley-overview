// SPDX-License-Identifier: GPL-3.0-or-later
//
// Arrow-key navigation over the visible tiles of one surface. Pure logic, no Quickshell. Specified in
// docs/interact.md "shell/lib/navigate.mjs".
//
//   readingOrder(rects) -> [id]          sorted by (centre y, centre x, id)
//   navigate(rects, fromId, dir) -> id   dir "left" | "right" | "up" | "down"
//     rects: [{ id, x, y, w, h }], never modified. No rects: "". fromId "" or not among the rects: the reading
//     order's first. Otherwise the candidates are the other rects whose centre is strictly beyond the from-centre
//     in dir; those in the beam (overlapping the from-rect on the other axis, touching edges excluded) come first,
//     then the smaller distance between centres, then the smaller id. No candidate: fromId.

function cx(r) { return r.x + r.w / 2; }
function cy(r) { return r.y + r.h / 2; }

function cmpId(a, b) {
    const x = String(a), y = String(b);
    return x < y ? -1 : (x > y ? 1 : 0);
}

export function readingOrder(rects) {
    return (rects || []).slice()
        .sort((a, b) => (cy(a) - cy(b)) || (cx(a) - cx(b)) || cmpId(a.id, b.id))
        .map(r => r.id);
}

export function navigate(rects, fromId, dir) {
    const list = rects || [];
    if (list.length === 0) return "";
    const f = fromId === "" ? null : list.find(r => r.id === fromId);
    if (!f) return readingOrder(list)[0];
    const fx = cx(f), fy = cy(f);
    const horizontal = dir === "left" || dir === "right";
    let best = null;
    for (const c of list) {
        if (c === f || c.id === f.id) continue;
        const x = cx(c), y = cy(c);
        let beyond;
        if (dir === "right") beyond = x > fx;
        else if (dir === "left") beyond = x < fx;
        else if (dir === "down") beyond = y > fy;
        else if (dir === "up") beyond = y < fy;
        else beyond = false;
        if (!beyond) continue;
        const inBeam = horizontal ? (c.y < f.y + f.h && f.y < c.y + c.h)
                                  : (c.x < f.x + f.w && f.x < c.x + c.w);
        const d = Math.hypot(x - fx, y - fy);
        const cand = { id: c.id, inBeam: inBeam, d: d };
        if (best === null) { best = cand; continue; }
        if (cand.inBeam !== best.inBeam) { if (cand.inBeam) best = cand; continue; }
        if (cand.d !== best.d) { if (cand.d < best.d) best = cand; continue; }
        if (cmpId(cand.id, best.id) < 0) best = cand;
    }
    return best ? best.id : fromId;
}
