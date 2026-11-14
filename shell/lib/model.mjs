// SPDX-License-Identifier: GPL-3.0-or-later
//
// The overlay's model: what each monitor shows, and where it goes. Pure logic, no Quickshell.
// Specified in docs/overlay.md "shell/lib/model.mjs".
//
//   monitorLogical(m) -> { w, h }
//     m: a `hyprctl monitors -j` entry. Device size, swapped on an odd transform (90/270, flipped or not), divided
//     by the scale.
//   nextEmptyWorkspace(workspaces) -> int: 1 + the largest id > 0 (1 when there is none).
//   overviewModel(monitors, workspaces, clients, records) -> [entry], one per enabled monitor, in input order:
//     { monitor, description, x, y, scale, logical: {w, h}, workspace: {id, name},
//       windows: [{address, class, title, x, y, w, h}], minimized: [{address, class, title, w, h}],
//       strip: [{id, name, current, empty}] }
//   minimizedRow(W, H, windows, cfg) -> { band, rects: [{address, x, y, w, h}] }
//   layoutMonitor(entry, cfg) -> { area, scale, rows, windows: [{address, x, y, w, h, scale}],
//                                  strip: [{index, id, name, current, empty, x, y, w, h}],
//                                  names: [{index, id, name, current, empty, x, y, w, h}],
//                                  minimized: [{address, x, y, w, h}] }
//     scale: the largest window scale; windows[].scale: that window's own (docs/design.md "Spread layout").
//     strip: the desktops bar expanded (hit-testing, drop target); names: the bar collapsed (desktops.mjs).
//
// Inputs are never modified. Hyprland 0.57 gives a special workspace no id at all (a client there has
// workspace {address, type: "special", name}), so special workspaces are told by name or by a missing or
// negative id. Everything here is in the monitor's logical pixels, relative to its top-left corner.

import { desktopsBar } from "./desktops.mjs";
import { spreadLayout } from "./spread.mjs";
import { safeArea, stripGeometry } from "./strip.mjs";

export const MINIMIZED_WORKSPACE = "special:minimized";

function num(v, fallback) {
    return typeof v === "number" && isFinite(v) ? v : fallback;
}

function isRegularId(id) {
    return typeof id === "number" && isFinite(id) && id > 0;
}

export function monitorLogical(m) {
    const scale = num(m.scale, 1) > 0 ? num(m.scale, 1) : 1;
    const odd = (num(m.transform, 0) & 1) === 1;
    const w = num(m.width, 0);
    const h = num(m.height, 0);
    return { w: (odd ? h : w) / scale, h: (odd ? w : h) / scale };
}

export function nextEmptyWorkspace(workspaces) {
    let max = 0;
    for (const ws of workspaces || [])
        if (isRegularId(ws.id) && ws.id > max) max = ws.id;
    return max + 1;
}

function pair(a, i) {
    return Array.isArray(a) ? num(a[i], 0) : 0;
}

