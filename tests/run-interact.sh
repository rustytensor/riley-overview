#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# M3 gate: interaction. Two parts, one verdict (interfaces: docs/interact.md):
#   1 offscreen: the pure modules shell/lib/navigate.mjs, search.mjs, drop.mjs and hittest.mjs's close button under
#     Qt Quick Test against hand-worked cases (tests/interact/unit/tst_*.qml): arrow order on M1's 5- and 12-window
#     spreads, search on 8 windows, drop targets on M1's strips, the drag threshold, the close button's hit area;
#   2 live: tests/interact/gate.py in a nested Hyprland in a window on an empty DP-2 workspace, under dp2-lock (held
#     for the live part only, never while staging), three outputs (one at scale 1.25, one rotated): the rotated
#     surface and its pixels, arrow keys and Return, search (visible set, hidden tiles not drawn, Escape, BackSpace),
#     Return on no match runs the launcher (a fake fuzzel on PATH), the close button (hover, pixels, click), middle
#     click, three real drags (strip workspace, the other output, the empty new workspace) with hyprctl showing the
#     result and the overview re-laid out, and the open animation with animations on (200-250 ms, eased out) and off (none).
#
#   tests/run-interact.sh           run the gate; prints PASS/FAIL per check, then GATE PASS or GATE FAIL
#   tests/run-interact.sh --plant   copy the tree to $FORGE/plant-m3, apply tests/faults/m3-*.patch, run the gate
#                                   there and expect it to fail (PLANTED FAULT CAUGHT)
#
# Environment:
#   RILEYOVERVIEW_BUILD_DIR  staging, logs, screenshots (default /srv/devops/forge/build/riley-overview/gate-m3)
#   RILEYOVERVIEW_PREFIX     an installed copy to test instead of the tree: $PREFIX/bin/riley-overview and
#                            $PREFIX/share/riley-overview/{shell/, config.xsd}
#   RILEYOVERVIEW_HYPRLAND   the Hyprland binary for the nest (default /usr/bin/Hyprland)
#
# The overlay runs from a staged copy ($BUILD/stage), so its Quickshell path never matches a resident overview in
# Marc's session, and every IPC call the gate makes names the staged instance by process ID. Screenshots are
# deleted on every exit. Exit 0 only on GATE PASS (or, with --plant, on PLANTED FAULT CAUGHT).
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(dirname "$HERE")
FORGE=/srv/devops/forge/build/riley-overview

