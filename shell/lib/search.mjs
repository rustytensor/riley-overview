// SPDX-License-Identifier: GPL-3.0-or-later
//
// The window search and the launcher command line. Pure logic, no Quickshell. Specified in docs/interact.md
// "shell/lib/search.mjs".
//
//   terms(query) -> [string]                 lower-cased, split on runs of white space, empty pieces dropped
//   matches(win, query) -> bool              every term is a plain substring of the lower-cased title or class
//   filterWindows(windows, query) -> [address]   the matching windows, in input order
//   launcherArgv(launcher, text) -> [string]     the launcher split on white space (no shell); every "{query}" is
//                                            replaced by text, or, with none, "--search=" + text is appended
// Windows are { address, class, title }; a missing class or title counts as "". Inputs are never modified.

export function terms(query) {
    return String(query === undefined || query === null ? "" : query).toLowerCase().split(/\s+/).filter(t => t !== "");
}

function field(v) {
    return v === undefined || v === null ? "" : String(v).toLowerCase();
}

export function matches(win, query) {
    const ts = terms(query);
    if (ts.length === 0) return true;
    const title = field(win && win.title);
    const cls = field(win && win.class);
    for (const t of ts)
        if (title.indexOf(t) < 0 && cls.indexOf(t) < 0) return false;
    return true;
}

export function filterWindows(windows, query) {
    return (windows || []).filter(w => matches(w, query)).map(w => w.address);
}

export function launcherArgv(launcher, text) {
    const words = String(launcher === undefined || launcher === null ? "" : launcher).trim().split(/\s+/)
        .filter(w => w !== "");
    if (words.length === 0) return [];
    const t = String(text === undefined || text === null ? "" : text);
    const placeholder = "{query}";
    if (words.some(w => w.indexOf(placeholder) >= 0))
        return words.map(w => w.split(placeholder).join(t));
    words.push("--search=" + t);
    return words;
}
