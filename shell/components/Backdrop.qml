// SPDX-License-Identifier: GPL-3.0-or-later
//
// The overview's backdrop: Riley's wallpaper for this monitor (cover fit), blurred, under black at `dim`; without
// a wallpaper (or while it loads, or if it fails), `fallbackColor` under the same black. Fills its parent.
import QtQuick
import QtQuick.Effects

Item {
    id: root

    property string wallpaper: ""        // file path, "" for none
    property color fallbackColor: "#1a1b26"
    property real dim: 0.5               // fixed: the gate expects 50 % black
    property int blurRadius: 48

    // True when what is drawn is final: no wallpaper, or the picture has loaded (or failed and the colour shows).
    readonly property bool ready: wallpaper === "" || picture.status === Image.Ready || picture.status === Image.Error

    anchors.fill: parent
    clip: true

    Rectangle {
        anchors.fill: parent
        color: root.fallbackColor
    }

    Image {
        id: picture
        // Larger than the surface by the blur radius, so the blur never pulls in the transparent edge.
        anchors.fill: parent
        anchors.margins: -root.blurRadius
        source: root.wallpaper === "" ? "" : (root.wallpaper.startsWith("/") ? "file://" + root.wallpaper : root.wallpaper)
        fillMode: Image.PreserveAspectCrop
        // Decode no larger than drawn; the picture is blurred anyway.
        sourceSize: Qt.size(Math.max(1, Math.ceil(width)), Math.max(1, Math.ceil(height)))
        asynchronous: true
        cache: true
        smooth: true
        visible: false
    }

    MultiEffect {
        anchors.fill: picture
        source: picture
        visible: root.wallpaper !== "" && picture.status === Image.Ready
        autoPaddingEnabled: false
        blurEnabled: root.blurRadius > 0
        blurMax: Math.max(1, root.blurRadius)
        blur: 1.0
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.dim
    }
}
