// SPDX-License-Identifier: GPL-3.0-or-later
//
// Hit-testing for the overlay. Pure logic, no Quickshell. Specified in docs/design.md "Hit-testing".
//
//   hitTest(px, py, windowRects, stripRects)
//     -> { kind: "workspace", index } | { kind: "window", id } | { kind: "none" }
//     windowRects: [{ id, x, y, w, h }] bottom to top (the last one is topmost).
//     stripRects:  [{ index, x, y, w, h }] as stripGeometry() returns them; drawn above the windows.
//     A rect holds (px, py) when x <= px < x + w and y <= py < y + h.
//
// M1 stub: the implementation is builder B's.

export function hitTest(px, py, windowRects, stripRects) {
    throw new Error("hitTest: not implemented");
}
