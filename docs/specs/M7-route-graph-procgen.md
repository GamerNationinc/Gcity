# M7 — Route graph and procedural wilds: specification

Milestone M7 of `docs/gcity-design.md` §16, in the terms of that document. Written
before implementation (standards §2.1, §10.2). Status: **approved** as written (CEOGG, 2026-09-23); implementation on branch
`m7-procgen`.

**Preconditions.** G6 is signed (`docs/gates/M6-gate.md`, Accepted 2026-09-23).
**ADR-003** is accepted as **B**, volumetric voxels with surface nets, proven on the
Deck by the disposed spike (4.10 ms p99 plugged). **ADR-010** is accepted as **B**
(CEOGG, 2026-09-23): one uniform hydration rule for both region types — unloaded runs
on tokens and schedules, loaded runs fully. ADR-001 remains open and blocks nothing.

**The claim of the milestone.** The world stops being one authored building. The
route graph is generated first from the world seed and is *authoritative*: terrain,
settlements and sites are all consumers of it, so connectivity is true by construction
rather than something to test for afterwards. A quest stops naming a place and starts
naming a **handle**, which the director binds to a slot when the contract is accepted.
Off-screen life runs as tokens on that graph.

**What this milestone is not.** It is not "make the wilds look good". The G7 bar
(standards §11) is about the graph: connectivity across ten thousand seeds, the same
seed always producing the same world hash, and deterministic site binding. Terrain
meshing gets exactly as much attention as proving it never contradicts the graph.

**Size.** Comparable to M6 and, like it, ordered so each claim lands whole: the graph,
then what consumes it, then what lives on it, then the seam, then the client.

## Claims

### The route graph (`sim/world/`)

1. **The graph comes first and is authoritative.** `RouteGraph` (system id `routes`)
   generates from the world seed alone: nodes are city gates, settlements, points of
   interest and junctions; edges are corridors carrying a guaranteed traversable
   width in millimetres. Nothing in generation may place a node or edge by reading
   terrain, because terrain does not exist yet.
2. **The same seed is the same world.** `RouteGraph.world_hash()` is a SHA-256 over
   the canonical graph, and equal seeds give equal hashes across processes. Property
   over 10 000 seeds: generate twice in separate sims, hashes agree; and no two
   distinct seeds in the sample collide.
3. **Connectivity is true by construction.** Every node is reachable from every other
   by edges whose width is at least the widest agent's. Property over 10 000 seeds:
   the graph is connected, has no edge narrower than `MIN_WIDTH_MM`, and no duplicate
   or self edge. A seed that fails is committed as a named regression case.
4. **Macro distance is a query, not a walk.** `distance_between(a, b)` answers in
   metres over the graph with the world unloaded, for quest distance and response
   times (design doc §6.1). Property: the distance is symmetric, obeys the triangle
   inequality, and never exceeds the sum of the edges of any path the test can find.

### What the graph produces (`sim/world/`, `content/`)

5. **Site slots are emitted by generation, not chosen later.** Each is a candidate
   location with a position, a biome and tags from `content/site_tag/`
   (`industrial`, `agricultural`, `ruin`, `corp`), and a distance from the city gate.
   Slots are part of the world hash: the same seed offers the same slots.
6. **Settlements are prefab kits, not noise.** `content/settlement/` entries carry
   road sockets so a town snaps onto the graph as a subgraph, and a district record
   (§7.2) so its rights tables already exist. Seeded variation picks blocks, rotation
   and density; the kit's own navigation comes with it.
7. **Terrain is a consumer.** `sim/world/terrain.gd` answers "what is the ground at
   this position" from the seed, and where an edge crosses a ravine it emits a
   bridge, where it meets rock a pass or a tunnel. Property over 10 000 seeds:
   **every edge of the graph is traversable in the terrain it produced** — the
   generator may not make a corridor it then blocks.

### Binding, not generating (`sim/quests/`)

8. **A quest names a handle.** `content/quest/` gains an optional `site` block —
   constraints, not a place: `{tags_any, min_km, max_km, undiscovered}`. Accepting a
   contract with one binds a slot.
9. **Binding is deterministic and permanent.** `SiteBinder` picks the matching slot
   from the seed, writes the binding into the save overlay, and never re-picks it:
   the same save always has the same place. The bound site gains a graph node with
   its edges stitched in, and appears on the map. Property over 10 000 bindings: the
   same seed and constraints give the same slot, and a bound slot is never offered
   to a second binding.
10. **Cold Storage becomes a bound site.** The M6 mission keeps working, unchanged,
    with its authored building placed at a bound slot rather than at a fixed base
    cell. Its four fixtures are re-recorded and still record the same four runs.

### Life off-screen (`sim/agents/`, ADR-010 B)

