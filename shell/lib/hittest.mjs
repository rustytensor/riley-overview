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

// ---- M3: the close button (docs/interact.md "shell/lib/hittest.mjs additions") ---------------------------------
//
//   CLOSE_SIZE = 24; closeRect(r) -> { x: r.x + r.w - 12, y: r.y - 12, w: 24, h: 24 }: centred on the top-right corner
//   hitTestOverlay(px, py, windowRects, stripRects, highlightedId)
//     -> the strip as hitTest | { kind: "close", id } (only the highlighted window's button) | the windows as hitTest
//        | { kind: "none" }

export const CLOSE_SIZE = 24;

export function closeRect(r) {
    const half = CLOSE_SIZE / 2;
    return { x: r.x + r.w - half, y: r.y - half, w: CLOSE_SIZE, h: CLOSE_SIZE };
}

export function hitTestOverlay(px, py, windowRects, stripRects, highlightedId) {
    for (const r of stripRects || [])
        if (holds(r, px, py)) return { kind: "workspace", index: r.index };
    if (highlightedId !== undefined && highlightedId !== null && highlightedId !== "") {
        const h = (windowRects || []).find(r => r.id === highlightedId);
        if (h && holds(closeRect(h), px, py)) return { kind: "close", id: h.id };
    }
    return hitTest(px, py, windowRects, []);
}
