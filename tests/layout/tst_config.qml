// SPDX-License-Identifier: GPL-3.0-or-later
// M1 gate: config defaults and value parsing (shell/lib/config.mjs). The XML samples are tests/layout/data/*.xml;
// the gate also runs each through xmllint against data/config.xsd and expects the same valid/invalid verdict.
// A file that is not valid is not used at all: parseConfig returns ok false, the defaults, and at least one error.
import QtQuick
import QtTest
import "../lib/config.mjs" as Config

TestCase {
    name: "config"

    // The defaults (docs/design.md "Config"), also written out in data/config.example.xml.
    readonly property var defaults: ({ margin: 24, stripHeight: 120, stripSpacing: 16, searchHeight: 40, sectionGap: 16,
                                       windowSpacing: 24, maxScale: 1.0, animationMs: 200, launcher: "fuzzel" })

    function read(name) {
        const x = new XMLHttpRequest();
        x.open("GET", Qt.resolvedUrl("data/" + name), false);
        x.send();
        return x.responseText;
    }
    function withValues(v) {
        const o = JSON.parse(JSON.stringify(defaults));
        for (const k in v) o[k] = v[k];
        return o;
    }

    // Key order does not matter.
    function canon(o) { return JSON.stringify(Object.keys(o).sort().map(k => [k, o[k]])); }

    function test_defaults() {
        compare(canon(Config.DEFAULTS), canon(defaults));
    }

    function test_parse_data() {
        return [
            // the example file spells out the defaults
            { tag: "example.xml", file: "example.xml", ok: true, e: defaults },
            { tag: "valid.xml", file: "valid.xml", ok: true,
              e: withValues({ margin: 32, stripHeight: 100, stripSpacing: 12, searchHeight: 44, sectionGap: 20,
                              windowSpacing: 30, maxScale: 0.9, animationMs: 150, launcher: "fuzzel --dmenu" }) },
            // " 32 " is collapsed to 32; &quot; is decoded; the launcher keeps its inner space
            { tag: "partial.xml", file: "partial.xml", ok: true,
              e: withValues({ windowSpacing: 32, launcher: "fuzzel --prompt=\"run \"" }) },
            { tag: "empty.xml", file: "empty.xml", ok: true, e: defaults },
            { tag: "bad-range.xml", file: "bad-range.xml", ok: false, e: defaults },
            { tag: "bad-element.xml", file: "bad-element.xml", ok: false, e: defaults },
            { tag: "bad-version.xml", file: "bad-version.xml", ok: false, e: defaults },
            { tag: "bad-duplicate.xml", file: "bad-duplicate.xml", ok: false, e: defaults },
            { tag: "bad-number.xml", file: "bad-number.xml", ok: false, e: defaults },
            { tag: "not-xml.xml", file: "not-xml.xml", ok: false, e: defaults },
        ];
    }
    function test_parse(d) {
        const text = read(d.file);
        verify(text.length > 0, "could not read " + d.file);
        const r = Config.parseConfig(text);
        compare(r.ok, d.ok, "ok");
        compare(canon(r.config), canon(d.e), "config");
        if (d.ok) compare(r.errors.length, 0, "errors on a valid file: " + r.errors.join("; "));
        else verify(r.errors.length > 0, "no error message for an invalid file");
    }

    // parseConfig hands out a fresh object: changing it must not change the defaults.
    function test_fresh_object() {
        const r = Config.parseConfig(read("empty.xml"));
        r.config.margin = 999;
        compare(Config.DEFAULTS.margin, 24);
    }
}
