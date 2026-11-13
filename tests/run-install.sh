#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# M4 gate: the installed build. Three parts, one verdict:
#   1 scratch install ($BUILD/scratch, always): install.sh into a throwaway prefix and unit directory, the installed
#     files against the tree, a reinstall over a stale file, then install.sh --uninstall removes exactly what it
#     installed (a neighbour file in bin/ stays);
#   2 the target install: install.sh into $PREFIX (default ~/.local) with the unit in $UNIT_DIR (default
#     ~/.config/systemd/user); the files against the tree; the unit's lines and `systemd-analyze --user verify`;
#     the example config valid and a broken one invalid against the installed XSD (xmllint); the installed launcher's
#     --help and an unknown command;
#   3 only when parts 1 and 2 passed: tests/run-layout.sh, run-overlay.sh and run-interact.sh once each with
#     RILEYOVERVIEW_PREFIX=$PREFIX (their live parts in the nested Hyprland under dp2-lock, as always), each must end
#     GATE PASS with the check count of its last real run.
#
#   tests/run-install.sh           run the gate; prints PASS/FAIL per check, then GATE PASS or GATE FAIL
#   tests/run-install.sh --plant   copy the tree to $FORGE/plant-m4, apply tests/faults/m4-*.patch, run the gate there
#                                  with a throwaway prefix ($FORGE/plant-m4/prefix) and expect it to fail
#
# Environment:
#   RILEYOVERVIEW_INSTALL_PREFIX  where part 2 installs (default ~/.local)
#   RILEYOVERVIEW_UNIT_DIR        where part 2 puts the unit (default ${XDG_CONFIG_HOME:-~/.config}/systemd/user)
#   RILEYOVERVIEW_BUILD_DIR       scratch prefix and logs (default /srv/devops/forge/build/riley-overview/gate-m4)
#
# The gate never runs systemctl and never starts the overview outside the nest. Exit 0 only on GATE PASS (or, with
# --plant, on PLANTED FAULT CAUGHT).
#
# Expected values, worked out before the run:
#   - installed files: bin/riley-overview (mode 755), share/riley-overview/shell/ identical to shell/ (diff -r, no
#     extra or missing file), share/riley-overview/config.xsd and config.example.xml identical to data/, and
#     $UNIT_DIR/riley-overview.service; nothing else under share/riley-overview;
#   - the unit holds the lines `ExecStart=<prefix>/bin/riley-overview run` (prefix made absolute with pwd -P),
#     `Restart=on-failure`, `PartOf=graphical-session.target`, `After=graphical-session.target`,
#     `WantedBy=graphical-session.target`; systemd-analyze --user verify exits 0 and prints no line about it
#     (verify also checks that ExecStart's program exists and is executable: seen on systemd 262 with a missing path,
#     "Command ... is not executable: No such file or directory", exit 1);
#   - xmllint --noout --schema: exit 0 for config.example.xml, exit 3 (xmllint(1): "validation error") for
#     tests/layout/data/bad-element.xml;
#   - `riley-overview --help`: exit 0, nothing on stderr, first line `usage: riley-overview [run|toggle|show|hide]`,
#     last line `shell: <prefix>/share/riley-overview/shell` (the directory `run` gives Quickshell);
#     `riley-overview frobnicate`: exit 2, nothing on stdout, the usage line first on stderr;
#   - sub-gates: GATE PASS, the log says `testing installed copy <prefix>`, and the counts of their last real runs
#     (reports 1 to 3): M1 274 passed, M2 101, M3 174, 0 failed. M2 was 99; its one timing check of the
#     `riley-overview toggle` command became three key-path checks (lead's decision on R1: time, shows through the
#     global shortcut, the key closes it), so 99 - 1 + 3 = 101.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(dirname "$HERE")
FORGE=/srv/devops/forge/build/riley-overview

