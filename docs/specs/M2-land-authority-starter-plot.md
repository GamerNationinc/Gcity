# M2 — Land authority + starter plot: specification

Milestone M2 of `docs/gcity-design.md` §16, in the terms of that document. Written
before implementation (standards §2.1, §10.2). Status: **draft, awaiting approval.**

**Preconditions.** G1 is signed in `docs/gates/M1-gate.md` (it is). ADR-003 is
`accepted` as B, volumetric (it is), so parcels have a real vertical extent and the
"dig under the neighbour" rule is a live requirement, not a placeholder. ADR-005 is
`proposed`; this spec assumes it closes as proposed (structures are owner-agnostic
records) because M2 writes the first structure and parcel records into the save
overlay and cannot leave their owner field undefined. If ADR-005 closes otherwise,
claims 9–10 are rewritten before any code.

**The claim of the milestone.** One spatial query underlies the whole game:
`LandAuthority.rights_at(position, actor) -> {build, dig, enter, carry, loot}`. Every
system that could violate ownership asks it before acting, unowned land is a parcel
with a null owner rather than a second code path, and a violation emits an event
rather than setting a wanted level (design doc §7.1, §8.4). On top of it: the
40×40 ft starter plot, one 20 ft container, three modules sharing a power and thermal
budget (§8.1, §8.2), and the first real save: `world seed + overlay`, round-tripped as
a property (§5.6, standards §3.2). G2's proof (standards §11): `rights_at()` totality
over 10 000 cases, the save round-trip property, and the Steam Cloud file set defined.

## Claims

### Land authority (`sim/land/`)

1. **`rights_at()` is total.** For every position in the world and every actor id,
   `LandSystem.rights_at(position, actor)` returns a `Rights` record with all five
   flags set to true or false. Positions are integer millimetre vectors
   (`{x, y, z}` ints, ADR-002: no floats in the sim). No position is unresolvable:
   a position inside no parcel resolves to the **unowned** parcel (id 0, owner none,
   all rights true). Property test, 10 000 generated positions and actors.
2. **Parcels are polygons with a vertical extent, spatially indexed.** A parcel is
   `{parcel_id, owner (actor id or 0), footprint: Array of {x, z} vertices
   (convex or simple polygon, ≥3 vertices), floor_y, ceiling_y, district_id}`.
   Lookup is a grid index over the footprint bounding boxes, then a point-in-polygon
   and a vertical range check. Per-voxel ownership never exists (design doc §7.1).
3. **Parcels never overlap.** Adding a parcel whose volume intersects an existing
   parcel's volume is rejected with `ERR_ALREADY_EXISTS`. Property test: 10 000
   generated parcel sets, then every generated point resolves to at most one
   non-unowned parcel, and to that parcel exactly when it lies inside its polygon and
   between its floor and ceiling.
4. **Rights derive from owner and district, as data.** Each district content file
   (`content/district/<id>.json`, design doc §7.2) carries `law_index`,
   `wealth_index`, `gang_control`, `informant_density` and a `rights` table: what an
   owner may do, what a non-owner may do, and what anyone may do on unowned land in
   that district. `rights_at()` is a lookup into that table keyed by
   (is_owner, parcel owned?); there is no per-parcel special case. M2 ships two
   districts: `starter_ghetto` and `badlands_outskirts`, with the numbers from
   design doc §7.2 as placeholders.
5. **Vertical extent matters.** A position below a parcel's `floor_y` or above its
   `ceiling_y` is outside that parcel and resolves to whatever is there (the unowned
   parcel at M2). The property test in claim 3 covers it; a named test digs from the
   starter plot to a position under the neighbouring parcel and shows `dig` false.
6. **Violations emit events, not consequences.** When a command asks `rights_at()`
   and the needed right is false, the command is rejected and
   `land.violation{actor, parcel_id, right, position}` is emitted on the event bus.
   Nothing in M2 subscribes to it except a counting test double; heat is M8. A
   rejected command changes no state (verified by state hash before/after).
7. **Ownership changes are one write.** `&"land.transfer"` sets a parcel's owner.
   At M2 it is a debug-class command like `actor.spawn` (G1 debt 4); purchase, price
   and takeover (design doc §9.4) are M8. The command exists so the "buy the adjacent
   parcel" upgrade path (§8.1) is exercisable in the fixture.

