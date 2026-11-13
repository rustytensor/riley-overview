#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""M2 gate, live part: the overlay in a nested Hyprland. Run by tests/run-overlay.sh under dp2-lock, never alone:

  dp2-lock python3 -I tests/overlay/gate.py --stage STAGE --work WORK --shots SHOTS --vpointer VPOINTER \
      --vkeyboard VKEYBOARD

STAGE holds bin/riley-overview and share/riley-overview/{shell/, config.xsd} (a copy of the tree or of an installed
prefix, so the overlay's path never matches a resident copy in Marc's session). WORK takes the nest's config, the
throwaway XDG folders and the logs; SHOTS the screenshots (deleted on exit by this script and by the wrapper).

The nest (a window on an empty DP-2 workspace of Marc's session; nothing runs in his session):
  RO-A  headless 3440x1440 at scale 1,    position 0,0      -> logical 3440x1440 (M1 area A)
  RO-C  headless 3440x1440 at scale 1.25, position 3440,0   -> logical 2752x1152 (M1 area C)
  the nest's own window output (WAYLAND-1) is disabled, so these are the only outputs.
  No gaps, borders, rounding, shadows, blur or animations; dwindle always splits to the right.
  The key: Super pressed alone (left Super, on release) runs the `global` dispatcher riley-overview:toggle, the bind
  the lead gives Marc's session (docs/files.md); the overview's GlobalShortcut takes it.
  Workspace 1 on RO-A tiles; workspace 2 on RO-C floats (as hypr-float-mode writes it).
Test windows (tests/overlay/colour.qml, one colour each, class "ro.<name>.qml", self-closing after 30 s, ended by
their saved process IDs):
  red     #ff0000  workspace 1, tiled: the first window, so 0,0 1720x1440 (dwindle halves 3440 wide)
  green   #00ff00  workspace 1, tiled: split to the right, 1720,0 1720x1440
  blue    #0000ff  workspace 2, floating, rule size 1364x1104 at 8,40 (monitor-relative) -> global 3448,40
  yellow  #ffff00  workspace 2, floating, rule size 1364x1104 at 1380,40                  -> global 4820,40
  magenta #ff00ff  special:minimized (phase 1 only), floating 800x600; its record names RO-A
These geometries are M1's hand-worked cases ("C 2 tiles") or halves worked out here; every expected rectangle is
derived in EXPECT below, before the run. The overlay's config, theme and wallpaper come from a throwaway
XDG_CONFIG_HOME.
"""
import argparse, json, os, shutil, signal, statistics, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from nested import Nest  # noqa: E402

HYPRLAND = os.environ.get('RILEYOVERVIEW_HYPRLAND', '/usr/bin/Hyprland')
QML = os.environ.get('RILEYOVERVIEW_QML', '/usr/lib64/qt6/bin/qml')
NS = 'riley-overview'
LIFETIME = 30                # seconds each test window lives
TOL_RECT = 1.0               # logical px: the overlay may round its rectangles when it draws
TOL_DEV = 1.5                # device px: 1 logical px times 1.25, plus rounding
TOL_RGB = 24                 # per channel, for a solid colour scaled by the compositor and Qt
TARGET_MS = 100              # brief: first frame within 100 ms of the key press
VPOINTER = None              # the pointer helper (--vpointer)
VKEYBOARD = None             # the keyboard helper (--vkeyboard)
KEY_BIND = 'hl.bind("SUPER + SUPER_L", hl.dsp.global("riley-overview:toggle"), { release = true })'

COLOURS = {'red': (255, 0, 0), 'green': (0, 255, 0), 'blue': (0, 0, 255), 'yellow': (255, 255, 0),
           'magenta': (255, 0, 255)}
MONS = {'RO-A': {'x': 0, 'y': 0, 'w': 3440, 'h': 1440, 'scale': 1.0, 'lw': 3440, 'lh': 1440},
        'RO-C': {'x': 3440, 'y': 0, 'w': 3440, 'h': 1440, 'scale': 1.25, 'lw': 2752, 'lh': 1152}}
# Where each window must be before the overlay is shown (global logical, from the rules above).
REAL = {'red': ('RO-A', 1, (0, 0, 1720, 1440), False), 'green': ('RO-A', 1, (1720, 0, 1720, 1440), False),
        'blue': ('RO-C', 2, (3448, 40, 1364, 1104), True), 'yellow': ('RO-C', 2, (4820, 40, 1364, 1104), True)}

# ---- Expected values, worked out by hand (docs/design.md, docs/overlay.md; M1 tests/layout/cases.mjs) ----------
# Config defaults: margin 24, strip height 120, strip spacing 16, search 40, section gap 16, window spacing 24,
# max scale 1. Safe area = {24, 216, W-48, H-240}. A: {24, 216, 3392, 1200}. C: {24, 216, 2704, 912}.
#
# Phase 1 (default config: the config file is broken on purpose, so defaults are used):
#  RO-A has a minimized window, so its area loses stripHeight + sectionGap = 136 at the bottom: {24, 216, 3392, 1064}.
#   red, green 1720x1440 in one row: s = min(1, (3392-24)/3440 = 0.97907, 1064/1440 = 0.73889) = 1064/1440
#   (two rows: (1064-24)/2880 = 0.36111, smaller). w = 1720*1064/1440 = 1270.8889, h = 1064.
#   Row 2w + 24 = 2565.7778; x(red) = 24 + (3392-2565.7778)/2 = 437.1111; x(green) = 437.1111+1270.8889+24 = 1732.
#   y = 216. Scale 1: device = logical.
#  RO-C: blue (8,40), yellow (1380,40), 1364x1104: M1 case "C 2 tiles": s = 19/23, w = 1364*19/23 = 1126.7826,
#   h = 912, x(blue) = 24 + (2704 - (2w+24))/2 = 237.2174, x(yellow) = 1388, y = 216.
#   Device (x1.25): blue {296.5217, 270, 1408.4783, 1140}, yellow {1735, 270, 1408.4783, 1140}.
#  Strip (2 thumbs each: the current workspace and the empty one, id 1 + max(1, 2) = 3; special ones left out):
#   thumb 120 high, 120*W/H = 286.6667 wide (A: 3440/1440, C: 2752/1152, the same ratio); row 589.3333.
#   A: x0 = 24 + (3392-589.3333)/2 = 1425.3333, x1 = 1728.   C: x0 = 24 + (2704-589.3333)/2 = 1081.3333, x1 = 1384.
#  Minimized row on A: band {24, 1296, 3392, 120}; magenta 800x600 -> 160x120 at x = 24 + (3392-160)/2 = 1640.
W1 = 1720 * 1064 / 1440
WC = 1364 * 19 / 23
EXPECT1 = {
    'red': ('RO-A', (24 + (3392 - (2 * W1 + 24)) / 2, 216, W1, 1064)),       # 437.1111
    'green': ('RO-A', (1732, 216, W1, 1064)),
    'blue': ('RO-C', (24 + (2704 - (2 * WC + 24)) / 2, 216, WC, 912)),        # 237.2174
    'yellow': ('RO-C', (1388, 216, WC, 912)),
}
STRIP1 = {'RO-A': [(1, True, False, (1425 + 1 / 3, 24, 286 + 2 / 3, 120)), (3, False, True, (1728, 24, 286 + 2 / 3, 120))],
          'RO-C': [(2, True, False, (1081 + 1 / 3, 24, 286 + 2 / 3, 120)), (3, False, True, (1384, 24, 286 + 2 / 3, 120))]}
MIN1 = {'RO-A': [('magenta', (1640, 1296, 160, 120))], 'RO-C': []}
# Phase 2 (valid config with max-scale 0.5, no minimized window):
#  A: s = min(0.5, 0.97907, 1200/1440 = 0.8333) = 0.5 (two rows 0.40833): 860x720; row 1744; x(red) = 24 +
#     (3392-1744)/2 = 848, x(green) = 848+860+24 = 1732; y = 216 + (1200-720)/2 = 456.
#  C: s = min(0.5, 0.98240, 0.82609) = 0.5: 682x552; row 1388; x(blue) = 24 + (2704-1388)/2 = 682,
#     x(yellow) = 682+682+24 = 1388; y = 216 + (912-552)/2 = 396.
EXPECT2 = {'red': ('RO-A', (848, 456, 860, 720)), 'green': ('RO-A', (1732, 456, 860, 720)),
           'blue': ('RO-C', (682, 396, 682, 552)), 'yellow': ('RO-C', (1388, 396, 682, 552))}
# Backdrop: Riley's wallpaper under black at 50 % (docs/overlay.md). RO-A has a white picture by name, RO-C the
# catch-all cyan one. Dimmed: white -> 127.5 grey, cyan (0,255,255) -> (0,127.5,127.5).
# Sample points, logical, away from the edges (blur), the tiles, the strip, the search field and the minimized row:
#  A (120, 800): left of red (x >= 437) and below the search field (y >= 216). C (120, 720): left of blue (x >= 237).
BACKDROP = {'RO-A': ((120, 800), (127.5, 127.5, 127.5)), 'RO-C': ((120, 720), (0, 127.5, 127.5))}
# The spacing between two tiles holds neither tile's colour: A between red (ends 437.1111+1270.8889 = 1708) and
# green (starts 1732): x 1720, y 748 (middle of 216..1280). C between blue (ends 237.2174+1126.7826 = 1364) and
# yellow (1388): x 1376, y 672 (middle of 216..1128).
GAPS = {'RO-A': ((1720, 748), ('red', 'green')), 'RO-C': ((1376, 672), ('blue', 'yellow'))}
THEME = {'base': '#101418', 'accent': '#123456', 'font': 'DejaVu Sans'}
CONFIG_DEFAULTS = {'margin': 24, 'stripHeight': 120, 'stripSpacing': 16, 'searchHeight': 40, 'sectionGap': 16,
                   'windowSpacing': 24, 'maxScale': 1.0, 'animationMs': 200, 'launcher': 'fuzzel'}

results = []


def check(name, ok, detail=''):
    results.append((name, bool(ok)))
    print(('PASS ' if ok else 'FAIL ') + 'overlay::' + name + (f': {detail}' if detail else ''), flush=True)
    return bool(ok)


def near(a, b, tol):
    return all(abs(x - y) <= tol for x, y in zip(a, b))


def fmt(r):
    return '(' + ', '.join(f'{v:.2f}' for v in r) + ')'


def rect_of(d):
    return (d['x'], d['y'], d['w'], d['h']) if isinstance(d, dict) else None


# ---- the nest ---------------------------------------------------------------------------------------------------
def nest_config(work):
    cfg = work / 'hyprland.lua'
    rules = []
    for name, (mon, ws, (x, y, w, h), floating) in REAL.items():
        r = f'hl.window_rule({{ name = "ro-{name}", match = {{ class = "^ro\\\\.{name}\\\\..*$" }}, workspace = "{ws} silent"'
        if floating:
            r += f', float = true, size = "{w} {h}", move = "{x - MONS[mon]["x"]} {y - MONS[mon]["y"]}"'
        rules.append(r + ' })')
    rules.append('hl.window_rule({ name = "ro-magenta", match = { class = "^ro\\\\.magenta\\\\..*$" }, '
                 'workspace = "special:minimized silent", float = true, size = "800 600" })')
    cfg.write_text('''-- the M2 gate's nest: two headless outputs, nothing else
hl.config({ xwayland = { enabled = false }, animations = { enabled = false },
            misc = { disable_hyprland_logo = true, disable_splash_rendering = true },
            ecosystem = { no_update_news = true, no_donation_nag = true },
            general = { gaps_in = 0, gaps_out = 0, border_size = 0 },
            decoration = { rounding = 0, shadow = { enabled = false }, blur = { enabled = false } },
            dwindle = { force_split = 2 } })
hl.monitor({ output = "WAYLAND-1", disabled = true })
hl.monitor({ output = "RO-A", mode = "3440x1440@60", position = "0x0", scale = 1 })
hl.monitor({ output = "RO-C", mode = "3440x1440@60", position = "3440x0", scale = 1.25 })
hl.workspace_rule({ workspace = "1", monitor = "RO-A", default = true })
hl.workspace_rule({ workspace = "2", monitor = "RO-C", default = true })
hl.window_rule({ name = "float-workspace-2", match = { workspace = "2" }, float = true })   -- as hypr-float-mode writes it
''' + KEY_BIND + '   -- the key: Super pressed alone\n' + '\n'.join(rules) + '\n')
    return cfg


class Run:
    """Processes this gate started, by saved Popen handle: ended on every exit."""

    def __init__(self):
        self.procs = []

    def spawn(self, argv, env, log):
        # same process group as the gate: run-overlay.sh can end the whole group by its saved ID
        p = subprocess.Popen(argv, env=env, stdout=open(log, 'ab'), stderr=subprocess.STDOUT)
        self.procs.append(p)
        return p

    def end(self, p, wait=5):
        if p.poll() is None:
            try:
                p.terminate()
                p.wait(wait)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait(5)
        if p in self.procs:
            self.procs.remove(p)

    def end_all(self):
        for p in list(self.procs):
            self.end(p)


def windows_by_name(nest):
    out = {}
    for c in nest.clients():
        cls = c.get('class', '')
        if cls.startswith('ro.') and c.get('mapped', True):
            out[cls.split('.')[1]] = c
    return out


def start_windows(nest, run, work, names):
    env = nest.client_env()
    for name in names:
        r, g, b = COLOURS[name]
        run.spawn([QML, str(HERE / 'colour.qml'), '--', name, f'#{r:02x}{g:02x}{b:02x}', '800', '600',
                   str(LIFETIME)], env, work / f'window-{name}.log')
        # one at a time, so dwindle splits in a known order
        if not nest.wait(lambda: name in windows_by_name(nest), timeout=10):
            return None
    time.sleep(0.5)
    return windows_by_name(nest)


def setup_ok(nest, wins, names):
    ok = True
    for name in names:
        c = wins.get(name) if wins else None
        if name == 'magenta':
            ok &= check('setup magenta is on special:minimized, 800x600',
                        c and c['workspace']['name'] == 'special:minimized' and tuple(c['size']) == (800, 600),
                        f'{c and c["workspace"]} {c and c["size"]}')
            continue
        mon, ws, rect, floating = REAL[name]
        got = c and (tuple(c['at']) + tuple(c['size']))
        ok &= check(f'setup {name} at {rect} on workspace {ws}, floating={floating}',
                    c and got == rect and c['workspace']['id'] == ws and c['floating'] == floating,
                    f'got {got} workspace {c and c["workspace"]["id"]} floating {c and c["floating"]}')
    return ok


# ---- the overlay ------------------------------------------------------------------------------------------------
class Overlay:
    def __init__(self, nest, run, stage, work, tag):
        self.nest, self.run, self.stage, self.work = nest, run, stage, work
        self.bin = stage / 'bin' / 'riley-overview'
        self.hook = work / f'hook-{tag}'
        shutil.rmtree(self.hook, ignore_errors=True)
        self.hook.mkdir(parents=True)
        xdg = work / 'xdg'
        self.env = nest.client_env({
            'XDG_CONFIG_HOME': str(xdg / 'config'), 'XDG_CACHE_HOME': str(xdg / 'cache'),
            'XDG_STATE_HOME': str(xdg / 'state'),
            'RILEYOVERVIEW_TEST_DIR': str(self.hook),
            'RILEYOVERVIEW_NOTIFY': str(work / 'notify.sh'),
            'RILEYOVERVIEW_MINIMIZED_FILE': str(work / 'minimized.json'),
        })
        self.env.pop('RILEYOVERVIEW_SHELL', None)
        self.log = work / f'overlay-{tag}.log'
        self.proc = None

    def start(self):
        self.proc = self.run.spawn([str(self.bin), 'run'], self.env, self.log)
        return self

    def ipc(self, *args, timeout=5):
        try:
            r = subprocess.run(['qs', 'ipc', '--pid', str(self.proc.pid), 'call', 'overview', *map(str, args)],
                               env=self.env, capture_output=True, text=True, timeout=timeout)
            return r.stdout.strip() if r.returncode == 0 else None
        except subprocess.TimeoutExpired:
            return None

    def state(self):
        out = self.ipc('state')
        try:
            return json.loads(out) if out else None
        except ValueError:
            return None

    def ready(self, timeout=15):
        return self.nest.wait(lambda: (self.state() or {}).get('ready'), timeout=timeout, step=0.2)

    def show_file(self, seq, timeout=3):
        f = self.hook / f'show-{seq}.json'

        def got():
            try:
                return json.loads(f.read_text())
            except (OSError, ValueError):
                return None
        return self.nest.wait(got, timeout=timeout, step=0.005)

    def stop(self):
        if self.proc:
            self.run.end(self.proc)


def our_layers(nest):
    """{monitor: [layer, ...]} of the layer surfaces with our namespace, from hyprctl (independent of the hook)."""
    out = {}
    for mon, v in (nest.j('layers') or {}).items():
        for level, layers in v.get('levels', {}).items():
            for layer in layers:
                if layer.get('namespace') == NS:
                    out.setdefault(mon, []).append(dict(layer, level=level))
    return out


def closed(nest, ov, timeout=2):
    return nest.wait(lambda: not our_layers(nest) and (ov.state() or {}).get('shown') is False,
                     timeout=timeout, step=0.05)


def surface(state, mon):
    return next((s for s in (state or {}).get('surfaces', []) if s.get('monitor') == mon), None)


def window_entry(state, nest_wins, name):
    addr = nest_wins[name]['address']
    for s in (state or {}).get('surfaces', []):
        for w in s.get('windows', []):
            if w.get('address') == addr:
                return s['monitor'], w
    return None, None


def grim(nest, shots, mon, tag):
    f = shots / f'{tag}-{mon}.png'
    r = subprocess.run(['grim', '-o', mon, str(f)], env=nest.client_env(), capture_output=True, timeout=10)
    if r.returncode != 0:
        return None
    from PIL import Image
    return Image.open(f).convert('RGB')


def samples(rect, scale):
    """3x3 points at 20/50/80 % of the rectangle, in device px: away from the tile's edge, frame and title."""
    x, y, w, h = (v * scale for v in rect)
    return [(int(x + w * fx), int(y + h * fy)) for fy in (0.2, 0.5, 0.8) for fx in (0.2, 0.5, 0.8)]


def colour_ok(px, want, tol=TOL_RGB):
    return all(abs(a - b) <= tol for a, b in zip(px, want))


# ---- phase 1: sizes, layout, pixels, click, Escape, toggle, strip ----------------------------------------------
def phase1(nest, run, stage, work, shots):
    print('\n== phase 1: default layout (broken config), tiled and floating, minimized row', flush=True)
    names = ['red', 'green', 'blue', 'yellow', 'magenta']
    wins = start_windows(nest, run, work, names)
    if not setup_ok(nest, wins, names):
        check('phase 1 set up', False, 'the nest did not place the test windows as planned; nothing else checked')
        return
    (work / 'minimized.json').write_text(json.dumps({wins['magenta']['address']: {'workspace': '1', 'monitor': 'RO-A'}}))
    nest.dispatch(f'hl.dsp.focus({{ window = "address:{wins["red"]["address"]}" }})')
    before = {n: (tuple(c['at']), tuple(c['size']), c['floating'], c['workspace'].get('id')) for n, c in wins.items()}

    ov = Overlay(nest, run, stage, work, 'p1').start()
    if not check('starts and answers IPC (state ready)', ov.ready(), f'log {ov.log}'):
        return
    check('started hidden: no layer surface', not our_layers(nest), f'{our_layers(nest)}')

    if not check('toggle shows (show-1.json written)', ov.ipc('toggle') is not None and ov.show_file(1),
                 f'hook dir {ov.hook}'):
        return
    st = ov.show_file(1)
    time.sleep(0.3)
    layers = our_layers(nest)
    for mon, m in MONS.items():
        ls = layers.get(mon, [])
        check(f'{mon} has exactly one overlay-layer surface', len(ls) == 1 and ls[0]['level'] == '3',
              f'{[(l["level"], l["w"], l["h"]) for l in ls]}')
        if len(ls) == 1:
            l = ls[0]
            pos_ok = (l['x'], l['y']) in ((0, 0), (m['x'], m['y']))
            check(f'{mon} surface covers the monitor: {m["lw"]}x{m["lh"]} logical (hyprctl layers)',
                  pos_ok and (l['w'], l['h']) == (m['lw'], m['lh']), f'{l["x"]},{l["y"]} {l["w"]}x{l["h"]}')
        s = surface(st, mon)
        dev = s and (round(s['device']['w']), round(s['device']['h']))
        log = s and (round(s['logical']['w']), round(s['logical']['h']))
        check(f'{mon} surface device size {m["w"]}x{m["h"]} (hook)', s and dev == (m['w'], m['h']), f'device {dev}')
        check(f'{mon} surface logical size {m["lw"]}x{m["lh"]} (hook)', s and log == (m['lw'], m['lh']),
              f'logical {log}')
        check(f'{mon} shows its current workspace', s and s.get('workspace', {}).get('id') == (1 if mon == 'RO-A' else 2),
              f'{s and s.get("workspace")}')
    others = set(layers) - set(MONS)
    check('no overlay surface on any other output', not others, f'{others}')
    check('surface count is the output count (hook)', len((st or {}).get('surfaces', [])) == len(MONS),
          f'{[s.get("monitor") for s in (st or {}).get("surfaces", [])]}')

    # layout from the hook
    for name, (mon, rect) in EXPECT1.items():
        smon, w = window_entry(st, wins, name)
        sc = MONS[mon]['scale']
        got = w and rect_of(w.get('logical'))
        check(f'{name} spread rect {fmt(rect)} logical on {mon}', w and smon == mon and near(got, rect, TOL_RECT),
              f'on {smon} got {got and fmt(got)}')
        dev = tuple(v * sc for v in rect)
        gotd = w and rect_of(w.get('device'))
        check(f'{name} spread rect {fmt(dev)} device', w and near(gotd, dev, TOL_DEV), f'got {gotd and fmt(gotd)}')
        check(f'{name} title under its tile is the window title', w and w.get('title') == wins[name]['title'],
              f'{w and w.get("title")!r}')
    for mon, want in STRIP1.items():
        s = surface(st, mon) or {}
        got = s.get('strip', [])
        ok = len(got) == len(want) and all(
            g.get('id') == wid and g.get('current') == cur and g.get('empty') == emp and near(rect_of(g.get('logical')), r, TOL_RECT)
            for g, (wid, cur, emp, r) in zip(got, want))
        check(f'{mon} strip: {[(w[0], "current" if w[1] else "empty" if w[2] else "") for w in want]} at the hand-worked rects',
              ok, f'got {[(g.get("id"), g.get("current"), g.get("empty"), rect_of(g.get("logical"))) for g in got]}')
    for mon, want in MIN1.items():
        s = surface(st, mon) or {}
        got = s.get('minimized', [])
        ok = len(got) == len(want) and all(
            g.get('address') == wins[n]['address'] and near(rect_of(g.get('logical')), r, TOL_RECT)
            for g, (n, r) in zip(got, want))
        check(f'{mon} minimized row: {[(n, r) for n, r in want]}', ok,
              f'got {[(g.get("class"), rect_of(g.get("logical"))) for g in got]}')
    in_spread = [w.get('class') for s in (st or {}).get('surfaces', []) for w in s.get('windows', [])]
    check('the minimized window is not in any spread', wins['magenta']['class'] not in in_spread, f'{in_spread}')
    check('special workspaces are not in the strip',
          all(g.get('id', 0) > 0 for s in (st or {}).get('surfaces', []) for g in s.get('strip', [])))
    check('animations off in Hyprland -> animationMs 0', (st or {}).get('animationMs') == 0,
          f'{(st or {}).get("animationMs")}')
    th = (st or {}).get('theme', {})
    check(f'theme from $XDG_CONFIG_HOME/riley/bar.json: accent {THEME["accent"]}, font {THEME["font"]}',
          str(th.get('accent', '')).lower() == THEME['accent'] and th.get('font') == THEME['font'], f'{th}')
    notes = (work / 'notify.log').read_text().splitlines() if (work / 'notify.log').exists() else []
    check('broken config: defaults used', (st or {}).get('configOk') is False and
          all((st or {}).get('config', {}).get(k) == v for k, v in CONFIG_DEFAULTS.items()),
          f'configOk {(st or {}).get("configOk")} config {(st or {}).get("config")}')
    check('broken config: one notification naming config.xml', len(notes) == 1 and 'config.xml' in notes[0], f'{notes}')

    # pixels: grim of each output inside the nest; the live images may need a few frames, so retry for 3 s
    nest.dispatch('hl.dsp.cursor.move({ x = 5, y = 1435 })')        # off every tile: no hover highlight
    deadline = time.time() + 3
    while True:
        imgs = {mon: grim(nest, shots, mon, 'p1') for mon in MONS}
        bad = []
        for name, (mon, rect) in EXPECT1.items():
            im = imgs[mon]
            if im is None:
                bad.append(f'{mon}: grim failed')
                continue
            for p in samples(rect, MONS[mon]['scale']):
                if not colour_ok(im.getpixel(p), COLOURS[name]):
                    bad.append(f'{name} at {p} is {im.getpixel(p)}')
                    break
        if not bad or time.time() > deadline:
            break
        time.sleep(0.5)
    for mon in MONS:
        im = imgs[mon]
        check(f'{mon} screenshot is {MONS[mon]["w"]}x{MONS[mon]["h"]} device px', im and im.size == (MONS[mon]['w'], MONS[mon]['h']),
              f'{im and im.size}')
    for name, (mon, rect) in EXPECT1.items():
        mine = [b for b in bad if b.startswith(name + ' ') or b.startswith(mon + ':')]
        check(f'{name} image fills its spread rect with {COLOURS[name]} (9 points, device px)', not mine,
              '; '.join(mine))
    for mon, ((x, y), (n1, n2)) in GAPS.items():
        im, sc = imgs[mon], MONS[mon]['scale']
        p = (int(x * sc), int(y * sc))
        px = im and im.getpixel(p)
        check(f'{mon} spacing between {n1} and {n2} shows neither', im and not colour_ok(px, COLOURS[n1]) and
              not colour_ok(px, COLOURS[n2]), f'{p} is {px}')
    for mon, ((x, y), want) in BACKDROP.items():
        im, sc = imgs[mon], MONS[mon]['scale']
        p = (int(x * sc), int(y * sc))
        px = im and im.getpixel(p)
        check(f'{mon} backdrop is the wallpaper dimmed to 50 % {want}', im and colour_ok(px, want), f'{p} is {px}')

    # click a window: the test hook routes the point through the same handler as the overlay's MouseArea
    gx, gy = EXPECT1['green'][1][0] + EXPECT1['green'][1][2] / 2, 216 + 1064 / 2   # centre of green: 2367.4444, 748
    # a warp sends no motion to the surface: warp 4 px short, then one real 4 px motion (tests/overlay/vpointer.c)
    nest.dispatch(f'hl.dsp.cursor.move({{ x = {int(gx) - 4}, y = {int(gy)} }})')
    subprocess.run([str(VPOINTER), 'move', '4', '0'], env=nest.client_env(), capture_output=True, timeout=5)
    nest.wait(lambda: (ov.state() or {}).get('hovered') == wins['green']['address'], timeout=1, step=0.05)
    hover = (ov.state() or {}).get('hovered')
    check('hover highlights the window under the cursor', hover == wins['green']['address'], f'hovered {hover}')
    hit = ov.ipc('click', f'{gx:.1f}', f'{gy:.1f}')
    focused = nest.wait(lambda: (nest.j('activewindow') or {}).get('class') == wins['green']['class'], timeout=2)
    check('click on green focuses green', focused, f'click -> {hit}; active {(nest.j("activewindow") or {}).get("class")}')
    check('click closes the overlay', closed(nest, ov), f'layers {our_layers(nest)}')

    # Escape: the overlay has the keyboard while shown (wtype runs inside the nest)
    seq = 2
    ov.ipc('toggle')
    if check('toggle shows again', ov.show_file(seq)):
        subprocess.run(['wtype', '-k', 'Escape'], env=nest.client_env(), timeout=5)
        check('Escape closes the overlay', closed(nest, ov), f'layers {our_layers(nest)}')
        check('Escape leaves the focus alone (green)', (nest.j('activewindow') or {}).get('class') == wins['green']['class'])
    seq += 1
    ov.ipc('toggle')
    if check('toggle shows a third time', ov.show_file(seq)):
        ov.ipc('toggle')
        check('toggle again closes the overlay', closed(nest, ov), f'layers {our_layers(nest)}')
    seq += 1

    # click the empty workspace in RO-C's strip: centre of {1384, 24, 286.6667, 120} = (1527.3333, 84), global
    # (3440 + 1527.3333, 84) = (4967.3333, 84) -> RO-C switches to workspace 3
    ov.ipc('toggle')
    if check('toggle shows a fourth time', ov.show_file(seq)):
        hit = ov.ipc('click', '4967.3', '84.0')
        sw = nest.wait(lambda: next((m['activeWorkspace']['id'] for m in nest.monitors() if m['name'] == 'RO-C'), 0) == 3,
                       timeout=2)
        check('click on the strip\'s empty workspace switches RO-C to workspace 3', sw,
              f'click -> {hit}; RO-C on {next((m["activeWorkspace"] for m in nest.monitors() if m["name"] == "RO-C"), None)}')
        ov.ipc('hide')
        check('hide closes the overlay', closed(nest, ov), f'layers {our_layers(nest)}')

    after = {n: (tuple(c['at']), tuple(c['size']), c['floating'], c['workspace'].get('id')) for n, c in windows_by_name(nest).items()}
    check('no window was moved, resized or re-floated by the overlay', after == before,
          f'changed: {[n for n in before if after.get(n) != before[n]]}')
    ov.stop()


# ---- phase 2: a valid config, then the first-frame time -----------------------------------------------------------
def phase2(nest, run, stage, work, shots):
    print('\n== phase 2: valid config (max-scale 0.5), first frame over 10 toggles', flush=True)
    (work / 'minimized.json').write_text('{}')
    cfgf = work / 'xdg/config/riley-overview/config.xml'
    cfgf.write_text('<?xml version="1.0"?>\n<overview xmlns="urn:riley-overview:config" version="1">\n'
                    '  <max-scale>0.5</max-scale>\n</overview>\n')
    xsd = stage / 'share/riley-overview/config.xsd'
    r = subprocess.run(['xmllint', '--noout', '--schema', str(xsd), str(cfgf)], capture_output=True, text=True)
    check('phase 2 config validates against config.xsd', r.returncode == 0, r.stderr.strip()[:200])
    notes_before = len((work / 'notify.log').read_text().splitlines()) if (work / 'notify.log').exists() else 0
    names = ['red', 'green', 'blue', 'yellow']
    wins = start_windows(nest, run, work, names)
    if not setup_ok(nest, wins, names):
        check('phase 2 set up', False, 'nothing else checked')
        return
    ov = Overlay(nest, run, stage, work, 'p2').start()
    if not check('phase 2 overlay starts', ov.ready(), f'log {ov.log}'):
        return
    ov.ipc('toggle')
    st = ov.show_file(1)
    check('valid config used: configOk, maxScale 0.5', st and st.get('configOk') is True and
          st.get('config', {}).get('maxScale') == 0.5, f'{st and st.get("config")}')
    notes = len((work / 'notify.log').read_text().splitlines()) if (work / 'notify.log').exists() else 0
    check('valid config: no notification', notes == notes_before, f'{notes - notes_before} new')
    for name, (mon, rect) in EXPECT2.items():
        smon, w = window_entry(st, wins, name)
        got = w and rect_of(w.get('logical'))
        check(f'max-scale 0.5: {name} at {fmt(rect)} logical', w and smon == mon and near(got, rect, TOL_RECT),
              f'got {got and fmt(got)}')
    ov.ipc('toggle')
    closed(nest, ov)

    # The key path (lead's decision on R1): the key is a Hyprland bind on the `global` dispatcher, so a key press
    # starts no process. tests/overlay/vkeyboard.c stays connected to the nest as a virtual keyboard; for each toggle
    # it taps left Super (press, then release; the bind fires on the release) and answers with T0, the wall clock
    # read immediately before the press is written to the compositor. The first frame is the latest of the surfaces'
    # first frameSwapped after the show (hook, ms since the epoch, Date.now()); key to first frame = frame - T0.
    # The same key again closes the overlay.
    kb = subprocess.Popen([str(VKEYBOARD), 'serve'], env=nest.client_env(), stdin=subprocess.PIPE,
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
    run.procs.append(kb)

    def tap(*keys):
        kb.stdin.write('tap ' + ' '.join(keys) + '\n')
        kb.stdin.flush()
        out = kb.stdout.readline().split()
        return float(out[1]) if len(out) == 2 and out[0] == 'ok' else None

    total, via_key, closes = [], 0, 0
    seq = 2
    for i in range(10):
        time.sleep(0.25)
        t0 = tap('super')
        st = ov.show_file(seq, timeout=3) if t0 is not None else None
        if not st or not st.get('surfaces'):
            total.append(float('inf'))
            print(f'     key {i + 1}: no show-{seq}.json (key sent: {t0 is not None})', flush=True)
        else:
            frame = max(s.get('firstFrameAt') or float('inf') for s in st['surfaces'])
            total.append(frame - t0)
            if st.get('shortcutAt') is not None and st.get('ipcAt') is None:
                via_key += 1
        seq += 1
        time.sleep(0.05)
        tap('super')
        if closed(nest, ov):
            closes += 1
        else:
            ov.ipc('hide')
            closed(nest, ov)
    ok_vals = [t for t in total if t != float('inf')]
    med = statistics.median(total) if total else float('inf')
    mx = max(total) if total else float('inf')
    print(f'     key press to first frame (ms): {", ".join(f"{t:.1f}" for t in total)}', flush=True)
    check(f'first frame within {TARGET_MS} ms of the key press, 10 presses: median {med:.1f} ms, max {mx:.1f} ms',
          len(ok_vals) == 10 and mx <= TARGET_MS)
    check('each of the 10 shows came through the global shortcut (shortcutAt set, ipcAt null)', via_key == 10,
          f'{via_key} of 10')
    check('the key again closes the overlay, 10 presses', closes == 10, f'{closes} of 10')

    # Not gated, printed: Super held while another key is tapped (Super+A, no bind) and then released. GNOME opens
    # nothing then; this shows what the release bind does with it.
    time.sleep(0.25)
    kb.stdin.write('down super\n'); kb.stdin.flush(); kb.stdout.readline()
    tap('a')
    kb.stdin.write('up super\n'); kb.stdin.flush(); kb.stdout.readline()
    time.sleep(0.4)
    chord_opened = bool((ov.state() or {}).get('shown'))
    print(f'     not gated: Super+A then Super released opens the overview: {"yes" if chord_opened else "no"}',
          flush=True)
    if chord_opened:
        ov.ipc('hide')
        closed(nest, ov)
        seq += 1
    run.end(kb)

    # Not gated, printed: the scripts' and the bar's path, `riley-overview toggle` (a `qs ipc` client process);
    # t0 just before that command starts.
    cmd_total, ipc_part = [], []
    for i in range(10):
        time.sleep(0.25)
        t0 = time.time() * 1000
        p = subprocess.Popen([str(ov.bin), 'toggle'], env=ov.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        st = ov.show_file(seq, timeout=3)
        p.wait(5)
        if st and st.get('surfaces'):
            frame = max(s.get('firstFrameAt') or float('inf') for s in st['surfaces'])
            cmd_total.append(frame - t0)
            ipc_part.append((st.get('ipcAt') or float('nan')) - t0)
        seq += 1
        q = subprocess.Popen([str(ov.bin), 'toggle'], env=ov.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        q.wait(5)
        closed(nest, ov)
    if cmd_total:
        print(f'     not gated: `riley-overview toggle` to first frame (ms): {", ".join(f"{t:.1f}" for t in cmd_total)}'
              f'; median {statistics.median(cmd_total):.1f}, max {max(cmd_total):.1f}; of which command start to IPC '
              f'receipt: median {statistics.median(ipc_part):.1f}, max {max(ipc_part):.1f}', flush=True)
    ov.stop()


def prepare(work):
    from PIL import Image
    xdg = work / 'xdg'
    shutil.rmtree(xdg, ignore_errors=True)
    for d in ('config/riley', 'config/hypr', 'config/riley-overview', 'cache', 'state'):
        (xdg / d).mkdir(parents=True)
    Image.new('RGB', (64, 64), (255, 255, 255)).save(work / 'white.png')
    Image.new('RGB', (64, 64), (0, 255, 255)).save(work / 'cyan.png')
    (xdg / 'config/riley/bar.json').write_text(json.dumps(THEME))
    (xdg / 'config/hypr/hyprpaper.conf').write_text(
        '# the gate\'s wallpapers, in the form hypr-theme.py writes\nsplash = false\nipc = true\n\n'
        f'wallpaper {{\n    monitor = RO-A\n    path = {work}/white.png\n    fit_mode = cover\n}}\n'
        f'wallpaper {{\n    monitor =\n    path = {work}/cyan.png\n    fit_mode = cover\n}}\n')
    # broken on purpose: margin out of range (0 to 400)
    (xdg / 'config/riley-overview/config.xml').write_text(
        '<?xml version="1.0"?>\n<overview xmlns="urn:riley-overview:config" version="1">\n'
        '  <margin>9999</margin>\n</overview>\n')
    notify = work / 'notify.sh'
    notify.write_text(f'#!/bin/sh\n# the gate\'s stand-in for notify-send: one line per notification\n'
                      f'printf \'%s\\n\' "$*" >> {work}/notify.log\n')
    notify.chmod(0o755)
    (work / 'notify.log').unlink(missing_ok=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--stage', required=True, type=Path)
    ap.add_argument('--work', required=True, type=Path)
    ap.add_argument('--shots', required=True, type=Path)
    ap.add_argument('--vpointer', required=True, type=Path)
    ap.add_argument('--vkeyboard', required=True, type=Path)
    a = ap.parse_args()
    global VPOINTER, VKEYBOARD
    VPOINTER = a.vpointer.resolve()
    VKEYBOARD = a.vkeyboard.resolve()
    work, shots = a.work.resolve(), a.shots.resolve()
    work.mkdir(parents=True, exist_ok=True)
    shots.mkdir(parents=True, exist_ok=True)
    prepare(work)
    nest = Nest(HYPRLAND, nest_config(work), work / 'nest.log')
    run = Run()
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(130))
    try:
        nest.start()
        for name in MONS:
            nest.ctl('output', 'create', 'headless', name)
        ok = nest.wait(lambda: {m['name']: (m['width'], m['height'], m['scale'], m['x'], m['y'])
                                for m in nest.monitors()} ==
                       {n: (m['w'], m['h'], m['scale'], m['x'], m['y']) for n, m in MONS.items()}, timeout=5)
        if check('setup nest outputs RO-A 3440x1440@1 at 0,0 and RO-C 3440x1440@1.25 at 3440,0', ok,
                 f'{[(m["name"], m["width"], m["height"], m["scale"], m["x"], m["y"]) for m in nest.monitors()]}'):
            try:
                phase1(nest, run, a.stage, work, shots)
            finally:
                # whatever phase 1 left: the overlay and its windows end; RO-C goes back to workspace 2, then the focus
                # to workspace 1 on RO-A as at the start (a window mapping while workspace 2 has the focus would
                # match its float rule before its own rule moves it to workspace 1)
                run.end_all()
                nest.wait(lambda: not windows_by_name(nest), timeout=10)
                nest.dispatch('hl.dsp.focus({ workspace = "2" })')
                nest.dispatch('hl.dsp.focus({ workspace = "1" })')
            phase2(nest, run, a.stage, work, shots)
    except Exception as e:     # a crash is a failure, not a pass
        check('gate ran to the end', False, f'{type(e).__name__}: {e}')
    finally:
        run.end_all()
        nest.stop()
        shutil.rmtree(shots, ignore_errors=True)
    failed = [n for n, ok in results if not ok]
    print(f'live checks: {len(results) - len(failed)} passed, {len(failed)} failed', flush=True)
    return 0 if results and not failed else 1


if __name__ == '__main__':
    sys.exit(main())
