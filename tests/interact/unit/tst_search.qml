// SPDX-License-Identifier: GPL-3.0-or-later
// M3 gate: window search and the launcher command line (shell/lib/search.mjs). Rules in docs/interact.md:
//   terms = query lower-cased, split on white space, empty pieces dropped; a window matches when every term is a
//   plain substring of its lower-cased title or of its lower-cased class; no terms -> every window.
//   launcherArgv: launcher trimmed and split on white space; "{query}" in any word -> replaced everywhere, nothing
//   appended; else "--search=" + text appended.
import QtQuick
import QtTest
import "../lib/search.mjs" as Search

TestCase {
    name: "search"

    function win(a, c, t) { return { address: a, class: c, title: t }; }
    readonly property var wins: [
        win("0xa1", "firefox", "Riley overview - Mozilla Firefox"),
        win("0xa2", "org.gnome.Nautilus", "Downloads"),
        win("0xa3", "kitty", "~/git/riley-overview"),
        win("0xa4", "kitty", "htop"),
        win("0xa5", "code", "overview.md - Visual Studio Code"),
        win("0xa6", "org.telegram.desktop", "Telegram (3)"),
        win("0xa7", "steam", "Steam"),
        win("0xa8", "", ""),
    ]

    // Worked out by reading each title and class (lower-cased) for each term:
    //  ""            no terms: all eight, input order
    //  "KITTY"       "kitty": class of a3 and a4 only
    //  "overview"    titles of a1 ("riley overview - ..."), a3 ("~/git/riley-overview"), a5 ("overview.md - ..."); no class
    //  "  riley   ov "  terms riley, ov: a1 (both in the title), a3 (both in the title); a5 has ov but no riley
    //  "org"         classes of a2 (org.gnome.nautilus) and a6 (org.telegram.desktop); no title holds "org"
    //  "steam code"  steam: a7 only; code: a5 only -> no window has both -> none
    //  "(3)"         a literal substring of a6's title "telegram (3)", not a pattern
    //  "e d"         e and d anywhere: a2 (e in the class "org.gnome.nautilus", d in "downloads"), a5 (title has both),
    //                a6 (e in the title, d in "desktop"); a1 has e but no d, a3 e but no d, a7 e but no d, a4 neither
    //  "TELEGRAM (3" terms telegram, (3: a6
    //  "Ü"           lower-cased ü: in no title or class -> none
    function test_filter_data() {
        return [
            { tag: "empty query: all", q: "", want: ["0xa1", "0xa2", "0xa3", "0xa4", "0xa5", "0xa6", "0xa7", "0xa8"] },
            { tag: "blank query: all", q: "   \t ", want: ["0xa1", "0xa2", "0xa3", "0xa4", "0xa5", "0xa6", "0xa7", "0xa8"] },
            { tag: "class, any case", q: "KITTY", want: ["0xa3", "0xa4"] },
            { tag: "title substring", q: "overview", want: ["0xa1", "0xa3", "0xa5"] },
            { tag: "two terms, spaces around", q: "  riley   ov ", want: ["0xa1", "0xa3"] },
            { tag: "class prefix", q: "org", want: ["0xa2", "0xa6"] },
            { tag: "two terms, no window has both", q: "steam code", want: [] },
            { tag: "literal, not a pattern", q: "(3)", want: ["0xa6"] },
            { tag: "terms across title and class", q: "e d", want: ["0xa2", "0xa5", "0xa6"] },
            { tag: "upper case query, open bracket", q: "TELEGRAM (3", want: ["0xa6"] },
            { tag: "nothing matches", q: "Ü", want: [] },
        ];
    }
    function test_filter(d) {
        compare(JSON.stringify(Search.filterWindows(wins, d.q)), JSON.stringify(d.want));
    }

    function test_matches_data() {
        return [
            { tag: "missing fields count as empty", w: { address: "x" }, q: "a", want: false },
            { tag: "missing fields, empty query", w: { address: "x" }, q: "", want: true },
            { tag: "dot is literal", w: win("x", "orgXgnome", "t"), q: "org.gnome", want: false },
            { tag: "each term on its own field", w: win("x", "kitty", "htop"), q: "htop kit", want: true },
        ];
    }
    function test_matches(d) {
        compare(Search.matches(d.w, d.q), d.want);
    }

    function test_terms() {
        compare(JSON.stringify(Search.terms("  Riley\tOV  x ")), JSON.stringify(["riley", "ov", "x"]));
        compare(JSON.stringify(Search.terms("")), "[]");
    }

    function test_input_not_modified() {
        const before = JSON.stringify(wins);
        Search.filterWindows(wins, "kitty");
        compare(JSON.stringify(wins), before);
    }

    function test_launcher_data() {
        return [
            { tag: "default fuzzel", l: "fuzzel", t: "xyz", want: ["fuzzel", "--search=xyz"] },
            { tag: "options kept, text not split", l: "  fuzzel   --prompt=run ", t: "a b", want: ["fuzzel", "--prompt=run", "--search=a b"] },
            { tag: "placeholder word", l: "my-launch --query {query}", t: "a b", want: ["my-launch", "--query", "a b"] },
            { tag: "placeholder twice in a word", l: "x {query}{query}", t: "q", want: ["x", "qq"] },
            { tag: "placeholder inside a word", l: "x --q={query}", t: "hi", want: ["x", "--q=hi"] },
            { tag: "no shell", l: "fuzzel", t: "$(rm -rf ~); `x`", want: ["fuzzel", "--search=$(rm -rf ~); `x`"] },
            { tag: "empty text", l: "fuzzel", t: "", want: ["fuzzel", "--search="] },
            { tag: "blank launcher", l: "   ", t: "x", want: [] },
        ];
    }
    function test_launcher(d) {
        compare(JSON.stringify(Search.launcherArgv(d.l, d.t)), JSON.stringify(d.want));
    }
}
