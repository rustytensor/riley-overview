// SPDX-License-Identifier: GPL-3.0-or-later
//
// The overview's backdrop: Riley's wallpaper for this monitor (cover fit), blurred, under black at `dim`; without
// a wallpaper (or while it loads, or if it fails), `fallbackColor` under the same black. Fills its parent.
//
// It fades with the zoom (docs/design.md "Motion"): `open` runs `progress` from 0 to 1 over `animationMs` (back on
// close), timed by the wall clock like WindowTile's move; the black's opacity is easeOutCubic(progress) times `dim`
// and the blur grows with it. `animationMs` 0 jumps.
import QtQuick
import QtQuick.Effects
import "../lib/motion.mjs" as Motion

Item {
    id: root

    property string wallpaper: ""        // file path, "" for none
    property color fallbackColor: "#1a1b26"
    property real dim: 0.5               // the full dim: the gate expects 50 % black once open
    property int blurRadius: 48
    property bool open: false
    property int animationMs: 0

    signal openAnimationDone()

    // 0 closed, 1 open; linear in time.
    property real progress: 0
    // How far the fade is, eased: 0 no dim and no blur, 1 the full dim and blur.
    readonly property real amount: {
        const span = fadeTo - fadeFrom;
        const t = span === 0 ? 1 : (progress - fadeFrom) / span;
        return amountFrom + Motion.easeOutCubic(t) * (fadeTo - amountFrom);
    }

    // True when what is drawn is final: no wallpaper, or the picture has loaded (or failed and the colour shows).
    readonly property bool ready: wallpaper === "" || picture.status === Image.Ready || picture.status === Image.Error

    anchors.fill: parent
    clip: true

    property real fadeFrom: 0
    property real fadeTo: 0
    property real amountFrom: 0
    property real fadeStart: 0
    property int fadeDuration: 0

    FrameAnimation {
        id: fade
        onTriggered: root.stepFade()
    }

    function stepFade() {
        const elapsed = Date.now() - fadeStart;
        const frameMs = fade.smoothFrameTime > 0 ? Math.min(50, fade.smoothFrameTime * 1000) : 1000 / 60;
        if (elapsed + frameMs / 2 >= fadeDuration) {
            fade.stop();
            progress = fadeTo;
            if (open) openAnimationDone();
            return;
        }
        progress = fadeFrom + (fadeTo - fadeFrom) * Math.min(1, Math.max(0, elapsed / fadeDuration));
    }

    function run() {
        fade.stop();
        const to = open ? 1 : 0;
        const dur = Math.max(0, Math.min(animationMs, 200));
        if (dur === 0 || progress === to) {
            fadeFrom = to;
            fadeTo = to;
            amountFrom = to;
            progress = to;
            if (open) openAnimationDone();
            return;
        }
        amountFrom = amount;
        fadeFrom = progress;
        fadeTo = to;
        fadeStart = Date.now();
        fadeDuration = Math.max(1, Math.round(dur * Math.abs(to - progress)));
        fade.start();
    }

    onOpenChanged: run()
    Component.onCompleted: if (open) run()

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
        blur: root.amount
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.dim * root.amount
    }
}
