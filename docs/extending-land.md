# Extending: rights, policies, districts, factions, parcels

The minimal diff for each thing the land authority (`sim/land/land_authority.gd`) can be
extended with. Design doc §7.1, §7.2, §8.4; M2 spec claims 1–5.

## The one query

```gdscript
var bits: int = land.rights_at(Vector3i(x, y, z), actor)   # total: always answers
if land.has_right(bits, &"build"): ...
if not land.check(position, actor, &"build"): return false  # denied -> land.violation emitted
```

Positions are world voxels in metres. A voxel belongs to exactly one parcel: the one
whose polygon contains the voxel's centre under the half-open crossing rule and whose
`[floor, ceiling)` contains `y`, or the implicit wilderness. Adjacent parcels that share
an edge never both claim a voxel; a parcel stacked exactly on another's ceiling is not
an overlap. There is no "unowned" branch anywhere: the wilderness is a district file
with `is_wilderness: true` and a policy like any other.

## A new right: one file

`content/right/<id>.json`. Bits are assigned in lexical id order at assembly (at most
62 rights). A policy that names it gets it; nothing else changes. A system that wants to
gate an action on it calls `check(position, actor, &"<id>")`.

## A new policy: one file

`content/rights_policy/<id>.json` lists the rights for each relation between the asking
actor and the parcel's owner: `owner`, `same_faction`, `other`, `unowned`. Actors carry
no faction until M8, so `same_faction` is present in data and inert until then.

## A new district: one file

`content/district/<id>.json`: the design's record (`law_index`, `wealth_index`,
`informant_density`, optional `gang_control`) plus `policy`. Exactly one district in the
whole content set has `is_wilderness: true`; assembly refuses zero or two.

## A new faction: one file

`content/faction/<id>.json`. It can own parcels (`"owner": {"kind": "faction", "id": …}`).

## A new parcel: one file

`content/parcel/<id>.json`: `district`, optional `policy` override, `polygon` (3–64
integer XZ vertices, simple, at most 1024 m in an axis), `floor`, `ceiling`, `owner`
(`none` or a faction; actors come to own parcels through `land.grant`, later through
purchase). The schema checks shape; `LandAuthority.validate_content()` checks
simplicity, positive area, the vertical extent and overlap against every other parcel,
and refuses assembly with the offending voxel named.

## Ownership at runtime

`land.grant {actor, parcel}` (debug-class, like `item.spawn`) makes the actor the owner.
Ownership is the parcel overlay in the save; geometry is content and is not saved.
`owner_of()`, `policy_of()`, `district_of()`, `parcel_bounds()` are the reads.

## What you may not do

- Store ownership per voxel, or cache `rights_at()` results in another system. Ask again;
  it is one bucket lookup and a polygon test.
- Add a "no-build volume" or any second path for denial. It is a parcel with a policy
  (design doc §8.4).
- Raise heat or suspicion from the authority. It emits `land.violation`; the threat
  systems decide what a violation costs (M8).