### Starter plot, container and modules (`sim/land/`, `sim/items/`)

8. **The starter plot is content, not code.** `content/parcel/starter_plot.json`
   describes a 40×40 ft (12 192 × 12 192 mm) parcel in `starter_ghetto` with a floor
   3 m below grade and a ceiling 9 m above, plus two neighbouring parcels owned by
   non-player actors. World assembly places them from content at tick 0.
9. **A structure is an owner-agnostic record on a parcel** (ADR-005 as proposed).
   `structures: parcel_id -> Array of {structure_id, kind, position, rotation,
   owner_at_placement}`. M2 ships one structure kind, `container_20ft`, as content
   (`content/structure/container_20ft.json`): an exterior footprint and an interior
   socket grid on 2 ft (609.6 mm, stored as 610 mm) centres, 3 × 9 sockets.
   Placing it is `&"structure.place"`, which asks `rights_at(position, actor).build`.
10. **Modules are data with a shared budget** (design doc §8.2). A module declares
    `{id, footprint (grid cells), mass, power_draw, heat_output, water_in, water_out,
    depends_on, emits}` in `content/module/<id>.json`. `&"module.install"` places a
    module on free sockets of a structure the actor may build on; `&"module.remove"`
    frees them. The container carries a `power_budget` and `heat_budget`; an install
    that would exceed either, overlap an occupied socket, or lack a `depends_on`
    module is rejected. Removing a module that another installed module depends on
    is rejected. M2 ships three modules: `power_cell_rack` (supplies power, emits
    heat), `work_station` (draws power, depends on power), `sustainment`
    (draws power and water, depends on power). Their `emits` lists are carried and
    validated but nothing reads them until M8.
11. **Power and heat are resolved through the stat resolver.** A structure's
    available power and heat headroom are stats (`structure.power_available`,
    `structure.heat_headroom`) with the container's budget as base and each
    installed module contributing `stat.add` modifiers from source
    `&"module:<instance_id>"`. Removing a module restores the exact prior value,
    which the M1 resolver invariants already guarantee. No second budget code path.
12. **Building on land you do not own is a violation, not a special case** (design
    doc §8.4). There is no no-build volume system; `structure.place` and
    `module.install` fail through claim 6. A named test places the container on the
    neighbour's parcel, sees the rejection and the event, transfers the parcel with
    `land.transfer`, and places it successfully.

### Save and load (`sim/core/`, `sim/assembly.gd`)

13. **The save is `world seed + overlay`** (design doc §5.6). `SaveFile`
    (`sim/core/save_file.gd`) serialises `{schema_version: 1, seed, tick, rng_state,
    inbox, dispatched, rejected, content_digest, systems: {...}}` to JSON text with
    canonical key order, and parses it back through the same untrusted-input
    discipline as `ReplayFixture` (exact key sets, types, ranges, unknown schema
    version rejected, a `content_digest` that does not match the loaded content
    rejected with a message). This closes G1 debt 6: tick, RNG state, inbox and the
    dispatch counters are restored, so `load(save(sim)).state_hash() ==
    sim.state_hash()`.
14. **Round trip is a property.** For 10 000 generated sims (random seed, random
    tick count, random command streams over every M1 and M2 command kind, random
    parcel sets), `load(save(state))` hashes equal to `state`, and stepping both
    another N ticks with the same commands keeps them equal. This is "the single most
    valuable property test in the project" (standards §3.2) and is the second proof
    G2 names.
15. **Saves are small.** The overlay for the M2 fixture is under 64 KiB; a test
    asserts the bound so a future full-snapshot regression is caught. Chunk deltas
    (terrain edits) are M7 and are not in this schema; the schema carries a version
    so adding them is additive.
16. **Hostile saves fail cleanly.** A fuzz corpus `tests/fuzz/save_file/` (empty,
    truncated, wrong versions, wrong digest, overflowing ids, duplicate parcel ids,
    overlapping parcels, a module on a socket that does not exist) plus 10 000 random
    mutations per run: never a crash, never a partially loaded sim, always a message.

### Command ownership (`sim/agents/`, all command handlers)

17. **A command names the actor issuing it, and the sim checks the actor exists.**
    Every M1 and M2 command with an `actor` field rejects an id that is not a live
    actor (closes G1 debt 5 for existence; tying a command to *the player's* actor is
    the client-authority work of co-op and stays in debt 4). Land rights are then
    checked against that actor.

