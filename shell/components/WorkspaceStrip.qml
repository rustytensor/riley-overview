// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound
//
// The desktops bar at the top of the overview (docs/design.md "Desktops bar"; the file keeps its M2 name).
// Collapsed (`expanded` false): one slim name pill per workspace at `names` (layoutMonitor(...).names), the current
// one marked in the accent, a "+" pill last for a new workspace. Expanded (the pointer in the band, or any drag):
// small live previews at `entries` (layoutMonitor(...).strip): the wallpaper with each of the workspace's windows
// drawn live at its place, the current one framed in the accent, the "+" entry a plain dashed panel. The current
// workspace's preview is a still of the output (capture(), called while the surface is unmapped, so it is the
// desktop and not the overview itself) when it has one.
//
// During a drag the entry under the pointer (dropIndex) is filled with a light accent tint and framed in the text
// colour, so it never looks like the current-workspace marker (accent frame, no fill). No input handling: the
// Overlay hit-tests the expanded rects (layoutMonitor(...).strip) whenever the pointer is in the band.
import QtQuick
import Quickshell.Wayland

Item {
    id: root

    property var entries: []             // layoutMonitor(...).strip: the expanded rects
    property var names: []               // layoutMonitor(...).names: the collapsed rects
    property bool expanded: false
    // Per workspace id: [{ toplevel, x, y, w, h }] with x, y, w, h fractions of the monitor (0..1), back to front.
    property var previews: ({})
    property string wallpaper: ""        // file path, "" for none
    property var screen: null            // ShellScreen
    property color accent: "#7aa2f7"
    property color textColor: "#e6e6e6"
    property color panelColor: "#24283b"
    property string fontFamily: ""
    property int animationMs: 0
    property int hoveredIndex: -1        // the entry under the pointer (strip index), -1 for none
    property int dropIndex: -1           // the entry under a drag (its strip index), -1 for none

    anchors.fill: parent

    // Take a new still of the output. Call it before the surface maps (hidden), e.g. right before show.
    function capture() {
        if (screenShot.captureSource) screenShot.captureFrame();
    }

    function isPlus(e) {
        return e && (e.plus !== undefined ? e.plus === true : e.empty === true);
    }

    readonly property var currentEntry: {
        for (const e of entries || []) if (e.current) return e;
        return null;
    }
    readonly property int fadeMs: Math.max(0, Math.min(120, animationMs))
    readonly property string wallpaperUrl: wallpaper === "" ? "" : (wallpaper.startsWith("/") ? "file://" + wallpaper : wallpaper)

    // ---- collapsed: the names row ------------------------------------------------------------------------------
    Item {
        id: namesRow
        anchors.fill: parent
        opacity: root.expanded ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: root.fadeMs; easing.type: Easing.OutCubic } }

        Repeater {
            model: root.names || []
            delegate: Item {
                id: nameCell
                required property var modelData
                readonly property bool plus: root.isPlus(modelData)
                readonly property bool current: modelData.current === true
                x: modelData.x
                y: modelData.y
                width: modelData.w
                height: modelData.h

                Rectangle {
                    id: pill
                    readonly property real want: nameCell.plus ? nameCell.height * 1.6 : nameLabel.implicitWidth + 28
                    width: Math.min(nameCell.width, Math.max(nameCell.height * 1.6, want))
                    height: nameCell.height
                    anchors.centerIn: parent
                    radius: height / 2
                    color: nameCell.current ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)
                                            : Qt.rgba(root.panelColor.r, root.panelColor.g, root.panelColor.b, nameCell.plus ? 0.5 : 0.85)
                    border.width: nameCell.current ? 2 : 1
                    border.color: nameCell.current ? root.accent
                                                   : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.2)
                    antialiasing: true
                    Text {
                        id: nameLabel
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, Math.max(0, pill.width - 16))
                        text: nameCell.plus ? "+" : (nameCell.modelData.name || String(nameCell.modelData.id))
                        color: root.textColor
                        opacity: nameCell.plus ? 0.7 : 0.95
                        font.family: root.fontFamily
                        font.pixelSize: Math.max(8, Math.round(nameCell.height * (nameCell.plus ? 0.6 : 0.46)))
                        font.bold: nameCell.current
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }
            }
        }
    }

    // ---- expanded: live previews -------------------------------------------------------------------------------
    Item {
        id: previewRow
        anchors.fill: parent
        opacity: root.expanded ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: root.fadeMs; easing.type: Easing.OutCubic } }

        // One still of the output, drawn in the current entry's rect; not live, so it never films the overview.
        // Kept outside the Loader so the still taken before the show survives collapsing.
        ScreencopyView {
            id: screenShot
            z: 1
            x: root.currentEntry ? root.currentEntry.x : 0
            y: root.currentEntry ? root.currentEntry.y : 0
            width: root.currentEntry ? Math.max(0, root.currentEntry.w) : 0
            height: root.currentEntry ? Math.max(0, root.currentEntry.h) : 0
            visible: root.currentEntry !== null && hasContent
            captureSource: root.screen
            live: false
            paintCursor: false
        }

        Repeater {
            model: root.entries || []
            delegate: Item {
                id: cell
                required property var modelData
                readonly property bool plus: root.isPlus(modelData)
                readonly property bool current: modelData.current === true
                readonly property bool dropTarget: root.dropIndex >= 0 && root.dropIndex === cell.modelData.index
                readonly property bool stillShown: cell.current && screenShot.hasContent
                x: modelData.x
                y: modelData.y
                width: modelData.w
                height: modelData.h
                z: 2                     // above the still; the panel hides itself where the still shows

                // Panel: the "+" entry dashed-looking (thin, dim border), the others the wallpaper.
                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: cell.plus ? Qt.rgba(root.panelColor.r, root.panelColor.g, root.panelColor.b, 0.35) : root.panelColor
                    border.width: cell.plus ? 2 : 0
                    border.color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.35)
                    clip: true
                    visible: !cell.stillShown
                    Image {
                        anchors.fill: parent
                        visible: !cell.plus && root.wallpaperUrl !== "" && status === Image.Ready
                        source: cell.plus || !root.expanded ? "" : root.wallpaperUrl
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(Math.max(1, Math.ceil(cell.width)), Math.max(1, Math.ceil(cell.height)))
                        asynchronous: true
                        cache: true
                    }
                    // The workspace's windows, live, only while the bar is expanded.
                    Loader {
                        anchors.fill: parent
                        active: root.expanded && !cell.plus && !cell.stillShown
                        sourceComponent: Item {
                            Repeater {
                                model: root.previews[cell.modelData.id] || []
                                delegate: ScreencopyView {
                                    required property var modelData
                                    x: modelData.x * cell.width
                                    y: modelData.y * cell.height
                                    width: modelData.w * cell.width
                                    height: modelData.h * cell.height
                                    captureSource: modelData.toplevel || null
                                    live: true
                                    paintCursor: false
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: cell.plus
                    text: "+"
                    color: root.textColor
                    opacity: 0.7
                    font.family: root.fontFamily
                    font.pixelSize: Math.max(8, Math.min(48, cell.height / 2))
                }
                // The workspace's name, in a small pill at the preview's bottom.
                Rectangle {
                    visible: !cell.plus && cell.height >= 40
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    width: Math.min(cell.width - 8, previewName.implicitWidth + 12)
                    height: previewName.implicitHeight + 2
                    radius: height / 2
                    color: Qt.rgba(0, 0, 0, 0.55)
                    Text {
                        id: previewName
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - 8)
                        text: cell.modelData.name || String(cell.modelData.id)
                        color: "white"
                        font.family: root.fontFamily
                        font.pixelSize: Math.max(8, Math.min(14, Math.round(cell.height / 7)))
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }
                // Current marker (accent) or hover frame (lighter accent), outside the preview.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -4
                    radius: 9
                    color: "transparent"
                    border.width: cell.current ? 3 : 2
                    border.color: cell.current ? root.accent
                                               : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6)
                    antialiasing: true
                    visible: (cell.current || root.hoveredIndex === cell.modelData.index) && !cell.dropTarget
                }
                // Drop target: tint over the entry plus a frame in the text colour, drawn above the previews.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -4
                    radius: 9
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.3)
                    border.width: 3
                    border.color: root.textColor
                    antialiasing: true
                    visible: cell.dropTarget
                }
            }
        }
    }
}
