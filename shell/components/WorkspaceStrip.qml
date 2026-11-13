// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound
//
// The workspace strip at the top of the overview. entries: layoutMonitor(...).strip, each with its rect in
// surface-relative logical px. The current workspace shows a still of the output (taken with capture(), which the
// Overlay calls while the surface is unmapped, so the still is the desktop and not the overview itself) and the
// accent frame; other workspaces show their number; the empty one at the end a plain "+". During a drag the entry
// under the pointer (dropIndex) is filled with a light accent tint and framed in the text colour, so it never looks
// like the current-workspace marker (accent frame, no fill). No input handling.
import QtQuick
import Quickshell.Wayland

Item {
    id: root

    property var entries: []
    property var screen: null            // ShellScreen
    property color accent: "#7aa2f7"
    property color textColor: "#e6e6e6"
    property color panelColor: "#24283b"
    property string fontFamily: ""
    property int hoveredIndex: -1        // optional: the Overlay may set the entry under the pointer
    property int dropIndex: -1           // the entry under a drag (its strip index), -1 for none

    anchors.fill: parent

    // Take a new still of the output. Call it before the surface maps (hidden), e.g. right before show.
    function capture() {
        if (screenShot.captureSource) screenShot.captureFrame();
    }

    readonly property var currentEntry: {
        for (const e of entries || []) if (e.current) return e;
        return null;
    }

    // The panels behind everything.
    Repeater {
        model: root.entries || []
        delegate: Rectangle {
            required property var modelData
            x: modelData.x
            y: modelData.y
            width: modelData.w
            height: modelData.h
            z: 0
            radius: 4
            color: modelData.empty ? "transparent" : root.panelColor
            border.width: modelData.empty ? 2 : 1
            border.color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, modelData.empty ? 0.35 : 0.2)
        }
    }

    // One still of the output, drawn in the current entry's rect; not live, so it never films the overview.
    ScreencopyView {
        id: screenShot
        z: 1
        x: root.currentEntry ? root.currentEntry.x + 1 : 0
        y: root.currentEntry ? root.currentEntry.y + 1 : 0
        width: root.currentEntry ? Math.max(0, root.currentEntry.w - 2) : 0
        height: root.currentEntry ? Math.max(0, root.currentEntry.h - 2) : 0
        visible: root.currentEntry !== null && hasContent
        captureSource: root.screen
        live: false
        paintCursor: false
    }

    // Labels and frames on top.
    Repeater {
        model: root.entries || []
        delegate: Item {
            id: cell
            required property var modelData
            x: modelData.x
            y: modelData.y
            width: modelData.w
            height: modelData.h
            z: 2
            readonly property bool dropTarget: root.dropIndex >= 0 && root.dropIndex === cell.modelData.index

            Text {
                anchors.centerIn: parent
                visible: cell.modelData.empty || !(cell.modelData.current && screenShot.hasContent)
                text: cell.modelData.empty ? "+" : (cell.modelData.name || String(cell.modelData.id))
                color: root.textColor
                opacity: cell.modelData.empty ? 0.6 : 0.85
                font.family: root.fontFamily
                font.pixelSize: Math.max(8, cell.modelData.empty ? Math.min(48, cell.height / 2) : Math.min(32, cell.height / 3))
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: -4
                radius: 6
                color: "transparent"
                border.width: cell.modelData.current ? 3 : 2
                border.color: cell.modelData.current ? root.accent
                                                     : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6)
                visible: (cell.modelData.current || root.hoveredIndex === cell.modelData.index) && !cell.dropTarget
            }
            // Drop target: tint over the entry plus a frame in the text colour, drawn above the still.
            Rectangle {
                anchors.fill: parent
                anchors.margins: -4
                radius: 6
                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.3)
                border.width: 3
                border.color: root.textColor
                visible: cell.dropTarget
            }
        }
    }
}
