# G7 — M7 "Route graph and procedural wilds": gate evidence package

Milestone: M7 — the route graph and the procedural wilds (design doc §6, §16;
standards §11 row G7; `docs/specs/M7-route-graph-procgen.md`, approved 2026-09-23
with ADR-003 as B and ADR-010 as B)
Submitted: {{DATE}} by Claude Code, on branch `m7-procgen`, commits `763ea52` … the
package commit
Outcome: **Draft — not yet submitted** (waiting on the mutation score; see docs/handoff.md)

---

## 1. Specification

See the spec. Eighteen claims; all implemented. Claim 10 was reordered by CEOGG
(2026-09-24) to land after claims 11–14, and the regions design note (claims 13–15)
was approved before any of it was written.

| Claims | Delivered by | Commit |
|---|---|---|
| 1 the graph comes first | `sim/world/route_graph.gd` (`routes`), generated from the seed alone at assembly | `763ea52` |
| 2 the same seed is the same world | `RouteGraph.world_hash()`, SHA-256 over the canonical graph; 10 000-seed property, no collisions | `064973d` |
| 3 connectivity by construction | `everywhere_is_reachable`, `narrowest_edge_mm`; 10 000-seed property | `2f58b8b` |
| 4 macro distance is a query | `distance_mm_between` (millimetres are the primitive, metres its reading — §4 item 1) | `dd742e2` |
| 5 site slots from generation | slots with biome and distance; tags are a *reading* over a slot from `content/site_tag/` (§4 item 2) | `51f38e5` |
| 6 settlements are kits | `sim/world/settlement_kits.gd`, `content/settlement/waystation.json`, sockets, blocks, validated at assembly | `2caaf95` |
| 7 terrain is a consumer | `sim/world/terrain.gd`: cuttings, tunnels, bridges; every edge traversable, 10 000 seeds | `1e4701e` |
| 8 a quest names a handle | the quest `site` block, `SiteConstraint` | `5614476` |
| 9 binding is deterministic and permanent | `sim/quests/site_binder.gd` (`bindings`), `RouteGraph.stitch_slot`; 10 000 bindings | `80f33a5`, `7c65491` |
| 10 Cold Storage is a bound site | the contract binds a slot 0–3 km out; the operator raises the building there; the four M6 fixtures walk out through the gate to it. The client's `--mission` did not until late (§4 item 4): it now takes the contract first, and its demo walks out through the gate, down the road and round the lot before the break-in | `feaf112`, `9ff7337`, {{CCLIENT}} |
| 11 an off-screen agent is a token | `sim/agents/macro_token_system.gd` (`tokens`), `token.spawn`; `advance(N) == N × advance(1)` | `d622f45` |
| 12 hydration is a round trip | `sim/agents/hydration_system.gd` (`hydration`), the travel stance, actor removal purged from every module; ADR-010's metamorphic property over 10 000 visits | `7e6f8d1` … `9ce2816` |
| 13 one rule for both region types | `Region` / `AuthoredRegion` / `WildRegion` behind `Regions`; `check_dependencies` rule 5 | `07ef765`, `0f11706` |
| 14 the seam | `region.enter` with an 80-tick load window; squads take the gate by dehydrating | `7b00128` |
| 15 seed plus overlay | `ground.dig` / `ground.fill` as chunk deltas, `Discovery`, save schema 2 with a migration from 1 | `7b00128` |
| 16 the client shows the graph | the map app draws the graph, bound sites and the player; the world view streams wild ground (`native/terrain_mesher`, proposed — §6) and the gate | `f063d1f`, `db245b4`, `22f2318` |
| 17 four fixtures | `tools/make_m7_fixtures.gd`, `tests/replay/m7-{graph,bind,hydrate,seam}.json`, `tests/sim/test_m7_fixtures.gd` | {{C17}} |
| 18 schemas, corpus, mutation | `site_tag`, `settlement`, `region` schemas and the quest `site` block; every new command kind in the hostile corpus; mutation **{{SCORE}} %** against a 75 % bar | across the branch, {{C18}} |
| ADR-003 condition 2 | the worst-frame trace (`docs/specs/spike-surface-nets-deck-results/worst-frame-trace.md`) and pooled mesh nodes in the streamer; done late, before claim 16 | `9a2f86b`, `22f2318` |
| Q4 extension exercise | `content/settlement/mining_camp.json`, `content/site_tag/extraction.json`, `content/quest/claim_jumpers.json`; **the diff under `sim/` is empty** | {{CQ4}} |

## 2. Verification report

{{WHERE — desktop Deck in desktop mode; the Deck run is §7}}

### Fitness functions, static analysis, tests, replay

