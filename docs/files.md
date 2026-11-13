# Files, settings and commands

## Installed files

`./install.sh` (default prefix `~/.local`; `--prefix DIR`, `--unit-dir DIR`, `--uninstall`):

| Path | What |
| --- | --- |
| `~/.local/bin/riley-overview` | The command (below). |
| `~/.local/share/riley-overview/shell/` | The Quickshell config: QML and the plain JS modules in `lib/`. Replaced as a whole on every install. |
| `~/.local/share/riley-overview/config.xsd` | The config schema. |
| `~/.local/share/riley-overview/config.example.xml` | Every element with its default; copy it to start a config. |
| `~/.config/systemd/user/riley-overview.service` | The user unit (below). |

The installer never runs `systemctl` and never writes a config file.

## The command

| Command | What | Exit |
| --- | --- | --- |
| `riley-overview` or `riley-overview run` | Start the resident overview, hidden. Does nothing when an overview with the same config already runs. | Quickshell's |
| `riley-overview toggle` | Show the overview, or hide it when it is shown. | Quickshell's (`qs ipc call`) |
| `riley-overview show` / `hide` | Show / hide. | as `toggle` |
| `riley-overview --help` | The usage, then `shell: DIR`, the config directory `run` uses. | 0 |
| anything else | The usage on stderr. | 2 |

## The key: a Hyprland global shortcut

The resident overview registers the global shortcut `riley-overview:toggle` (Quickshell's `GlobalShortcut`, appid
`riley-overview`, name `toggle`). A Hyprland bind on the `global` dispatcher reaches it over the connection the
overview already holds, so a key press starts no process (the M2 gate times it: first frame within 100 ms of the
press). Super pressed alone, as in GNOME, in Hyprland 0.57's Lua config:

```
hl.bind("SUPER + SUPER_L", hl.dsp.global("riley-overview:toggle"), { release = true, description = "Activities overview" })
```

`release = true` fires when Super goes up and only when no other key was pressed while it was held (Super+A does not
open it; seen in the M2 gate's nest). A bind on press works too; either way one key press toggles once. Hyprland
allows one registration of `riley-overview:toggle` per session: a second overview started with another config
directory is refused by the compositor and exits, so run one (the unit).

`toggle`, `show` and `hide` are for scripts and the bar's button: they are Quickshell IPC calls (`qs -p DIR ipc call overview toggle`) to the instance running
that config directory. The directory is `$RILEYOVERVIEW_SHELL`, else `../share/riley-overview/shell` next to the
command, else the source tree's `shell/`, always made absolute.

## The user unit

`riley-overview.service`: `PartOf` and `After` `graphical-session.target`, `WantedBy=graphical-session.target`,
`ExecStart=<prefix>/bin/riley-overview run`, `Restart=on-failure` after 2 s. Riley's Hyprland session brings up
`graphical-session.target` (through `hyprland-session.target`), so the overview starts with the session, hidden,
and stops with it. Enable it once:

```
systemctl --user daemon-reload
systemctl --user enable --now riley-overview.service
```

Hidden means no surface at all: no `riley-overview` layer in `hyprctl layers`, no keyboard grab.

## Config: `~/.config/riley-overview/config.xml`

(`$XDG_CONFIG_HOME/riley-overview/config.xml` when that is set.) Optional: no file means every default. The file is
watched; an edit applies at once. On every read it is checked with `xmllint` against the installed `config.xsd`
(then by `lib/config.mjs`, which applies the same rules). A file that does not validate is not used at all: every
value takes its default and one notification (`notify-send`) says why.

Root element `<overview xmlns="urn:riley-overview:config" version="1">`; `version` is required and is `1`. Every
child is optional, at most once, in any order. Sizes are logical pixels of the monitor (device pixels divided by its
scale).

| Element | Default | Allowed | Meaning |
| --- | --- | --- | --- |
| `margin` | 24 | 0 to 400 | Space between the monitor's edges and the overview's content. |
| `strip-height` | 120 | 40 to 400 | Height of the workspace strip at the top (and of the minimized row). |
| `strip-spacing` | 16 | 0 to 200 | Gap between the workspace previews in the strip. |
| `search-height` | 40 | 20 to 200 | Height of the search field. |
| `section-gap` | 16 | 0 to 200 | Gap between the strip, the search field, the windows and the minimized row. |
| `window-spacing` | 24 | 0 to 200 | Least gap between two spread windows. |
| `max-scale` | 1 | above 0, at most 1 | Largest scale a spread window gets (windows are never enlarged). |
| `animation-ms` | 200 | 0 to 200 | Open and close animation length; 0 turns it off. |
| `launcher` | `fuzzel` | one line, not only spaces | The command that gets the search text when Enter finds no window. Split on spaces (no shell). Every `{query}` in it is replaced by the text; without `{query}`, `--search=TEXT` is appended. |

Whole numbers are digits only (`24`, not `+24` or `24.0`).

## Theme

Colours (`base`, `surface0`, `surface1`, `text`, `subtext`, `accent`) and `font` come from
`~/.config/riley/bar.json`, the file Riley's bar reads and `hypr-theme` writes; a theme switch recolours at once. A
missing file or key keeps the bar's own defaults. The backdrop is Riley's wallpaper for that monitor from
`~/.config/hypr/hyprpaper.conf`, blurred and dimmed; without one, `base` dimmed.

## Riley's animations setting

Riley Settings' animations switch writes Hyprland's `animations:enabled`. When it is off, the overview opens and
closes without animation, whatever `animation-ms` says. It is read on every show.

## Other inputs

| Input | Use |
| --- | --- |
| `$XDG_RUNTIME_DIR/riley/minimized.json` | hypr-minimize's records: which monitor a minimized window belongs to (its row). |
| `hyprctl -j monitors / workspaces / clients`, Hyprland's events | The windows and workspaces shown. |

## IPC calls (target `overview`)

| Call | What |
| --- | --- |
| `toggle`, `show`, `hide` | As the commands above. |
| `state`, `snapshot`, `click X Y` | Test only: answer `disabled` unless `RILEYOVERVIEW_TEST_DIR` is set (`docs/overlay.md`, `docs/interact.md`). |

## Environment (tests and overrides)

| Variable | Default | Use |
| --- | --- | --- |
| `RILEYOVERVIEW_SHELL` | see above | The Quickshell config directory the command uses. |
| `RILEYOVERVIEW_XSD` | `<shell>/../config.xsd`, else `<shell>/../data/config.xsd` | The schema. |
| `RILEYOVERVIEW_NOTIFY` | `notify-send` | Called as `CMD SUMMARY BODY` for a broken config. |
| `RILEYOVERVIEW_MINIMIZED_FILE` | `$XDG_RUNTIME_DIR/riley/minimized.json` | hypr-minimize's records. |
| `RILEYOVERVIEW_TEST_DIR` | unset | Test hooks on: the test-only IPC calls and the state files written there on every show. Never set in normal use. |

The gates' own variables (`RILEYOVERVIEW_PREFIX`, `RILEYOVERVIEW_BUILD_DIR`, `RILEYOVERVIEW_INSTALL_PREFIX`,
`RILEYOVERVIEW_UNIT_DIR`, `RILEYOVERVIEW_HYPRLAND`, `RILEYOVERVIEW_QML`) are described at the top of each
`tests/run-*.sh`.
