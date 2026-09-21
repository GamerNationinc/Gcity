# `sim/nav`

Route graph (macro, M7), portal graph over player structures (M3), player path traces
and token hydration (design doc §6). The portal graph is derived from the build
system on every change: enclosed volumes are nodes, every face piece and every solid
block between two volumes is an edge whose cost is read through the stat resolver.

**Allowed imports:** `sim/` only.

**Introduced at:** M3 (portal graph), M7 (route graph).

**Extension point:** [docs/extending-building.md](../../docs/extending-building.md).
