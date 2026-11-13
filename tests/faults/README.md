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
