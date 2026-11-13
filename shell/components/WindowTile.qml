// SPDX-License-Identifier: GPL-3.0-or-later
//
// One window in the overview: its live image, a hover frame around it, the close button on its top-right corner,
// the app icon and title under it, and the move between where the window really is and where the overview puts
// it. No input handling: the Overlay hit-tests the same rects (docs/overlay.md and docs/interact.md "Components").
//
// The item itself is placed by the tile: its parent should be the surface (or an item covering it at 0,0), and
// all rects are in that item's logical px.
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland

Item {
    id: tile

    property var toplevel: null          // Quickshell Toplevel (HyprlandToplevel.wayland) for the live image
    property string address
    property string appClass
    property string title
    property var realRect: ({ x: 0, y: 0, w: 0, h: 0 })
    property var spreadRect: ({ x: 0, y: 0, w: 0, h: 0 })
    property int animationMs: 0
    property bool highlighted: false
    property bool open: false
    // This window is being dragged: the tile stays at its spread rect, dimmed (the DragProxy follows the pointer).
    property bool dragging: false

    // Looks; the Overlay may bind these to the Theme. Not part of the hit-test contract.
    property color accent: "#7aa2f7"
    property color textColor: "#e6e6e6"
    property string fontFamily: ""
    property int titleSize: 12

    signal closeAnimationDone()
    // open went true and the move reached the spread rect; sent at once when animationMs is 0.
    signal openAnimationDone()
    signal closeRequested(string address)

    // 0 = at realRect, 1 = at spreadRect.
    property real progress: 0
    // True once the move to the spread is finished (the test hook waits for this).
    readonly property bool settled: open ? progress >= 1 : progress <= 0
    // True when the live image has a frame (or there is nothing to capture).
    readonly property bool hasContent: !toplevel || view.hasContent
    // The rect as drawn right now, monitor-relative logical.
    readonly property var drawnRect: ({ x: x, y: y, w: width, h: height })
    // How many progress values strictly between 0 and 1 the move went through since open last changed (one per
    // animation frame; 0 when the move was instant).
    readonly property int steps: stepCount
    property int stepCount: 0
    onProgressChanged: if (progress > 0 && progress < 1) stepCount++

    function lerp(a, b) { return a + (b - a) * progress; }
    function num(r, k) { return r && isFinite(r[k]) ? r[k] : 0; }

    x: lerp(num(realRect, "x"), num(spreadRect, "x"))
    y: lerp(num(realRect, "y"), num(spreadRect, "y"))
    width: Math.max(0, lerp(num(realRect, "w"), num(spreadRect, "w")))
    height: Math.max(0, lerp(num(realRect, "h"), num(spreadRect, "h")))

    // The move is timed by the wall clock from the moment open changed, not from the first animation tick (an
    // animation counted from its first tick ended up to two frames late in the nest). It lands on the frame nearest
    // to that moment plus the duration: a frame less than half a frame before the end already shows the end.
    // Ease out cubic.
    property real moveFrom: 0
    property real moveTo: 0
    property real moveStart: 0
    property int moveDuration: 0

    FrameAnimation {
        id: move
        onTriggered: tile.stepMove()
    }

    function stepMove() {
        const elapsed = Date.now() - moveStart;
        const frameMs = move.smoothFrameTime > 0 ? Math.min(50, move.smoothFrameTime * 1000) : 1000 / 60;
        const t = Math.min(1, Math.max(0, elapsed / moveDuration));
        if (elapsed + frameMs / 2 >= moveDuration) {
            move.stop();
            progress = moveTo;
            if (open) openAnimationDone(); else closeAnimationDone();
            return;
        }
        progress = moveFrom + (moveTo - moveFrom) * (1 - Math.pow(1 - t, 3));
    }

    function run() {
        move.stop();
        const to = open ? 1 : 0;
        const dur = Math.max(0, Math.min(animationMs, 200));
        if (dur === 0 || progress === to) {
            progress = to;
            if (open) openAnimationDone(); else closeAnimationDone();
            return;
        }
        moveFrom = progress;
        moveTo = to;
        moveStart = Date.now();
        moveDuration = Math.max(1, Math.round(dur * Math.abs(to - progress)));
        move.start();
    }

    onOpenChanged: {
        stepCount = 0;
        run();
    }
    Component.onCompleted: if (open) run()

    // Hover frame: outside the rect, never over the image. Drawn first so the image stays on top.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -6
        radius: 6
        color: "transparent"
        border.width: 3
        border.color: tile.accent
        visible: tile.highlighted
    }

    // Placeholder while the live image has no frame yet: a dim panel with the icon.
    Rectangle {
        anchors.fill: parent
        color: "#33000000"
        visible: !view.hasContent
        opacity: tile.dragging ? 0.35 : 1
        IconImage {
            anchors.centerIn: parent
            implicitSize: Math.max(16, Math.min(64, Math.min(parent.width, parent.height) / 3))
            source: icon.source
            visible: parent.width > 24 && parent.height > 24
        }
    }

    // The live image fills the rect exactly, at full opacity, untinted.
    ScreencopyView {
        id: view
        anchors.fill: parent
        captureSource: tile.toplevel
        live: true
        paintCursor: false
        opacity: tile.dragging ? 0.35 : 1
    }

    // Close button: a 24x24 disc of the accent centred on the rect's top-right corner, exactly at
    // hittest.mjs closeRect (relative to the tile: x w - 12, y -12), above the image and the frame. The cross stays
    // inside the middle 12x12 (two 10x2 bars at 45 degrees reach at most 4.3 px from the centre), so the disc is
    // plain accent from 6 px outwards.
    Item {
        id: closeButton
        z: 2
        x: tile.width - 12
        y: -12
        width: 24
        height: 24
        visible: tile.highlighted && tile.open && tile.settled && !tile.dragging
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: tile.accent
            antialiasing: true
        }
        Repeater {
            model: [45, -45]
            delegate: Rectangle {
                required property var modelData
                x: 7
                y: 11
                width: 10
                height: 2
                radius: 1
                rotation: modelData
                color: tile.textColor
                antialiasing: true
            }
        }
    }

    // Icon and title, under the rect, inside the spacing between rows; hidden while moving.
    Row {
        id: caption
        anchors.top: parent.bottom
        anchors.topMargin: 3
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 4
        visible: tile.open && tile.settled && tile.width > 24
        IconImage {
            id: icon
            implicitSize: tile.titleSize + 4
            anchors.verticalCenter: parent.verticalCenter
            source: {
                const c = tile.appClass || "";
                const entry = c ? DesktopEntries.heuristicLookup(c) : null;
                const names = [entry ? entry.icon : "", c, c.toLowerCase()];
                for (const n of names) {
                    if (!n) continue;
                    const p = Quickshell.iconPath(n, true);
                    if (p) return p;
                }
                return Quickshell.iconPath("application-x-executable", true);
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Math.max(0, tile.width - icon.width - caption.spacing))
            text: tile.title || tile.appClass
            color: tile.textColor
            font.family: tile.fontFamily
            font.pixelSize: tile.titleSize
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }
}
