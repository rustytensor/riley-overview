// SPDX-License-Identifier: GPL-3.0-or-later
//
// Overlay geometry: the safe area for the spread and the workspace strip. Pure logic, no Quickshell.
// Specified in docs/design.md "Geometry".
//
//   safeArea(monW, monH, cfg) -> { x, y, w, h }
//     monW, monH: the monitor's logical size (device size / scale, after its transform).
//     cfg: { margin, stripHeight, sectionGap, searchHeight } (config.mjs keys; extra keys ignored).
//
//   stripGeometry(monW, monH, count, cfg) -> { band: {x,y,w,h}, thumbW, thumbH, rects: [{ index, x, y, w, h }] }
//     count: the monitor's workspaces plus one empty one at the end (the caller passes the total).
//     cfg: { margin, stripHeight, stripSpacing }.
//
// M1 stub: the implementation is builder B's.

export function safeArea(monW, monH, cfg) {
    throw new Error("safeArea: not implemented");
}

export function stripGeometry(monW, monH, count, cfg) {
    throw new Error("stripGeometry: not implemented");
}
