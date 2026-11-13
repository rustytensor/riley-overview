// SPDX-License-Identifier: GPL-3.0-or-later
//
// Riley's wallpaper for a monitor, from hyprpaper's config. Pure: no Quickshell, no file access.
//
// hypr-theme.py writes ~/.config/hypr/hyprpaper.conf as blocks
//     wallpaper {
//         monitor = DP-1            (a connector name, "desc:<description>", or empty for every monitor)
//         path = /path/to/picture
//         fit_mode = cover
//     }
// Older hyprpaper used one line, "wallpaper = MONITOR,PATH" (the path may carry a "contain:" or "tile:" prefix).

const MODE_PREFIX = /^(cover|contain|tile|fill):/;

function lineValue(line) {
    const eq = line.indexOf("=");
    if (eq < 0) return null;
    return { key: line.slice(0, eq).trim(), value: line.slice(eq + 1).trim() };
}

// parseHyprpaper(text) -> [{monitor, path, fitMode}] in file order; fitMode "" when absent.
export function parseHyprpaper(text) {
    const out = [];
    let block = null;
    for (const raw of String(text || "").split(/\r?\n/)) {
        const line = raw.trim();
        if (line === "" || line.startsWith("#")) continue;
        if (block) {
            if (line.startsWith("}")) {
                out.push(block);
                block = null;
                continue;
            }
            const kv = lineValue(line);
            if (!kv) continue;
            if (kv.key === "monitor") block.monitor = kv.value;
            else if (kv.key === "path") block.path = kv.value;
            else if (kv.key === "fit_mode") block.fitMode = kv.value;
            continue;
        }
        if (/^wallpaper\s*\{/.test(line)) {
            block = { monitor: "", path: "", fitMode: "" };
            continue;
        }
        const kv = lineValue(line);
        if (!kv || kv.key !== "wallpaper") continue;
        const comma = kv.value.indexOf(",");
        if (comma < 0) continue;
        let path = kv.value.slice(comma + 1).trim();
        let fitMode = "";
        const m = MODE_PREFIX.exec(path);
        if (m) {
            fitMode = m[1];
            path = path.slice(m[0].length).trim();
        }
        out.push({ monitor: kv.value.slice(0, comma).trim(), path: path, fitMode: fitMode });
    }
    return out;
}

// wallpaperFor(blocks, name, description, home) -> path. A block naming the monitor (by connector name or
// "desc:" + description) wins over an empty-monitor block; among equals the last one wins; "" when none fits.
export function wallpaperFor(blocks, name, description, home) {
    let named = "";
    let any = "";
    for (const b of blocks || []) {
        if (!b || !b.path) continue;
        const mon = b.monitor || "";
        if (mon === "") any = b.path;
        else if (mon === name || (description && mon === "desc:" + description)) named = b.path;
    }
    const path = named || any;
    if (path.startsWith("~/")) return String(home || "").replace(/\/+$/, "") + path.slice(1);
    return path;
}
