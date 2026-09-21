# G4 — M4 Perception AI: gate evidence package

Milestone: M4 — Perception AI (design doc §16; standards §11 row G4;
`docs/specs/M4-perception-ai.md`, approved 2026-09-21 with ADR-004 and ADR-008 as A)
Submitted: 2026-09-21 by Claude Code, on branch `m4-perception-ai` (PR #6),
commits `e8e9f1a` … the package commit
Outcome: _pending review_ — **needs the G4 Deck feel run from CEOGG (§7); every
number in §2 is from the approver's own Deck, plugged, so only the battery profile
and the hand-played feel notes are outstanding**

---

## 1. Specification

See the spec. Eighteen claims; all implemented. Deviations recorded in §4: four
content fields the spec did not name (the formulae it left open), an investigation
minimum, the corridor and windows of the building moved to close sightlines the
fixtures found, advance and flank gated on an alert, and the M1 range demo left on
wall time.

| Claims | Delivered by | Commit |
|---|---|---|
| 1–5 perception: profiles, awareness, sight, noise, memory | `sim/agents/perception_system.gd`, `perception_profile` / `agent_profile` content and schemas, the `noise` weapon stat | `e8e9f1a` |
| 6 aim cone as a resolver modifier | `sim/agents/aim_system.gd`, `aim_profile` content | `8f6c2c7` |
| 7 a shot at an unseen target is a `no_los` miss | `sim/items/combat_system.gd` (a sight check installed at assembly) | `c1c6390` |
| 8 stress and morale | `sim/agents/stress_system.gd`, `stress_profile` content | `8db394c` |
| 9 budgeted cell pathing, walked through the movement rules | `sim/agents/pathing_system.gd` | `7dec2d3` |
| 10 stances: utility, hysteresis, time-sliced, executed | `sim/agents/stance_system.gd`, `stance` and `patrol_route` content | `808c426` |
| 11 squads: radio reports, entry edges | `sim/agents/squad_system.gd` | `e9e93df` |
| 12 arcade is the same AI retuned | `content/agent_profile/guard_arcade.json` and its three profiles; the `m4-arcade` fixture | `e8e9f1a` … `e2dfe2a` |
| 13 the agent budget measured on the Deck; frame capture; the soak | `tools/bench_agents.gd`, `--capture` and `--demo-loop` in `client/world_view.gd`; §2 | this package |
| 14 the building and its fixtures | `client/m4_building.gd`, `tools/make_m4_fixtures.gd`, six `tests/replay/m4-*.json`, `tests/sim/test_m4_fixtures.gd`, `tests/agents/test_m4_building.gd` | `b111fe4`, `e2dfe2a` |
| 15 save round trip with agents in the stream | `tests/sim/test_save_file.gd` (agent, build, raid and move commands in the generated stream) | this package |
| 16 schemas | six new schemas; every reference checked at build, every stance's scorer at assembly | `e8e9f1a` … `808c426` |
| 17 commands and corpus | `agent.spawn`, `agent.set_profile`; 19 new hostile cases (110 total) | `e8e9f1a` |
| 18 client | `client/world_view.gd`: the building, four armed guards, stance colours, facing, awareness bar, sight line, last-known marker, D-pad profile swap and overlay toggle, Back restarts | `b111fe4` |
| Q4 extension exercise | `content/agent_profile/sentry_drone.json` with its three profiles, `content/patrol_route/street_sweep.json`, `tests/agents/test_extension_agents.gd`, `docs/extending-agents.md` | this package |

## 2. Verification report

Produced **on the approver's Steam Deck** (SteamOS, AMD Custom APU 0932, Godot
4.6.1-stable, plugged in, desktop mode), except where a line says container.
Reproduce with `tools/test.sh`, `tools/bench_agents.gd` and the soak command in §3.

### Fitness functions

| Check | Result |
|---|---|
| Python tool tests | 37 tests, OK |
| `tools/check_dependencies.py` | clean |
| `tools/validate_content.py` | clean: 106 content entries across 26 kinds |

### Static analysis

Every `.gd` file passes `--check-only` with warnings as errors.

### Headless test suite

