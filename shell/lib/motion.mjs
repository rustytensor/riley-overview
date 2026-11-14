// SPDX-License-Identifier: GPL-3.0-or-later
//
// Open and close motion: the ease-out zoom of each tile between its window's real rect and its spread rect. Pure
// logic, no Quickshell. Specified in docs/design.md "Motion".
//
//   easeOutCubic(p) -> 1 - (1 - p)^3, with p clamped to [0, 1].
//   zoomRect(from, to, p) -> { x, y, w, h }: from + easeOutCubic(p) * (to - from) per field. Inputs not modified.

export function easeOutCubic(p) {
    const q = p < 0 ? 0 : (p > 1 ? 1 : p);
    const u = 1 - q;
    return 1 - u * u * u;
}

export function zoomRect(from, to, p) {
    const e = easeOutCubic(p);
    return {
        x: from.x + e * (to.x - from.x),
        y: from.y + e * (to.y - from.y),
        w: from.w + e * (to.w - from.w),
        h: from.h + e * (to.h - from.h),
    };
}
