# SPDX-License-Identifier: GPL-3.0-or-later
"""A nested Hyprland for live tests: one window on an empty DP-2 workspace of Marc's session, its own config.

Copied from Riley's tests/popups/nested.py (not imported across repos) and extended with the nest's Wayland socket
and an environment for clients that must run inside it.

Nothing in it reaches Marc's session: it starts with no systemd or D-Bus environment update (HYPRLAND_NO_SD_VARS,
HYPRLAND_NO_SD_TARGET), without Xwayland. The parent is asked for one thing only: to start the nest silently on the
workspace (DP-2 is not switched, focus stays where it is). Everything is ended by process ID.
"""
import json, os, signal, subprocess, time
from pathlib import Path

RUNTIME = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'))
HYPR_RUNTIME = RUNTIME / 'hypr'
WORKSPACE = 77          # an empty workspace, opened on DP-2 only for the test (Riley's gates use it too)


def parent(*args):
    return subprocess.run(['hyprctl', *args], capture_output=True, text=True, timeout=10).stdout


def lua_str(s):
    return '[==[' + s + ']==]'


class Nest:
    def __init__(self, hyprland, config, log, env=None):
        self.hyprland, self.config, self.log = str(hyprland), str(config), Path(log)
        self.env = ' '.join(f'{k}={v}' for k, v in (env or {}).items())
        self.pid = self.sig = self.socket = None

    def start(self, timeout=20):
        # The workspace may exist (left active on DP-2 by an earlier test) but must hold no window.
        if any(w['id'] == WORKSPACE and w.get('windows', 0) for w in json.loads(parent('workspaces', '-j'))):
            raise RuntimeError(f'workspace {WORKSPACE} is in use in the session')
        before = {p.name for p in HYPR_RUNTIME.iterdir()} if HYPR_RUNTIME.exists() else set()
        cmd = (f'env -u HYPRLAND_INSTANCE_SIGNATURE HYPRLAND_NO_SD_VARS=1 HYPRLAND_NO_SD_TARGET=1 {self.env} '
               f'{self.hyprland} --config {self.config} >{self.log} 2>&1')
        parent('dispatch', f'hl.dsp.exec_cmd({lua_str(cmd)}, {{ monitor = "DP-2", workspace = "{WORKSPACE} silent" }})')
        end = time.time() + timeout
        while time.time() < end:
            for d in HYPR_RUNTIME.iterdir():
                lock = d / 'hyprland.lock'
                if d.name in before or not lock.exists() or not (d / '.socket.sock').exists():
                    continue
                try:
                    fields = lock.read_text().split()
                    pid = int(fields[0])
                except (OSError, ValueError, IndexError):
                    continue
                if os.path.realpath(f'/proc/{pid}/exe') == os.path.realpath(self.hyprland):
                    self.pid, self.sig = pid, d.name
                    # hyprland.lock: pid on the first line, the Wayland socket name on the second
                    if len(fields) > 1:
                        self.socket = fields[1]
            if self.sig and self.ctl('monitors', '-j').strip().startswith('['):
                if not self.socket:
                    for i in json.loads(parent('instances', '-j') or '[]'):
                        if i.get('instance') == self.sig:
                            self.socket = i.get('wl_socket')
                if self.socket:
                    return self
            time.sleep(0.2)
        raise RuntimeError(f'the nested Hyprland did not start; log {self.log}')

    def client_env(self, extra=None):
        """Environment for a program that must run inside the nest and nowhere else."""
        env = {k: v for k, v in os.environ.items() if k not in ('DISPLAY', 'WAYLAND_SOCKET')}
        env['WAYLAND_DISPLAY'] = self.socket
        env['HYPRLAND_INSTANCE_SIGNATURE'] = self.sig
        env['QT_QPA_PLATFORM'] = 'wayland'
        env.update(extra or {})
        return env

    def ctl(self, *args):
        return subprocess.run(['hyprctl', '-i', self.sig, *args], capture_output=True, text=True, timeout=10).stdout

    def j(self, *args):
        try:
            return json.loads(self.ctl(*args, '-j'))
        except ValueError:
            return None

    def dispatch(self, lua):
        return self.ctl('dispatch', lua)

    def clients(self):
        return self.j('clients') or []

    def monitors(self):
        return self.j('monitors') or []

    def wait(self, test, timeout=30, step=0.1):
        end = time.time() + timeout
        while time.time() < end:
            got = test()
            if got:
                return got
            time.sleep(step)
        return None

    def stop(self):
        if not self.pid:
            return
        try:
            os.kill(self.pid, signal.SIGTERM)
        except ProcessLookupError:
            return
        for _ in range(50):
            if not Path(f'/proc/{self.pid}').exists():
                return
            time.sleep(0.1)
        try:
            os.kill(self.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def end_pids(pids, wait=5):
    """SIGTERM each saved process ID, then SIGKILL what is left after WAIT seconds."""
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    end = time.time() + wait
    while time.time() < end and any(Path(f'/proc/{p}').exists() for p in pids):
        time.sleep(0.1)
    for pid in pids:
        if Path(f'/proc/{pid}').exists():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