| Suite | Tests | What it proves |
|---|---|---|
| `tests/agents/test_perception_system.gd` | 13 | spawn and profile contracts; the recorded time to alert (32 ticks sim, 12 arcade, at rest at 10 m); range, cone and movement gains; walls, doors, windows and solids; **10 000-case line-of-sight property against a sampled oracle** (symmetric, never through a wall, always across empty cells); **10 000-case gain monotonicity**; **150-case full-sim metamorphic: reduced perception never alerts sooner**; noise, memory, squads are not contacts; restore |
| `tests/agents/test_aim_and_stress.gd` | 11 | cone arithmetic; settle, break and swing with recorded hit chances; a swing outlives a break; target switching; **10 000-case cone relations**; **60 generated profiles in the sim: exposure never lowers hit chance, a break never raises it**; stress gains and squad scoping, decay, thresholds, the resolver path; **10 000-case penalty monotonicity**; restore |
| `tests/agents/test_sight_check.gd` | 3 | a shot through a wall is a `no_los` miss that still makes noise; an agent must see, not merely have a line; the reason survives the round trip and is validated |
| `tests/agents/test_agent_pathing.gd` | 4 | door versus wall with a live re-plan when the doorway is bricked; budget accounting and a walled-in goal; **10 000-case property against a breadth-first oracle** (paths legal, exist exactly when joined); save round trips mid-search and mid-walk |
| `tests/agents/test_stance_scoring.gd` | 9 | registry and assembly refusal; patrol loop; detection delay and the command path (33 ticks at rest at 10 m); investigate then forget; broken retreat, routed surrender; hysteresis; **10 000-case choice property** (always allowed, routed never advances, minimum duration); time slicing; restore |
| `tests/agents/test_squad.gd` | 4 | latency and radio gating, the echo, another squad unaffected; **120-case metamorphic: no radio never alerts sooner, more members never slow the others**; the planner's distinct entries; restore mid-flight |
| `tests/agents/test_m4_building.gd` | 2 | the building raises with no rejection, every piece supported, two volumes; guards' routes walkable with no blocked step; sight through doors and windows, not walls; no line from the wing to the street |
| `tests/sim/test_m4_fixtures.gd` | 5 | the six fixtures replayed tick by tick: see "Recorded numbers" |
| `tests/agents/test_extension_agents.gd` | 2 | every agent profile spawns with all three profiles and scorers; every route takes an agent; the reduced-perception relation holds for every profile |
| M0–M3 suites | 156 | unchanged claims; `test_save_file.gd`'s stream gained agents, build, raid and move; `test_sim_assembly.gd` knows the six new systems |
| **Total** | **211 tests, 0 failed** | `check_test_log: clean` |

### Replay determinism

Thirteen fixtures replayed in two processes each, identical and equal to the
recorded hashes. Every M0–M3 hash moved with each new system in the snapshot and
with the new content in the digest; every move is in the commit that caused it.

### Recorded numbers

| Number | Value | Where |
|---|---|---|
| `time_to_first_shot`, sim guard, contact at rest at 10 m in the open | 33 ticks (0.825 s): alerted on the 32nd tick of sight, the shot lands on the 33rd | `test_stance_scoring.gd` |
| `time_to_first_shot`, sim guard, walking contact seen through the door at 15 m | 25 ticks: alerted after 24, the shot the tick after | `m4-detect` |
| `time_to_first_shot`, arcade guard, the same walk | 11 ticks | `m4-arcade` |
| radio latency, sim / arcade | 20 / 4 ticks, exact | `m4-radio`, `m4-arcade` |
| a glimpse (awareness peak 39 %) | investigated and forgotten, no shot | `m4-break-contact` |
| a shot through a wall | heard by all four, walked toward, nobody alerted | `m4-noise` |
| without a radio | the wing never learns (awareness stays 0) | `m4-radio-off` |

### The agent budget on the Deck (claim 13)

`tools/bench_agents.gd`, 12 000 ticks, the building with **six** armed guards
firing at a target they cannot kill, a wall placed or removed every 400 ticks;
headless, plugged. Sim time per tick in microseconds; the 1 % and 0.1 % lows of a
25 ms frame are the 99th and 99.9th percentiles.

| Run | mean | p50 | p99 | p99.9 | max |
|---|---|---|---|---|---|
| six guards | 1 073 | 1 038 | 1 418 | 12 695 | 15 203 |
| no guards | 39 | 12 | 20 | 11 441 | 12 657 |
| **agent row** (difference) | | **1.03 ms** | **1.40 ms** | | |
| rebuild ticks (30 of 12 000), six guards | | 15 085 | | | 22 943 |

The agent row of §4.1 (3.0 ms) holds with two times headroom at six agents in
GDScript; the first measurement was 3.4 / 5.3 ms, cut by caching visibility per
tick (the aim and stance layers were re-walking every line of sight) and a
coarse-then-fine facing search, with every fixture hash unchanged. The p99.9 is
the rebuild ticks: the navigation row (1.5 ms) is **exceeded ten times over on the
tick a piece is placed or removed** at 93 pieces. That is the G3 debt item 2 dirty
set, now demanded by a Deck measurement (§4, item 7). Capture:
`tests/out/bench-plugged.json`.

### Thermal soak (standards §4.2)

The export's demo looped for 30 minutes on the Deck, plugged, in desktop mode at
1280×800, frame times captured; the final five minutes reported. _Filled in below
from `soak-plugged.json`._

