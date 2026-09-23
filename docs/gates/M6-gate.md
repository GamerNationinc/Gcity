# G6 — M6 "Cold Storage": gate evidence package

Milestone: M6 — "Cold Storage", the playable vertical slice (design doc §15–16;
standards §11 row G6; `docs/specs/M6-cold-storage.md`, approved 2026-09-22 with
ADR-007 as C)
Submitted: 2026-09-23 by Claude Code, on branch `m6-cold-storage` (PR #8),
commits `78b8939` … the package commit
Outcome: awaiting CEOGG; the Deck run goes in §7

---

## 1. Specification

See the spec. Sixteen claims; all implemented. Four of them were corrected after
they had already landed, because building the next claim proved the earlier one
wrong — each is in §4 with what went wrong and how it was found.

| Claims | Delivered by | Commit |
|---|---|---|
| 1 vertical movement | `sim/agents/movement_system.gd` (`dy`, standable cells, climbable faces, gravity, fall damage, `actor.fell`), `piece_kind.climb`, `combat_profile.fall_damage_per_level` | `78b8939` |
| 2 pathing across levels | the same rules under `sim/agents/pathing_system.gd`; the extended property in `tests/agents/test_agent_pathing.gd` | `78b8939` |
| 3 the site is content | `sim/world/site_system.gd`, `content/site/`, `site.raise`, `tools/make_sites.gd`; the M4 building converted to a site file | `0e4dae3` |
| 4 three routes in | `content/site/cold_storage.json`: a token-checked street door, a fire stair to a maintenance window, a tunnel under the slab entered by cutting a street grate. The lot, the street step and the guards' kit corrected it — §4 items 1, 2, 3 | `0e4dae3`, `fc108a8`, `e29357f`, `1b11f8b` |
| 5 the terminal and the hack | `sim/quests/terminal_system.gd`, `content/terminal/`, `terminal.hack_start` / `hack_cancel` / `wipe` | `9b0a8d3` |
| 6 the hacking pane | `client/device/apps/hacking_app.gd`: progress with the world running, because ADR-006 C forbids pausing on a site | `9b0a8d3` |
| 7 stealth scoring | `sim/quests/run_score_system.gd` (four counters, `run.begin` / `run.end`), `content/payout_curve/`. Breaches became a reading rather than a tally — §4 item 2 | `18108ca`, `fc108a8` |
| 8 three standing scalars | `sim/threat/standing_system.gd`, `content/standing_rule/`: heat, notoriety and visible wealth, raised by content rules and decayed at a district-scaled rate | `cc759c0` |
| 9 the contract pays | `actor.left_parcel` (movement), `currency` as an item kind, `quest.turn_in` with a `turn_in` block priced by the run's multiplier — three commits, one sim module each | `2cafee3`, `f9ef530`, `2f497e1` |
| 10 a dead actor leaves a corpse | `ActorSystem.actor.died`, `sim/agents/corpse_system.gd`, `corpse.loot`, `ItemSystem.move_container` | `43c7641` |
| 11 recovery softened by law | `actor.respawn`, `content/recovery_rule/police.json`, the fee taken from the money the station is holding | `76ec463` |
| 12 mutation testing | `tools/mutate.py`, `tools/run_test_file.gd`, 54 Python tests; §2 for the score | `ed9033f` |
| 13 the client shows the mission | `content/device_app/mission.json` and its pane (counters live, run summary, death screen); `--mission` raises Cold Storage and hands you the controls, `--mission --demo` plays the under route | `fd88c00`, `2615773`, `c67e17f` |
| 14 everything survives the round trip | the save property's stream and the hostile corpus are now **derived from `CommandRegistry.kinds()`**, so neither can fall behind again | `2f21e8e` |
| 15 four fixtures | `tools/make_m6_fixtures.gd`, `tests/replay/m6-{stealth,loud,death,side}.json`, `tests/sim/test_m6_fixtures.gd` | `e29357f` |
| 16 schemas and corpus | `site`, `terminal`, `standing_rule`, `payout_curve`, `currency`, `recovery_rule`; `piece_kind.climb` and `door_check`; `combat_profile.fall_damage_per_level`; 200 corpus cases | across the branch |
| Q4 extension exercise | **outstanding** — see §4 item 9 | — |

## 2. Verification report

Produced **on the approver's Steam Deck** (SteamOS, AMD Custom APU 0932, RADV
Vangogh, Godot 4.6.1-stable, plugged, desktop mode, 1280×800). Reproduce with
`tools/test.sh`, `tools/mutate.py` and the client's own flags.

