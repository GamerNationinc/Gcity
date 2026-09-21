# M3 — Portal graph + build system: specification

Milestone M3 of `docs/gcity-design.md` §16, in the terms of that document. Written
before implementation (standards §2.1, §10.2). Status: **draft, awaiting approval.**

**Preconditions.** G2 is signed (it is). No ADR blocks M3: ADR-003 (volumetric
terrain) is accepted and M3 builds on flat parcels, not terrain. One ADR-003
condition needs a decision (see "Open points").

**The claim of the milestone.** Player structures are never navmeshed. A flood fill
runs when a build piece is placed or destroyed and produces enclosed volumes as nodes
and every door, window, hatch **and wall** as an edge with a breach cost derived from
material HP, the tool required and the noise it makes (design doc §6.3). Raid planning
is A* to the highest-value container with breach cost as the edge weight, so a sealed
bunker is not unraidable, only expensive, and the cheap path is the one the player
turns into a killbox. G3's proof (standards §11): flood-fill partition invariants hold
under 10 000 random build/destroy sequences; a dumb agent reaches the vault by the
cheapest path; raising a wall's HP never lowers that path's cost.

## Claims

### Build pieces (`sim/land/`)

1. **Pieces are content.** `content/build_piece/<id>.json` declares `kind`
   (`foundation`, `wall`, `floor`, `door`, `window`, `hatch`: registry entries in
   `content/piece_kind/`, not an enum), `material` (ref), size in build cells, and
   the sockets it snaps to (design doc §8.3). `content/material/<id>.json` declares
   `hp`, `breach_tool` (ref to `content/tool_class/`), `breach_noise` (milli-units) and
   `breach_ticks`. M3 ships one material (`scrap_steel`), the six kinds, one piece per
   kind, and one tool class (`cutter`).
2. **The build grid is integer cells on a parcel.** Cell size 1 000 mm, aligned to the
   world millimetre grid; a piece occupies a set of cells (walls occupy a cell face,
   floors a cell, doors/windows/hatches a face with an opening). Positions and cells are
   ints; there is no float in the build system (ADR-002).
3. **Placement is a command that asks the land for `build`** at the piece's cells
   (`&"build.place {actor, piece, x, y, z, facing}"`); removal is `&"build.remove
   {actor, piece_id}"`. Both are rejected without state change on any rights, snap,
   overlap or support failure, and a rights failure emits `land.violation` (M2
   claim 6). Pieces are entities with sim-issued ids.
4. **Structural support propagates on a dirty set** (design doc §8.3): a piece is
   supported if it stands on a foundation, on the ground of a parcel it may be on, or
   on a supported piece within the material's `max_span` cells. Placement that would
   be unsupported is rejected; removal that leaves pieces unsupported removes them too
   (collapse), in one deterministic pass over the dirty set on the tick of the change.
   Property: after any sequence of commands, every piece present is supported.

### Portal graph (`sim/nav/`)

5. **Flood fill partitions the build cells** on every change (not per frame): every
   interior cell belongs to exactly one volume; the exterior is one node; volumes are
   maximal sets of cells connected through open faces. Property over 10 000 random
   build/destroy sequences: partition (each cell in exactly one volume), every volume has
   at least one edge to another node (a wall counts), and the graph is connected from
   the exterior after any single piece removal or the structure is provably sealed.
6. **Every face between two nodes is an edge with a cost.** Open faces cost the
   traversal base; doors, windows and hatches cost their `open_cost` (closed but
   passable: material-independent) and are flagged for later locks; walls, floors and
   foundations cost `breach_cost = material.hp × tool_factor(tool_class) +
   material.breach_noise × noise_weight`, all integers from content, computed through
   the stat resolver on the piece entity so perks and tools later modify it without
   code. Recompute touches only the changed volume's neighbourhood.
7. **A* over the graph** (`PortalGraph.cheapest_path(from_node, to_node, tool_class)`)
   returns the ordered edge list and total cost, deterministic under ties (lowest edge
   id wins). Metamorphic relations (standards §3.4): raising any wall's `hp` never
   lowers the cost of the returned path; adding a door never raises the cheapest cost;
   removing the cheapest edge never lowers it.
8. **A container is a target.** The M2 structure kind gains no code; a build-cell
   "vault" target is any structure or storage entity placed inside a volume
   (`content/target_value/` ranks them). `PortalGraph.raid_plan(exterior, tool_class)`
   picks the highest-value reachable target and its cheapest path. M3 ships one
   storage piece kind (`crate`) with a value.
9. **A dumb agent follows the plan.** `sim/agents/` gains `RaidTokenSystem`: a token
   `{position node, path, progress}` that advances one edge per `edge.cost /
   TOKEN_SPEED` ticks, breaching (removing the piece and emitting `build.breached`)
   when it crosses a wall edge. No perception, no steering, no combat: it exists to
   prove claim 7 end to end and is the M8 raid resolution's skeleton.