if [ "${1:-}" = "--plant" ]; then
    shopt -s nullglob
    patches=("$TREE"/tests/faults/m4-*.patch)
    if [ ${#patches[@]} -eq 0 ]; then
        echo "no fault patch (tests/faults/m4-*.patch)"
        exit 2
    fi
    PLANT=$FORGE/plant-m4
    rm -rf "$PLANT"
    mkdir -p "$PLANT/tree"
    tar -C "$TREE" --exclude=.git --exclude=build -cf - . | tar -C "$PLANT/tree" -xf -
    for p in "${patches[@]}"; do
        if ! patch -d "$PLANT/tree" -p1 --forward --batch --silent < "$p"; then
            echo "FAIL fault patch $(basename "$p") does not apply"
            rm -rf "$PLANT/tree"
            exit 1
        fi
        echo "applied $(basename "$p")"
    done
    RILEYOVERVIEW_BUILD_DIR=$PLANT/build RILEYOVERVIEW_INSTALL_PREFIX=$PLANT/prefix \
        RILEYOVERVIEW_UNIT_DIR=$PLANT/prefix/systemd-user \
        bash "$PLANT/tree/tests/run-install.sh" > "$PLANT/gate.log" 2>&1
    rc=$?
    grep -E '^FAIL' "$PLANT/gate.log" | head -n 20
    tail -n 1 "$PLANT/gate.log"
    rm -rf "$PLANT/tree" "$PLANT/build" "$PLANT/prefix"
    if [ $rc -ne 0 ]; then
        echo "PLANTED FAULT CAUGHT (log: $PLANT/gate.log)"
        exit 0
    fi
    echo "PLANTED FAULT MISSED: the gate passed with the fault in place (log: $PLANT/gate.log)"
    exit 1
fi

BUILD=${RILEYOVERVIEW_BUILD_DIR:-$FORGE/gate-m4}
PREFIX=${RILEYOVERVIEW_INSTALL_PREFIX:-$HOME/.local}
UNIT_DIR=${RILEYOVERVIEW_UNIT_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user}
LOGS=$BUILD/logs
SCRATCH=$BUILD/scratch
child=""
cleanup() {
    if [ -n "$child" ] && kill -0 "$child" 2>/dev/null; then
        kill "$child" 2>/dev/null
        wait "$child" 2>/dev/null
    fi
    rm -rf "$SCRATCH"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

pass=0
fail=0
ok() { echo "PASS $*"; pass=$((pass + 1)); }
bad() { echo "FAIL $*"; fail=$((fail + 1)); }
check() { local name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }

for tool in xmllint systemd-analyze diff patch; do
    command -v "$tool" >/dev/null || { echo "FAIL missing tool $tool"; echo "GATE FAIL"; exit 1; }
done
if [ ! -x "$TREE/install.sh" ]; then
    echo "FAIL install.sh missing or not executable in $TREE"
    echo "GATE FAIL"
    exit 1
fi

rm -rf "$LOGS" "$SCRATCH"
mkdir -p "$LOGS" "$SCRATCH"

# files_match PREFIX UNITDIR LABEL: the installed files against the tree
files_match() {
    local p=$1 u=$2 l=$3 share=$1/share/riley-overview
    check "$l: bin/riley-overview is installed with mode 755" \
        test "$(stat -c %a "$p/bin/riley-overview" 2>/dev/null)" = 755
    check "$l: bin/riley-overview equals the tree's" cmp -s "$TREE/bin/riley-overview" "$p/bin/riley-overview"
    check "$l: share/riley-overview/shell equals shell/ (diff -r)" diff -r -q "$TREE/shell" "$share/shell"
    check "$l: config.xsd equals data/config.xsd" cmp -s "$TREE/data/config.xsd" "$share/config.xsd"
    check "$l: config.example.xml equals data/config.example.xml" \
        cmp -s "$TREE/data/config.example.xml" "$share/config.example.xml"
    check "$l: share/riley-overview holds shell, config.xsd, config.example.xml and nothing else" \
        test "$(ls -A "$share" 2>/dev/null | sort | tr '\n' ' ')" = "config.example.xml config.xsd shell "
    check "$l: the unit is installed in $u" test -f "$u/riley-overview.service"
}

# Part 1: scratch install, reinstall over a stale file, uninstall.
sp=$SCRATCH/prefix
su=$SCRATCH/systemd-user
mkdir -p "$sp/bin"
echo keep > "$sp/bin/other-tool"
"$TREE/install.sh" --prefix "$sp" --unit-dir "$su" > "$LOGS/scratch-install.txt" 2>&1
check "scratch: install.sh exits 0" test $? -eq 0
files_match "$sp" "$su" scratch
echo stale > "$sp/share/riley-overview/shell/stale.qml"
"$TREE/install.sh" --prefix "$sp" --unit-dir "$su" > "$LOGS/scratch-reinstall.txt" 2>&1
check "scratch: reinstall exits 0" test $? -eq 0
check "scratch: reinstall removes a file the tree no longer has" test ! -e "$sp/share/riley-overview/shell/stale.qml"
"$TREE/install.sh" --prefix "$sp" --unit-dir "$su" --uninstall > "$LOGS/scratch-uninstall.txt" 2>&1
check "scratch: install.sh --uninstall exits 0" test $? -eq 0
check "scratch: uninstall removes bin/riley-overview" test ! -e "$sp/bin/riley-overview"
check "scratch: uninstall removes share/riley-overview" test ! -e "$sp/share/riley-overview"
check "scratch: uninstall removes the unit" test ! -e "$su/riley-overview.service"
check "scratch: uninstall leaves the neighbour bin/other-tool" test "$(cat "$sp/bin/other-tool" 2>/dev/null)" = keep

# Part 2: the target install.
mkdir -p "$PREFIX"
PREFIX=$(cd "$PREFIX" && pwd -P)
echo "installing into $PREFIX (unit: $UNIT_DIR)"
"$TREE/install.sh" --prefix "$PREFIX" --unit-dir "$UNIT_DIR" > "$LOGS/install.txt" 2>&1
check "target: install.sh exits 0" test $? -eq 0
files_match "$PREFIX" "$UNIT_DIR" target

unit=$UNIT_DIR/riley-overview.service
for line in "ExecStart=$PREFIX/bin/riley-overview run" "Restart=on-failure" "PartOf=graphical-session.target" \
            "After=graphical-session.target" "WantedBy=graphical-session.target"; do
    check "unit: has the line '$line'" grep -qxF -- "$line" "$unit"
done
systemd-analyze --user verify "$unit" > "$LOGS/verify.txt" 2>&1
vrc=$?
check "unit: systemd-analyze --user verify exits 0" test $vrc -eq 0
about=$(grep -E "^(riley-overview\.service|$unit)" "$LOGS/verify.txt")
check "unit: systemd-analyze prints nothing about it${about:+ (got: $about)}" test -z "$about"

xsd=$PREFIX/share/riley-overview/config.xsd
xmllint --noout --schema "$xsd" "$PREFIX/share/riley-overview/config.example.xml" > "$LOGS/xmllint-example.txt" 2>&1
check "xsd: the installed example config validates against the installed XSD (exit 0)" test $? -eq 0
xmllint --noout --schema "$xsd" "$TREE/tests/layout/data/bad-element.xml" > "$LOGS/xmllint-bad.txt" 2>&1
xrc=$?
check "xsd: bad-element.xml is rejected by the installed XSD (exit 3, got $xrc)" test $xrc -eq 3

bin=$PREFIX/bin/riley-overview
"$bin" --help > "$LOGS/help.out" 2> "$LOGS/help.err"
hrc=$?
check "launcher: --help exits 0 (got $hrc)" test $hrc -eq 0
check "launcher: --help writes nothing to stderr" test ! -s "$LOGS/help.err"
check "launcher: --help first line is the usage line" \
    test "$(head -n 1 "$LOGS/help.out")" = "usage: riley-overview [run|toggle|show|hide]"
check "launcher: --help last line names the installed shell" \
    test "$(tail -n 1 "$LOGS/help.out")" = "shell: $PREFIX/share/riley-overview/shell"
"$bin" frobnicate > "$LOGS/unknown.out" 2> "$LOGS/unknown.err"
urc=$?
check "launcher: an unknown command exits 2 (got $urc)" test $urc -eq 2
check "launcher: an unknown command writes nothing to stdout" test ! -s "$LOGS/unknown.out"
check "launcher: an unknown command puts the usage line first on stderr" \
    test "$(head -n 1 "$LOGS/unknown.err")" = "usage: riley-overview [run|toggle|show|hide]"

# Part 3: M1 to M3 once each on the installed copy.
if [ $fail -ne 0 ]; then
    bad "M1 to M3 not run: the install checks above failed"
else
    for g in "layout 274" "overlay 101" "interact 174"; do
        set -- $g
        name=$1 want=$2
        log=$LOGS/run-$name.txt
        echo "running tests/run-$name.sh on $PREFIX"
        RILEYOVERVIEW_PREFIX=$PREFIX bash "$TREE/tests/run-$name.sh" > "$log" 2>&1 &
        child=$!
        wait "$child"
        rc=$?
        child=""
        grep -E '^FAIL' "$log" | head -n 10 | sed 's/^/    /'
        check "run-$name.sh: tested the installed copy" grep -q "^testing installed copy $PREFIX" "$log"
        check "run-$name.sh: GATE PASS (exit $rc)" test $rc -eq 0 -a "$(tail -n 1 "$log")" = "GATE PASS"
        got=$(grep -E '^checks: ' "$log" | tail -n 1 | sed -E 's/^checks: ([0-9]+ passed, [0-9]+ failed).*/\1/')
        check "run-$name.sh: $want passed, 0 failed (got: ${got:-none})" test "$got" = "$want passed, 0 failed"
    done
fi

echo "checks: $pass passed, $fail failed (logs: $LOGS)"
if [ $fail -eq 0 ] && [ $pass -gt 0 ]; then
    echo "GATE PASS"
    exit 0
fi
echo "GATE FAIL"
exit 1
