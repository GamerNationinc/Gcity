# `sim/land`

Parcels, rights, ownership (design doc §7.1, §8.4).

| File | What |
|---|---|
| `land_authority.gd` | `LandAuthority` (system id `land`): `rights_at(position, actor)`, the one total spatial query. Simple integer polygons with a half-open vertical extent, grid-bucketed, every voxel in exactly one parcel with the wilderness as the implicit one; rights, policies, districts, factions and authored parcels from content; ownership as the only state; `check()` emits `land.violation`; `land.grant` (debug-class). |

**Allowed imports:** `sim/` only.

**Introduced at:** M2 (land authority + starter plot). Procgen parcels attach to route
graph nodes at M7.

**Extension point:** [docs/extending-land.md](../../docs/extending-land.md).
