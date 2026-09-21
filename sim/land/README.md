# `sim/land`

Parcels, rights and ownership. Home of `LandSystem.rights_at()`, the one spatial query
the whole game asks (design doc §7.1). Positions are integer millimetres; footprints
are simple polygons with a half-open vertical extent; owners are tags (player, NPC,
faction), and actors act as the owner they are identified with.

**Allowed imports:** `sim/` only.

**Introduced at:** M2 (land authority + starter plot).

**Extension point:** [docs/extending-land.md](../../docs/extending-land.md).
