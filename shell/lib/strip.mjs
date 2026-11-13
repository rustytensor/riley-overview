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
//   searchArea(monW, monH, cfg) -> { x, y, w, h }: the search field between the strip and the spread (used from M2).
//
// No rounding here; the overlay rounds when it draws.

export function safeArea(monW, monH, cfg) {
    const m = cfg.margin;
    const y = m + cfg.stripHeight + cfg.sectionGap + cfg.searchHeight + cfg.sectionGap;
    return { x: m, y: y, w: monW - 2 * m, h: monH - y - m };
}

export function searchArea(monW, monH, cfg) {
    const m = cfg.margin;
    return { x: m, y: m + cfg.stripHeight + cfg.sectionGap, w: monW - 2 * m, h: cfg.searchHeight };
}

export function stripGeometry(monW, monH, count, cfg) {
    const m = cfg.margin;
    const sp = cfg.stripSpacing;
    const band = { x: m, y: m, w: monW - 2 * m, h: cfg.stripHeight };
    // Thumbnails keep the monitor's aspect ratio: full strip height, unless the row would not fit the band.
    let h = cfg.stripHeight;
    let w = h * monW / monH;
    if (count > 0 && count * w + (count - 1) * sp > band.w) {
        w = (band.w - (count - 1) * sp) / count;
        h = w * monH / monW;
    }
    const rowW = count > 0 ? count * w + (count - 1) * sp : 0;
    const x0 = band.x + (band.w - rowW) / 2;
    const y = band.y + (band.h - h) / 2;
    const rects = [];
    for (let i = 0; i < count; i++)
        rects.push({ index: i, x: x0 + i * (w + sp), y: y, w: w, h: h });
    return { band: band, thumbW: w, thumbH: h, rects: rects };
}