11. **An off-screen agent is a token.** `{edge_id, progress, faction, payload}`,
    advanced on the graph with no navigation, no perception and no geometry.
    Property over 10 000 tick streams: a token never leaves its edge, progress is
    monotone within a leg, and a token that reaches a node either stops or continues
    onto exactly one edge.
12. **Hydration is a round trip.** A token within range becomes real entities at the
    world position its progress maps to, and dehydrates back when the player leaves.
    Metamorphic property, the one ADR-010 names: a district's macro state after N
    ticks unloaded equals its state after loading, ticking N, and unloading, for
    every quantity the macro model claims to track.
13. **One rule for both region types.** `Region` is the only thing the player
    controller, inventory, AI, quests and saving talk to; `AuthoredRegion` and
    `WildRegion` are behind it. `tools/check_dependencies.py` gains a rule: nothing
    outside `sim/world/` may name either implementation.

### The seam, the save, the client

14. **The transition is a designed seam**, with a load window: `region.enter
    {actor, region}` is refused unless the actor stands at a gate, and the sim keeps
    running on the far side through tokens.
15. **The save is seed plus overlay.** Bound sites, discovered nodes, terrain edits
    as chunk deltas, and everything M2–M6 already saved. Save schema goes to version
    2 with a migration from 1, and a property asserts a version-1 save still loads.
16. **The client shows the graph.** The map app draws the route graph, the bound
    sites and the player's own position on it; the world view renders a wild region
    around the player and the seam when they stand at one.

### Verification

17. **Fixtures**: `m7-graph.json` (a seed generated, hashed and re-generated),
    `m7-bind.json` (a contract accepted and a slot bound), `m7-hydrate.json` (a token
    hydrated, walked and dehydrated), `m7-seam.json` (a region entered and left).
18. **Schemas** for `site_tag`, `settlement`, `region`; the `quest` schema's `site`
    block. **Corpus** extended with every new command kind, and the two fitness
    checks from M6 keep that true. Mutation score **≥ 75 %** on `sim/` (M6 landed
    76.8 %; the bar rises rather than holds).

## Out of scope (goes to the debt log if touched)

Terrain art and materials beyond what proves claim 7; weather; vegetation; interiors
of procedural settlements beyond their kits; the threat director, raids and suspicion
(M8); drone control; dialogue; fast travel as a player action; and any second mission.

## Open points

- **The wilds are not a playground yet.** M7 proves the world is coherent, not that
  it is fun to walk across. If the G7 run wants "does it feel like a place", that is
  M8's content pass and should be said now rather than discovered at the gate.
- **Terrain cost on the Deck is the risk.** ADR-003's spike measured meshing at
  1.12 ms plugged for one chunk. A streamed region is many chunks; if the measured
  budget (§4.1) cannot hold at 40 fps, the fallback is fewer, larger chunks with a
  longer load window at the seam, recorded as a deviation.
- **Cold Storage moving is the one thing that can break M6.** Claim 10 is written to
  make that visible: if the mission cannot be placed at a bound slot without changing
  its content, the binding model is wrong, not the mission.

## Assumptions to record in the gate

- A "world" is one seed. Multiple worlds per save are not a thing at M7.
- The city is one authored region and remains the only one.
- Slot tags are content; the director's constraint language is not extended beyond
  the four fields in claim 8.
- Macro state is per district, not per agent, for anything the player has not met.

## Extension exercise for Q4 (standards §11, G7)

Add a second settlement kit and a fifth site tag using only new content files, and
bind a contract to it; `tools/test.sh` passes, the settlement appears on the graph
with its roads stitched, and the diff under `sim/` is empty.
`docs/extending-world.md` records the procedure.

## Fixtures and property seeds

| Test | Cases | File |
|---|---|---|
| Same seed, same world hash; no collisions in the sample | 10 000 seeds | `tests/world/test_route_graph.gd` |
| Connected, no narrow edge, no duplicate or self edge | 10 000 seeds | `tests/world/test_route_graph.gd` |
| Macro distance symmetric and obeys the triangle inequality | 10 000 | `tests/world/test_route_graph.gd` |
| Every edge traversable in the terrain it produced | 10 000 seeds | `tests/world/test_terrain.gd` |
| Binding deterministic; a slot is never bound twice | 10 000 | `tests/quests/test_site_binder.gd` |
| A token never leaves its edge; progress monotone | 10 000 streams | `tests/agents/test_tokens.gd` |
| Metamorphic: macro state unloaded == loaded, ticked, unloaded | 10 000 | `tests/agents/test_hydration.gd` |
| Save round trip at version 2, and a version-1 save still loads | 10 000 | `tests/sim/test_save_file.gd` (extended) |
| Command payload fuzz, every new kind | corpus + 10 000 | `tests/fuzz/` |
| Mutation score on `sim/` | every mutant | `tools/mutate.py` |

A failing seed is committed as a named regression case (standards §3.2).
