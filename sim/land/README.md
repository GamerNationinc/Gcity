# `sim/land`

Parcels, rights and ownership. Home of `LandSystem.rights_at()`, the one spatial query
the whole game asks (design doc §7.1). Positions are integer millimetres; footprints
are simple polygons with a half-open vertical extent; owners are tags (player, NPC,
faction), and actors act as the owner they are identified with.

Sites (`site_system.gd`, M6 claim 12) are places written as content (`content/site/`):
parcels, a dug basement, pieces with their sensors, hack targets, agents and an exfil
polygon, raised at a cell origin by `site.spawn` in one all-or-nothing step.

**Allowed imports:** `sim/` only.

**Introduced at:** M2 (land authority + starter plot).

**Extension point:** [docs/extending-land.md](../../docs/extending-land.md).
