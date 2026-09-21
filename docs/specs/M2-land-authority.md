# M2 — Land authority + starter plot: specification

Milestone M2 of `docs/gcity-design.md` §16, in the terms of that document. Written
before implementation (standards §2.1, §10.2).

**Preconditions.** G1 is accepted (2026-09-20). No ADR blocks M2; ADR-003 (volumetric
terrain, accepted) fixes the coordinate model below. ADR-005 (claimed base structure)
stays open and is not needed until M8.

**The claim of the milestone.** One spatial query answers every "may I?" in the game,
and the player's first base is a data-driven container on a parcel that query knows
about. Parcels, rights, the starter plot, one container, three modules sharing a power
budget (design doc §16). Proves §7.1 and §8.2. G2 additionally demands the
`rights_at()` totality property, the save round-trip property, and a defined Steam
Cloud file set (standards §11).

## Claims

### Land authority (`sim/land/`)

1. **One query.** `LandAuthority.rights_at(position: Vector3i, actor: int) -> int`
   returns a bit set over the five rights `{build, dig, enter, carry, loot}` (design
   doc §7.1). It is total: every position in the world resolves. A position inside no
   parcel resolves as the implicit wilderness parcel with no owner and the wilderness
   policy's permissive rights, through the same code path as any other parcel; there is
   no "unowned" branch anywhere else in the sim.
2. **Parcels are polygons with a vertical extent, never per-voxel ownership.** A parcel
   is `{id, district, polygon (integer XZ vertices, simple, ≥3), floor, ceiling, owner}`
   in world metres (1 m voxels, ADR-003). Point-in-parcel is an exact integer test
   (crossing number; boundary counts as inside). Parcels are indexed in a uniform grid
   of buckets; a lookup touches one bucket. Parcels never overlap in volume; a parcel
   that would overlap an existing one is rejected at registration with an `Error`.
3. **The three land invariants hold for all inputs** (standards §3.2), each as a
   property test over ≥10 000 generated cases: (a) `rights_at()` resolves for random
   positions across the full integer range, including far outside every parcel;
   (b) generated parcel sets never contain two parcels sharing a voxel (accepted sets
   are pairwise disjoint; every overlapping candidate is rejected); (c) a random point
   inside a parcel's polygon and vertical extent returns that parcel's owner and
   policy, and a point one voxel outside in any axis does not.
4. **Rights are data.** `content/rights_policy/<id>.json` maps the relation between
   the asking actor and the parcel's owner (`owner`, `same_faction`, `other`,
   `unowned`) to a set of rights. A `content/district/<id>.json` carries the design's
   record (`law_index`, `wealth_index`, `gang_control`, `informant_density`, design doc
   §7.2) plus the policy its parcels use; `response_time` is derived, not stored.
   Authored parcels are `content/parcel/<id>.json`. Owners are `{"kind": "none" |
   "actor" | "faction", "id"}`; factions are `content/faction/<id>.json`. Adding a
   district, a policy, a faction or a parcel is a file.
5. **Violations emit, they do not punish.** Any system that acts on land asks
   `rights_at()` first; a denied action is rejected as a command and emits
   `land.violation {actor, right, parcel, position}` on the event bus. Nothing at M2
   subscribes; heat and suspicion are M8 (design doc §7.1, §7.4).
6. **Commands are tied to a controller** (closes M1 debt item 5). `SimCommand` gains a
   `client` id (fixture schema stays at version 1; the field is optional and defaults to
   0, the local host). A `ControllerRegistry` in `sim/agents/` records which actors a
   client controls; every command that names an `actor` is rejected unless that client
   controls that actor. The local host controls the player; tests control whoever they
   spawn; a fixture's commands carry the client that issued them. `actor.spawn` and
   `item.spawn` remain debug-class (M1 debt item 4) and are unaffected.

### The starter plot and modules (`sim/items/`)

7. **The starter plot is content.** `content/parcel/starter_plot.json`: a 12 × 12 m
   parcel (the design's ~40 × 40 ft) with floor −4 m and ceiling +8 m in district
   `starter_ghetto`, owner `none` until granted. `land.grant {actor, parcel}` is a
   debug-class command that assigns ownership (purchase needs an economy: M6+). The
   range view grants the plot to the player at start through it.
8. **A structure is an item on a parcel.** `content/structure/<id>.json` describes a
   placeable chassis: footprint in metres, an interior grid (`cells_x × cells_z` of 2 ft
   / 0.6 m cells, independent of world voxels), `power_capacity` of its bus (0 for the
   bare container), `heat_capacity`. `structure.place {actor, structure, position,
   rotation}` requires `build` at every footprint voxel via `rights_at()` and no other
   structure there; `structure.remove` returns it to the inventory. One structure
   exists at M2: `container_20ft`, 6 × 2.4 m, a 9 × 3 interior grid.
9. **Modules are data** (design doc §8.2). `content/module/<id>.json` carries `footprint`
   (cells), `mass`, `power_draw` (negative is generation), `heat_output`, `water_in`,
   `water_out`, `depends_on` (module ids), `emits` (signal type ids, consumed at M8),
   plus the `stats` it contributes as an item. The starter catalogue ships as five
   files (Work Station, Power, Sustainment, Work & Repair, Drone Automation Station);
   the milestone proves three. `module.install {actor, structure, module, cell,
   rotation}` requires the module item in the actor's inventory, the actor's `build`
   right at the structure, a footprint inside the grid with no overlap, and every
   `depends_on` already installed; `module.remove` is the inverse and is rejected while
   another installed module depends on this one.
10. **A shared power and heat budget decides what runs.** After every install or
    removal the structure resolves its budget deterministically: generation is the sum
    of negative `power_draw`; modules are powered in install order until the draw would
    exceed generation, the rest are `unpowered`; the same in heat against
    `heat_capacity`. `module_state(structure, module)` reports `powered | unpowered |
    overheated`. Two invariants as ≥10 000-case properties: powered draw never exceeds
    generation, and installing then removing a module restores every other module's
    state exactly. Module counts are conserved like every other item (the M1 property
    extends to install/remove).

### Save and load (`sim/core/`)

11. **A save is seed plus overlay** (design doc §5.6). `SaveFile.write(sim) -> Dictionary`
    and `SaveFile.read(content, dict) -> SimRoot` cover the whole root: schema version,
    seed, tick, RNG state, dispatch counters, inbox, and every system's snapshot (which
    already are overlays: item placement, bases and modifiers, actors, parcels' owners,
    structures, progression). This closes M1 debt item 6. The document is JSON on disk,
    canonicalised through `JsonNumbers` on read, with a size bound.