### Steam Cloud file set (`docs/steam-cloud.md`)

18. **The sync file set is defined at M2** (standards §8.5): one save slot per
    world, `user://saves/<slot>/world.json` (the save from claim 13) plus
    `user://saves/<slot>/meta.json` (seed, tick, wall-clock last played, game
    version, content digest, save schema version), and nothing else. Conflict
    handling is explicit: on two differing `world.json` for one slot, both are kept
    and the client offers the choice; the sim never picks. The document also lists
    what is deliberately not synced (settings are; replay recordings and telemetry
    are not). No Steam API is called at M2; the file layout is what GodotSteam's
    cloud config at M5 points at.

### Content, tooling, client

19. **Every new content kind has a schema** (`district`, `parcel`, `structure`,
    `module`) in `tools/content_schemas/`, validated at build. Module `depends_on`
    must name module ids that exist (cross-reference check at `ContentDb`
    validation, the same place M1 checks routing entries).
20. **The client shows the plot and the budget, and writes nothing.** A top-down
    debug view of the parcels around the player with the owner colour, the container
    footprint, its sockets and installed modules, and a text panel with the resolved
    power and heat numbers. Input: move the cursor, place the container, install and
    remove the three modules, transfer the neighbouring parcel. Every action is a
    submitted command; every number on screen is read from the sim.
21. **Replay fixtures exercise the new systems.** `tests/replay/m2-starter-plot.json`:
    place the container, install power then work station then sustainment, attempt a
    fourth install over budget (rejected), remove and reinstall, attempt to place on
    the neighbour (rejected, one violation event), transfer, place. Recorded hash;
    CI replays it with the M0 and M1 fixtures. `tests/replay/m2-save-mid-run.json`
    is the same run saved at tick 200 and resumed, hashing equal at the end.

## Out of scope (goes to the debt log if touched)

Heat, notoriety, wealth, signals and suspicion (M8); purchase prices and the economy;
police or any response; structural support propagation and snap sockets for building
pieces (M3); the portal graph (M3); terrain, chunks, digging as terrain modification
(M7, only the rights answer exists at M2); more than one structure kind; module
behaviour beyond budget accounting (a work station does no work); water as anything
but a budget number; the device shell (M5); Steam API calls (M5); procedural parcels
attached to route graph nodes (M7); any performance number.

## Assumptions to record in the gate

- Positions are integer millimetres. The design doc uses feet for the plot; content
  stores millimetres and the 2 ft socket pitch is rounded to 610 mm. Alternative
  rejected: floats, for the same reason as M1's milli-unit stats.
- The parcel index is a flat grid of bounding-box buckets, sized from content at
  assembly. A quadtree is not justified by two uses (standards §1 principle 6).
- `land.transfer` is debug-class at M2, like `actor.spawn`. Recorded alongside G1
  debt 4 and gated with it before co-op.
- The starter plot's vertical extent (−3 m, +9 m) is a placeholder for level design.
- Districts are content at M2 because only authored districts exist; the generated
  district records of design doc §7.2 arrive with M7 and use the same schema.

## Extension exercise for Q4 (standards §11, G2)

Add a fourth module (`content/module/<id>.json`) with a `depends_on` on the work
station and a non-zero `water_in`, and a third district with a stricter non-owner
rights table, using only new files under `content/`; `tools/test.sh` passes and the
diff under `sim/` is empty. `docs/extending-land.md` and
`docs/extending-modules.md` record the procedure; the performed instances are
committed.

## Fixtures and property seeds

| Test | Cases | Fixed seed constant |
|---|---|---|
| `rights_at()` totality and parcel exclusivity | 10 000 each | `tests/land/test_land_system.gd` |
| Parcel overlap rejection over generated sets | 10 000 | `tests/land/test_parcel_index.gd` |
| Module budget: install/remove sequences never exceed budget, removal restores headroom exactly | 10 000 | `tests/land/test_module_budget.gd` |
| Save round trip, then N more ticks stay equal | 10 000 | `tests/sim/test_save_file.gd` |
| Save file fuzz | corpus + 10 000 mutations | `tests/fuzz/save_file/` |
| Command payload fuzz, every new kind | corpus + 10 000 mutations | `tests/fuzz/commands/` |

A failing seed is committed as a named regression case (standards §3.2).