### Fitness functions, static analysis, tests, replay

```
tools/test.sh
  == fitness functions       54 Python tests; check_dependencies clean; validate_content clean
  == script analysis         every .gd file, warnings as errors
  == headless tests          293 tests, 241 404 assertions, 0 failed
  == replay determinism      20 fixtures, each replayed twice and diffed
  == all stages passed
```

Ten 10 000-case properties now run per suite, including the three M6 adds:
scoring counters monotone and the multiplier monotone in each; standing rules
crediting only the actor their payload names with decay never below zero; and no
item created or destroyed by death, looting or the police return.

### Mutation score (claim 12)

`tools/mutate.py --json docs/gates/M6-mutation.json`, six mutants sampled per file
across `sim/`, each run against the tests that cover the file it mutates.

> **Score and surviving mutants: filled from the run before submission.**

A mutant that will not compile is reported as invalid and left out of the score.
The first sample counted two such as kills, which is why it is called out here: an
inflated mutation score is worse than none.

### Frame times on the Deck (claim 13)

`--mission --demo --capture=…`, 2 786 to 6 705 frames per run.

| | median | 1% low | 0.1% low |
|---|---|---|---|
| Cold Storage, as first written | 37.1 fps | 32.0 | 10.8 |
| pieces batched into multimeshes | 39.0 fps | 35.0 | 5.0 |
| **state hash cached** | **90.0 fps** | **88.0** | **51.1** |
| M4 building, for scale | 68.0 fps | 49.2 | 4.7 |

The site rendered at 37 fps, under the 40 fps floor. The first guess was wrong and
the measurement said so: batching 363 per-piece nodes into four multimeshes bought
two frames a second. The cost was the HUD drawing `state_hash()`, which snapshots
the whole world and runs SHA-256 over it, every frame — so the frame rate fell as
the site grew. Taken once a second instead, the mission runs faster than the older
and much smaller demo ever did. The scripted run scores identically at every step
of that change, so nothing about behaviour moved.

The 0.1% lows are the machine, not the build: the same ~225 ms worst frame appears
in the M4 capture, taken minutes apart, on a Deck with about 1.7 GB free.

### What the four fixtures record (claim 15)

| Fixture | The run |
|---|---|
| `m6-stealth` | in under the building, hack, wipe, put the grate back, hand it in. All four counters zero, no heat, the clean bonus, 2 400 credits |
| `m6-loud` | the wall beside a door with no token; seen 486 times, two guards down, the data taken anyway, paid at the curve's floor with heat raised |
| `m6-death` | killed mid-hack; the corpse holds the kit, the recovery run goes back in by the fire stair and takes all six items off its own body |
| `m6-side` | up the outside fire stair and in at the maintenance window: four level changes, nothing fell |

`tests/sim/test_m6_fixtures.gd` asks each one what happened in it. A fixture that
only reproduced a hash would prove determinism and nothing else.

### Screenshots

`docs/gates/screenshots/M6-mission.png` — the scripted stealth run mid-hack: the
HUD reading `M6 mission`, the player in the server room corner, 362 pieces standing
with the grate cut.

## 3. Demo script

Steps 1–4 on any Linux x86_64 machine; the rest on the Deck.

1. `tools/test.sh` → `293 tests, … 0 failed`, twenty `ok` replay lines,
   `all stages passed`.
