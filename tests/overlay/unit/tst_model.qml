// SPDX-License-Identifier: GPL-3.0-or-later
// M2 gate, offscreen part: the overlay's model (shell/lib/model.mjs). Every expected value worked out by hand below,
// before any run. Inputs are shaped like `hyprctl monitors -j`, `workspaces -j`, `clients -j`.
//
// Rules (docs/overlay.md "model.mjs"):
//   monitorLogical(m): device size (width x height), swapped when the transform is odd (1, 3, 5, 7), divided by scale.
//   nextEmptyWorkspace(ws): 1 + the largest id > 0 among the workspaces (1 when there is none).
//   overviewModel(monitors, workspaces, clients, records): one entry per enabled monitor, in input order. windows =
//   the mapped, not hidden clients on the monitor's active workspace, monitor-relative (at - monitor x,y), in input
//   order. minimized = clients on "special:minimized", on the monitor named by records[address].monitor when that
//   monitor exists, else on the monitor whose id is client.monitor. strip = the monitor's workspaces with id > 0 by
//   id, current marked, then one empty entry with nextEmptyWorkspace's id. Special workspaces are never in the strip.
//   layoutMonitor(entry, cfg): area = strip.mjs safeArea, made shorter by stripHeight + sectionGap when the entry
//   has minimized windows; spread = spread.mjs in that area; strip = strip.mjs stripGeometry; minimized row:
//   minimizedRow below.
//   minimizedRow(W, H, windows, cfg): band {margin, H - margin - stripHeight, W - 2*margin, stripHeight}; each
//   window stripHeight high and stripHeight*w/h wide, stripSpacing apart, in input order; if the row is wider than
//   the band every size is scaled by (band.w - (n-1)*stripSpacing) / (sum of widths); the row is centred in the band
//   in both directions.
import QtQuick
import QtTest
import "../lib/model.mjs" as Model
import "../lib/config.mjs" as Config