if [ "${1:-}" = "--plant" ]; then
    shopt -s nullglob
    patches=("$TREE"/tests/faults/m3-*.patch)
    if [ ${#patches[@]} -eq 0 ]; then
        echo "no fault patch (tests/faults/m3-*.patch)"
        exit 2
    fi
    PLANT=$FORGE/plant-m3
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
    RILEYOVERVIEW_BUILD_DIR=$PLANT/build RILEYOVERVIEW_PREFIX='' \
        bash "$PLANT/tree/tests/run-interact.sh" > "$PLANT/gate.log" 2>&1
    rc=$?
    grep -E '^FAIL' "$PLANT/gate.log" | head -n 20
    tail -n 1 "$PLANT/gate.log"
    rm -rf "$PLANT/tree" "$PLANT/build"
    if [ $rc -ne 0 ]; then
        echo "PLANTED FAULT CAUGHT (log: $PLANT/gate.log)"
        exit 0
    fi
    echo "PLANTED FAULT MISSED: the gate passed with the fault in place (log: $PLANT/gate.log)"
    exit 1
fi

BUILD=${RILEYOVERVIEW_BUILD_DIR:-$FORGE/gate-m3}
PREFIX=${RILEYOVERVIEW_PREFIX:-}
if [ -n "$PREFIX" ]; then
    SRC_BIN=$PREFIX/bin/riley-overview
    SRC_SHELL=$PREFIX/share/riley-overview/shell
    SRC_XSD=$PREFIX/share/riley-overview/config.xsd
    echo "testing installed copy $PREFIX"
else
    SRC_BIN=$TREE/bin/riley-overview
    SRC_SHELL=$TREE/shell
    SRC_XSD=$TREE/data/config.xsd
    echo "testing tree $TREE"
fi

STAGE=$BUILD/stage
UNIT=$BUILD/unit
LOGS=$BUILD/logs
LIVE=$BUILD/live
SHOTS=$BUILD/shots
child=""
group=""
cleanup() {
    if [ -n "$child" ] && kill -0 "$child" 2>/dev/null; then
        kill "$child" 2>/dev/null
        wait "$child" 2>/dev/null
    fi
    # the live part runs in its own session whose group id is its saved process ID: end the whole group
    if [ -n "$group" ] && kill -0 -- "-$group" 2>/dev/null; then
        kill -TERM -- "-$group" 2>/dev/null
        sleep 8
        kill -KILL -- "-$group" 2>/dev/null
    fi
    rm -rf "$SHOTS"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

pass=0
fail=0
ok() { echo "PASS $*"; pass=$((pass + 1)); }
bad() { echo "FAIL $*"; fail=$((fail + 1)); }

QMLBIN=${RILEYOVERVIEW_QML:-/usr/lib64/qt6/bin/qml}
for tool in qmltestrunner-qt6 xmllint qs hyprctl grim wtype python3 patch gcc "${RILEYOVERVIEW_HYPRLAND:-/usr/bin/Hyprland}" \
            "$QMLBIN" "$HOME/.local/bin/dp2-lock"; do
    command -v "$tool" >/dev/null || { echo "FAIL missing tool $tool"; echo "GATE FAIL"; exit 1; }
done
python3 -I -c 'import PIL' 2>/dev/null || { echo "FAIL missing python3 module PIL (python3-pillow)"; echo "GATE FAIL"; exit 1; }

# Stage: an installed-layout copy (bin/, share/riley-overview/{shell,config.xsd}) and the unit tests next to lib/.
rm -rf "$STAGE" "$UNIT" "$LOGS" "$LIVE"
mkdir -p "$STAGE/bin" "$STAGE/share/riley-overview" "$UNIT/lib" "$UNIT/tests" "$LOGS" "$LIVE" "$SHOTS"
if [ -d "$SRC_SHELL" ]; then cp -r "$SRC_SHELL" "$STAGE/share/riley-overview/shell"; else bad "shell tree missing: $SRC_SHELL"; fi
if [ -f "$SRC_BIN" ]; then cp "$SRC_BIN" "$STAGE/bin/riley-overview"; chmod +x "$STAGE/bin/riley-overview"; else bad "launcher missing: $SRC_BIN"; fi
if [ -f "$SRC_XSD" ]; then cp "$SRC_XSD" "$STAGE/share/riley-overview/config.xsd"; else bad "config.xsd missing: $SRC_XSD"; fi
if [ -d "$SRC_SHELL/lib" ]; then cp "$SRC_SHELL"/lib/*.mjs "$UNIT/lib/" 2>/dev/null; fi
cp "$TREE"/tests/interact/unit/tst_*.qml "$UNIT/tests/"
# M1's hand-worked spread inputs, for the navigation cases built on them
cp "$TREE"/tests/layout/cases.mjs "$TREE"/tests/layout/checks.mjs "$UNIT/tests/"
# the gate's pointer helper (real motion events inside the nest; a cursor warp sends none)
if ! gcc -O2 -o "$BUILD/vpointer" "$TREE/tests/overlay/vpointer.c" -lwayland-client -lm > "$LOGS/vpointer.txt" 2>&1; then
    bad "tests/overlay/vpointer.c does not build: $(head -n 3 "$LOGS/vpointer.txt" | tr '\n' ' ')"
fi

# Part 1: offscreen unit checks, one file at a time so a file that does not load is named.
for t in navigate search drop; do
    log=$LOGS/tst_$t.txt
    if [ ! -f "$UNIT/lib/$t.mjs" ]; then bad "module $t.mjs missing in $SRC_SHELL/lib"; continue; fi
    if [ "$t" = drop ] && [ ! -f "$UNIT/lib/hittest.mjs" ]; then bad "module hittest.mjs missing in $SRC_SHELL/lib"; continue; fi
    QT_QPA_PLATFORM=offscreen timeout 120 qmltestrunner-qt6 -input "$UNIT/tests/tst_$t.qml" > "$log" 2>&1 &
    child=$!
    wait "$child"
    rc=$?
    child=""
    n=0
    while IFS= read -r line; do
        case $line in
            "PASS   : "*)
                name=${line#PASS   : qmltestrunner::}
                case $name in *::initTestCase\(\)|*::cleanupTestCase\(\)) continue ;; esac
                ok "$name"; n=$((n + 1)) ;;
            "FAIL!  : "*)
                name=${line#FAIL!  : qmltestrunner::}
                bad "$name"; n=$((n + 1)) ;;
        esac
    done < "$log"
    if [ $rc -ne 0 ] && ! grep -q '^FAIL!' "$log"; then
        bad "tst_$t.qml did not run (exit $rc): $(grep -m1 -iE 'error|warning|unable|not' "$log")"
    elif [ $n -eq 0 ]; then
        bad "tst_$t.qml ran no checks"
    fi
done

# Part 2: live, in the nest, holding dp2-lock only for this.
if [ -f "$STAGE/share/riley-overview/shell/shell.qml" ] && [ -x "$STAGE/bin/riley-overview" ]; then
    # setsid: a new session and process group whose id is the saved $! (no job control here, so setsid does not
    # fork), so an interrupted gate can end dp2-lock, timeout, the gate and everything it started by that ID.
    setsid "$HOME/.local/bin/dp2-lock" timeout -k 10 300 python3 -I "$TREE/tests/interact/gate.py" \
        --stage "$STAGE" --work "$LIVE" --shots "$SHOTS" --vpointer "$BUILD/vpointer" > "$LOGS/live.txt" 2>&1 &
    group=$!
    wait "$group"
    rc=$?
    group=""
    grep -vE '^(PASS|FAIL) ' "$LOGS/live.txt" | grep -E '^ |^==|^live' || true
    while IFS= read -r line; do
        case $line in
            "PASS "*) ok "${line#PASS }" ;;
            "FAIL "*) bad "${line#FAIL }" ;;
        esac
    done < "$LOGS/live.txt"
    if [ $rc -ne 0 ] && ! grep -q '^FAIL ' "$LOGS/live.txt"; then
        bad "live part did not run (exit $rc): $(tail -n 3 "$LOGS/live.txt" | tr '\n' ' ')"
    fi
else
    bad "live part not run: no staged shell.qml or launcher"
fi

echo "checks: $pass passed, $fail failed (logs: $LOGS, live work: $LIVE)"
if [ $fail -eq 0 ] && [ $pass -gt 0 ]; then
    echo "GATE PASS"
    exit 0
fi
echo "GATE FAIL"
exit 1
