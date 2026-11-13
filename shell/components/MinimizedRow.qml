// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound
//
// The row of minimized (hidden) windows under the spread. entries: layoutMonitor(...).minimized merged with
// {toplevel, appClass, title}; each rect is surface-relative logical px. No input handling.
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland

Item {
    id: root

    property var entries: []
    property color accent: "#7aa2f7"
    property color textColor: "#e6e6e6"
    property string fontFamily: ""
    property string highlightedAddress: ""

    anchors.fill: parent

    function iconFor(c) {
        c = c || "";
        const entry = c ? DesktopEntries.heuristicLookup(c) : null;
        for (const n of [entry ? entry.icon : "", c, c.toLowerCase()]) {
            if (!n) continue;
            const p = Quickshell.iconPath(n, true);
            if (p) return p;
        }
        return Quickshell.iconPath("application-x-executable", true);
    }

    Repeater {
        model: root.entries || []
        delegate: Item {
            id: cell
            required property var modelData
            x: modelData.x
            y: modelData.y
            width: modelData.w
            height: modelData.h

            Rectangle {
                anchors.fill: parent
                anchors.margins: -4
                radius: 4
                color: "transparent"
                border.width: 2
                border.color: root.accent
                visible: root.highlightedAddress !== "" && root.highlightedAddress === cell.modelData.address
            }
            Rectangle {
                anchors.fill: parent
                color: "#33000000"
                visible: !shot.hasContent
            }
            // A window on the hidden workspace may never send a frame; then the icon stands in for it.
            ScreencopyView {
                id: shot
                anchors.fill: parent
                captureSource: cell.modelData.toplevel || null
                live: true
                paintCursor: false
            }
            IconImage {
                implicitSize: Math.min(32, cell.height / 3)
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 4
                source: root.iconFor(cell.modelData.appClass)
            }
        }
    }
}
