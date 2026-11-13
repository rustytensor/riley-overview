# riley-overview

A GNOME-style Activities overview for the Riley desktop on Hyprland. One overlay per screen spreads that screen's
windows out as live previews, with a workspace strip at the top, search, and drag and drop between workspaces and
screens. It is shown on demand and changes no layout: close it and tiling (or floating) is exactly as it was.
Qt Quick, as a Quickshell config; no Hyprland plugin.

## What it shows

On every screen, for that screen's current workspace:

- the wallpaper, blurred and dimmed;
- the windows spread so none overlap, scaled down with their aspect ratio kept, placed near where they really are,
  each with its live image, app icon and title; minimized windows (hypr-minimize) in a row of their own;
- at the top, the screen's workspaces as small previews, the current one marked, and an empty one at the end;
- a search field.

Opening animates every window from its real place to its spread place, closing animates back (200 ms at most; off
when Riley's animations setting is off). Special workspaces are left out.

## Usage

The key is a Hyprland bind on the global shortcut `riley-overview:toggle` (no process starts on a key press). Super
pressed alone, in Hyprland's Lua config:

```
hl.bind("SUPER + SUPER_L", hl.dsp.global("riley-overview:toggle"), { release = true })
```

For scripts and a bar button:

```
riley-overview toggle      # show it, or hide it when shown
riley-overview show | hide
riley-overview run         # the resident instance; the user unit runs this
riley-overview --help
```

### Mouse

- Hover a window: it is highlighted and gets a close button on its top-right corner.
- Click a window: focus it and close the overview. Click empty space: close.
- Click a workspace in the strip: switch to it.
- Drag a window onto a workspace in the strip, the empty one at the end, or another screen's overview: it moves
  there (without following it).
- Close button or middle click: close that window.

### Keys

- Arrow keys move the highlight; Enter focuses the highlighted window and closes the overview.
- Typing searches the windows by title and class (every word must match); Backspace edits.
- Enter with no match closes the overview and hands the text to the launcher (fuzzel by default).
- Escape clears the search, else closes. The toggle key closes too.

## Config

Optional, `~/.config/riley-overview/config.xml`, checked against `config.xsd` on every read; a broken file means the
defaults plus a notification. Start from `~/.local/share/riley-overview/config.example.xml`. Colours and font follow
Riley's bar theme (`~/.config/riley/bar.json`). Every element, default and meaning: `docs/files.md`.

## Install

Needs Quickshell 0.2 (Qt 6), Hyprland 0.57, `xmllint`, and `notify-send` for the config warning. Nothing to build.

```
./install.sh                       # to ~/.local, the unit to ~/.config/systemd/user
systemctl --user daemon-reload
systemctl --user enable --now riley-overview.service
```

`./install.sh --prefix DIR --unit-dir DIR` installs elsewhere; `./install.sh --uninstall` removes the files again.

## Build and test

Each milestone has one gate that says GATE PASS or GATE FAIL, with expected values worked out by hand:

| Gate | What |
| --- | --- |
| `tests/run-layout.sh` | Layout, strip and hit-testing, config parsing and the schema (offscreen, Qt Quick Test). |
| `tests/run-overlay.sh` | The overlay, live in a nested Hyprland: surfaces, pixels, click, Escape, first frame. |
| `tests/run-interact.sh` | Drag and drop, close, keys, search, launcher, animation (offscreen and nested). |
| `tests/run-install.sh` | The install, the unit, the launcher, then the three gates above on the installed copy. |

`--plant` on any of them applies that milestone's fault from `tests/faults/` to a copy and expects GATE FAIL. The live
parts run in a nested Hyprland in a window and need `dp2-lock`; they never touch the running session. Design notes and
interfaces: `docs/`.

## Licence

GPL-3.0-or-later. See `LICENSE`.
