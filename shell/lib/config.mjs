// SPDX-License-Identifier: GPL-3.0-or-later
//
// Config defaults and value parsing for ~/.config/riley-overview/config.xml (schema data/config.xsd).
// Pure logic, no Quickshell. Specified in docs/design.md "Config".
//
//   DEFAULTS: the default values (below; data/config.example.xml spells them out).
//   parseConfig(text) -> { ok, config, errors }
//     ok true: config holds the file's values, defaults for missing elements; errors [].
//     ok false: the file is not used at all; config is a copy of DEFAULTS; errors says why (one or more strings).
//     Always a fresh config object.
//
// M1 stub: DEFAULTS is the interface; parseConfig is builder B's.

export const DEFAULTS = Object.freeze({
    margin: 24,
    stripHeight: 120,
    stripSpacing: 16,
    searchHeight: 40,
    sectionGap: 16,
    windowSpacing: 24,
    maxScale: 1.0,
    animationMs: 200,
    launcher: "fuzzel",
});

export function parseConfig(text) {
    throw new Error("parseConfig: not implemented");
}
