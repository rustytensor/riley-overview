// SPDX-License-Identifier: GPL-3.0-or-later
//
// The desktops bar (Spaces style) at the top of each surface: a slim row of workspace names that grows into live
// previews while the pointer is in its band or a window is being dragged. Pure logic, no Quickshell. Specified in
// docs/design.md "Desktops bar".
//
//   NAMES_HEIGHT: the height of the collapsed names row.
//   desktopsBar(W, H, count, cfg, expanded) -> { band, zone, expanded, rects: [{ index, x, y, w, h, plus }] }
//     W, H: the monitor's logical size; count: its workspaces plus the empty one (the "+" entry, last).
//     cfg: { margin, stripHeight, stripSpacing }. Expanded rects are stripGeometry's; collapsed ones keep x and w,
//     with y = band.y and h = min(NAMES_HEIGHT, stripHeight). zone = band in both states.
//   barExpanded(px, py, band, dragging) -> bool: dragging, or the point in band (half-open).
//
// No rounding here; the overlay rounds when it draws.

import { stripGeometry } from "./strip.mjs";

export const NAMES_HEIGHT = 28;

export function desktopsBar(W, H, count, cfg, expanded) {
    const geo = stripGeometry(W, H, count, cfg);
    const b = geo.band;
    const band = { x: b.x, y: b.y, w: b.w, h: b.h };
    const zone = { x: b.x, y: b.y, w: b.w, h: b.h };
    const nh = Math.min(NAMES_HEIGHT, cfg.stripHeight);
    const open = expanded === true;
    const rects = geo.rects.map(r => ({
        index: r.index,
        x: r.x,
        y: open ? r.y : band.y,
        w: r.w,
        h: open ? r.h : nh,
        plus: r.index === count - 1,
    }));
    return { band: band, zone: zone, expanded: open, rects: rects };
}

export function barExpanded(px, py, band, dragging) {
    if (dragging === true) return true;
    return px >= band.x && px < band.x + band.w && py >= band.y && py < band.y + band.h;
}
