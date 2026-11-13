// SPDX-License-Identifier: GPL-3.0-or-later
//
// Drag and drop: the drag threshold and the drop target. Pure logic, no Quickshell. Specified in docs/interact.md
// "shell/lib/drop.mjs".
//
//   DRAG_THRESHOLD = 8; dragStarted(dx, dy) -> bool: hypot(dx, dy) >= 8 (logical px since the press)
//   dropTarget(px, py, surfaces, source)
//     px, py: the pointer, global logical. surfaces: [{ monitor, x, y, w, h, workspace, strip }] with x, y the
//     monitor's global logical position, w, h its logical size, workspace its current workspace id and strip the
//     layoutMonitor(...).strip entries { index, id, x, y, w, h } relative to the surface. source: { monitor,
//     workspace } of the dragged window. Rects hold a point half-open (x <= p < x + w).
//     -> { kind: "workspace", monitor, id, index }   a strip entry of the surface under the point (not the source's
//                                                    own workspace)
//      | { kind: "monitor", monitor, id }            another monitor's overlay, away from its strip: its workspace
//      | { kind: "none" }

export const DRAG_THRESHOLD = 8;

export function dragStarted(dx, dy) {
    return Math.hypot(dx, dy) >= DRAG_THRESHOLD;
}

function holds(r, px, py) {
    return r.x <= px && px < r.x + r.w && r.y <= py && py < r.y + r.h;
}

export function dropTarget(px, py, surfaces, source) {
    const src = source || {};
    const s = (surfaces || []).find(q => holds(q, px, py));
    if (!s) return { kind: "none" };
    const lx = px - s.x, ly = py - s.y;
    const e = (s.strip || []).find(r => holds(r, lx, ly));
    if (e) {
        if (e.id === src.workspace) return { kind: "none" };
        return { kind: "workspace", monitor: s.monitor, id: e.id, index: e.index };
    }
    if (s.monitor !== src.monitor) return { kind: "monitor", monitor: s.monitor, id: s.workspace };
    return { kind: "none" };
}
