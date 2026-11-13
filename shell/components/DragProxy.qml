// SPDX-License-Identifier: GPL-3.0-or-later
//
// The small live image that follows the pointer during a drag (docs/interact.md "Components"). px, py: the
// pointer, surface-relative logical px; the proxy is centred on it. w, h: its size (the Overlay passes the tile size
// scaled to at most 300 wide). Drawing only; the Overlay shows it on the surface the pointer is over.
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland

Item {
    id: proxy

    property var toplevel: null
    property string appClass: ""
    property real px: 0
    property real py: 0
    property real w: 0
    property real h: 0
    property color accent: "#7aa2f7"

    x: px - width / 2
    y: py - height / 2
    width: Math.max(0, w)
    height: Math.max(0, h)
    z: 100
    opacity: 0.9

    // Placeholder until the image has a frame: a dim panel with the app icon.
    Rectangle {
        anchors.fill: parent
        color: "#66000000"
        visible: !view.hasContent
        IconImage {
            anchors.centerIn: parent
            implicitSize: Math.max(16, Math.min(64, Math.min(parent.width, parent.height) / 2))
            visible: parent.width > 24 && parent.height > 24
            source: {
                const c = proxy.appClass || "";
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
    }

    ScreencopyView {
        id: view
        anchors.fill: parent
        captureSource: proxy.toplevel
        live: true
        paintCursor: false
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -2
        radius: 4
        color: "transparent"
        border.width: 2
        border.color: proxy.accent
    }
}