12. **The round-trip property passes** (standards §3.2, "the single most valuable
    property test in the project"): for ≥10 000 generated states (random command
    sequences over the range, the plot, structures and modules, at random ticks with
    pending commands in the inbox), `read(write(sim)).state_hash() == sim.state_hash()`,
    and stepping both sims N further ticks keeps them equal. Hostile saves (a committed
    corpus under `tests/fuzz/save/` plus 10 000 mutations) are rejected with a message
    and never partially applied.
13. **The Steam Cloud file set is defined** (standards §8.5) in `docs/save-format.md`:
    `user://saves/slot_<n>.json` (the save), `user://saves/slot_<n>.meta.json` (schema
    version, tick, wall-clock write time supplied by the client, content digest,
    state hash, a 64 × 64 PNG thumbnail path), `user://profile.json` (settings, not
    synced). Conflict rule: when local and cloud metadata disagree, the client shows
    both with their tick and write time and asks; it never silently picks one. Steam
    integration itself is M5/G5; at M2 the client writes and reads this layout locally
    and the meta file is validated like the save.

### Content, tooling, client

14. **New content kinds are schema-validated at build**: `district`, `rights_policy`,
    `faction`, `parcel`, `structure`, `module`, with cross-references (parcel → district,
    district → policy, module `depends_on` → module, parcel owner → faction). Polygon
    simplicity and the no-overlap rule are checked by the sim at assembly (`LandAuthority.
    validate_content()`), because they need geometry the schema dialect cannot express.
15. **The client shows the plot and drives it, writing no state.** The range view gains
    a top-down plot map drawn from sim state: the parcel outline, the container and its
    grid, module footprints coloured by power state, the player's position marker, the
    rights at the cursor. Keys and Deck buttons move the cursor, place and remove the
    container, install and remove modules, grant the plot, save to and load from
    `slot_1`. The client rule in `tools/check_dependencies.py` continues to enforce
    submit-only access; `SaveFile.read` builds a new sim, which only the host may do,
    so loading is a host operation the view requests.
16. **Replay fixtures and corpus grow with the milestone**: `tests/replay/m2-plot.json`
    (grant, place, install three modules including one over budget, remove one, save
    round trip mid-fixture is asserted by the test, not the fixture) reproduces its hash
    across processes; `tests/fuzz/commands/hostile_payloads.json` gains cases for every
    new command kind; `tests/fuzz/save/` is the hostile save corpus.

## Out of scope (goes to the debt log if touched)

Buying parcels or any economy, procedurally generated parcels (M7), structural support
and the portal graph (M3), terrain digging beyond answering `dig` (M3/M7), signal
propagation, suspicion, heat and raids (M8), Steam Cloud synchronisation and GodotSteam
(M5/G5), water and mass simulation beyond storing the numbers, module behaviour of any
kind (a Work Station does nothing yet), doors, locks, more than one structure type, the
device shell (M5), any performance number.

## Assumptions to record in the gate

- World units are metres (ADR-003, the spike), so the design's ~40 × 40 ft plot is 12 × 12
  m and the container's 2 ft grid is 0.6 m cells on the structure's own interior grid.
  (The spike spec's "40 × 40 m" was a slip; this is the authoritative figure.)
- Polygons are simple integer polygons in XZ with a flat floor and ceiling. Sloped or
  stepped parcels are not needed until procgen.
- Ownership changes only through content and the debug-class `land.grant` until an
  economy exists.
- Budget resolution is by install order. A player-facing priority scheme is a device
  feature (M5).

## Extension exercise for Q4 (standards §6)

Add a second district with its own policy, a second parcel in it, a second faction that
owns it, and a sixth module that depends on Power, using only new files under
`content/`; `tools/test.sh` passes and the diff under `sim/` is empty. A name-agnostic
test walks every district/parcel/module the content holds. `docs/extending-land.md`
records the procedure.

## Fixtures and property seeds

| Test | Cases | File |
|---|---|---|
| `rights_at()` totality | 10 000 | `tests/land/test_land_authority.gd` |
| Parcel sets never overlap; inside returns owner, outside does not | 10 000 each | `tests/land/test_land_authority.gd` |
| Powered draw ≤ generation; install+remove restores states | 10 000 each | `tests/items/test_structure_system.gd` |
| Item conservation extended to install/remove | 10 000 | `tests/items/test_structure_system.gd` |
| Save round trip, incl. pending inbox, then N more ticks | 10 000 | `tests/sim/test_save_file.gd` |
| Hostile saves | corpus + 10 000 mutations | `tests/sim/test_save_file.gd`, `tests/fuzz/save/` |

A failing seed is committed as a named regression case (standards §3.2).