TestCase {
    name: "model"

    function near(a, e, msg) {
        verify(Math.abs(a - e) < 1e-3, msg + ": got " + a + ", expected " + e);
    }
    function rectNear(r, e, msg) {
        near(r.x, e.x, msg + " x"); near(r.y, e.y, msg + " y"); near(r.w, e.w, msg + " w"); near(r.h, e.h, msg + " h");
    }
    function cfg(over) {
        const c = Object.assign({}, Config.DEFAULTS);
        return Object.assign(c, over || {});
    }

    // Marc's outputs (hyprctl monitors -j, 2026-11-13).
    //   HDMI-A-1 2560x1440 transform 3 scale 1 -> swapped 1440x2560.
    //   DP-1, DP-3 3440x1440 scale 1 -> 3440x1440.
    //   DP-2 2560x1600 scale 1.25 -> 2048x1280.   HDMI-A-2 2560x1600 scale 1.6 -> 1600x1000.
    function test_logical_data() {
        return [
            { tag: "HDMI-A-1", m: { width: 2560, height: 1440, scale: 1, transform: 3 }, w: 1440, h: 2560 },
            { tag: "DP-1", m: { width: 3440, height: 1440, scale: 1, transform: 0 }, w: 3440, h: 1440 },
            { tag: "DP-2", m: { width: 2560, height: 1600, scale: 1.25, transform: 0 }, w: 2048, h: 1280 },
            { tag: "HDMI-A-2", m: { width: 2560, height: 1600, scale: 1.6, transform: 0 }, w: 1600, h: 1000 },
            // the nest's RO-C: 3440x1440 at 1.25 -> 2752x1152 (M1 area C)
            { tag: "RO-C", m: { width: 3440, height: 1440, scale: 1.25, transform: 0 }, w: 2752, h: 1152 },
            // transform 1 (90) swaps as well: 1440x2560 at 1.25 -> 2048x1152
            { tag: "rot1 1.25", m: { width: 2560, height: 1440, scale: 1.25, transform: 1 }, w: 1152, h: 2048 },
        ];
    }
    function test_logical(d) {
        const r = Model.monitorLogical(d.m);
        near(r.w, d.w, "w"); near(r.h, d.h, "h");
    }

    // Marc's workspaces: 1, 4, 7, 8, 9, 77 and the special minimized one (id -98): max id > 0 is 77 -> 78.
    function test_next_empty() {
        compare(Model.nextEmptyWorkspace([{ id: 1 }, { id: 4 }, { id: 7 }, { id: 8 }, { id: 9 }, { id: 77 },
                                          { id: -98, name: "special:minimized" }]), 78);
        compare(Model.nextEmptyWorkspace([]), 1);
        compare(Model.nextEmptyWorkspace([{ id: -98, name: "special:minimized" }]), 1);
    }

    // The nest of the live gate, plus the cases the live gate cannot set up cheaply.
    readonly property var monitors: [
        { id: 0, name: "RO-A", description: "headless A", width: 3440, height: 1440, x: 0, y: 0, scale: 1,
          transform: 0, disabled: false, activeWorkspace: { id: 1, name: "1" } },
        { id: 1, name: "RO-C", description: "headless C", width: 3440, height: 1440, x: 3440, y: 0, scale: 1.25,
          transform: 0, disabled: false, activeWorkspace: { id: 2, name: "2" } },
        { id: 2, name: "OFF", description: "off", width: 1920, height: 1080, x: 9000, y: 0, scale: 1,
          transform: 0, disabled: true, activeWorkspace: { id: 9, name: "9" } },
    ]
    readonly property var workspaces: [
        { id: 2, name: "2", monitor: "RO-C" },
        { id: 1, name: "1", monitor: "RO-A" },
        { id: 5, name: "5", monitor: "RO-A" },
        { id: -98, name: "special:minimized", monitor: "RO-A" },
        { name: "special:scratch", monitor: "RO-C" },     // Hyprland 0.57 gives special workspaces no id at all
    ]
    function cl(address, cls, ws, mon, at, size, extra) {
        return Object.assign({ address: address, class: cls, title: "t " + address, at: at, size: size,
                               workspace: ws, monitor: mon, mapped: true, hidden: false }, extra || {});
    }
    readonly property var wsMin: ({ name: "special:minimized", type: "special" })   // as hyprctl 0.57 shows it: no id
    readonly property var clients: [
        cl("0xa1", "ro.red.qml", { id: 1, name: "1" }, 0, [0, 0], [1720, 1440]),
        cl("0xc1", "ro.blue.qml", { id: 2, name: "2" }, 1, [3448, 40], [1364, 1104]),
        cl("0xa2", "ro.green.qml", { id: 1, name: "1" }, 0, [1720, 0], [1720, 1440]),
        cl("0xm1", "ro.magenta.qml", wsMin, 1, [1320, 420], [800, 600]),        // record says RO-A
        cl("0xc2", "ro.yellow.qml", { id: 2, name: "2" }, 1, [4820, 40], [1364, 1104]),
        cl("0xa5", "old", { id: 5, name: "5" }, 0, [0, 0], [3440, 1440]),            // inactive workspace: left out
        cl("0xa6", "ghost", { id: 1, name: "1" }, 0, [10, 10], [100, 100], { mapped: false }),  // unmapped: out
        cl("0xa7", "tab", { id: 1, name: "1" }, 0, [0, 0], [1720, 1440], { hidden: true }),     // hidden tab: out
        cl("0xm2", "ro.min2.qml", wsMin, 1, [3500, 100], [1200, 400]),          // no record: client.monitor 1 = RO-C
    ]
    readonly property var records: ({ "0xm1": { workspace: "1", monitor: "RO-A" },
                                      "0xm2": { workspace: "2", monitor: "GONE" } })   // GONE: falls back

    function test_overview_model() {
        const m = Model.overviewModel(monitors, workspaces, clients, records);
        compare(m.length, 2, "OFF is disabled: two entries");
        const a = m[0], c = m[1];
        compare(a.monitor, "RO-A"); compare(c.monitor, "RO-C");
        near(a.logical.w, 3440, "A w"); near(a.logical.h, 1440, "A h");
        near(c.logical.w, 2752, "C w"); near(c.logical.h, 1152, "C h");
        compare(a.scale, 1); compare(c.scale, 1.25);
        compare(a.workspace.id, 1); compare(c.workspace.id, 2);
        // A: red, green in input order; monitor-relative = global (A at 0,0)
        compare(a.windows.map(w => w.address).join(","), "0xa1,0xa2");
        rectNear(a.windows[0], { x: 0, y: 0, w: 1720, h: 1440 }, "red");
        rectNear(a.windows[1], { x: 1720, y: 0, w: 1720, h: 1440 }, "green");
        compare(a.windows[0].class, "ro.red.qml"); compare(a.windows[0].title, "t 0xa1");
        // C: blue (3448-3440, 40) = (8, 40); yellow (4820-3440, 40) = (1380, 40)
        compare(c.windows.map(w => w.address).join(","), "0xc1,0xc2");
        rectNear(c.windows[0], { x: 8, y: 40, w: 1364, h: 1104 }, "blue");
        rectNear(c.windows[1], { x: 1380, y: 40, w: 1364, h: 1104 }, "yellow");
        // minimized: m1 by its record on RO-A; m2's record names a monitor that is gone, so client.monitor (RO-C)
        compare(a.minimized.map(w => w.address).join(","), "0xm1");
        near(a.minimized[0].w, 800, "m1 w"); near(a.minimized[0].h, 600, "m1 h");
        compare(c.minimized.map(w => w.address).join(","), "0xm2");
        // strip: A has 1 (current) and 5, C has 2 (current); the empty one is 1 + max(1, 2, 5) = 6 on both
        compare(a.strip.map(s => s.id).join(","), "1,5,6");
        compare(a.strip.map(s => s.current).join(","), "true,false,false");
        compare(a.strip.map(s => s.empty).join(","), "false,false,true");
        compare(a.strip[2].name, "6");
        compare(c.strip.map(s => s.id).join(","), "2,6");
        compare(c.strip.map(s => s.current).join(","), "true,false");
        compare(c.strip.map(s => s.empty).join(","), "false,true");
    }

    // An input the model must not change.
    function test_inputs_untouched() {
        const before = JSON.stringify([monitors, workspaces, clients, records]);
        Model.overviewModel(monitors, workspaces, clients, records);
        compare(JSON.stringify([monitors, workspaces, clients, records]), before);
    }

    // Phase 1 of the live gate, RO-A: red and green tiled halves (1720x1440 each), magenta minimized (800x600),
    // strip [1 current, 3 empty]; default config.
    //   area: safeArea {24, 216, 3392, 1200}, minus stripHeight + sectionGap = 136 -> {24, 216, 3392, 1064}.
    //   spread (r=1): horizontal (3392-24)/3440 = 0.97907, vertical 1064/1440 = 0.738889 -> s = 1064/1440.
    //     (r=2: rows [red],[green], vertical (1064-24)/2880 = 0.36111, smaller.)
    //     w = 1720*1064/1440 = 1270.8889, h = 1064. Row 2w+24 = 2565.7778; x(red) = 24 + (3392-2565.7778)/2
    //     = 437.1111; x(green) = 437.1111 + 1270.8889 + 24 = 1732. y = 216 (row fills the area).
    //   strip, 2 thumbs: w = 120*3440/1440 = 286.6667, row 2*286.6667+16 = 589.3333 < 3392;
    //     x0 = 24 + (3392-589.3333)/2 = 1425.3333, x1 = 1425.3333+286.6667+16 = 1728; y = 24, h = 120.
    //   minimized row: band {24, 1440-24-120 = 1296, 3392, 120}; magenta 120 high, 120*800/600 = 160 wide;
    //     x = 24 + (3392-160)/2 = 1640, y = 1296.
    readonly property var entryA: ({
        monitor: "RO-A", logical: { w: 3440, h: 1440 }, scale: 1,
        windows: [{ address: "0xa1", x: 0, y: 0, w: 1720, h: 1440 }, { address: "0xa2", x: 1720, y: 0, w: 1720, h: 1440 }],
        minimized: [{ address: "0xm1", w: 800, h: 600 }],
        strip: [{ id: 1, name: "1", current: true, empty: false }, { id: 3, name: "3", current: false, empty: true }],
    })
    function test_layout_a() {
        const L = Model.layoutMonitor(entryA, cfg());
        rectNear(L.area, { x: 24, y: 216, w: 3392, h: 1064 }, "area");
        near(L.scale, 1064 / 1440, "scale");
        compare(L.rows, 1);
        compare(L.windows.map(w => w.address).join(","), "0xa1,0xa2");
        const w = 1720 * 1064 / 1440;
        rectNear(L.windows[0], { x: 24 + (3392 - (2 * w + 24)) / 2, y: 216, w: w, h: 1064 }, "red");
        near(L.windows[0].x, 437.1111, "red x literal");
        rectNear(L.windows[1], { x: 1732, y: 216, w: w, h: 1064 }, "green");
        compare(L.strip.length, 2);
        rectNear(L.strip[0], { x: 1425.3333, y: 24, w: 286.6667, h: 120 }, "strip 0");
        rectNear(L.strip[1], { x: 1728, y: 24, w: 286.6667, h: 120 }, "strip 1");
        compare(L.strip[0].index, 0); compare(L.strip[1].index, 1);
        compare(L.strip[0].id, 1); compare(L.strip[0].current, true);
        compare(L.strip[1].id, 3); compare(L.strip[1].empty, true);
        compare(L.minimized.length, 1);
        compare(L.minimized[0].address, "0xm1");
        rectNear(L.minimized[0], { x: 1640, y: 1296, w: 160, h: 120 }, "magenta");
    }

    // Phase 1, RO-C: blue (8,40) and yellow (1380,40), 1364x1104, floating; no minimized; strip [2 current, 3 empty].
    //   area C {24, 216, 2704, 912}; spread = M1 case "C 2 tiles": s = 19/23, w = 1364*19/23 = 1126.7826, h = 912,
    //   x(blue) = 24 + (2704 - (2w+24))/2 = 237.2174, x(yellow) = 1388, y = 216.
    //   strip: w = 120*2752/1152 = 286.6667, row 589.3333; x0 = 24 + (2704-589.3333)/2 = 1081.3333, x1 = 1384.
    readonly property var entryC: ({
        monitor: "RO-C", logical: { w: 2752, h: 1152 }, scale: 1.25,
        windows: [{ address: "0xc1", x: 8, y: 40, w: 1364, h: 1104 }, { address: "0xc2", x: 1380, y: 40, w: 1364, h: 1104 }],
        minimized: [],
        strip: [{ id: 2, name: "2", current: true, empty: false }, { id: 3, name: "3", current: false, empty: true }],
    })
    function test_layout_c() {
        const L = Model.layoutMonitor(entryC, cfg());
        rectNear(L.area, { x: 24, y: 216, w: 2704, h: 912 }, "area");
        near(L.scale, 19 / 23, "scale");
        const w = 1364 * 19 / 23;
        rectNear(L.windows[0], { x: 237.2174, y: 216, w: w, h: 912 }, "blue");
        rectNear(L.windows[1], { x: 1388, y: 216, w: w, h: 912 }, "yellow");
        rectNear(L.strip[0], { x: 1081.3333, y: 24, w: 286.6667, h: 120 }, "strip 0");
        rectNear(L.strip[1], { x: 1384, y: 24, w: 286.6667, h: 120 }, "strip 1");
        compare(L.minimized.length, 0);
    }

    // Phase 2 of the live gate: config max-scale 0.5, no minimized.
    //   A: r=1 s = min(0.5, 0.97907, 1200/1440 = 0.8333) = 0.5 (r=2: (1200-24)/2880 = 0.40833, smaller).
    //      w = 860, h = 720; row 2*860+24 = 1744; x(red) = 24 + (3392-1744)/2 = 848, x(green) = 848+860+24 = 1732;
    //      y = 216 + (1200-720)/2 = 456.
    //   C: r=1 s = min(0.5, (2704-24)/2728 = 0.98240, 912/1104 = 0.82609) = 0.5. w = 682, h = 552; row 1388;
    //      x(blue) = 24 + (2704-1388)/2 = 682, x(yellow) = 682+682+24 = 1388; y = 216 + (912-552)/2 = 396.
    function test_layout_max_scale() {
        const a = Object.assign({}, entryA, { minimized: [] });
        const La = Model.layoutMonitor(a, cfg({ maxScale: 0.5 }));
        rectNear(La.area, { x: 24, y: 216, w: 3392, h: 1200 }, "A area");
        rectNear(La.windows[0], { x: 848, y: 456, w: 860, h: 720 }, "red");
        rectNear(La.windows[1], { x: 1732, y: 456, w: 860, h: 720 }, "green");
        const Lc = Model.layoutMonitor(entryC, cfg({ maxScale: 0.5 }));
        rectNear(Lc.windows[0], { x: 682, y: 396, w: 682, h: 552 }, "blue");
        rectNear(Lc.windows[1], { x: 1388, y: 396, w: 682, h: 552 }, "yellow");
    }

    // minimizedRow on A (3440x1440, defaults: band {24, 1296, 3392, 120}).
    //   Two windows 800x600 and 1200x400: widths 120*800/600 = 160 and 120*1200/400 = 360; row 160+16+360 = 536;
    //   x0 = 24 + (3392-536)/2 = 1452, x1 = 1452+160+16 = 1628; y = 1296, h = 120.
    //   Thirty windows 800x600: 30*160 + 29*16 = 5264 > 3392, factor (3392-464)/4800 = 0.61: w = 97.6,
    //   h = 73.2; row 30*97.6 + 464 = 3392 -> x0 = 24, x(k) = 24 + k*(97.6+16); y = 1296 + (120-73.2)/2 = 1319.4.
    function test_minimized_row() {
        const r = Model.minimizedRow(3440, 1440, [{ address: "p", w: 800, h: 600 }, { address: "q", w: 1200, h: 400 }], cfg());
        rectNear(r.band, { x: 24, y: 1296, w: 3392, h: 120 }, "band");
        rectNear(r.rects[0], { x: 1452, y: 1296, w: 160, h: 120 }, "p");
        rectNear(r.rects[1], { x: 1628, y: 1296, w: 360, h: 120 }, "q");
        compare(r.rects[1].address, "q");
        const many = [];
        for (let i = 0; i < 30; i++) many.push({ address: "m" + i, w: 800, h: 600 });
        const r2 = Model.minimizedRow(3440, 1440, many, cfg());
        compare(r2.rects.length, 30);
        rectNear(r2.rects[0], { x: 24, y: 1319.4, w: 97.6, h: 73.2 }, "m0");
        rectNear(r2.rects[29], { x: 24 + 29 * 113.6, y: 1319.4, w: 97.6, h: 73.2 }, "m29");
        near(r2.rects[29].x + r2.rects[29].w, 3416, "row ends at the band's right edge");
        compare(Model.minimizedRow(3440, 1440, [], cfg()).rects.length, 0);
    }
}