```
tools/test.sh
{{SUITE OUTPUT}}
```

### Mutation score (claim 18)

{{MUTATION}}

The tool changed for this run. A mutant used to get a flat 600 s and a timeout
counted as a kill, but M7's metamorphic hydration property alone runs for about ten
minutes untouched, so every mutant in `sim/agents/hydration_system.gd` would have
been "killed" by the clock. A mutant now gets three times what its file's tests took
untouched, plus a minute, and a file whose tests fail untouched is reported as
unscored rather than scored.

### Frame times on the Deck (claim 16)

`--wilds` demo, walking out through the gate and down the road with the ground
streaming: `docs/gates/captures/M7-wilds-deck.json`, 1 % low 90 fps, 0.1 % low
55 fps. The streamer holds to 3 ms of meshing a frame; see §4 for the sim-side cost
of a cold column.

### What the four fixtures record (claim 17)

| Fixture | The run |
|---|---|
| `m7-graph` | the world alone, no commands: its hash is the route graph's world hash, re-generated every replay, and the test generates it again outside the sim and compares |
| `m7-bind` | `quest.accept cold_storage`: a slot is bound, a site node stitched onto the graph that the gate's road reaches, the contract active |
| `m7-hydrate` | the player walks through the gate onto the apron; a three-strong squad leaves the gate for the outskirts, comes in as agents at tick 1 000, walks 100+ m of road itself, and goes back to being a token at tick 5 240, all three in it |
| `m7-seam` | through the gate with its load window, 30 m down the road, a cell of ground dug out beside it (claim 15's overlay), back along the road and home through the gate |

Each is replayed a tick at a time and watched on the way, so the test asserts that
the squad really was loaded and the player really was in the wilds, not only where
they ended.

### Screenshots

`docs/gates/screenshots/M7-mission.png` — `--mission --demo` 45 s in: through the
gate and 182 m down the road in a cutting, on the way to where the contract bound
Cold Storage. `docs/gates/screenshots/M7-wilds.png` — the wild ground streamed around the player
south of the gate. `docs/gates/screenshots/M7-seam.png` — the gate posts and the
curtain during the load window.

## 3. Demo script

Steps 1–4 on any Linux x86_64 machine; the rest on the Deck.

1. `tools/test.sh` → `{{N}} tests, … 0 failed`, twenty-four `ok` replay lines,
   `all stages passed`.
2. `$(tools/godot.sh) --headless --path . -s tools/make_m7_fixtures.gd` → the four
   runs re-authored, the hydrate run printing `squad in at tick 1000, out at tick
   5240, 3 of 3 back`.
3. Delete `content/settlement/mining_camp.json`;
   `$(tools/godot.sh) --headless --path . -s tools/run_test_file.gd -- res://tests/world/test_world_extension.gd`
   → `a mining camp stands in one of 50 worlds` fails. Revert.
4. `python3 tools/mutate.py sim/world/discovery.gd --per-file 3` → a short pass.
5. Launch `--wilds`. → The city side of the gate. Walk south into the opening. → The
   curtain for the load window, then the wilds: streamed ground, the road cut into it.
6. View, R1 to Map. → The route graph, your position on it, the gate and the towns.
7. Relaunch `--mission`. → You are in town; the contract is already taken. View, R1
   to Map, select for the world page. → Where it was bound, somewhere 0–3 km out.
   Walk out through the gate and there. → Cold Storage on a levelled lot in the wilds.
8. `--mission --demo` → the whole run: out through the gate, down the road, round the
   lot and in under the building, scoring `seen 0, alarms 0, bodies 0, traces 0`.

## 4. Debt and deviation log

| # | Item | Kind | Scheduled |
|---|---|---|---|
| 1 | **Whole metres broke the triangle inequality** 351 times in 10 000: two truncations on one side lose up to 2 m the other side does not. Millimetres are the primitive; anything comparing distances asks in millimetres. | correction to claim 4 | closed |
| 2 | **Site tags are a reading, not a field.** Writing them in at generation would put content inside the world hash, and the Q4 exercise (a fifth tag as one file) would move every world. | design, claim 5 | closed |
| 3 | **A squad hydrating just past the gate stood its trailing members on the gate itself**, on the city side of the seam, behind its wall for good; the squad never dehydrated. Found authoring `m7-hydrate`. A token now hydrates only when its whole file is through (`HydrationSystem._file_is_through`), with a regression test. | correction to claim 12 | closed |
| 3a | **The client's `--mission` still raised Cold Storage in the city**, at its old authored base, and took the contract afterwards: the fixtures proved claim 10 and the game on the Deck did not show it. Found writing this package. It now binds first and raises at the bound slot; `--mission --demo` ran clean on two random worlds (bound 1 459 m and 1 230 m out; seen 0, alarms 0, bodies 0, traces 0, nothing refused). | correction to claim 10 | closed |
| 4 | **GDScript reference cycles are never freed.** `Regions` ↔ `BuildSystem` leaked ~0.26 MB a sim and the suite, which builds 20 000+, was killed for memory twice. One side now holds a method `Callable`; `test_a_sim_nobody_holds_is_freed_with_every_system` guards it. | defect | closed |
| 5 | **ADR-003 condition 2 was done late**: the worst-frame trace belonged before M7 and was done before claim 16. The stalls were the spike harness rescanning its own frames; one frame in 571 k over 25 ms, nothing of ours. | late | closed |
| 6 | **A cold wild column costs 1.3–2.7 ms in the sim** (`WildRegion._column` / `_near`), so a streaming frame can run to ~5 ms on desktop against its 3 ms allocation. | performance | M8 |
| 7 | **`undiscovered` saw nothing until claims 13–15**, and a bound site appeared on the map only as a graph node until claim 16. Both closed by the later claims. | ordering | closed |
| 8 | **Binding is per quest, not per actor**: two actors taking one contract share its place. Right for one player; co-op will need to decide. | scope | co-op |
| 9 | **The suite now takes {{TIME}}**, dominated by the M7 properties (hydration metamorphic ~10 min, the walk property ~8 min). | residue | M8 |
| 10 | **A new settlement kit moves every world** and so every fixture, and can move where a contract binds. The Q4 exercise did exactly that: M6's and M7's fixtures were regenerated, each checked for the run it is named for, then re-recorded. | note | none |
| 11 | **Mutation timeouts** — see §2; the tool change is in `tools/mutate.py` with tests. | tooling | closed |
| 12 | M6 debt 5 (mission items on the `ammo` kind), 6 (one-cell landing), 7 (`run.end` before `quest.turn_in`), 9 (no `assert_errors` helper), 13 (range demo on wall time) and the M4 building's missing way in (M6 debt 1) were scheduled for M7 and **were not done**: none is in the M7 spec, and CLAUDE.md keeps work outside the spec out of the milestone. | carried | M8 |
| 13 | The `gate` Steam branch line is still unmet (no app id). | external | with the app id |

## 5. The four standing questions

**Q1 — Does it function?** {{Q1}}

**Q2 — Is it secure?** New untrusted inputs: the `site_tag`, `settlement` and
`region` content kinds and the quest `site` block (schema-checked at build,
cross-referenced at assembly: a tag naming an unknown biome, a kit reaching past
200 m or with a block that cannot be reached, a constraint whose band is inverted —
each refused with a reason); the command kinds `token.spawn`, `region.enter`,
`ground.dig`, `ground.fill` and the `quest` field of `site.raise`, all with exact
payloads, bounds and reach checks and all in the hostile corpus; and the save at
schema 2, with a migration from 1 and a property that a version-1 save still loads.
One new binary dependency, `native/terrain_mesher` (Rust, godot crate `=0.5.5`,
Rust 1.98.0), **proposed** — §6.

**Q3 — Is it complete?** All eighteen claims are delivered with no stubs or `TODO`s
in a shipped path, and the Q4 exercise is performed. What was not done is §4 item 12.

**Q4 — Is it expandable?** Performed. A second settlement kit (`mining_camp`: a
weighbridge, a haul road to the pit head, and spoil heaps, bunkhouses and a washing
plant as optional blocks), a fifth site tag (`extraction`: rock and scrub, at a
place of its own or a fork) and a contract bound to it (`claim_jumpers`) are three
content files, and **the diff under `sim/` is empty**. Mining camps stand in
generated worlds with their roads stitched in, the tag is carried by exactly the
slots it describes, and accepting the contract binds one of them.
`docs/extending-world.md` records the procedure.

## 6. Sign-off

Approver: CEOGG

Date:

Outcome:

Conditions (if any):

**For CEOGG's decision with this gate:**

1. **`native/terrain_mesher`** — the ADR-003 spike's surface nets promoted as a Rust
   GDExtension, 130× the GDScript port it falls back to. Recorded as *proposed* in
   `docs/dependencies.md` and the M7 spec note; accept or reject it.
2. The Q4 content (`mining_camp`, `extraction`, `claim_jumpers`) stays in the game,
   or is kept as an exercise only.
3. The carried M6 debt (§4 item 12) goes to M8.

## 7. Deck run and feel notes

{{Deck run by CEOGG: steps 5–7 of §3, and whether the wilds feel like a place — the
spec's open point says that is M8's content pass, not M7's bar.}}
