# Extending: build pieces, materials, tools and the portal graph

The minimal diff for each thing the build system (`sim/land/build_system.gd`) and the
portal graph (`sim/nav/portal_graph.gd`) can be extended with. Design doc §6.3, §8.3;
M3 spec claims 1–9. The G3 extension exercise is a second material with a different
tool class and a second wall piece, data only, empty `sim/` diff.

## Vocabulary

- **Build cell**: 1 000 mm, `Vector3i(floor(x / 1000), …)`. Ground is cell y = 0.
- **Cell piece** (foundation, crate): occupies a cell. **Face piece** (wall, floor,
  door, window, hatch): occupies one face, stored canonically as the lower cell along
  the face's axis plus the axis, so a wall is the same face from either side.
- **Support**: a piece stands if a chain of touching pieces no longer than its
  material's `max_span` reaches a ground-level foundation. Removal collapses whatever
  it left unsupported.
- **Node**: the exterior (0) or an enclosed volume of air cells. **Edge**: a face piece
  between two nodes, or a solid block with air on two open opposite faces. Openings
  cost `open_cost`; solids cost `piece_hp × hp_factor + breach_noise × noise_weight`
  for the tool class asked about, read through the stat resolver.

## A new material: one file

`content/material/<id>.json`: `hp`, `breach_tool` (a `tool_class` id), `breach_noise`
(milli-units), `breach_ticks`, `max_span`. The material's `hp` and `breach_noise` become
the piece entity's bases for the `piece_hp` and `breach_noise` stats at placement, so a
perk or a tool can modify them with a modifier and no code.

## A new tool class: one file

`content/tool_class/<id>.json`: `hp_factor`, `noise_weight`. Every solid piece has a
cost under every tool; `tests/land/test_extension_building.gd` prices every wall under
every tool and checks the monotone relation between materials.

## A new piece: one file

`content/build_piece/<id>.json`: `kind` (a `piece_kind` id), `material`, `open_cost`
(used when the kind is passable), `value` (used when the kind is a target).

## A new piece kind: one file, maybe

`content/piece_kind/<id>.json`: `occupies` (cell | face), `orientation` (vertical |
horizontal | any), `passable`, `target`. A passable kind must be a face; a target kind
must be a cell; `foundation` must exist. Anything expressible with those four fields
is data; a kind that needs behaviour (a turret, a sensor) is an M8 registration.

## Commands

| Kind | Payload | Effect |
|---|---|---|
| `build.place` | `{actor, piece, x, y, z, facing}` | mm position; facing `""` for cell pieces, `px/nx/py/ny/pz/nz` for faces; needs `build` at the cell and support |
| `build.remove` | `{actor, piece_id}` | needs `build`; collapses dependants; emits `build.changed` |
| `raid.spawn` | `{tool}` | debug-class: a token follows `PortalGraph.raid_plan(tool)` |
| `actor.move` | `{actor, dx, dz}` | capped by `speed_mm_per_tick`; refused into solids, through non-passable faces, into parcels without `enter` |

## Reading the graph

`node_at(cell)`, `edges_of(node)`, `edge_cost(piece, tool)`, `cheapest_path(a, b, tool)`
and `raid_plan(tool)`. The graph is rebuilt on every `build.changed`; a restore rebuilds
it from the pieces and refuses a saved graph that differs.

## What you may not do

- Store a piece's cost anywhere. It is resolved from the material's stats and the tool.
- Give an edge a hand-set cost, a "locked" flag or a special case. Locks are M8 and will
  be modifiers on the piece's stats or a registered edge rule.
- Read the graph's node numbers as stable across changes. Volumes renumber when the
  structure changes; keep a cell, ask `node_at()`.


## Climbable faces and standing (M6)

`content/piece_kind/<id>.json` carries `climb`: a face an actor may change level
through (`stair`). An actor may move a level when a climbable face touches the cell
it leaves or the cell it enters, the floor between them is passable or absent, and
the cell it enters is standable — you climb onto something, never into the air.

A cell is **standable** when a solid horizontal face carries it from below, a solid
piece fills the cell beneath, it is at or below the ground level of its parcel, or it
carries a climbable face (you are on the stairs). An actor over nothing falls a level
a tick and takes its combat profile's `fall_damage_per_level` for every level beyond
the first.

A flight that ends in open air ends there: the move up is refused rather than
dropping the actor. A floor panel blocks its own stairwell, so put a `roof_hatch` (a
passable horizontal face) at the cell the flight passes through.