| Window | frames | mean | p50 | p99 (1 % low) | p99.9 (0.1 % low) | max |
|---|---|---|---|---|---|---|
| all 30 minutes (149 demo loops) | 129 988 | 14.16 ms | 14.08 ms | 15.63 ms (64.0 fps) | 198.9 ms (5.0 fps) | 223.9 ms |
| **final five minutes** | 21 595 | 13.89 ms | 13.89 ms | **14.58 ms (68.6 fps)** | **25.0 ms (40.0 fps)** | 223.9 ms |

No thermal degradation: the final five minutes are marginally faster than the
whole. The 0.1 % low sits exactly on the 40 fps target in the final window; the
whole-run p99.9 of 199 ms is the demo's restart, when the building's 93 pieces are
raised in one tick with a portal-graph rebuild each (§4, item 7): once per loop,
never in play. Capture: `docs/gates/captures/M4-soak-plugged.json`; the bench:
`docs/gates/captures/M4-bench-plugged.json`.

### Fuzz corpora

`tests/fuzz/commands/hostile_payloads.json`: 110 cases (19 new for `agent.*`).
The fuzz targets of standards §3.5 for the new parsers are the property tests
(line of sight, pathing, stance choice); no failing seed was found, so no case was
added.

### Screenshots

- `docs/gates/screenshots/M4-world.png`: the grey-box world at 5 s into the demo, captured on the Deck itself (`--screenshot`, Vulkan; the Deck has no Xvfb for `tools/screenshot.sh`):
  the player down in the doorway after walking straight in, the post and the
  roamer in green (hold again, the contact gone) with the post's sight line to the
  body, the two patrollers in orange (advance) coming from the wing on the radio
  report, the lobby's side windows in blue, the HUD's guard lines with stress at
  35 % on the post the player shot.

## 3. Demo script

Steps 1–4 on any Linux x86_64 machine; steps 5–14 on the Deck from
`tools/export.sh`'s build, sideloaded or added to the Steam client as a non-store game.

1. `tools/test.sh` → `211 tests, … 0 failed`, thirteen `ok` replay lines, `all stages passed`.
2. `git show --stat <extension commit>` → four content files, one route, one test, one
   doc; nothing under `sim/`, `client/` or `tools/` (Q4).
3. Set `gain_per_tick` in `content/perception_profile/guard_sim.json` to 62500;
   `tools/test.sh unit` → the recorded-tick tests fail (alerted on the 16th tick), the
   metamorphic tests still pass, and every fixture hash moves. Revert.
4. `$(tools/godot.sh) --headless --path . -s tools/bench_agents.gd` → JSON as in §2.
5. Launch. → Third-person view on the street; the building ahead, its door orange,
   its side windows blue. Four capsules inside: green (hold) and, as they walk,
   noses turning the way they look. A green bar over each guard's head.
6. Walk up the street toward the door. → The bar over the post behind the door
   fills as it notices you, turns red when it is alerted, and a red line joins it to
   you. About 0.8 s later it fires: `last shot by #95` in the HUD. The other guards'
   bars turn red 0.5 s later (the radio) and they come: orange capsules.
7. Step back behind the wall before the bar fills. → The bar drains; a yellow marker
   appears where you were last seen; the post turns yellow (investigate) and walks
   out to that marker, looks, and goes back (green).
