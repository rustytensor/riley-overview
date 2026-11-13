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
//
// M1 stub: the implementation is builder A's.

export function spreadLayout(windows, area, opts) {
    throw new Error("spreadLayout: not implemented");
}