2. `$(tools/godot.sh) --headless --path . -s tools/make_m6_fixtures.gd` → the four
   runs re-authored, each printing its counters. `tools/rerecord_hashes.sh` →
   `unchanged` for all twenty: the mission is deterministic across a re-author.
3. `python3 tools/mutate.py sim/quests --per-file 3` → a short pass, in about three
   minutes, printing each mutant killed, survived or invalid.
4. Open `content/site/cold_storage.json` and delete the `kit` from one spawn;
   `$(tools/godot.sh) --headless --path . -s tools/run_test_file.gd -- res://tests/world/test_site_system.gd`
   → `all four guards are armed` fails. Revert.
5. Launch `--mission`. → The street south of the cold store, the slab a metre up,
   the device in your pocket with a coprocessor in it and a pistol on your hip. You
   own nothing here.
6. Walk north and up the step onto the slab, then north again to the grate at the
   tunnel mouth. Press B on it. → The grate is cut. That is a breach and the mission
   pane will count it until you put it back.
7. Drop through and walk north up the tunnel, under the building. Climb the ladder.
   → The back hall. A guard walks the hall and the lobby; wait in the tunnel until
   it has gone south.
8. West through the door into the server room and stand at the terminal. Press View,
   R1 to Hacking, A. → The bar runs **with the world running**: the device cannot
   pause on somebody else's land (ADR-006 C). Lower the device and watch the hall.
9. When it completes, wipe the log from the same pane. → One trace gone.
10. Back out the way you came, and place a floor panel over the hole. → The mission
    pane's trace count returns to zero.
11. R1 to Mission while you walk. → The four counters, live, and what the curve
    currently makes of them.
12. Walk south-west to the fixer's office and turn the contract in. → Paid double
    for a run nobody saw: 24 notes.
13. Now do it loudly. Relaunch, cut the wall beside the front door instead, and walk
    in. → Four armed guards. Fight from the breach; an open lobby is a losing hand.
14. Let them kill you. → The death screen: where your body is, what is on it, and
    what the law will and will not hand back. Press A to come back, then walk to the
    body and take your kit off it.
15. `--mission --demo` → the whole stealth run played end to end, scoring
    `seen 0, alarms 0, bodies 0, traces 0`.
16. Write the feel notes (§7). The numbers to move are all content:
    `content/payout_curve/fixer_standard.json` (what quiet is worth),
    `content/standing_rule/heat.json` (how fast heat cools and where),
    `content/recovery_rule/police.json` (what dying costs),
    `content/terminal/cs_server.json` (how long the exposure lasts), and the guards'
    routes and kit in `content/site/cold_storage.json`.

## 4. Debt and deviation log