8. From behind a wall, fire at a guard you cannot see (`no target in the aim cone`
   means none is in the camera's cone; aim through the wall at one). → `last shot:
   no line of sight`; every guard's bar rises; all four turn yellow and walk toward
   where you fired from.
9. Shoot a guard three times. → It drops to a dark slab; its squadmates' stress
   rises (the HUD's `stress` column); a guard at 60 % stress turns blue (retreat)
   and backs off while still facing you; at 90 % it turns white (surrender) if you
   are close, and stands.
10. D-pad up. → `guards now guard_arcade`; repeat step 6: the bar fills in a third
    of the time and the shot comes in 0.3 s.
11. D-pad down. → The bars, lines and markers vanish; the capsules keep their
    colours.
12. Back. → A fresh sim on the street, no relaunch.
13. F5, quit, relaunch, F9 → the guards, their stances, awareness and paths return.
14. Write the feel notes (§7): the numbers to move are all content:
    `content/perception_profile/` (detection delay), `content/aim_profile/` (how fast
    a guard settles, how wide it starts), `content/stress_profile/` (when it breaks),
    `content/combat_profile/guard.json` (walking pace), `content/ammo/` (damage).

## 4. Debt and deviation log

| # | Item | Kind | Scheduled |
|---|---|---|---|
| 1 | Four content fields the spec left open: `hearing_gain` (perception), `penalty_per_mdeg` (aim: the cone-to-hit-chance formula), `hit_penalty_at_max` (stress), and `radio` / `radio_latency_ticks` live on the agent profile as named. | deviation, closed | none |
| 2 | `INVESTIGATE_MIN` (200 000): a remembered contact below that awareness is a flicker and starts no investigation; once started, an investigation finishes on memory alone. Advance and flank need an alerted contact. Without these, guards left their posts for a two-tick glimpse and abandoned a walk when awareness faded. | strengthening | none |
| 3 | The building's windows are in the lobby's side walls and the corridor is two cells off the door's axis, because the fixtures showed patrollers at the corridor mouth looking straight down it to the street and the roamer glimpsing the far street through a street-side window. The spec's building text names no layout. | deviation, closed | none |
| 4 | Doors have no open or closed state (M3): a door passes sight and movement. Locks and closed doors arrive with §9.1 sensors. | scope | M8 |
| 5 | Windows are passable to movement in the M3 piece data, so agents can path through a window. The spec says windows block movement. A content change to `content/piece_kind/window.json` (`passable: false`) would make them sight-only, but then the portal graph prices them as breaches, which M3's fixtures assume otherwise. | content question | M6, before the authored building |
| 6 | Pathing is bounded to `SEARCH_RADIUS` (32 cells) around the agent; the spec's portal-graph handoff for larger sites is not built. An M4 building fits; "Cold Storage" decides. | scope | M6 |
| 7 | The portal graph rebuild costs 11–15 ms on the Deck at 93 pieces (§2), over the navigation row on the tick of a build change, and raising the whole building in one tick (the demo's restart) is a 200 ms hitch. G3 debt item 2's dirty set is now demanded by measurement; a batched raise (one rebuild per tick, not per piece) is the same item. | performance | M6, before authored buildings; G6 |
| 8 | A guard's `weapon.fire` submitted for the next tick at a target another guard kills on that tick is rejected by the sim: one sim-internal rejected command per such race. Harmless; the counter no longer means "the client misbehaved". | strengthening | M6 |
| 9 | Lighting is not modelled (assumption recorded in the spec): exposure is distance, cone and movement only. | assumption | M6/M7 |
| 10 | The player has no aim or stress profile; only agents carry cones and morale. | assumption | M6 |
| 11 | The stance scorers read `in_cover` but none uses it yet; the flank goal is geometric (beside the contact), not a portal edge. Squad entries only exist for a contact inside an enclosed volume (the roofless lobby is exterior). | scope | M6 |
| 12 | The battery power profile was not measured: the approver's Deck was on charge for every run. The plugged numbers are in §2; the battery run is the §7 Deck run's first item. | external | G4 review |
| 13 | The M1 range demo (`client/main.gd`) still runs on wall time (G3 debt 8); not touched, since M4's client work was the world view. | residue | M5 |
| 14 | `time_to_first_shot` is recorded twice: at rest at 10 m in the open (33 ticks, the spec's definition) and on the fixture's walking contact seen through a door (25 ticks). Both are tests. | note | none |
| 15 | The soak ran while the headless unit suite ran on other cores for its first minutes; the reported final five minutes were undisturbed. | note | none |
| 16 | Mutation testing not run; target G6. | scope | G6 |

## 5. The four standing questions

**Q1 — Does it function?** Yes, on the Deck: 211 tests, seven 10 000-case
properties and three full-sim metamorphic suites for the new systems, six fixtures
reproduced across processes with their timings asserted, the agent budget measured
at 1.0 / 1.4 ms for six guards, the soak in §2. The hand-played feel run is
outstanding.

**Q2 — Is it secure?** New untrusted inputs are six content kinds (schema-checked at
build; references, scorers and routes checked at assembly) and two command kinds
(exact payloads, ranges, existence; 19 corpus cases). Every new system validates its
restore and leaves its state untouched on refusal; a search in progress and a report
in flight survive the round trip. No new dependency.

**Q3 — Is it complete?** Every claim is delivered; no stubs or `TODO`s; every refusal
returns an `Error` or a false with the state untouched. Debt items are scheduled.

**Q4 — Is it expandable?** Performed: the extension commit adds a sentry drone (its
own perception, aim and stress, a two-stance list, an instant radio) and a second
patrol route with zero changes under `sim/`, `client/` or `tools/`; the walking test
spawns every profile and holds the reduced-perception relation on each.
`docs/extending-agents.md` records the procedure.

## 6. Sign-off

Approver: CEOGG
Date:
Outcome: ☐ Accepted   ☐ Accepted with conditions (list below)   ☐ Rejected
Conditions:

## 7. Deck run and feel notes (P5) — to be filled by CEOGG

Build: `tools/export.sh` output, installed via: ☐ sideload  ☐ Steam client (non-store)
Date:                    Battery / plugged:

| # | What felt wrong or right | Number changed (file, value) or debt item |
|---|---|---|
| 1 | | |
| 2 | | |
| 3 | | |
