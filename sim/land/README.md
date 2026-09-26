# `sim/land`

Parcels, rights and ownership. Home of `LandSystem.rights_at()`, the one spatial query
the whole game asks (design doc §7.1). Positions are integer millimetres; footprints
are simple polygons with a half-open vertical extent; owners are tags (player, NPC,
faction), and actors act as the owner they are identified with.

Two kinds of act ask it (ADR-011 C): construction, digging and entering ask
`require()`, which refuses a denied right; a crime against someone else's property
asks `offend()`, which never refuses and records the denied right as one
`land.violation`. `breach_system.gd` is the first `offend()` caller: `build.breach`
cuts a piece out with a carried tool, heard while it works (M6 spec claim 9).

**Allowed imports:** `sim/` only.

**Introduced at:** M2 (land authority + starter plot).

**Extension point:** [docs/extending-land.md](../../docs/extending-land.md).
