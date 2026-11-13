// SPDX-License-Identifier: GPL-3.0-or-later
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Colours and font from $XDG_CONFIG_HOME/riley/bar.json (default ~/.config), the file Riley's bar reads (written by
// hypr-theme); a theme switch recolours at once. Missing file or keys: the bar's own defaults.
Singleton {
    id: root
    property color base: "#151a23"
    property color surface0: "#1d2430"
    property color surface1: "#283244"
    property color text: "#f0ece0"
    property color subtext: "#d6d2c4"
    property color accent: "#e9a046"
    property string font: "IBM Plex Mono"
    // true once the file was read or found missing
    property bool loaded: false

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")

    function apply(text) {
        try {
            const t = JSON.parse(text);
            for (const k of ["base", "surface0", "surface1", "text", "subtext", "accent", "font"])
                if (t[k]) root[k] = t[k];
        } catch (e) {}
    }

    FileView {
        path: root.configHome + "/riley/bar.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { root.apply(text()); root.loaded = true; }
        onLoadFailed: root.loaded = true
    }
}
