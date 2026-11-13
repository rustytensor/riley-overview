// SPDX-License-Identifier: GPL-3.0-or-later
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "lib/config.mjs" as Cfg

// $XDG_CONFIG_HOME/riley-overview/config.xml (default ~/.config): checked with xmllint against the schema, then read
// by lib/config.mjs, which applies the same rules itself. A missing file means the defaults. A broken file means
// the defaults plus one notification per load ($RILEYOVERVIEW_NOTIFY, default notify-send, called as
// CMD SUMMARY BODY). The file is watched: an edit is loaded at once.
//
// The schema is $RILEYOVERVIEW_XSD, else <shell>/../config.xsd (installed layout), else <shell>/../data/config.xsd
// (source tree).
Singleton {
    id: root

    property var values: Cfg.parseConfig("").config     // a fresh copy of the defaults
    property bool ok: true                              // false: the file exists but is broken (defaults in use)
    property var errors: []
    property bool loaded: false

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string path: configHome + "/riley-overview/config.xml"
    readonly property string notifyCommand: Quickshell.env("RILEYOVERVIEW_NOTIFY") || "notify-send"
    readonly property string shellDir: String(Quickshell.shellDir).replace(/\/+$/, "")

    property string pendingText: ""

    function defaults() {
        return Cfg.parseConfig("").config;
    }

    function useDefaults(ok, errors) {
        root.values = root.defaults();
        root.ok = ok;
        root.errors = errors;
        root.loaded = true;
    }

    function broken(errors) {
        root.useDefaults(false, errors);
        const why = String(errors[0] || "unknown error").replace(/[\r\n]+/g, " ").trim();
        console.warn("riley-overview: " + root.path + " is not valid, using the defaults: " + errors.join("; "));
        Quickshell.execDetached([root.notifyCommand, "riley-overview: config.xml is not valid",
                                 "Using the defaults. " + root.path + ": " + why]);
    }

    // xmllint finished: 0 valid, 127 not installed (config.mjs alone then), anything else invalid.
    function linted(code, stderr) {
        const text = root.pendingText;
        if (code !== 0 && code !== 127) {
            const lines = String(stderr).split("\n").map(l => l.trim())
                .filter(l => l !== "" && !/ fails to validate$/.test(l) && !/ validates$/.test(l));
            const msg = (lines[0] || ("xmllint exit " + code)).replace(root.path + ":", "line ");
            root.broken([msg]);
            return;
        }
        const r = Cfg.parseConfig(text);
        if (!r.ok) {
            root.broken(r.errors);
            return;
        }
        root.values = r.config;
        root.ok = true;
        root.errors = [];
        root.loaded = true;
    }

    FileView {
        id: file
        path: root.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.pendingText = text();
            if (lint.running) lint.again = true;
            else lint.running = true;
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) root.useDefaults(true, []);
            else root.broken(["cannot read the file (error " + error + ")"]);
        }
    }

    Process {
        id: lint
        property bool again: false
        command: ["sh", "-c",
                  'x=${RILEYOVERVIEW_XSD:-}; [ -n "$x" ] || x="$1/../config.xsd"; [ -f "$x" ] || x="$1/../data/config.xsd"; ' +
                  'command -v xmllint >/dev/null 2>&1 || exit 127; exec xmllint --noout --schema "$x" "$2"',
                  "sh", root.shellDir, root.path]
        stderr: StdioCollector { id: lintErr }
        onExited: code => {
            if (again) {
                again = false;
                Qt.callLater(() => { lint.running = true; });
                return;
            }
            root.linted(code, lintErr.text);
        }
    }
}
