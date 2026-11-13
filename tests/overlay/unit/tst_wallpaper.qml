// SPDX-License-Identifier: GPL-3.0-or-later
// M2 gate, offscreen part: finding Riley's wallpaper for a monitor (shell/lib/wallpaper.mjs).
//
// Riley sets wallpapers with hyprpaper; hypr-theme.py (set_wallpapers) writes ~/.config/hypr/hyprpaper.conf as
// blocks "wallpaper { monitor = X / path = P / fit_mode = cover }", X being a connector name (DP-1), "desc:<the
// monitor's description>", or empty (every monitor). Older hyprpaper used one line "wallpaper = X,P".
// Rules (docs/overlay.md "wallpaper.mjs"):
//   parseHyprpaper(text) -> [{monitor, path, fitMode}] in file order (fitMode "" when absent); lines starting with
//   "#" are comments; keys and values are trimmed; "preload", "splash", "ipc" and anything else are ignored.
//   wallpaperFor(blocks, name, description, home) -> path: a block naming the monitor (name, or "desc:" +
//   description) wins over an empty-monitor block; among equals the last one in the file wins (hyprpaper applies
//   them in order); "" when none fits. A path starting with "~/" gets home in front.
import QtQuick
import QtTest
import "../lib/wallpaper.mjs" as Wall

TestCase {
    name: "wallpaper"

    readonly property string theme:
        "# Written by hypr-theme.py; the theme decides the wallpapers.\nsplash = false\nipc = true\n\n" +
        "wallpaper {\n    monitor = DP-1\n    path = /home/u/Pictures/a.png\n    fit_mode = cover\n}\n" +
        "wallpaper {\n    monitor = desc:GWD ARZOPA 0x37330206\n    path = /p/arzopa.png\n    fit_mode = cover\n}\n" +
        "wallpaper {\n    monitor =\n    path = /p/all.png\n    fit_mode = cover\n}\n"

    function test_parse() {
        const b = Wall.parseHyprpaper(theme);
        compare(b.length, 3);
        compare(b[0].monitor, "DP-1"); compare(b[0].path, "/home/u/Pictures/a.png"); compare(b[0].fitMode, "cover");
        compare(b[1].monitor, "desc:GWD ARZOPA 0x37330206"); compare(b[1].path, "/p/arzopa.png");
        compare(b[2].monitor, ""); compare(b[2].path, "/p/all.png");
    }

    function test_pick_data() {
        return [
            { tag: "by name", name: "DP-1", desc: "Samsung Electric Company S34C65xU HCNYB00237", e: "/home/u/Pictures/a.png" },
            { tag: "by description", name: "DP-2", desc: "GWD ARZOPA 0x37330206", e: "/p/arzopa.png" },
            { tag: "catch-all", name: "DP-3", desc: "Samsung Electric Company S34C65xU HCNYB00019", e: "/p/all.png" },
            // a description that only starts like the block's is not a match
            { tag: "description prefix only", name: "HDMI-A-2", desc: "GWD ARZOPA 0x3733", e: "/p/all.png" },
        ];
    }
    function test_pick(d) {
        compare(Wall.wallpaperFor(Wall.parseHyprpaper(theme), d.name, d.desc, "/home/u"), d.e);
    }

    // No catch-all block: a monitor that is not named has no wallpaper (the overlay falls back to a solid colour).
    function test_none() {
        const t = "wallpaper {\n    monitor = DP-1\n    path = /p/one.png\n}\n";
        compare(Wall.wallpaperFor(Wall.parseHyprpaper(t), "DP-3", "x", "/home/u"), "");
        compare(Wall.parseHyprpaper(t)[0].fitMode, "");
        compare(Wall.wallpaperFor(Wall.parseHyprpaper(""), "DP-1", "x", "/home/u"), "");
        compare(Wall.parseHyprpaper("").length, 0);
    }

    // Old one-line syntax, "~/" paths, comments, and the last of two equal blocks winning.
    function test_old_syntax() {
        const t = "# old style\npreload = /p/x.png\nwallpaper = DP-1,/p/x.png\nwallpaper = ,~/Pictures/y.png\n";
        const b = Wall.parseHyprpaper(t);
        compare(b.length, 2);
        compare(Wall.wallpaperFor(b, "DP-1", "d", "/home/u"), "/p/x.png");
        compare(Wall.wallpaperFor(b, "DP-3", "d", "/home/u"), "/home/u/Pictures/y.png");
    }
    function test_last_wins() {
        const t = "wallpaper {\n monitor = DP-1\n path = /p/first.png\n}\n" +
                  "# wallpaper {\n#  monitor = DP-1\n#  path = /p/commented.png\n# }\n" +
                  "wallpaper {\n monitor = DP-1\n path = /p/second.png\n}\n";
        compare(Wall.wallpaperFor(Wall.parseHyprpaper(t), "DP-1", "d", "/home/u"), "/p/second.png");
    }
}
