// SPDX-License-Identifier: GPL-3.0-or-later
//
// The search field between the workspace strip and the spread (docs/interact.md "Components"). Drawing only: the
// Overlay's key handling edits the query. rect is strip.mjs searchArea(W, H, cfg), surface-relative logical px;
// the field is a pill centred in it, never outside it. Empty query: a dim "Type to search" hint. A query with no
// visible window (noMatch): the hint "Enter: search in the launcher" after the text.
import QtQuick

Item {
    id: root

    property var rect: ({ x: 0, y: 0, w: 0, h: 0 })
    property string query: ""
    property bool noMatch: false
    property color accent: "#7aa2f7"
    property color textColor: "#e6e6e6"
    property color panelColor: "#24283b"
    property string fontFamily: ""

    function num(k) { return rect && isFinite(rect[k]) ? rect[k] : 0; }

    readonly property real fieldW: Math.min(Math.max(0, num("w")), 520)
    readonly property real fieldH: Math.max(0, num("h"))

    x: num("x") + (Math.max(0, num("w")) - fieldW) / 2
    y: num("y")
    width: fieldW
    height: fieldH
    visible: width > 0 && height > 0

    Rectangle {
        id: pill
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(root.panelColor.r, root.panelColor.g, root.panelColor.b, 0.9)
        border.width: root.query.length > 0 ? 2 : 1
        border.color: root.query.length > 0 ? root.accent
                                            : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.25)
        clip: true

        Row {
            anchors.left: parent.left
            anchors.leftMargin: pill.radius
            anchors.right: parent.right
            anchors.rightMargin: pill.radius
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            Text {
                id: queryText
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - (hint.visible ? hint.implicitWidth + parent.spacing : 0))
                text: root.query.length > 0 ? root.query : "Type to search"
                color: root.textColor
                opacity: root.query.length > 0 ? 1 : 0.5
                font.family: root.fontFamily
                font.pixelSize: Math.max(8, Math.round(root.height * 0.42))
                elide: Text.ElideLeft
                maximumLineCount: 1
            }
            Text {
                id: hint
                anchors.verticalCenter: parent.verticalCenter
                visible: root.noMatch && root.query.length > 0
                text: "Enter: search in the launcher"
                color: root.textColor
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Math.max(8, Math.round(root.height * 0.32))
                maximumLineCount: 1
            }
        }
    }
}
