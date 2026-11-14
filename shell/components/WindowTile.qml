// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound
//
// One window in the overview: its live image with rounded corners and a soft shadow, an accent ring around it when
// highlighted, the close button on its top-right corner, a small app icon overlapping the bottom edge, the title in
// a pill under it on hover, and the zoom between where the window really is and where the overview puts it. No
// input handling: the Overlay hit-tests the same rects (docs/overlay.md and docs/interact.md "Components").
//
// The item itself is placed by the tile: its parent should be the surface (or an item covering it at 0,0), and
// all rects are in that item's logical px.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import "../lib/motion.mjs" as Motion

Item {
    id: tile

    property var toplevel: null          // Quickshell Toplevel (HyprlandToplevel.wayland) for the live image
    property string address
    property string appClass
    property string title
    property var realRect: ({ x: 0, y: 0, w: 0, h: 0 })
    property var spreadRect: ({ x: 0, y: 0, w: 0, h: 0 })
    // The window's own spread scale (layoutMonitor windows[].scale): tile width / window width, at most 1.
    property real tileScale: 1
    property int animationMs: 0
    property bool highlighted: false
    property bool open: false
    // This window is being dragged: the tile stays at its spread rect, dimmed (the DragProxy follows the pointer).
    property bool dragging: false

    // Looks; the Overlay may bind these to the Theme. Not part of the hit-test contract.
    property color accent: "#7aa2f7"
    property color textColor: "#e6e6e6"
    property color panelColor: "#24283b"
    property string fontFamily: ""
    property int titleSize: 12
    property real radius: 10

    signal closeAnimationDone()
    // open went true and the move reached the spread rect; sent at once when animationMs is 0.
    signal openAnimationDone()
    signal closeRequested(string address)

    // 0 = at realRect, 1 = at spreadRect. Linear in time; the easing is applied to the rect (lib/motion.mjs).
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
    // The last open move as drawn, for the test hook: one { e, x, y, w, h } per step (e = ms since the move
    // started, the rect after that step). Started afresh on each animated open.
    property var openTrace: []

    function num(r, k) { return r && isFinite(r[k]) ? r[k] : 0; }
    function rectOf(r) { return { x: num(r, "x"), y: num(r, "y"), w: num(r, "w"), h: num(r, "h") }; }

    // The move in progress runs progress from moveFrom to moveTo (0 or 1). Opening from the real rect, the drawn
    // rect is Motion.zoomRect(realRect, spreadRect, progress); closing from the spread it is
    // zoomRect(spreadRect, realRect, 1 - progress), so both directions ease out. A move that starts half-way (the
    // overview toggled during an animation) starts from the rect drawn at that moment (moveStartRect).
    property real moveFrom: 0
    property real moveTo: 0
    property var moveStartRect: null
    readonly property var zoomed: {
        const real = rectOf(realRect);
        const spread = rectOf(spreadRect);
        const to = moveTo >= 1 ? spread : real;
        const from = moveStartRect || (moveTo >= 1 ? real : spread);
        const span = moveTo - moveFrom;
        const t = span === 0 ? 1 : (progress - moveFrom) / span;
        return Motion.zoomRect(from, to, t);
    }

    x: zoomed.x
    y: zoomed.y
    width: Math.max(0, zoomed.w)
    height: Math.max(0, zoomed.h)
    // The highlighted tile's ring and title pill go above its neighbours.
    z: highlighted ? 1 : 0

    // The move is timed by the wall clock from the moment open changed, not from the first animation tick (an
    // animation counted from its first tick ended up to two frames late in the nest). It lands on the frame nearest
    // to that moment plus the duration: a frame less than half a frame before the end already shows the end.
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
            traceStep(elapsed);
            if (open) openAnimationDone(); else closeAnimationDone();
            return;
        }
        progress = moveFrom + (moveTo - moveFrom) * t;
        traceStep(elapsed);
    }

    function traceStep(elapsed) {
        if (moveTo < 1) return;
        const r = zoomed;
        openTrace.push({ e: elapsed, x: r.x, y: r.y, w: r.w, h: r.h });
    }

    function run() {
        move.stop();
        const to = open ? 1 : 0;
        const dur = Math.max(0, Math.min(animationMs, 200));
        if (dur === 0 || progress === to) {
            moveStartRect = null;
            moveFrom = to;
            moveTo = to;
            progress = to;
            if (open) openAnimationDone(); else closeAnimationDone();
            return;
        }
        moveStartRect = progress > 0 && progress < 1 ? { x: x, y: y, w: width, h: height } : null;
        moveFrom = progress;
        moveTo = to;
        moveStart = Date.now();
        if (to === 1) openTrace = [];
        moveDuration = Math.max(1, Math.round(dur * Math.abs(to - progress)));
        move.start();
    }

    onOpenChanged: {
        stepCount = 0;
        run();
    }
    Component.onCompleted: if (open) run()

    readonly property string iconSource: {
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
    readonly property real cornerRadius: Math.max(0, Math.min(radius, width / 2, height / 2))
    readonly property real dimmed: dragging ? 0.35 : 1

    // Soft shadow under the tile, outside the rect (an analytic shadow, no extra render pass).
    RectangularShadow {
        anchors.fill: parent
        visible: tile.width > 0 && tile.height > 0
        radius: tile.cornerRadius
        offset.y: 6
        blur: 24
        spread: 0
        color: Qt.rgba(0, 0, 0, 0.55 * tile.dimmed)
    }

    // Highlight ring in the accent colour: outside the rect, never over the image.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -5
        radius: tile.cornerRadius + 5
        color: "transparent"
        border.width: 3
        border.color: tile.accent
        antialiasing: true
        visible: tile.highlighted && !tile.dragging
    }

    // Placeholder while the live image has no frame yet: a dim rounded panel with the icon.
    Rectangle {
        anchors.fill: parent
        radius: tile.cornerRadius
        color: Qt.rgba(tile.panelColor.r, tile.panelColor.g, tile.panelColor.b, 0.85)
        visible: !view.hasContent
        opacity: tile.dimmed
        IconImage {
            anchors.centerIn: parent
            implicitSize: Math.max(16, Math.min(64, Math.min(parent.width, parent.height) / 3))
            source: tile.iconSource
            visible: parent.width > 24 && parent.height > 24
        }
    }

    // The rounded mask for the live image (only its alpha counts).
    readonly property Item maskItem: mask
    Item {
        id: mask
        width: view.width
        height: view.height
        layer.enabled: true
        visible: false
        Rectangle {
            anchors.fill: parent
            radius: tile.cornerRadius
            color: "black"
            antialiasing: true
        }
    }

    // The live image fills the rect exactly, at full opacity, untinted, clipped to the rounded mask. The tile is
    // never larger than the window (tileScale <= 1), so the image is only ever scaled down: filtered when it is,
    // drawn pixel for pixel when it is at its real size.
    ScreencopyView {
        id: view
        anchors.fill: parent
        captureSource: tile.toplevel
        live: true
        paintCursor: false
        smooth: tile.tileScale < 0.999 || !tile.settled
        opacity: tile.dimmed
        layer.enabled: tile.cornerRadius > 0 && width > 0 && height > 0
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: tile.maskItem
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }

    // Close button: a 24x24 disc of the accent centred on the rect's top-right corner, exactly at
    // hittest.mjs closeRect (relative to the tile: x w - 12, y -12), above the image and the ring. The cross stays
    // inside the middle 12x12 (two 10x2 bars at 45 degrees reach at most 4.3 px from the centre), so the disc is
    // plain accent from 6 px outwards.
    Item {
        id: closeButton
        z: 3
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

    // The app icon, small, centred on the bottom edge (half over the image). At most a fifth of the tile's smaller
    // side, so it stays below 90 % of the tile's height.
    IconImage {
        id: icon
        z: 2
        readonly property real size: Math.round(Math.max(16, Math.min(40, Math.min(tile.width, tile.height) / 5)))
        implicitSize: size
        x: (tile.width - size) / 2
        y: tile.height - size / 2
        source: tile.iconSource
        visible: tile.open && tile.settled && tile.width >= 5 * 16 && tile.height >= 5 * 16
        opacity: tile.dimmed
    }

    // The title, in a pill under the icon, on hover only.
    Rectangle {
        id: titlePill
        z: 2
        readonly property real padX: 10
        width: Math.min(titleText.implicitWidth + 2 * padX, Math.max(tile.width, 160))
        height: titleText.implicitHeight + 8
        radius: height / 2
        x: (tile.width - width) / 2
        y: tile.height + (icon.visible ? icon.size / 2 : 0) + 6
        color: Qt.rgba(tile.panelColor.r, tile.panelColor.g, tile.panelColor.b, 0.92)
        border.width: 1
        border.color: Qt.rgba(tile.textColor.r, tile.textColor.g, tile.textColor.b, 0.15)
        visible: tile.highlighted && tile.open && tile.settled && !tile.dragging && (tile.title || tile.appClass) !== ""
        Text {
            id: titleText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 2 * titlePill.padX)
            text: tile.title || tile.appClass
            color: tile.textColor
            font.family: tile.fontFamily
            font.pixelSize: tile.titleSize
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }
}
