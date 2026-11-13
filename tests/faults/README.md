# Planted faults

`tests/run-layout.sh --plant` copies the tree to `/srv/devops/forge/build/riley-overview/plant-m1`, applies every
`m1-*.patch` here with `patch -p1`, runs the gate in the copy and expects it to fail.

M1 fault (brief): the layout ignores the spacing, so neighbouring windows touch. A patch that drops `spacing`
from the placement in `shell/lib/spread.mjs` is caught by `spread::test_no_overlap` and `spread::test_exact`.
