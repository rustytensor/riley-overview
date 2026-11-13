#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# install.sh [--prefix DIR] [--unit-dir DIR] [--uninstall]
#   Installs riley-overview from this tree (nothing to build):
#     DIR/bin/riley-overview
#     DIR/share/riley-overview/shell/          the Quickshell config (replaced as a whole on every install)
#     DIR/share/riley-overview/config.xsd      the config schema
#     DIR/share/riley-overview/config.example.xml
#     UNITDIR/riley-overview.service           the systemd user unit, ExecStart pointing at DIR/bin
#   --prefix defaults to ~/.local, --unit-dir to ${XDG_CONFIG_HOME:-~/.config}/systemd/user.
#   --uninstall removes exactly those files.
#   It never runs systemctl and never writes ~/.config/riley-overview/config.xml; the next steps are printed.
set -eu
src=$(cd "$(dirname "$0")" && pwd -P)
prefix=$HOME/.local
unitdir=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
mode=install
while [ $# -gt 0 ]; do
    case $1 in
        --prefix) prefix=$2; shift 2 ;;
        --unit-dir) unitdir=$2; shift 2 ;;
        --uninstall) mode=uninstall; shift ;;
        -h|--help) sed -n '4,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "install.sh: unknown option $1" >&2; exit 2 ;;
    esac
done
mkdir -p "$prefix"
prefix=$(cd "$prefix" && pwd -P)
share=$prefix/share/riley-overview
unit=$unitdir/riley-overview.service

if [ "$mode" = uninstall ]; then
    rm -f "$prefix/bin/riley-overview" "$unit"
    rm -rf "$share"
    echo "removed $prefix/bin/riley-overview, $share and $unit"
    echo "if the unit was enabled: systemctl --user disable --now riley-overview.service; systemctl --user daemon-reload"
    exit 0
fi

mkdir -p "$prefix/bin" "$share" "$unitdir"
# the shell is copied to a new directory first and swapped in, so a removed file does not linger
rm -rf "$share/shell.new"
cp -R "$src/shell" "$share/shell.new"
rm -rf "$share/shell"
mv "$share/shell.new" "$share/shell"
install -m 0644 "$src/data/config.xsd" "$share/config.xsd"
install -m 0644 "$src/data/config.example.xml" "$share/config.example.xml"
install -m 0755 "$src/bin/riley-overview" "$prefix/bin/riley-overview"
sed "s#@BINDIR@#$prefix/bin#g" "$src/data/riley-overview.service.in" > "$unit.new"
chmod 0644 "$unit.new"
mv "$unit.new" "$unit"
echo "installed $prefix/bin/riley-overview, $share and $unit"
echo "start it with the session: systemctl --user daemon-reload; systemctl --user enable --now riley-overview.service"
echo "show it: riley-overview toggle"
