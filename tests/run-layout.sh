#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# M1 gate: layout, no UI. Runs the pure-logic modules (shell/lib/*.mjs) offscreen under Qt Quick Test against
# hand-worked cases, and checks the config samples against data/config.xsd with xmllint.
#
#   tests/run-layout.sh           run the gate; prints PASS/FAIL per check, then GATE PASS or GATE FAIL
#   tests/run-layout.sh --plant   copy the tree to $FORGE/plant-m1, apply tests/faults/m1-*.patch, run the gate
#                                 there and expect it to fail (PLANTED FAULT CAUGHT)
#
# Environment:
#   RILEYOVERVIEW_BUILD_DIR  staging and logs (default /srv/devops/forge/build/riley-overview/gate-m1)
#   RILEYOVERVIEW_PREFIX     an installed copy to test instead of the tree: $PREFIX/share/riley-overview/
#                            {shell/lib/*.mjs, config.xsd, config.example.xml}
#
# Exit 0 only on GATE PASS (or, with --plant, on PLANTED FAULT CAUGHT).
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(dirname "$HERE")
FORGE=/srv/devops/forge/build/riley-overview

if [ "${1:-}" = "--plant" ]; then
    shopt -s nullglob
    patches=("$TREE"/tests/faults/m1-*.patch)
    if [ ${#patches[@]} -eq 0 ]; then
        echo "no fault patch (tests/faults/m1-*.patch)"
        exit 2
    fi
    PLANT=$FORGE/plant-m1
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
        bash "$PLANT/tree/tests/run-layout.sh" > "$PLANT/gate.log" 2>&1
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

BUILD=${RILEYOVERVIEW_BUILD_DIR:-$FORGE/gate-m1}
PREFIX=${RILEYOVERVIEW_PREFIX:-}
if [ -n "$PREFIX" ]; then
    SHARE=$PREFIX/share/riley-overview
    LIB=$SHARE/shell/lib
    XSD=$SHARE/config.xsd
    EXAMPLE=$SHARE/config.example.xml
    echo "testing installed copy $SHARE"
else
    LIB=$TREE/shell/lib
    XSD=$TREE/data/config.xsd
    EXAMPLE=$TREE/data/config.example.xml
    echo "testing tree $TREE"
fi

STAGE=$BUILD/stage
LOGS=$BUILD/logs
SHOTS=$BUILD/shots
child=""
cleanup() {
    if [ -n "$child" ] && kill -0 "$child" 2>/dev/null; then
        kill "$child" 2>/dev/null
        wait "$child" 2>/dev/null
    fi
    rm -rf "$SHOTS"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

pass=0
fail=0
ok() { echo "PASS $*"; pass=$((pass + 1)); }
bad() { echo "FAIL $*"; fail=$((fail + 1)); }

for tool in qmltestrunner-qt6 xmllint; do
    command -v "$tool" >/dev/null || { echo "FAIL missing tool $tool"; echo "GATE FAIL"; exit 1; }
done

# Stage: lib/ holds the modules under test, tests/ the test sources (they import "../lib/<name>.mjs").
rm -rf "$STAGE" "$LOGS"
mkdir -p "$STAGE/lib" "$STAGE/tests" "$LOGS"
for m in spread strip hittest config; do
    if [ -f "$LIB/$m.mjs" ]; then cp "$LIB/$m.mjs" "$STAGE/lib/"; else bad "module $m.mjs missing in $LIB"; fi
done
cp -r "$TREE/tests/layout/." "$STAGE/tests/"
if [ -f "$EXAMPLE" ]; then cp "$EXAMPLE" "$STAGE/tests/data/example.xml"; else bad "config.example.xml missing"; fi

# Qt Quick Test, one file at a time so a file that does not load is named.
for t in spread strip hittest config; do
    log=$LOGS/tst_$t.txt
    QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 \
        timeout 120 qmltestrunner-qt6 -input "$STAGE/tests/tst_$t.qml" > "$log" 2>&1 &
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

# The config samples against the schema: the same verdicts tst_config.qml expects from parseConfig.
for f in example valid partial empty; do
    if xmllint --noout --schema "$XSD" "$STAGE/tests/data/$f.xml" >/dev/null 2>&1; then
        ok "xsd::valid($f.xml)"
    else
        bad "xsd::valid($f.xml) rejected by $XSD"
    fi
done
for f in bad-range bad-element bad-version bad-duplicate bad-number not-xml; do
    if xmllint --noout --schema "$XSD" "$STAGE/tests/data/$f.xml" >/dev/null 2>&1; then
        bad "xsd::invalid($f.xml) accepted by $XSD"
    else
        ok "xsd::invalid($f.xml)"
    fi
done

echo "checks: $pass passed, $fail failed (logs: $LOGS)"
if [ $fail -eq 0 ] && [ $pass -gt 0 ]; then
    echo "GATE PASS"
    exit 0
fi
echo "GATE FAIL"
exit 1
