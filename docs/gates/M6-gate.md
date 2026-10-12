# G6 — M6 Cold Storage: gate evidence package (DRAFT, in progress)

**Status: draft, not submitted.** Phases 1 to 4 are built; the Deck run (claim 24) is
not, and the mutation score waits on the scheduled job. Nothing here is marked complete on its author's authority: CEOGG
signs the gate. Spec: [`docs/specs/M6-cold-storage.md`](../specs/M6-cold-storage.md).

## 1. Specification

| Claim | Delivered by | Commits | State |
|---|---|---|---|
| 1 storeys | `BuildSystem` (one cell a storey, standing, nothing built into or removed from under a living actor), `MovementSystem` gravity and fall damage from content | `a35ca97` … `5a88e30` | built |
| 2 climb, mantle, jump | timed moves from the combat profile's move list; climb edges in the portal graph | `e975ad4` … `2fab204` | built |
| 3 openings have state | open flag, locks, latches, grates, ground holes; movement, pathing and sight honour them; `may_pass` | `9371ca4`, `3d87a87`, `71c9144` | built |
| 4 the player breaches | tools as items, wielded; `build.breach` timed by material | `0b2857c` … `51da92c` | built |
| 5 noise is an event | `noise.emitted` from shots, landings, breaches, hacks; perception hears it by storey | `1df4ab6`, `def498a` | built |
| 6 perception and pathing know storeys | earth, the basement, storey pathing (radius 64; the long-route handoff is M7, D7) | `b1333b9` … `2e7a4fe` | built |
| 7 incremental portal rebuild | packed grids, batched rebuilds, in-place removals; spec amended as built (`f99e49f`) | `642a14a` … `7d5fafc` | built |
| 8 cameras and sensors | cameras are agents; `SensorSystem` and `security.alarm`; reports queued from outside a squad | `3c2e311` … `fab99ba` | built |
| 9 the hack | `HackSystem`: timed, noisy, interruptible, logins hold slots; the spoof effect | `490701e`, `12a0dcc` | built |
| 10 credentials | key items; the door's heat check; the door camera (and, since `f0b5c36`, a cut door) | `1e88b93` … `63b92b5`, `f0b5c36` | built |
| 11 heat and notoriety | `StandingSystem`, content rules | `22324a6` | built |
| 12 a site is content | `SiteSystem`, `site.spawn`, one batch; the M4 building as a site file | `6241457` … `5fa063f` | built |
| 13 Cold Storage | `content/site/cold_storage.json` (generated), three routes, the keycard in the yard crate | `f7eb35f` … `d536f02`, `79c824c` | built; D1 decided, D14, D15 |
| 14 the contract | run record, exfil, delivery, scoring tiers | `e381295` … `c91bcb2` | built |
| 15 credits | `WalletSystem` | `b6b2913` | built |
| 16 corpses | `actor.died`; `CorpseSystem` (bodies, piles, crates; `item.take` / `item.drop`; loot recorded) | `bd512b3` … `79c824c` | built; G4 debt 8 closed by D2 (`4501582`) |
| 17 respawn, recovery, the city | home spawn, `actor.respawn`, `RecoverySystem`, the item conservation property | `5ef30fb` … `3e3c3a2`, `75af716` | built |
| 18 the player's aim and stress | content bound by the combat profile (not data-only: D5) | `340da99` | built |
| 19 client | world view (storey cutaway, openings, camera cones cut by line of sight, bodies, the fixer, exfil zones, site parcels), the context button (`Interact`), the hacking pane, the contract view, credits on the shell bar, the panel at 1920×1080, the inventory sorted, the range demo on ticks; `--demo-script=cold_storage` | `e6b0e12` … `b60c007` | built; screenshots `M6-world-*.png`, `M6-device-*.png`, `M6-range-ticks.png` |
| 20 fixtures | `tools/fixture_driver.gd`, `tools/make_m6_fixtures.gd`, `tests/sim/test_m6_fixtures.gd`: m6-front, m6-front-hot, m6-side, m6-fall, m6-loud, m6-death, m6-city-death, m6-hack-interrupt, m6-stealth (all counters zero, the ghost rate); showcase `stealth_run` replays m6-stealth | `b096f10` … `ae772ec`, `ef04a51`, `980ce2a` | built, 9 of 9 |
| 21 snapshot and save v2 | save schema 2, migration from real version-1 saves, the save property over every new command | `b8a9394` | built |
| 22 schemas and corpus | every new kind has a schema; hostile commands and hostile site files | `4fa91f4` and with each claim | built |
| 23 mutation testing | `tools/mutate.py`, weekly sharded CI job; a 40-mutant sample (shards 1, 11, 21, 31 of 40) scored 31/40 = 77.5 % (95 % interval 62.5–87.7 %); eight of its nine survivors now fail a test, one of them a real bug (int64's minimum did not round-trip a save, `b422f70`) | `46580c3`, `8667f5b`, `b422f70`, and the hostile-input tests after it | built; **the 400-mutant score** comes from the scheduled job, which runs on the default branch |
| 24 the Deck run | — | — | **not started** (needs the Deck) |

## 2. Verification report

To be filled at submission: the full `tools/test.sh` run at the submitted commit, the
replay table, the mutation score from the scheduled job, the Deck numbers.

Showcases (CLAUDE.md §13): every claim from 10 on has a scenario under
`tools/showcase/scenarios/` rendered by `tools/showcase.sh`.

## 3. Demo script (draft)

Steps 1–3 on any Linux x86_64 machine; steps 4–15 on the Deck from `tools/export.sh`.
Counts are filled in at submission.

1. `tools/test.sh` → every test passes, twenty-five `ok` replay lines (nine of them
   `m6-*`), `all stages passed`.
2. `tools/showcase.sh stealth_run out.gif` → the m6-stealth fixture played back in
   plain words: the counters stay at zero and Marlow pays 2000 credits.
3. `DEMO=cold_storage tools/screenshot.sh out.png 7.5` and `… 17` → the contract
   view on the device; the front door with its prompt.
4. Launch, walk east along the street to the purple figure labelled *Marlow (fixer)*.
   → The prompt reads `[D-pad left] take Marlow's contract: Cold Storage`.
5. Press D-pad left. → Cold Storage appears to the east, its exit zone outlined green.
6. Press View, R1 to Quests, D-pad down to *Cold Storage*. → `[active]`, Marlow's
   briefing, `detected 0 alarms 0 bodies 0 traces 0`, `pays now: ghost x2.0 = 2000
   credits`; `credits 0` on the bar. View to lower.
7. Walk to the city's utility box on the pavement in front of the site. → `[D-pad
   left] take maintenance key from the crate`; press it.
8. Stand on the street grate. → `open street grate`; press it: you drop into the
   tunnel. No alarm, no cut.
9. Along the tunnel, face the basement grate, D-pad left. → It opens with the key.
10. Up the stairs (`climb stair steel` at each), into the maintenance room; watch the
    hall's patrols turn away before crossing to the server room. → Above you the
    building is cut away; below, the storey you are on.
11. At the terminal, View, R1 to Hacking. → `daemons 0 / 2`, `cold storage terminal
    ready 15 s`; A starts it: the panel goes see-through, a progress bar fills. Moving
    or being hit stops it (Y cancels). When done: `logged in`; A logs out.
12. Back down and out by the tunnel's hatch (`climb tunnel hatch` from below), off
    the site (the exit zone), back to Marlow. → `deliver cold storage data to Marlow`.
13. Press it. → Paid; the shell bar's credits show the pay and the tier by how quiet
    the run was.
14. Try it loud: a plasma cutter wielded, face the front door. → `cut cold storage
    door with the plasma cutter`; the lobby camera's cone (on the floor, cut by the
    walls) turns amber, then red, and the alarm rings.
15. The device at a second resolution: dock the Deck at 1920×1080. → The panel fills
    the same share of the screen.

## 4. Debt, deviations and decisions

### Decisions taken by CEOGG

| # | What | Decision |
|---|---|---|
| D1 | m6-stealth could not be built with Cold Storage as first authored: a grate was scrap steel, audible 40 m away, and the basement guard stood 4 m from the basement grate. | "Quieter grates, move guard": grates are `grate_steel` (noise reach 6 m), and the basement guard is posted at the basement's north-east desk, facing west (`6eb873d`). Then "Add a maintenance key": unlocking a grate with the city's maintenance key is silent and leaves no trace; cutting stays the fallback (D14). |
| D2 | G4 debt 8 could not be fixed as the spec says: a guard's shot is submitted at T for T+1, and another guard's earlier-queued shot can kill the target at T+1. | "Quiet no-op": a fire by a living shooter at a target killed by a shot earlier the same tick is accepted and does nothing; the sim counts it (`CombatSystem.late_shots()`, in the snapshot) (`4501582`). |

### Deviations and interpretations (for review)

| # | What | Where |
|---|---|---|
| D3 | Only first-hand alerts go on the radio; M4's echo (a member re-reporting what it was told) is gone. It looped indefinitely with three or more members and carried the contact's live position. `test_squad`'s echo assertions changed. | `5b299df` |
| D4 | The door camera also reports its door being cut (it reported only a hot card). | `f0b5c36` |
| D5 | Claim 18 is not data-only: the aim and stress systems found profiles only through agent profiles; any actor whose combat profile binds one is now served. The player's own cone is zero. | `340da99` |
| D6 | Trespass is recorded, not refused (movement into a parcel without `enter`); looting someone else's body is recorded and the take happens; breaching is recorded. | `77a665a`, `ca8a524` |
| D7 | The portal-graph handoff for long routes (G4 debt 6) moved to M7; pathing radius raised to 64 (CEOGG: "Raise the radius, defer handoff"). | `2e7a4fe` |
| D8 | A latched hatch is passed from below; a forced opening counts at exfil; a camera kill is a trace; logins hold daemon slots; a shrinking device drops the running hack first. | claims 9, 13, 14 |
| D9 | The player's home is the starter plot (`spawn` on its parcel); the "base container" is `base.<actor>`, standing in for storage in the plot's 20 ft container (design doc §8.1). | `5ef30fb`, `0e58072` |
| D10 | A version-1 save cannot match current content's digest, so it is loaded on every system's restore validation. | `b8a9394` |
| D11 | Heat's "witnessed trespass" counts every `perception.alerted` whose contact stands in violation, including alerts by noise and by report, per the spec's wording; a loud run's heat runs into the thousands. | claim 11 |
| D12 | The crate place for the keycard has no loot check (the spec's loot rule names corpses). | `43afba6` |
| D13 | `key_item` is a new item kind (the spec names a keycard but no kind). | `1e88b93` |
| D14 | The maintenance key (`content/key_item/maintenance_key.json`) is new content: it lies in the city's utility box on the pavement (a crate place spawned with the site, like the keycard's) and unlocks both grates (D1). The fixer's briefing names it. | `6eb873d` |
| D15 | `grate_steel` is a new material (hp 150, cutter, noise reach 6 m); both grates use it (D1). | `6eb873d` |
| D17 | The world view's camera cone is drawn from the sim's own line of sight, ray by ray; it is the camera's sight on its storey, not hearing. The cold_storage demo leaves out the M4 guards, whose street it crosses. | `b60c007` |
| D18 | The context button is D-pad left / G (`world_interact`): A is taken by building in the world set. | `4e29918` |
| D16 | The m6-stealth fixture is made by a plan that, before each of six stretches, waits until a look ahead on a copy of the sim (every 10 ticks) shows the stretch and 420 ticks more, past a guard's 400-tick memory, with nobody alerted: a careful player watching the patrols. The look ahead runs only in the generator; the fixture is an ordinary command log. The route needs the maintenance room as a hiding place between the stairs and the server room, and the hack done from (2, 1, 7): the hall's east patrol and the stairs roamer cover the corridor the spec's route names, and the west patrol sees the rest of the server room through its doorway. Guards may glimpse the player (amber) without being alerted; the contract counts alerts only. | `ef04a51` |

### Debt

| # | Debt | Kind | Due |
|---|---|---|---|
| 1 | Guards do not open doors. | scope | M7 |
| 2 | `BuildSystem.supported_set` was over budget at Cold Storage's size (desktop, idle: 401 pieces p50 12.23 ms, max 25.55). It now walks a standing support graph each insert and removal updates for its own piece: 401 pieces p50 0.63 ms, p99 1.46, max 2.29; 93 pieces p50 0.11 ms (`tools/bench_build.gd`). Same results in the same order: every replay reproduces its hash, and a 10 000-case property compares it with a full recount. The Deck figure is confirmed in the gate's one Deck run. | performance (fixed) | the gate's Deck run |
| 3 | A site's `door_camera` sensor is not tied to a living camera agent: killing the lobby camera does not blind the door. | fidelity | M8 |
| 4 | Guards of different squads or sites treat each other as contacts until factions (M8). | scope | M8 |
| 5 | The test runner counted a test that hit a runtime script error as passed; `tools/test.sh` always caught it through `check_test_log.py`, and the runner now fails the test itself (`bca1e44`). | tooling (closed) | — |
| 6 | Scavenging of bodies by factions is M8. | scope | M8 |
| 7 | The G6 conditions on Steam (spec) stand. | condition | M7 |

## 5. The four standing questions

To be answered at submission.

## 6. Sign-off

Approver: CEOGG — _pending_