| # | Item | Kind | Scheduled |
|---|---|---|---|
| 1 | **Neither authored site could be walked into.** Both sit on a metre-high slab and a level change needs a climbable face, so the only way inside was to place the actor there by hand — which every test did, which is why nobody noticed until the fixtures, which are command logs and cannot cheat. Cold Storage now has a hatch landing and a flight at its street edge, with a test that walks in from the pavement. `m4_test_building` still has none: its own client places the player inside. | correction to claim 3 | M7 for the M4 building |
| 2 | **A breach was a tally, not a reading**, so it could never be undone, while the other two kinds of trace were readings all along. The spec's clean under-route run was therefore impossible. Traces now count the gaps still open at the end, so a grate the player puts back is not a hole. | correction to claim 7 | closed |
| 3 | **The lot covered the street**, so cutting the grate needed the `build` right and only the operator could do it — the third route did not exist for a player. The lot now begins at the building's wall; the street is public and the trespass starts where the tunnel passes under it. | correction to claim 4 | closed |
| 4 | **A site's guards carried no kit**, so a raised building was guarded by four people holding nothing and the mission had no lethal opposition at all. Site spawns gained a `kit`; `ItemSystem.arm` seats a magazine and chambers a round in one call, because entity ids are handed out as commands execute and nothing can name what it just spawned. This spans three sim modules against the one-module-per-pass rule: the feature is exactly "a site arms its guards" and each piece alone does nothing. | correction to claim 4; rule deviation | closed |
| 5 | **Mission items ride on the `ammo` kind.** `cold_storage_data` and `access_token` are `content/ammo/` entries because `SPAWNABLE` had no generic carried-item kind when claim 5 landed. They are not rounds and the schema makes them declare a calibre. A `gear` kind alongside `currency` is one content move and one constant. | wrong kind | M7 |
| 6 | **The step's landing is one cell wide**, so walking off it sideways drops the actor a metre. The fixtures and the demo go north onto the slab before moving in x. A wider apron is a content change. | content | M7 |
| 7 | **`quest.turn_in` reads the multiplier when the contract is handed in**, so `run.end` must be issued first for the trace reading to be frozen. Nothing enforces the order; it is documented in `docs/extending-missions.md`. | note | M7 |
| 8 | **One currency denomination.** Every payout is a multiple of 100 and a turn-in spawns up to 24 item entities. Smaller notes are a content-only change. | scope | when the economy needs change |
| 9 | **The Q4 extension exercise is outstanding.** A second contract against the same site, content only, with an empty `sim/` diff. | scope | before submission |
| 10 | **Suite runtime is about twenty minutes on the Deck**, dominated by the ten 10 000-case properties. The G3/G4 portal-graph dirty-set item would cut it and is still open. | residue | M7 |
| 11 | **Any content addition re-records every fixture**, because the content digest is hashed into the sim state. That is the replay stage doing its job, but content changes and fixture re-records always travel together. `tools/rerecord_hashes.sh` exists because doing it by hand with a string replace destroyed four fixtures: a fresh fixture has an empty `expected_hash`, and replacing the empty string inserts the hash between every character. | note | none |
| 12 | **The `gate` Steam branch line is unmet.** The registered app id has not arrived, so the Deck runs are from a source checkout and an export, not a Steam install. CEOGG decided on 2026-09-22 that M6 proceeds and this is recorded unmet. | external | with the app id |
| 13 | The M1 range demo still runs on wall time (G3 debt 8, G4 debt 13, G5 debt 13); untouched. | residue | M7 |

## 5. The four standing questions

**Q1 — Does it function?** Yes, on the Deck: 293 tests and 241 404 assertions pass,
twenty fixtures reproduce across processes, and the mission plays end to end in the
client at 90 fps median with an 88 fps 1% low, comfortably over the 40 fps floor.
The four fixtures record the mission played four ways and each is asked what
happened in it. The hand-played feel run is outstanding.

**Q2 — Is it secure?** New untrusted inputs are six content kinds (schema-checked at
build, cross-referenced at assembly: a payout curve's floor, a standing rule naming
an unknown condition, a recovery rule falling back to a parcel that does not exist,
a site placing two pieces in one slot, a currency worth nothing — each refused with
a reason) and nine command kinds, all with exact payloads and ownership checks and
all in the 200-case hostile corpus. The corpus and the save property's command
stream are now **derived from the command registry**, so a kind cannot be added
without coverage. No new binary dependency.

**Q3 — Is it complete?** Fifteen of sixteen claims are delivered with no stubs or
`TODO`s in a shipped path. The Q4 extension exercise is outstanding (§4 item 9).
Four claims were corrected after landing; each correction is logged with how it was
found, because the pattern is the point: every one surfaced when the next claim
tried to use it, and none would have surfaced from reading the code.

**Q4 — Is it expandable?** Not yet performed. The pieces are in place — a contract,
its payout curve, its terminal and its access token are all content, and
`docs/extending-missions.md` records the procedure — but the exercise itself is
outstanding and this question cannot be answered yes until it is run.

## 6. Sign-off

Approver: CEOGG

Date:

Outcome:

Conditions (if any):

## 7. Deck run and feel notes

_For CEOGG, after the demo script in §3._