10. **Time slicing is measured, not assumed.** Flood fill and support propagation run
    to completion on the tick of the change but only over the affected region; the
    tick cost for the largest M3 structure (the 10 000-sequence property's worst case)
    is recorded in the G3 report so G4 can budget it. If it exceeds the 1.5 ms
    navigation row on the container it is an M3 debt item, not a gate failure
    (standards §4.1 budgets are enforced from G4 on Deck numbers).

### Save, fixtures, content, client

11. **Everything is in the snapshot and survives the save round trip**: pieces,
    volumes, edges, tokens. The M2 property test (10 000 generated sims) gains build
    and raid commands in its stream. Save schema stays at version 1 (additive keys
    inside a new system's state).
12. **Replay fixtures**: `m3-bunker.json` builds a two-room structure with a door, a
    window and a sealed vault, spawns a raid token and lets it breach; the recorded hash
    and the breach sequence are asserted. `m3-killbox.json` shows the cheap-door path
    being chosen over the wall.
13. **Schemas** for `build_piece`, `piece_kind`, `material`, `tool_class`,
    `target_value`; cross-references checked at build and semantics at assembly.
14. **Client**: the plot view gains piece placement on the build grid with a facing,
    a volume overlay (each volume a colour, edges labelled with cost), the raid plan
    drawn as a path, and a "spawn raid token" action. Screenshot in the gate package.
15. **Hostile corpus** extended with every new command kind; a fuzz target for the
    build system (random placement/removal sequences against the partition invariants,
    standards §3.5) is the property of claim 5 with a committed corpus of found cases.

### Optional claim set P — player movement in 3D (accept or strike)

Not in the design doc's M3; offered because the approver asked how far 3D movement
is. Costs about a fifth of M3 and touches `sim/agents/` and the client only.

P1. `&"actor.move {actor, dx, dz}"` moves an actor by integer millimetres per tick
    with a per-profile speed cap, on flat parcel ground; a move into a wall piece's
    face or off a supported floor is rejected. Position is sim state and in the hash.
P2. The client gains a grey-box 3D scene: parcels as planes, pieces as boxes, the
    player as a capsule, third-person camera with a first-person toggle (design doc
    §1), Steam Deck stick and trackpad bindings alongside keyboard. Every step is a
    submitted command; the camera reads the sim's position.
P3. A replay fixture walks the player through the door of the M3 bunker.

If accepted, the "walkable slice" arrives with G3 instead of G6.

## Out of scope (goes to the debt log if touched)

Navmesh or steering inside volumes (M4), perception and combat (M4), locks and
sensors on edges (M8/§9.1), raid scheduling and resolution (M8), path traces (§6.4,
M6), terrain and chunk colliders (M7), a second material or tool beyond the extension
exercise, any performance number claimed as a budget.

## Open points

- **ADR-003 condition 1** says colliders and runtime navigation on volumetric chunks
  are measured at G3. M3 has no chunks (terrain is M7). Proposed: the condition moves
  to G7, recorded as an amendment to ADR-003's consequences, signed by CEOGG. Until
  decided, this spec assumes the move.
- Whether claim set P is accepted.

## Assumptions to record in the gate

- Build cells are 1 m; the M2 socket pitch (610 mm) is inside a container and does not
  interact with the build grid. A container is one opaque block of build cells.
- Breach cost is linear in HP and noise with integer weights from `tool_class` content;
  the design doc gives no formula.
- Tokens move at a constant `TOKEN_SPEED`; real agents (M4) replace the mover, not the
  planner.

## Extension exercise for Q4 (standards §11, G3)

Add a second material (`content/material/reinforced_concrete.json`, higher HP,
different tool) and a second wall piece using it, using only new files under
`content/`; `tools/test.sh` passes, the metamorphic relations hold with the new
material in the mix, and the diff under `sim/` is empty. `docs/extending-building.md`
records the procedure.

## Fixtures and property seeds

| Test | Cases | Fixed seed constant |
|---|---|---|
| Partition, edge-to-exterior, connectivity after single removal | 10 000 sequences | `tests/nav/test_portal_graph.gd` |
| Support: every present piece is supported after any sequence | 10 000 | `tests/land/test_build_system.gd` |
| Metamorphic: HP up never lowers path cost; door never raises; removal never lowers | 10 000 | `tests/nav/test_raid_plan.gd` |
| Save round trip with build and raid commands in the stream | 10 000 | `tests/sim/test_save_file.gd` (extended) |
| Command payload fuzz, every new kind | corpus + 10 000 mutations | `tests/fuzz/commands/` |

A failing seed is committed as a named regression case (standards §3.2).
