// SPDX-License-Identifier: GPL-3.0-or-later
//
// One window in the overview: its live image, a hover frame around it, the app icon and title under it, and the
// move between where the window really is and where the overview puts it. No input handling: the Overlay
// hit-tests the same rects (docs/overlay.md "Components").
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

    // Looks; the Overlay may bind these to the Theme. Not part of the hit-test contract.
    property color accent: "#7aa2f7"
    property color textColor: "#e6e6e6"
    property string fontFamily: ""
    property int titleSize: 12

    signal closeAnimationDone()
    signal closeRequested(string address)

    // 0 = at realRect, 1 = at spreadRect.
    property real progress: 0
    // True once the move to the spread is finished (the test hook waits for this).
    readonly property bool settled: open ? progress >= 1 : progress <= 0
    // True when the live image has a frame (or there is nothing to capture).
    readonly property bool hasContent: !toplevel || view.hasContent
    // The rect as drawn right now, monitor-relative logical.
    readonly property var drawnRect: ({ x: x, y: y, w: width, h: height })

    function lerp(a, b) { return a + (b - a) * progress; }
    function num(r, k) { return r && isFinite(r[k]) ? r[k] : 0; }

    x: lerp(num(realRect, "x"), num(spreadRect, "x"))
    y: lerp(num(realRect, "y"), num(spreadRect, "y"))
    width: Math.max(0, lerp(num(realRect, "w"), num(spreadRect, "w")))
    height: Math.max(0, lerp(num(realRect, "h"), num(spreadRect, "h")))

    NumberAnimation {
        id: move
        target: tile
        property: "progress"
        easing.type: Easing.OutCubic
        onFinished: if (!tile.open) tile.closeAnimationDone()
    }

    function run() {
        move.stop();
        const to = open ? 1 : 0;
        const dur = Math.max(0, Math.min(animationMs, 200));
        if (dur === 0 || progress === to) {
            progress = to;
            if (!open) closeAnimationDone();
            return;
        }
        move.from = progress;
        move.to = to;
        move.duration = Math.round(dur * Math.abs(to - progress));
        move.start();
    }

    onOpenChanged: run()
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
    }

    // Close button stub (M3 wires the click through the Overlay's hit-test): outside the image's top-right corner.
    Rectangle {
        width: 24
        height: 24
        radius: 12
        x: parent.width - width / 2
        y: -height / 2
        color: tile.accent
        visible: tile.highlighted && tile.open && tile.settled
        Text {
            anchors.centerIn: parent
            text: "×"
            color: tile.textColor
            font.pixelSize: 16
            font.bold: true
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
