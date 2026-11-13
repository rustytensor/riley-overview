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
function holds(r, px, py) {
    return r.x <= px && px < r.x + r.w && r.y <= py && py < r.y + r.h;
}

export function hitTest(px, py, windowRects, stripRects) {
    // The strip is drawn above the windows: test it first. Its gaps fall through to the windows.
    for (const r of stripRects || [])
        if (holds(r, px, py)) return { kind: "workspace", index: r.index };
    // Bottom to top: the last rect holding the point is the topmost one.
    const wins = windowRects || [];
    for (let i = wins.length - 1; i >= 0; i--)
        if (holds(wins[i], px, py)) return { kind: "window", id: wins[i].id };
    return { kind: "none" };
}