export function overviewModel(monitors, workspaces, clients, records) {
    const recs = records && typeof records === "object" ? records : {};
    const enabled = (monitors || []).filter(m => m && m.disabled !== true);
    const emptyId = nextEmptyWorkspace(workspaces);

    const entries = enabled.map(m => {
        const aw = m.activeWorkspace || {};
        return {
            monitor: String(m.name),
            description: String(m.description || ""),
            x: num(m.x, 0),
            y: num(m.y, 0),
            scale: num(m.scale, 1),
            logical: monitorLogical(m),
            workspace: { id: num(aw.id, 0), name: String(aw.name === undefined ? "" : aw.name) },
            windows: [],
            minimized: [],
            strip: [],
        };
    });
    const byName = {};
    const byId = {};
    enabled.forEach((m, i) => {
        byName[String(m.name)] = entries[i];
        if (typeof m.id === "number") byId[m.id] = entries[i];
    });

    for (const c of clients || []) {
        if (!c || c.mapped === false) continue;
        const ws = c.workspace || {};
        const address = String(c.address);
        if (ws.name === MINIMIZED_WORKSPACE) {
            const rec = recs[address];
            const target = (rec && byName[rec.monitor]) || byId[c.monitor];
            if (target)
                target.minimized.push({ address: address, class: String(c.class || ""), title: String(c.title || ""),
                                        w: pair(c.size, 0), h: pair(c.size, 1) });
            continue;
        }
        if (c.hidden === true || !isRegularId(ws.id)) continue;
        for (const e of entries) {
            if (e.workspace.id !== ws.id) continue;
            e.windows.push({ address: address, class: String(c.class || ""), title: String(c.title || ""),
                             x: pair(c.at, 0) - e.x, y: pair(c.at, 1) - e.y, w: pair(c.size, 0), h: pair(c.size, 1) });
            break;
        }
    }

    for (const e of entries) {
        const own = (workspaces || [])
            .filter(ws => ws && isRegularId(ws.id) && String(ws.monitor) === e.monitor)
            .map(ws => ({ id: ws.id, name: String(ws.name === undefined ? ws.id : ws.name) }))
            .sort((a, b) => a.id - b.id);
        e.strip = own.map(ws => ({ id: ws.id, name: ws.name, current: ws.id === e.workspace.id, empty: false }));
        e.strip.push({ id: emptyId, name: String(emptyId), current: false, empty: true });
    }
    return entries;
}

export function minimizedRow(W, H, windows, cfg) {
    const m = cfg.margin;
    const sh = cfg.stripHeight;
    const sp = cfg.stripSpacing;
    const band = { x: m, y: H - m - sh, w: W - 2 * m, h: sh };
    const list = windows || [];
    if (list.length === 0) return { band: band, rects: [] };
    const widths = list.map(win => (win.h > 0 ? sh * win.w / win.h : sh));
    let sum = 0;
    for (const w of widths) sum += w;
    const gaps = (list.length - 1) * sp;
    let f = 1;
    if (sum + gaps > band.w && sum > 0) f = Math.max(0, (band.w - gaps) / sum);
    const h = sh * f;
    const rowW = sum * f + gaps;
    let x = band.x + (band.w - rowW) / 2;
    const y = band.y + (band.h - h) / 2;
    const rects = list.map((win, i) => {
        const r = { address: win.address, x: x, y: y, w: widths[i] * f, h: h };
        x += r.w + sp;
        return r;
    });
    return { band: band, rects: rects };
}

export function layoutMonitor(entry, cfg) {
    const W = entry.logical.w;
    const H = entry.logical.h;
    const minimized = entry.minimized || [];
    const base = safeArea(W, H, cfg);
    const area = { x: base.x, y: base.y, w: base.w, h: base.h };
    if (minimized.length > 0) area.h -= cfg.stripHeight + cfg.sectionGap;

    const wins = (entry.windows || []).map(w => ({ id: w.address, x: w.x, y: w.y, w: w.w, h: w.h }));
    const spread = spreadLayout(wins, area, { spacing: cfg.windowSpacing, maxScale: cfg.maxScale });
    const windows = spread.rects.map(r => ({ address: r.id, x: r.x, y: r.y, w: r.w, h: r.h, scale: r.scale }));

    const items = entry.strip || [];
    const geo = stripGeometry(W, H, items.length, cfg);
    const strip = geo.rects.map((r, i) => ({ index: r.index, id: items[i].id, name: items[i].name,
                                             current: items[i].current, empty: items[i].empty,
                                             x: r.x, y: r.y, w: r.w, h: r.h }));
    const bar = desktopsBar(W, H, items.length, cfg, false);
    const names = bar.rects.map((r, i) => ({ index: r.index, id: items[i].id, name: items[i].name,
                                             current: items[i].current, empty: items[i].empty,
                                             x: r.x, y: r.y, w: r.w, h: r.h }));

    return { area: area, scale: spread.scale, rows: spread.rows, windows: windows, strip: strip, names: names,
             minimized: minimizedRow(W, H, minimized, cfg).rects };
}
