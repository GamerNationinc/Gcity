# Extending: districts, parcels and rights

The minimal diff for each thing the land system (`sim/land/land_system.gd`) can be
extended with. Design doc §7.1, §7.2, §8.4; M2 spec claims 1–7. The G2 extension
exercise is a third district with a stricter rights table, data only, empty `sim/` diff.

## Vocabulary

- **Position**: integer millimetres, `Vector3i(x, y, z)`; x/z is the ground plane.
- **Parcel**: a simple polygon footprint (3–64 `[x, z]` vertices, ≥ 1 m²) with a
  half-open vertical extent `[floor_y, ceiling_y)`, a district and an owner tag.
  Parcels never overlap in volume; parcels sharing an edge are fine and the half-open
  rule gives the edge to exactly one of them.
- **Owner tag**: `[a-z0-9][a-z0-9_.]*` or `""` for unowned: `player`, `npc.<name>`,
  `faction.<id>`, `city`. Owners are tags, not actor ids, because factions and the
  city-state own land (design doc §9.4). An actor acts as the owner it is identified
  with (`land.identify`); an unidentified actor owns nothing.
- **District**: a record of indices plus a rights table with three rows: `owner`,
  `other`, `unowned`. Exactly one district sets `covers_unparcelled` and answers for
  every position inside no parcel.

`rights_at(position, actor)` is total: every position and every actor id, including
ids that name nothing, resolve to five booleans. `tests/land/test_land_system.gd`
proves it over 10 000 generated positions and a rectangle oracle.

## A new district: one file

`content/district/<id>.json`:

```json
{
	"schema_version": 1,
	"description": "…",
	"law_index": 950, "wealth_index": 900, "informant_density": 100,
	"gang_control": {"faction": "", "strength": 0},
	"covers_unparcelled": false,
	"rights": {
		"owner":   {"build": true,  "dig": false, "enter": true, "carry": true,  "loot": true},
		"other":   {"build": false, "dig": false, "enter": true, "carry": false, "loot": false},
		"unowned": {"build": false, "dig": false, "enter": true, "carry": true,  "loot": false}
	}
}
```

Indices are milli-units (0–1000) and are carried for M8; only `rights` and
`covers_unparcelled` act at M2. `tests/land/test_extension_content.gd` walks every
district, places an owned and an unowned parcel in it, and checks `rights_at()`
reports exactly the table.

## A new authored parcel: one file

`content/parcel/<id>.json` with `district`, `owner`, `footprint`, `floor_y`,
`ceiling_y`. The assembly places every content parcel at tick 0; a parcel that
overlaps another, names an unknown district, or is not a simple polygon refuses to
assemble with the reason logged. Generated parcels (M7) call `add_parcel()` with the
same record shape.

## A new right

Rights are the five named in design doc §7.1 (`build`, `dig`, `enter`, `carry`,
`loot`), listed in `LandSystem.RIGHTS` and required by the district schema. Adding a
sixth is a design change: add it to both, and every district file gains a column.

## Commands (owned by the land system)

| Kind | Payload | Effect |
|---|---|---|
| `land.transfer` | `{parcel, owner}` | set a parcel's owner tag; debug-class at M2 (purchase and takeover are M8) |
| `land.identify` | `{actor, owner}` | the actor acts as that owner; `""` clears; the actor must exist |

## Asking for a right

Every system that could violate ownership asks before acting:

```gdscript
if not _land.require(position, actor, &"build"):
	return false
```

`require()` returns true or emits `land.violation {actor, parcel, right, x, y, z}`
on the event bus, counts it, and returns false. The command is then rejected with no
state change. Nothing else reads the event at M2; heat (M8) subscribes to it.

## What you may not do

- Store ownership anywhere but the parcel record, or per voxel.
- Add a no-build volume, a "protected area" flag or any second rule. If land should
  refuse building, it is a parcel with the right owner in the right district.
- Check a right by reading the district table yourself. `rights_at()` is the one
  code path, and `require()` is the one that emits.
