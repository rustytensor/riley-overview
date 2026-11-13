# Planted faults

`tests/run-layout.sh --plant` copies the tree to `/srv/devops/forge/build/riley-overview/plant-m1`, applies every
`m1-*.patch` here with `patch -p1`, runs the gate in the copy and expects it to fail.

M1 fault (brief): the layout ignores the spacing, so neighbouring windows touch. A patch that drops `spacing`
from the placement in `shell/lib/spread.mjs` is caught by `spread::test_no_overlap` and `spread::test_exact`.

`tests/run-overlay.sh --plant` does the same for M2 in `/srv/devops/forge/build/riley-overview/plant-m2` with every
`m2-*.patch`. M2 fault (brief): one surface sized in logical instead of device pixels. The gate catches it three
ways: the layer size in `hyprctl layers` (`overlay::RO-C surface covers the monitor`), the hook's device size
(`overlay::RO-C surface device size`), and the colours at the spread rects in the grim screenshot. Until the
integrator writes `m2-*.patch`, `--plant` reports `no fault patch`.

`tests/run-interact.sh --plant` does the same for M3 in `/srv/devops/forge/build/riley-overview/plant-m3` with every
`m3-*.patch`. M3 fault (brief): a drop moves the window to the workspace before the target. The live drags catch it
(`interact::drop: red is on workspace 3 (not 2 or 6)` and the drop on the empty entry, workspace 6, landing on 3);
a fault placed in `dropTarget` is also caught by `drop::test_target`. `m3-drop-before-target.patch` puts it in
`dropTarget` (the strip entry before the one under the pointer): caught by 6 `drop::test_target` cases and 5 live
checks (both strip drags' drop targets and landing workspaces, and workspace 6 never appearing on RO-A).

`tests/run-install.sh --plant` does the same for M4 in `/srv/devops/forge/build/riley-overview/plant-m4` with every
`m4-*.patch`, installing into the throwaway prefix `plant-m4/prefix`. M4 fault: `m4-unit-wrong-execstart.patch`
points the unit's `ExecStart` at `<prefix>/bin/../libexec/riley-overview`, which does not exist. Caught by the unit's
ExecStart line check and by `systemd-analyze --user verify` (exit 1, "is not executable"); the M1 to M3 runs are then
skipped.
