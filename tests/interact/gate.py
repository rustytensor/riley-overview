#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""M3 gate, live part: interaction in a nested Hyprland. Run by tests/run-interact.sh under dp2-lock, never alone:

  dp2-lock python3 -I tests/interact/gate.py --stage STAGE --work WORK --shots SHOTS --vpointer VPOINTER

STAGE holds bin/riley-overview and share/riley-overview/{shell/, config.xsd}; WORK the nest's config, the throwaway
XDG folders, the fake launcher and the logs; SHOTS the screenshots (deleted on exit). Interfaces: docs/interact.md.

The nest (a window on an empty DP-2 workspace of Marc's session; nothing runs in his session), three headless outputs:
  RO-A  3440x1440 at scale 1,    position 0,0,    transform 0 -> logical 3440x1440; workspaces 1 (shown), 2, 3
  RO-C  3440x1440 at scale 1.25, position 3440,0, transform 0 -> logical 2752x1152; workspace 4
  RO-B  2560x1440 at scale 1,    position 6192,0, transform 1 -> logical 1440x2560 (rotated); workspace 5
  The nest's own window output (WAYLAND-1) is disabled. No gaps, borders, rounding, shadows, blur; animations off
  until the last phase. Every test window floats by its own rule at a fixed size and monitor-relative place.
Test windows (tests/overlay/colour.qml: one colour each, class "ro.<name>.qml", title "ro <name>"):
  red     1600x600 at   40,40  ws 1      green  1600x600 at 1800,40  ws 1
  blue    1400x600 at   40,760 ws 1      yellow 1400x600 at 1800,760 ws 1
  cyan     800x600 at  100,100 ws 2      orange  800x600 at  100,100 ws 3
  magenta 1200x800 at  100,100 ws 4 (RO-C: global 3540,100)
  white   1000x800 at  200,200 ws 5 (RO-B: global 6392,200)
Pointer input is real: hl.dsp.cursor.move places the cursor, the gate's vpointer (virtual-pointer protocol) sends
motion and buttons; keys come from wtype inside the nest. Every expected value is derived in EXPECTED below, before
the run.
"""
import argparse, json, os, shutil, signal, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
OVERLAY_TESTS = HERE.parent / 'overlay'
sys.path.insert(0, str(OVERLAY_TESTS))
from nested import Nest  # noqa: E402

HYPRLAND = os.environ.get('RILEYOVERVIEW_HYPRLAND', '/usr/bin/Hyprland')
QML = os.environ.get('RILEYOVERVIEW_QML', '/usr/lib64/qt6/bin/qml')
NS = 'riley-overview'
LIFETIME = 240               # seconds each test window lives (the whole live part is well under this)
TOL_RECT = 1.0               # logical px: the overlay may round its rectangles when it draws
TOL_RGB = 24                 # per channel, for a solid colour scaled by the compositor and Qt
FRAME_MS = 1000 / 60         # one frame of the nest's 60 Hz outputs
VPOINTER = None

COLOURS = {'red': (255, 0, 0), 'green': (0, 255, 0), 'blue': (0, 0, 255), 'yellow': (255, 255, 0),
           'cyan': (0, 255, 255), 'orange': (255, 128, 0), 'magenta': (255, 0, 255), 'white': (255, 255, 255)}
MONS = {'RO-A': {'x': 0, 'y': 0, 'w': 3440, 'h': 1440, 'scale': 1.0, 'transform': 0, 'lw': 3440, 'lh': 1440},
        'RO-C': {'x': 3440, 'y': 0, 'w': 3440, 'h': 1440, 'scale': 1.25, 'transform': 0, 'lw': 2752, 'lh': 1152},
        'RO-B': {'x': 6192, 'y': 0, 'w': 2560, 'h': 1440, 'scale': 1.0, 'transform': 1, 'lw': 1440, 'lh': 2560}}
# name -> (monitor, workspace, (x, y, w, h) monitor-relative logical)
WINDOWS = {'red': ('RO-A', 1, (40, 40, 1600, 600)), 'green': ('RO-A', 1, (1800, 40, 1600, 600)),
           'blue': ('RO-A', 1, (40, 760, 1400, 600)), 'yellow': ('RO-A', 1, (1800, 760, 1400, 600)),
           'cyan': ('RO-A', 2, (100, 100, 800, 600)), 'orange': ('RO-A', 3, (100, 100, 800, 600)),
           'magenta': ('RO-C', 4, (100, 100, 1200, 800)), 'white': ('RO-B', 5, (200, 200, 1000, 800))}
THEME = {'base': '#101418', 'accent': '#123456', 'font': 'DejaVu Sans'}
ACCENT = (0x12, 0x34, 0x56)

# ---- EXPECTED: worked out by hand (docs/design.md, docs/overlay.md, docs/interact.md) -------------------------
# Config defaults (a valid config file with no elements): margin 24, strip 120, strip spacing 16, search 40, gap 16,
# window spacing 24, max scale 1, launcher "fuzzel". Safe area {24, 216, W-48, H-240}:
#   A {24, 216, 3392, 1200}; C {24, 216, 2704, 912}; B {24, 216, 1392, 2320}.
#
# Show 1, RO-A (red, green, blue, yellow; centres (840,340), (2600,340), (740,1060), (2500,1060); widths 1600,
# 1600, 1400, 1400, sum 6000, all 600 high):
#   r=1: (3392-72)/6000 = 0.55333.
#   r=2: ideal 3000; red 1600, + green 3200 (|1-1.0667| = 0.0667 < |1-0.5333| = 0.4667: joins), + blue 4600 (0.5333,
#        worse): rows [red green], [blue yellow]; horizontal 3368/3200 = 1.0525, 3368/2800 = 1.2029; vertical
#        (1200-24)/1200 = 0.98 -> 0.98.
#   r=3: ideal 2000: rows [red], [green] (+blue 3000: 0.5 vs 0.2, worse), [blue yellow]: vertical 1152/1800 = 0.64.
#   r=4: vertical 1128/2400 = 0.47. Winner r=2, s = 0.98: 1568x588 and 1372x588.
#   Row 0: 2*1568+24 = 3160, x0 = 24 + (3392-3160)/2 = 140, green at 140+1568+24 = 1732, y 216.
#   Row 1: 2*1372+24 = 2768, x0 = 24 + (3392-2768)/2 = 336, yellow at 336+1372+24 = 1732, y 216+588+24 = 828.
SPREAD1 = {'red': ('RO-A', (140, 216, 1568, 588)), 'green': ('RO-A', (1732, 216, 1568, 588)),
           'blue': ('RO-A', (336, 828, 1372, 588)), 'yellow': ('RO-A', (1732, 828, 1372, 588)),
           # RO-C magenta 1200x800: s = min(1, 2704/1200, 912/800) = 1; x = 24 + (2704-1200)/2 = 776,
           # y = 216 + (912-800)/2 = 272.
           'magenta': ('RO-C', (776, 272, 1200, 800)),
           # RO-B white 1000x800: s = min(1, 1392/1000, 2320/800) = 1; x = 24 + (1392-1000)/2 = 220,
           # y = 216 + (2320-800)/2 = 976.
           'white': ('RO-B', (220, 976, 1000, 800))}
# Strips (next empty workspace: 1 + the largest id 5 = 6, on every strip):
#   RO-A [1 current, 2, 3, 6 empty]: thumb 120 high, 120*3440/1440 = 286.6667 wide; row 4*286.6667 + 3*16 =
#     1194.6667, x0 = 24 + (3392-1194.6667)/2 = 1122.6667, step 302.6667: 1122.6667, 1425.3333, 1728, 2030.6667.
#   RO-C [4 current, 6 empty]: same thumb (2752/1152 = 3440/1440); row 589.3333, x0 = 24 + (2704-589.3333)/2 =
#     1081.3333, then 1384.
#   RO-B [5 current, 6 empty]: thumb 120*1440/2560 = 67.5 wide; row 151, x0 = 24 + (1392-151)/2 = 644.5, then 728.
TW = 860 / 3
STRIP1 = {'RO-A': [(1, True, False, (1122 + 2 / 3, 24, TW, 120)), (2, False, False, (1425 + 1 / 3, 24, TW, 120)),
                   (3, False, False, (1728, 24, TW, 120)), (6, False, True, (2030 + 2 / 3, 24, TW, 120))],
          'RO-C': [(4, True, False, (1081 + 1 / 3, 24, TW, 120)), (6, False, True, (1384, 24, TW, 120))],
          'RO-B': [(5, True, False, (644.5, 24, 67.5, 120)), (6, False, True, (728, 24, 67.5, 120))]}
# RO-B, rotated: a point left of white's tile (x < 220) in the safe area shows the backdrop, not white.
ROTATED_OFF_TILE = (100, 1300)
#
# Keyboard (show 1; spread above; centres red (924,510), green (2516,510), blue (1022,1122), yellow (2418,1122);
# x ranges red 140..1708, green 1732..3300, blue 336..1708, yellow 1732..3104; the navigation surface is RO-A, the
# monitor with the pointer):
#   Right -> red     start: reading order first
#   Right -> green   in beam
#   Down  -> yellow  in beam (x 1732..3104 overlaps 1732..3300); blue is not
#   Left  -> blue    in beam; red is out of beam
#   Up    -> red     in beam (x 140..1708 overlaps 336..1708); green is not
#   Left  -> red     nothing to the left
#   Down  -> blue
#   Right -> yellow  in beam; green (cx 2516 > 2418) out of beam
#   Right -> green   no rect in beam to the right; green is the only candidate
#   Up    -> green   nothing above
#   Return focuses green and closes the overview.
KEYS1 = [('Right', 'red'), ('Right', 'green'), ('Down', 'yellow'), ('Left', 'blue'), ('Up', 'red'), ('Left', 'red'),
         ('Down', 'blue'), ('Right', 'yellow'), ('Right', 'green'), ('Up', 'green')]
# Search (titles "ro <name>", classes "ro.<name>.qml"; shown: red, green, blue, yellow, magenta, white):
#   "re"  -> red ("ro red"), green ("ro green"); no other title or class holds "re". The highlight: after "r" every
#            window matches ("ro ..."), nothing was highlighted -> reading order of RO-A = red; "re" keeps red.
#            Then Down -> red (nothing visible below), Right -> green, Left -> red, Return focuses red.
#   "llo" -> yellow only; highlight yellow. Escape clears the query (all six visible again, still shown, yellow
#            still highlighted); Escape again closes; the focus stays on red.
#   "xyzq", BackSpace -> "xyz": nothing visible, no highlight; Return closes and runs the launcher: the default
#            "fuzzel" -> argv fuzzel --search=xyz (the fake fuzzel records argc 1 and "--search=xyz").
SEARCH_RE = {'red', 'green'}
KEYS_RE = [('Down', 'red'), ('Right', 'green'), ('Left', 'red')]
#
# Mouse (show 5, all in one show; the overview stays open throughout):
#   Close button of yellow: closeRect({1732, 828, 1372, 588}) = {3092, 816, 24, 24}, centre (3104, 828). Hover
#   yellow at its centre (2418, 1122), glide to (3104, 828): the highlight stays on yellow (close button), the disc
#   is accent at (3104, 819) and (3113, 828) (9 px from its centre). No button on red (not highlighted): (1708, 207)
#   is not accent. Left click -> yellow closes (gone from clients, its process exits).
#   Re-layout of RO-A with red (840,340), green (2600,340), blue (740,1060); sum 4600:
#     r=1: 3344/4600 = 0.72696. r=2: ideal 2300: red; + green 3200 (|1-1.3913| = 0.3913 vs 0.3043: worse) -> rows
#     [red], [green blue]; horizontal 3392/1600, 3368/3000 = 1.1227; vertical 1176/1200 = 0.98 -> 0.98.
#     r=3: 1152/1800 = 0.64. Winner r=2, s = 0.98. Row 0 red 1568 wide: x = 24 + (3392-1568)/2 = 936, y 216.
#     Row 1 by centre x: blue (740) then green (2600): 1372+24+1568 = 2964, x0 = 24 + (3392-2964)/2 = 238,
#     green at 238+1372+24 = 1634, y 828.
AFTER_CLOSE = {'red': (936, 216, 1568, 588), 'blue': (238, 828, 1372, 588), 'green': (1634, 828, 1568, 588)}
YELLOW_CLOSE = (3104, 828)
CLOSE_SAMPLES = [(3104, 819), (3113, 828)]
NO_CLOSE_SAMPLE = (1708, 207)
#   Middle click on magenta, centre of {776, 272, 1200, 800} on RO-C = local (1376, 672), global (4816, 672) ->
#   magenta closes; RO-C's spread is empty.
MAGENTA_AT = (4816, 672)
#   Drag 1: red from its centre (936+784, 216+294) = (1720, 510) onto RO-A's strip entry 2 = workspace 3, centre
#   (1728+143.3333, 84) -> red on workspace 3 (not 2, not 6); while over it the drop target is workspace 3.
#   Re-layout of RO-A with blue (740,1060) 1400x600, green (2600,340) 1600x600: r=1: 3368/3000 = 1.1227, vertical
#   2 -> capped at 1; r=2: 1176/1200 = 0.98 < 1. Winner r=1, s = 1. Row by centre x: blue, green: 1400+24+1600 =
#   3024, x0 = 24 + (3392-3024)/2 = 208, green at 208+1400+24 = 1632; y = 216 + (1200-600)/2 = 516.
DRAG1 = {'name': 'red', 'from': (1720, 510), 'to': (1871.3333, 84), 'ws': 3, 'not': (2, 6),
         'target': {'kind': 'workspace', 'monitor': 'RO-A', 'id': 3}}
AFTER_DRAG1 = {'blue': (208, 516, 1400, 600), 'green': (1632, 516, 1600, 600)}
#   Drag 2: green from its centre (1632+800, 516+300) = (2432, 816) onto RO-C's overlay away from its strip,
#   local (1376, 700) = global (4816, 700) -> green on workspace 4 (RO-C's), monitor RO-C.
#   RO-A then has blue alone: s = min(1, 3392/1400, 1200/600) = 1, x = 24 + (3392-1400)/2 = 1020, y 516.
DRAG2 = {'name': 'green', 'from': (2432, 816), 'to': (4816, 700), 'ws': 4, 'not': (3, 5),
         'target': {'kind': 'monitor', 'monitor': 'RO-C', 'id': 4}}
AFTER_DRAG2 = {'blue': (1020, 516, 1400, 600)}
#   Drag 3: blue from its centre (1720, 816) onto RO-A's empty entry (index 3, workspace 6), centre
#   (2030.6667+143.3333, 84) = (2174, 84) -> blue on workspace 6 (not 3, not 7), and workspace 6 is on RO-A.
DRAG3 = {'name': 'blue', 'from': (1720, 816), 'to': (2174, 84), 'ws': 6, 'not': (3, 7),
         'target': {'kind': 'workspace', 'monitor': 'RO-A', 'id': 6}}
#
# Animations: with Hyprland's animations off (shows 1 to 5) animationMs is 0 and no tile takes an in-between step
# (anim.frames 0). With them on (last phase, a fresh overlay): animationMs 200 (config default, cap 200); the open
# move takes at least 3 in-between steps (200 ms at 60 Hz is about 12 frames) and anim.doneAt - anim.startedAt is
# at most 200 ms plus one 60 Hz frame (the last step lands on a frame): 216.7 ms.
ANIM_MS = 200
ANIM_LIMIT = ANIM_MS + FRAME_MS
ANIM_MIN_FRAMES = 3

results = []


def check(name, ok, detail=''):
    results.append((name, bool(ok)))
    print(('PASS ' if ok else 'FAIL ') + 'interact::' + name + (f': {detail}' if detail else ''), flush=True)
    return bool(ok)


def near(a, b, tol):
    return a is not None and b is not None and len(a) == len(b) and all(abs(x - y) <= tol for x, y in zip(a, b))


def fmt(r):
    return '(' + ', '.join(f'{v:.2f}' for v in r) + ')' if r else 'None'


def rect_of(d):
    return (d['x'], d['y'], d['w'], d['h']) if isinstance(d, dict) else None


# ---- the nest ---------------------------------------------------------------------------------------------------
def nest_config(work):
    cfg = work / 'hyprland.lua'
    rules = []
    for name, (mon, ws, (x, y, w, h)) in WINDOWS.items():
        rules.append(f'hl.window_rule({{ name = "ro-{name}", match = {{ class = "^ro\\\\.{name}\\\\..*$" }}, '
                     f'workspace = "{ws} silent", float = true, size = "{w} {h}", move = "{x} {y}" }})')
    mons = []
    for name, m in MONS.items():
        mons.append(f'hl.monitor({{ output = "{name}", mode = "{m["w"]}x{m["h"]}@60", position = "{m["x"]}x{m["y"]}", '
                    f'scale = {m["scale"]:g}, transform = {m["transform"]} }})')
    cfg.write_text('''-- the M3 gate's nest: three headless outputs, one of them rotated
hl.config({ xwayland = { enabled = false }, animations = { enabled = false },
            misc = { disable_hyprland_logo = true, disable_splash_rendering = true },
            ecosystem = { no_update_news = true, no_donation_nag = true },
            general = { gaps_in = 0, gaps_out = 0, border_size = 0 },
            decoration = { rounding = 0, shadow = { enabled = false }, blur = { enabled = false } } })
hl.monitor({ output = "WAYLAND-1", disabled = true })
''' + '\n'.join(mons) + '''
hl.workspace_rule({ workspace = "1", monitor = "RO-A", default = true })
hl.workspace_rule({ workspace = "2", monitor = "RO-A" })
hl.workspace_rule({ workspace = "3", monitor = "RO-A" })
hl.workspace_rule({ workspace = "4", monitor = "RO-C", default = true })
hl.workspace_rule({ workspace = "5", monitor = "RO-B", default = true })
''' + '\n'.join(rules) + '\n')
    return cfg


class Run:
    """Processes this gate started, by saved Popen handle: ended on every exit."""

    def __init__(self):
        self.procs = []

    def spawn(self, argv, env, log, stdin=None, stdout=None, text=False):
        # same process group as the gate: run-interact.sh can end the whole group by its saved ID; output goes to
        # the log unless the caller takes stdout (then only stderr goes to the log)
        out = open(log, 'ab')
        p = subprocess.Popen(argv, env=env, stdin=stdin, stdout=stdout if stdout is not None else out,
                             stderr=out if stdout is not None else subprocess.STDOUT, text=text)
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
    procs = {}
    for name in names:
        r, g, b = COLOURS[name]
        procs[name] = run.spawn([QML, str(OVERLAY_TESTS / 'colour.qml'), '--', name, f'#{r:02x}{g:02x}{b:02x}',
                                 '800', '600', str(LIFETIME)], env, work / f'window-{name}.log')
        if not nest.wait(lambda: name in windows_by_name(nest), timeout=10):
            return None, procs
    time.sleep(0.5)
    return windows_by_name(nest), procs


def mon_ids(nest):
    return {m['id']: m['name'] for m in nest.monitors()}


def setup_ok(nest, wins):
    ok = True
    ids = mon_ids(nest)
    for name, (mon, ws, (x, y, w, h)) in WINDOWS.items():
        c = wins.get(name) if wins else None
        want = (MONS[mon]['x'] + x, MONS[mon]['y'] + y, w, h)
        got = c and (tuple(c['at']) + tuple(c['size']))
        ok &= check(f'setup {name} at {want} on workspace {ws} ({mon}), floating',
                    c and got == want and c['workspace'].get('id') == ws and ids.get(c['monitor']) == mon and c['floating'],
                    f'got {got} workspace {c and c["workspace"]} monitor {c and ids.get(c["monitor"])} '
                    f'floating {c and c["floating"]}')
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
            # the fake launcher first on PATH
            'PATH': str(work / 'bin') + ':' + os.environ.get('PATH', '/usr/bin:/bin'),
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

    def _json(self, *args):
        out = self.ipc(*args)
        try:
            return json.loads(out) if out else None
        except ValueError:
            return None

    def state(self):
        return self._json('state')

    def snapshot(self):
        return self._json('snapshot')

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

    def wait_state(self, pred, timeout=2):
        last = [None]

        def t():
            last[0] = self.state()
            return last[0] is not None and pred(last[0])
        ok = self.nest.wait(t, timeout=timeout, step=0.05)
        return bool(ok), last[0]

    def stop(self):
        if self.proc:
            self.run.end(self.proc)


def our_layers(nest):
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


def entry_of(state, addr):
    for s in (state or {}).get('surfaces', []):
        for w in s.get('windows', []):
            if w.get('address') == addr:
                return s['monitor'], w
    return None, None


def spread_of(state, mon):
    """{address: logical rect} of one surface's spread."""
    s = surface(state, mon) or {}
    return {w.get('address'): rect_of(w.get('logical')) for w in s.get('windows', [])}


def grim(nest, shots, mon, tag):
    f = shots / f'{tag}-{mon}.png'
    r = subprocess.run(['grim', '-o', mon, str(f)], env=nest.client_env(), capture_output=True, timeout=10)
    if r.returncode != 0:
        return None
    from PIL import Image
    return Image.open(f).convert('RGB')


def samples(rect, scale):
    x, y, w, h = (v * scale for v in rect)
    return [(int(x + w * fx), int(y + h * fy)) for fy in (0.2, 0.5, 0.8) for fx in (0.2, 0.5, 0.8)]


def colour_ok(px, want, tol=TOL_RGB):
    return px is not None and all(abs(a - b) <= tol for a, b in zip(px, want))


def pixel(im, p, scale=1.0):
    if im is None:
        return None
    q = (int(p[0] * scale), int(p[1] * scale))
    if not (0 <= q[0] < im.size[0] and 0 <= q[1] < im.size[1]):
        return None
    return im.getpixel(q)


def centre(r):
    return (r[0] + r[2] / 2, r[1] + r[3] / 2)


# ---- input ------------------------------------------------------------------------------------------------------
class Pointer:
    """One virtual pointer (vpointer serve) for the whole mouse phase: motion and buttons are real input events."""

    def __init__(self, nest, run, work):
        self.nest = nest
        self.p = run.spawn([str(VPOINTER), 'serve'], nest.client_env(), work / 'vpointer.log',
                           stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        self.held = set()

    def cmd(self, line):
        try:
            self.p.stdin.write(line + '\n')
            self.p.stdin.flush()
            return self.p.stdout.readline().strip() == 'ok'
        except (BrokenPipeError, OSError, ValueError):
            return False

    def pos(self):
        c = self.nest.j('cursorpos') or {}
        return c.get('x'), c.get('y')

    def warp(self, x, y):
        self.nest.dispatch(f'hl.dsp.cursor.move({{ x = {int(round(x))}, y = {int(round(y))} }})')

    def hover(self, x, y):
        """Warp 4 px short, then one real 4 px motion: a warp alone sends no motion to the surface under it."""
        self.warp(x - 4, y)
        return self.cmd('move 4 0')

    def glide(self, x, y, step=40):
        """Real relative motion from the cursor to (x, y) (global logical, rounded), at most `step` px per event,
        corrected with hyprctl cursorpos until within 1 px."""
        tx, ty = int(round(x)), int(round(y))
        for _ in range(6):
            cx, cy = self.pos()
            if cx is None:
                return False
            dx, dy = tx - cx, ty - cy
            if abs(dx) <= 1 and abs(dy) <= 1:
                return True
            n = int(max(abs(dx), abs(dy)) // step) + 1
            for _ in range(n):
                self.cmd(f'move {dx / n:.3f} {dy / n:.3f}')
                self.cmd('sleep 8')
        cx, cy = self.pos()
        return cx is not None and abs(tx - cx) <= 1 and abs(ty - cy) <= 1

    def press(self, b):
        self.held.add(b)
        return self.cmd(f'press {b}')

    def release(self, b):
        self.held.discard(b)
        return self.cmd(f'release {b}')

    def click(self, b):
        ok = self.press(b)
        self.cmd('sleep 30')
        return self.release(b) and ok

    def close(self):
        for b in list(self.held):
            self.release(b)
        try:
            self.p.stdin.close()
            self.p.wait(5)
        except (OSError, subprocess.TimeoutExpired):
            pass


def wtype(nest, *args):
    subprocess.run(['wtype', *args], env=nest.client_env(), capture_output=True, timeout=5)


def park(nest):
    # bottom-left corner of RO-A, inside the margin: no tile, strip, search field or anything else of the overview
    nest.dispatch('hl.dsp.cursor.move({ x = 5, y = 1435 })')


def show(ov, seq):
    # an earlier step that failed may have left the overview open: close it, so each show starts the same way
    if (ov.state() or {}).get('shown'):
        ov.ipc('hide')
        closed(ov.nest, ov, timeout=3)
    park(ov.nest)
    time.sleep(0.1)
    ov.ipc('toggle')
    return ov.show_file(seq)


def wait_client(nest, addr, pred, timeout=3):
    last = [None]

    def t():
        last[0] = next((c for c in nest.clients() if c['address'] == addr), None)
        return pred(last[0])
    return bool(nest.wait(t, timeout=timeout, step=0.05)), last[0]


def gone(p, timeout=3):
    end = time.time() + timeout
    while time.time() < end:
        if p.poll() is not None:
            return True
        time.sleep(0.05)
    return p.poll() is not None


# ---- phase 1: show 1, the rotated output, the keys ---------------------------------------------------------------
def phase_keys(nest, ov, wins, shots):
    addr = {n: c['address'] for n, c in wins.items()}
    name_of = {a: n for n, a in addr.items()}
    print('\n== shows 1-4: layout with a rotated output, keyboard navigation, search, launcher', flush=True)
    nest.dispatch(f'hl.dsp.focus({{ window = "address:{addr["red"]}" }})')
    st = show(ov, 1)
    if not check('show 1 (show-1.json written)', st, f'hook dir {ov.hook}'):
        return False
    time.sleep(0.3)
    layers = our_layers(nest)
    for mon, m in MONS.items():
        ls = layers.get(mon, [])
        ok = len(ls) == 1 and (ls[0]['x'], ls[0]['y']) in ((0, 0), (m['x'], m['y'])) and \
            (ls[0]['w'], ls[0]['h']) == (m['lw'], m['lh'])
        check(f'{mon} has one overlay surface of {m["lw"]}x{m["lh"]} logical (hyprctl layers)', ok,
              f'{[(l["x"], l["y"], l["w"], l["h"]) for l in ls]}')
        s = surface(st, mon)
        dev = s and (round(s['device']['w']), round(s['device']['h']))
        log = s and (round(s['logical']['w']), round(s['logical']['h']))
        want_dev = (round(m['lw'] * m['scale']), round(m['lh'] * m['scale']))
        check(f'{mon} surface logical {m["lw"]}x{m["lh"]}, device {want_dev[0]}x{want_dev[1]} (hook)',
              s and log == (m['lw'], m['lh']) and dev == want_dev, f'logical {log} device {dev}')
    for name, (mon, rect) in SPREAD1.items():
        smon, w = entry_of(st, addr[name])
        got = w and rect_of(w.get('logical'))
        check(f'show 1: {name} spread rect {fmt(rect)} on {mon}', w and smon == mon and near(got, rect, TOL_RECT),
              f'on {smon} got {fmt(got)}')
    for mon, want in STRIP1.items():
        got = (surface(st, mon) or {}).get('strip', [])
        ok = len(got) == len(want) and all(
            g.get('id') == wid and g.get('current') == cur and g.get('empty') == emp and near(rect_of(g.get('logical')), r, TOL_RECT)
            for g, (wid, cur, emp, r) in zip(got, want))
        check(f'show 1: {mon} strip {[w[0] for w in want]} at the hand-worked rects', ok,
              f'got {[(g.get("id"), g.get("current"), g.get("empty"), fmt(rect_of(g.get("logical")))) for g in got]}')
    check('show 1: empty query, no highlight, every tile visible',
          st.get('query') == '' and st.get('highlighted') == '' and
          all(w.get('visible') is True for s in st.get('surfaces', []) for w in s.get('windows', [])),
          f'query {st.get("query")!r} highlighted {st.get("highlighted")!r}')
    anim = st.get('anim') or {}
    check('animations off: animationMs 0 and no in-between step (anim.frames 0)',
          st.get('animationMs') == 0 and anim.get('frames') == 0 and anim.get('doneAt') is not None,
          f'animationMs {st.get("animationMs")} anim {anim}')

    # the rotated output's pixels: white fills its spread rect, the backdrop beside it is not white
    im = None
    deadline = time.time() + 3
    while True:
        im = grim(nest, shots, 'RO-B', 's1')
        bad = [p for p in samples(SPREAD1['white'][1], 1.0) if not colour_ok(pixel(im, p), COLOURS['white'])]
        if not bad or time.time() > deadline:
            break
        time.sleep(0.5)
    check('RO-B (rotated) screenshot is 1440x2560', im and im.size == (1440, 2560), f'{im and im.size}')
    check('RO-B (rotated): white fills its spread rect (9 points)', im and not bad,
          f'{[(p, pixel(im, p)) for p in bad][:3]}')
    off = pixel(im, ROTATED_OFF_TILE)
    check(f'RO-B (rotated): {ROTATED_OFF_TILE} beside the tile is not white', off is not None and not colour_ok(off, COLOURS['white']),
          f'{off}')

    # arrows
    seq_ok = True
    got_seq = []
    for k, want in KEYS1:
        wtype(nest, '-k', k)
        time.sleep(0.1)
        ok, s = ov.wait_state(lambda s, w=want: s.get('highlighted') == addr[w], timeout=1)
        got_seq.append(name_of.get((s or {}).get('highlighted'), (s or {}).get('highlighted')))
        seq_ok &= ok
    check(f'arrows {[k for k, _ in KEYS1]} highlight {[w for _, w in KEYS1]}', seq_ok, f'got {got_seq}')
    check('hovered (M2 alias) is the highlight', (ov.state() or {}).get('hovered') == addr['green'],
          f'{(ov.state() or {}).get("hovered")}')
    wtype(nest, '-k', 'Return')
    check('Return focuses the highlighted window (green)',
          nest.wait(lambda: (nest.j('activewindow') or {}).get('address') == addr['green'], timeout=2),
          f'active {(nest.j("activewindow") or {}).get("class")}')
    check('Return closes the overview', closed(nest, ov))

    # search "re"
    st = show(ov, 2)
    if check('show 2', st):
        wtype(nest, 're')
        ok, s = ov.wait_state(lambda s: s.get('query') == 're', timeout=2)
        vis = {name_of.get(a, a) for a in (s or {}).get('visible', [])}
        check(f'typing "re" sets the query and shows {sorted(SEARCH_RE)}', ok and vis == SEARCH_RE,
              f'query {(s or {}).get("query")!r} visible {sorted(vis)}')
        check('after typing, the highlight is the first visible in reading order (red)',
              (s or {}).get('highlighted') == addr['red'], f'{name_of.get((s or {}).get("highlighted"))}')
        snap = ov.snapshot()
        flags = {name_of.get(w.get('address')): w.get('visible') for sf in (snap or {}).get('surfaces', [])
                 for w in sf.get('windows', [])}
        check('snapshot marks red and green visible, the other four not',
              flags == {'red': True, 'green': True, 'blue': False, 'yellow': False, 'magenta': False, 'white': False},
              f'{flags}')
        # hidden tiles are not drawn: blue's spread centre is not blue, red's still red
        deadline = time.time() + 2
        while True:
            im = grim(nest, shots, 'RO-A', 's2')
            pb, pr = pixel(im, centre(SPREAD1['blue'][1])), pixel(im, centre(SPREAD1['red'][1]))
            if (pb and not colour_ok(pb, COLOURS['blue']) and colour_ok(pr, COLOURS['red'])) or time.time() > deadline:
                break
            time.sleep(0.3)
        check('a tile that does not match is not drawn (blue centre is not blue, red centre is red)',
              pb is not None and not colour_ok(pb, COLOURS['blue']) and colour_ok(pr, COLOURS['red']), f'blue {pb} red {pr}')
        seq_ok, got_seq = True, []
        for k, want in KEYS_RE:
            wtype(nest, '-k', k)
            time.sleep(0.1)
            ok, s = ov.wait_state(lambda s, w=want: s.get('highlighted') == addr[w], timeout=1)
            got_seq.append(name_of.get((s or {}).get('highlighted'), (s or {}).get('highlighted')))
            seq_ok &= ok
        check(f'arrows among the matches {[k for k, _ in KEYS_RE]} -> {[w for _, w in KEYS_RE]}', seq_ok, f'got {got_seq}')
        wtype(nest, '-k', 'Return')
        check('Return on a search focuses the highlighted match (red)',
              nest.wait(lambda: (nest.j('activewindow') or {}).get('address') == addr['red'], timeout=2),
              f'active {(nest.j("activewindow") or {}).get("class")}')
        check('and closes the overview', closed(nest, ov))

    # "llo", Escape twice
    st = show(ov, 3)
    if check('show 3: a new show starts with an empty query', st and st.get('query') == '', f'{st and st.get("query")!r}'):
        wtype(nest, 'llo')
        ok, s = ov.wait_state(lambda s: s.get('query') == 'llo', timeout=2)
        vis = {name_of.get(a, a) for a in (s or {}).get('visible', [])}
        check('typing "llo" shows yellow only, highlighted', ok and vis == {'yellow'} and s.get('highlighted') == addr['yellow'],
              f'visible {sorted(vis)} highlighted {name_of.get((s or {}).get("highlighted"))}')
        wtype(nest, '-k', 'Escape')
        ok, s = ov.wait_state(lambda s: s.get('query') == '', timeout=2)
        vis = {name_of.get(a, a) for a in (s or {}).get('visible', [])}
        check('Escape with a query clears it: all six visible, still shown, yellow still highlighted',
              ok and s.get('shown') is True and vis == set(SPREAD1) and s.get('highlighted') == addr['yellow'],
              f'shown {(s or {}).get("shown")} visible {sorted(vis)} highlighted {name_of.get((s or {}).get("highlighted"))}')
        wtype(nest, '-k', 'Escape')
        check('Escape with no query closes', closed(nest, ov))
        # the overview gives the focus back once its surfaces are gone: wait for it as for the Return checks
        check('the focus stayed on red',
              nest.wait(lambda: (nest.j('activewindow') or {}).get('address') == addr['red'], timeout=2),
              f'active {(nest.j("activewindow") or {}).get("class")}')

    # no match -> the launcher
    st = show(ov, 4)
    if check('show 4', st):
        wtype(nest, 'xyzq')
        ov.wait_state(lambda s: s.get('query') == 'xyzq', timeout=2)
        wtype(nest, '-k', 'BackSpace')
        ok, s = ov.wait_state(lambda s: s.get('query') == 'xyz', timeout=2)
        check('BackSpace removes the last character ("xyzq" -> "xyz"); nothing visible, no highlight',
              ok and s.get('visible') == [] and s.get('highlighted') == '',
              f'query {(s or {}).get("query")!r} visible {(s or {}).get("visible")} highlighted {(s or {}).get("highlighted")!r}')
        log = ov.work / 'launcher.log'
        wtype(nest, '-k', 'Return')
        check('Return on no match closes the overview', closed(nest, ov))
        got = nest.wait(lambda: log.exists() and log.read_text().splitlines(), timeout=3) or []
        check('Return on no match runs the launcher once: fuzzel --search=xyz', got == ['argc=1', 'arg=--search=xyz'],
              f'{got}')
    return True


# ---- phase 2: show 5, close button, middle click, drag and drop -------------------------------------------------
def drag(nest, ov, ptr, addr, d):
    name = d['name']
    ptr.glide(*d['from'])
    time.sleep(0.15)
    ptr.press('left')
    ptr.cmd('sleep 30')
    arrived = ptr.glide(*d['to'])
    time.sleep(0.15)
    ok, s = ov.wait_state(lambda s: (s.get('drag') or {}).get('address') == addr[name] and
                          all((s['drag'].get('target') or {}).get(k) == v for k, v in d['target'].items()), timeout=1)
    check(f'dragging {name}: the pointer reached {d["to"]} and the drop target is {d["target"]}', arrived and ok,
          f'cursor {ptr.pos()} drag {(s or {}).get("drag")}')
    ptr.release('left')
    landed, c = wait_client(nest, addr[name], lambda c: c is not None and c['workspace'].get('id') == d['ws'])
    check(f'drop: {name} is on workspace {d["ws"]} (not {d["not"][0]} or {d["not"][1]}, hyprctl clients)', landed,
          f'workspace {c and c["workspace"]}')
    check(f'after dropping {name} the overview stays open', (ov.state() or {}).get('shown') is True)
    return c


def relaid(ov, mon, want, addr):
    """Wait for the snapshot's spread on `mon` to hold exactly `want`'s windows, then compare the rects."""
    want_a = {addr[n]: r for n, r in want.items()}
    snap = [None]

    def t():
        snap[0] = ov.snapshot()
        return set(spread_of(snap[0], mon)) == set(want_a)
    ov.nest.wait(t, timeout=3, step=0.1)
    got = spread_of(snap[0], mon)
    ok = set(got) == set(want_a) and all(near(got[a], r, TOL_RECT) for a, r in want_a.items())
    return ok, {a: fmt(r) for a, r in got.items()}


def phase_mouse(nest, ov, run, work, shots, wins, procs):
    addr = {n: c['address'] for n, c in wins.items()}
    name_of = {a: n for n, a in addr.items()}
    print('\n== show 5: close button, middle click, drag to a strip workspace, to the other output, to a new workspace',
          flush=True)
    st = show(ov, 5)
    if not check('show 5', st):
        return
    ptr = Pointer(nest, run, work)
    try:
        # close button
        ptr.hover(*centre(SPREAD1['yellow'][1]))
        ok, s = ov.wait_state(lambda s: s.get('highlighted') == addr['yellow'], timeout=1)
        check('hover highlights yellow', ok, f'{name_of.get((s or {}).get("highlighted"))}')
        ptr.glide(*YELLOW_CLOSE)
        ok, s = ov.wait_state(lambda s: s.get('overClose') == addr['yellow'] and s.get('highlighted') == addr['yellow'], timeout=1)
        check(f'on the close button {YELLOW_CLOSE}: overClose yellow, still highlighted', ok,
              f'cursor {ptr.pos()} overClose {name_of.get((s or {}).get("overClose"))} '
              f'highlighted {name_of.get((s or {}).get("highlighted"))}')
        deadline = time.time() + 2
        while True:
            im = grim(nest, shots, 'RO-A', 's5')
            px = [pixel(im, p) for p in CLOSE_SAMPLES]
            if all(colour_ok(p, ACCENT) for p in px) or time.time() > deadline:
                break
            time.sleep(0.3)
        check(f'the close button is drawn: accent {ACCENT} at {CLOSE_SAMPLES}', all(colour_ok(p, ACCENT) for p in px), f'{px}')
        pn = pixel(im, NO_CLOSE_SAMPLE)
        check(f'no close button on red (not highlighted): {NO_CLOSE_SAMPLE} is not accent', pn is not None and not colour_ok(pn, ACCENT),
              f'{pn}')
        ptr.click('left')
        ok, _ = wait_client(nest, addr['yellow'], lambda c: c is None)
        check('close button click: yellow is gone from hyprctl clients', ok)
        check('close button click: yellow\'s process exited', gone(procs['yellow']))
        check('the overview stays open after a close', (ov.state() or {}).get('shown') is True)
        ok, got = relaid(ov, 'RO-A', AFTER_CLOSE, addr)
        check(f'RO-A re-lays out without yellow: {({n: fmt(r) for n, r in AFTER_CLOSE.items()})}', ok, f'got {got}')

        # middle click
        ptr.glide(*MAGENTA_AT)
        time.sleep(0.15)
        ptr.click('middle')
        ok, _ = wait_client(nest, addr['magenta'], lambda c: c is None)
        check('middle click: magenta is gone from hyprctl clients', ok)
        check('middle click: magenta\'s process exited', gone(procs['magenta']))
        check('the overview stays open after a middle click', (ov.state() or {}).get('shown') is True)
        ok, got = relaid(ov, 'RO-C', {}, addr)
        check('RO-C\'s spread is empty now', ok, f'got {got}')

        # drags
        drag(nest, ov, ptr, addr, DRAG1)
        ok, got = relaid(ov, 'RO-A', AFTER_DRAG1, addr)
        check(f'RO-A re-lays out without red: {({n: fmt(r) for n, r in AFTER_DRAG1.items()})}', ok, f'got {got}')
        c = drag(nest, ov, ptr, addr, DRAG2)
        check('drop on the other output: green is on RO-C', c and mon_ids(nest).get(c['monitor']) == 'RO-C',
              f'monitor {c and mon_ids(nest).get(c["monitor"])}')
        ok, got = relaid(ov, 'RO-A', AFTER_DRAG2, addr)
        check(f'RO-A re-lays out with blue alone: {fmt(AFTER_DRAG2["blue"])}', ok, f'got {got}')
        snap = ov.snapshot()
        check('RO-C\'s spread now holds green', addr['green'] in spread_of(snap, 'RO-C'),
              f'{[name_of.get(a, a) for a in spread_of(snap, "RO-C")]}')
        drag(nest, ov, ptr, addr, DRAG3)
        ws6 = next((w for w in (nest.j('workspaces') or []) if w.get('id') == 6), None)
        check('drop on the empty entry: workspace 6 is on RO-A', ws6 and ws6.get('monitor') == 'RO-A', f'{ws6}')
    finally:
        ptr.close()
    ov.ipc('hide')
    check('hide closes the overview', closed(nest, ov))


# ---- phase 3: animations on ---------------------------------------------------------------------------------------
def phase_anim(nest, run, stage, work):
    print('\n== animations on: the open animation', flush=True)
    nest.ctl('eval', 'hl.config({ animations = { enabled = true } })')
    opt = nest.j('getoption', 'animations:enabled') or {}
    if not check('nest: animations:enabled is on', opt.get('bool') is True or opt.get('int') == 1, f'{opt}'):
        return
    ov = Overlay(nest, run, stage, work, 'anim').start()
    if not check('overlay (animations on) starts', ov.ready(), f'log {ov.log}'):
        return
    st = show(ov, 1)
    anim = (st or {}).get('anim') or {}
    took = (anim.get('doneAt') or 0) - (anim.get('startedAt') or 0)
    tiles = sum(len(s.get('windows', [])) for s in (st or {}).get('surfaces', []))
    check(f'animations on: animationMs {ANIM_MS}', st and st.get('animationMs') == ANIM_MS, f'{st and st.get("animationMs")}')
    check(f'animations on: the open move ran ({ANIM_MIN_FRAMES}+ in-between steps over {tiles} tiles)',
          tiles > 0 and (anim.get('frames') or 0) >= ANIM_MIN_FRAMES, f'anim {anim}')
    check(f'animations on: the open animation completes within {ANIM_MS} ms (+1 frame: {ANIM_LIMIT:.1f} ms)',
          anim.get('startedAt') and anim.get('doneAt') and 0 < took <= ANIM_LIMIT, f'took {took:.1f} ms')
    ov.ipc('toggle')
    check('animations on: toggle closes', closed(nest, ov, timeout=3))
    ov.stop()


def prepare(work):
    xdg = work / 'xdg'
    shutil.rmtree(xdg, ignore_errors=True)
    for d in ('config/riley', 'config/riley-overview', 'cache', 'state'):
        (xdg / d).mkdir(parents=True)
    (xdg / 'config/riley/bar.json').write_text(json.dumps(THEME))
    # a valid config with nothing in it: every default, the launcher "fuzzel"
    (xdg / 'config/riley-overview/config.xml').write_text(
        '<?xml version="1.0"?>\n<overview xmlns="urn:riley-overview:config" version="1"/>\n')
    (work / 'minimized.json').write_text('{}')
    notify = work / 'notify.sh'
    notify.write_text(f'#!/bin/sh\nprintf \'%s\\n\' "$*" >> {work}/notify.log\n')
    notify.chmod(0o755)
    (work / 'notify.log').unlink(missing_ok=True)
    # the fake launcher: records its argument count and each argument, one per line
    (work / 'bin').mkdir(exist_ok=True)
    fake = work / 'bin' / 'fuzzel'
    fake.write_text(f'#!/bin/sh\n# the gate\'s stand-in for fuzzel\n{{ printf \'argc=%s\\n\' "$#"; '
                    f'for a in "$@"; do printf \'arg=%s\\n\' "$a"; done; }} >> {work}/launcher.log\n')
    fake.chmod(0o755)
    (work / 'launcher.log').unlink(missing_ok=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--stage', required=True, type=Path)
    ap.add_argument('--work', required=True, type=Path)
    ap.add_argument('--shots', required=True, type=Path)
    ap.add_argument('--vpointer', required=True, type=Path)
    a = ap.parse_args()
    global VPOINTER
    VPOINTER = a.vpointer.resolve()
    work, shots = a.work.resolve(), a.shots.resolve()
    work.mkdir(parents=True, exist_ok=True)
    shots.mkdir(parents=True, exist_ok=True)
    prepare(work)
    xsd = a.stage / 'share/riley-overview/config.xsd'
    r = subprocess.run(['xmllint', '--noout', '--schema', str(xsd), str(work / 'xdg/config/riley-overview/config.xml')],
                       capture_output=True, text=True)
    check('the gate\'s config validates against config.xsd', r.returncode == 0, r.stderr.strip()[:200])
    nest = Nest(HYPRLAND, nest_config(work), work / 'nest.log')
    run = Run()
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(130))
    try:
        nest.start()
        for name in MONS:
            nest.ctl('output', 'create', 'headless', name)
        want = {n: (m['w'], m['h'], m['scale'], m['x'], m['y'], m['transform']) for n, m in MONS.items()}
        ok = nest.wait(lambda: {m['name']: (m['width'], m['height'], m['scale'], m['x'], m['y'], m['transform'])
                                for m in nest.monitors()} == want, timeout=5)
        if check(f'setup nest outputs {want}', ok,
                 f'{[(m["name"], m["width"], m["height"], m["scale"], m["x"], m["y"], m["transform"]) for m in nest.monitors()]}'):
            wins, procs = start_windows(nest, run, work, list(WINDOWS))
            if setup_ok(nest, wins):
                ov = Overlay(nest, run, a.stage, work, 'main').start()
                if check('starts and answers IPC (state ready)', ov.ready(), f'log {ov.log}'):
                    s = ov.state() or {}
                    check('state() has the M3 fields', all(k in s for k in ('highlighted', 'query', 'visible', 'overClose', 'drag')),
                          f'{sorted(s)}')
                    check('snapshot() answers while hidden', isinstance(ov.snapshot(), dict))
                    if phase_keys(nest, ov, wins, shots):
                        phase_mouse(nest, ov, run, work, shots, wins, procs)
                    notes = (work / 'notify.log').read_text().splitlines() if (work / 'notify.log').exists() else []
                    check('valid config: no notification', not notes, f'{notes}')
                ov.stop()
                phase_anim(nest, run, a.stage, work)
            else:
                check('set up', False, 'the nest did not place the test windows as planned; nothing else checked')
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
