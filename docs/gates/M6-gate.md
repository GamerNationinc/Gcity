# G6 — M6 Cold Storage: gate evidence package (DRAFT, in progress)

**Status: draft, not submitted.** Phases 1 to 3 and most of phase 4 are built; the client
(claim 19), the m6-stealth fixture (blocked on a decision, §4 item D1) and the Deck run
(claim 24) are not. Nothing here is marked complete on its author's authority: CEOGG
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
| 13 Cold Storage | `content/site/cold_storage.json` (generated), three routes, the keycard in the yard crate | `f7eb35f` … `d536f02`, `79c824c` | built; see D1 |
| 14 the contract | run record, exfil, delivery, scoring tiers | `e381295` … `c91bcb2` | built |
| 15 credits | `WalletSystem` | `b6b2913` | built |
| 16 corpses | `actor.died`; `CorpseSystem` (bodies, piles, crates; `item.take` / `item.drop`; loot recorded) | `bd512b3` … `79c824c` | built; G4 debt 8 open (D2) |
| 17 respawn, recovery, the city | home spawn, `actor.respawn`, `RecoverySystem`, the item conservation property | `5ef30fb` … `3e3c3a2`, `75af716` | built |
| 18 the player's aim and stress | content bound by the combat profile (not data-only: D5) | `340da99` | built |
| 19 client | — | — | **not started** |
| 20 fixtures | `tools/fixture_driver.gd`, `tools/make_m6_fixtures.gd`, `tests/sim/test_m6_fixtures.gd`: m6-front, m6-front-hot, m6-side, m6-fall, m6-loud, m6-death, m6-city-death, m6-hack-interrupt | `b096f10` … `ae772ec` | 8 of 9; **m6-stealth blocked (D1)** |
| 21 snapshot and save v2 | save schema 2, migration from real version-1 saves, the save property over every new command | `b8a9394` | built |
| 22 schemas and corpus | every new kind has a schema; hostile commands and hostile site files | `4fa91f4` and with each claim | built |
| 23 mutation testing | `tools/mutate.py`, weekly sharded CI job | `46580c3` | built; **no full score yet** (the scheduled job gives it) |
| 24 the Deck run | — | — | **not started** (needs the Deck) |

## 2. Verification report

To be filled at submission: the full `tools/test.sh` run at the submitted commit, the
replay table, the mutation score from the scheduled job, the Deck numbers.

Showcases (CLAUDE.md §13): every claim from 10 on has a scenario under
`tools/showcase/scenarios/` rendered by `tools/showcase.sh`.

## 3. Demo script

To be written with the client (claim 19).

## 4. Debt, deviations and decisions

### Decisions needed from CEOGG

| # | What | Options |
|---|---|---|
| D1 | **m6-stealth cannot be built with Cold Storage as authored.** A grate is scrap steel, audible 40 m away on its storey and 20 m one storey off; a guard's awareness gains 0.5 of its threshold per breach noise (every 40 ticks) and loses 0.4 meanwhile, so any guard within earshot is alerted. The basement guard stands 4 m from the basement grate. | (a) a thin-grate material with a short noise reach, and the basement guard posted out of earshot of the grate (recommended: keeps a basement guard); (b) remove the basement guard (the spec's pre-approved lever) and a thin-grate material; (c) keep the content and prove stealth on another route (a deviation from the spec) |
| D2 | **G4 debt 8 cannot be fixed as the spec says.** A guard's shot is submitted at tick T for T+1; another guard's earlier-queued shot kills the target at T+1, so at T there is no dead contact to drop. | (a) guards fire inside the stance tick through a sim-internal call (an M4 design change; every M4 combat fixture moves); (b) a fire at a target that died earlier the same tick is a recorded no-op, not a rejection |

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

### Debt

| # | Debt | Kind | Due |
|---|---|---|---|
| 1 | Guards do not open doors. | scope | M7 |
| 2 | `BuildSystem.supported_set` costs about 2.2 ms per change at 93 pieces; not yet measured on the Deck. | performance | before the Deck run |
| 3 | A site's `door_camera` sensor is not tied to a living camera agent: killing the lobby camera does not blind the door. | fidelity | M8 |
| 4 | Guards of different squads or sites treat each other as contacts until factions (M8). | scope | M8 |
| 5 | The test runner counted a test that hit a runtime script error as passed; `tools/test.sh` always caught it through `check_test_log.py`, and the runner now fails the test itself (`bca1e44`). | tooling (closed) | — |
| 6 | Scavenging of bodies by factions is M8. | scope | M8 |
| 7 | The G6 conditions on Steam (spec) stand. | condition | M7 |

## 5. The four standing questions

To be answered at submission.

## 6. Sign-off

Approver: CEOGG — _pending_
