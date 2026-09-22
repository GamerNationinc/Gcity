# M6 — "Cold Storage": specification

Milestone M6 of `docs/gcity-design.md` §16, in the terms of that document. Written
before implementation (standards §2.1, §10.2). Status: **draft, awaiting approval**
(submitted 2026-09-22).

**Preconditions.** G5 is signed in `docs/gates/M5-gate.md` (it is). One ADR blocks
this milestone and is still `proposed`: **ADR-007** (death cost), proposed as **C**,
a corpse that persists with the gear on it, a recovery run, softened inside city
limits by the district's `law_index`. This spec is written against C because the
mission must survive a death mid-run and the gate's fixtures include one. **No code
starts on claims 10–11 until it carries CEOGG's signature**; the rest of the
milestone does not depend on it. ADR-010 (hub interiors) does not block M6.

**The claim of the milestone.** This is the playable vertical slice: the §15 mission,
in an authored building, with no procgen at all. A contract is accepted from a fixer,
the site is entered by one of three authored routes, a terminal is hacked under real
time pressure, the data is exfiltrated and sold, and the run is scored. Nothing here
is a new architecture: every beat is an existing system carrying weight for the first
time — the portal graph as a building with floors, the perception stack as opposition
that must be legible enough to outwit, the device as the only UI, quests as a
contract with a payout. The one genuinely new mechanic is **vertical movement**
(claim 1), which M3 deferred (G3 debt item 4) and the mission's three routes now
demand. G6's proof (standards §11): the full mission playable on the Deck from a
Steam install on the `gate` branch; all three routes completable; stealth scoring
correct on a full-stealth replay fixture; mutation score ≥ 70 % on `sim/`.

**Size.** This is the largest milestone since M1 and will take several sessions. The
claims are ordered so each lands whole: vertical movement, the building, the
terminal, scoring, the contract and payout, death and recovery, then the client and
the fixtures.

## Claims

### Vertical movement (`sim/agents/`, `sim/land/`)

1. **Floors are walking surfaces and levels connect.** A cell is standable when a
   floor piece covers its lower face or it rests on a foundation or the ground of a
   parcel; `actor.move` gains `dy` in `{-1, 0, +1}` **cell levels**, accepted only
   where a `content/piece_kind/` entry with `climb: true` (stairs, a ladder) occupies
   a face of the cell being left or entered, and rejected otherwise. Falling: an
   actor whose cell is not standable descends one level a tick until it is, taking
   `fall_damage_per_level` (content, on the combat profile) beyond the first level.
   Properties over 10 000 random structures: an actor never stands in a solid cell
   nor in the air; a level change always has a climbable face; total fall damage is
   the levels fallen beyond the first, times the profile's number.
2. **Sight, pathing and the portal graph already work in three dimensions** (the
   line walk, the A\*, the flood fill all carry a `y`); what changes is that
   `PathingSystem` may expand a vertical step where claim 1 allows one, and
   `M4Building`-style content may place pieces above ground. The pathing property
   gains vertical cases. The portal graph needs no change: a floor between two
   levels is already a face piece.

### The site (`content/`, `client/`)

3. **The building is authored content, not procgen** (design doc §15, §16 M7): a
   `content/site/<id>.json` declares the build pieces of a site by cell and facing
   (the same payloads `build.place` takes), its actors' spawns, its terminals and its
   patrol routes, and `SiteSystem` raises it at assembly or on `site.raise {site}`.
   `cold_storage` is a two-storey building with a lobby, a stair well, an upper
   corridor with two rooms, a basement service tunnel, and a server room the three
   routes converge on. The M4 test building becomes a site file by the same schema
   (its layout unchanged, its hashes re-recorded), so the format is proven by the
   thing that already worked.
4. **Three routes, all authored, all legitimate** (design doc §15.2), each a
   different existing rule:
   - **Front**: the lobby door refuses entry unless the actor carries an item with
     the `access.cold_storage` tag (a `content/ammo`-style item instance; the check
     is a `door_check` piece kind whose `passable` is resolved from the actor's tags
     through the stat resolver, so it is content, not a branch), and the lobby post
     sees you either way: heat is the cost.
   - **Side**: a window on the upper floor, reachable by the fire stair outside,
     which is stairs (claim 1) and nothing else.
   - **Under**: a service tunnel below ground, entered through a grate whose piece
     is breachable with the `cutter` tool (M3's breach path), bypassing the lobby
     entirely and proving the vertical parcel rules (§6.1: the tunnel is inside the
     parcel's `floor_y`).
   Each route is completable in the fixtures of claim 15 and in the demo script.

### The terminal and the hack (`sim/quests/`, `client/device/`)

5. **A terminal is an entity with a state machine.** `content/terminal/<id>.json`
   declares `hack_ticks`, `requires` (a device `provides` tag: `daemon_coprocessor`),
   `emits` (a signal name for M8) and the `data` item template it yields.
   `TerminalSystem` (system id `terminals`) owns `terminal.hack_start {actor,
   terminal}` and `terminal.hack_cancel {actor, terminal}`: a hack runs while the
   actor stays within `reach_mm` and alive, advances one tick per tick, and on
   completion spawns the data item into the actor's inventory and emits
   `terminal.hacked`. Moving out of reach cancels it and loses the progress: this is
   the exposure the mission is built on (ADR-006's verification). A terminal left
   hacked is a `trace` (claim 7) until `terminal.wipe`.
6. **The hacking app runs it** (M5's placeholder becomes real): the pane lists
   terminals in reach, starts and cancels the hack, and shows the progress and the
   ticks remaining. The device cannot pause here: the site is not a `safe` parcel
   (ADR-006 C), so the progress window is played with the world running, which is
   the legibility check ADR-006's verification asks for.

### Scoring, standing and the payout (`sim/quests/`, `sim/threat/`)

7. **Stealth scoring is four counters** (design doc §15.4), kept per run by
   `RunScoreSystem` (system id `score`) subscribing to the bus: `times_detected`
   (`perception.alerted` naming the player), `alarms_raised` (`squad.report` whose
   reporter saw the player), `bodies` (`combat.hit` with `killed`), `traces_left`
   (a breached piece, a terminal left un-wiped, a body left in the open). All four at
   zero is the full stealth bonus; partial credit is a payout multiplier from
   `content/payout_curve/`. Property over 10 000 generated event streams: every
   counter is monotone, the multiplier is monotone in each counter, and a run with no
   events scores the bonus.
8. **Three standing scalars, not one wanted level** (design doc §7.3):
   `StandingSystem` (system id `standing`) keeps `heat`, `notoriety` and
   `visible_wealth` per actor as integers, raised by content rules on bus events
   exactly as `skill` xp rules are (`content/standing_rule/`), and decayed per tick
   by a district-scaled rate. M6 ships: heat from `land.violation` and from being
   detected on another's parcel, notoriety from `quest.completed`, visible wealth
   from the resolved value of carried items. Nothing reads them but the device and
   the payout yet; the threat director is M8.
9. **The contract pays**: a `content/quest/cold_storage.json` whose objectives are
   the terminal hack and the exfil (leaving the site's parcel carrying the data), and
   whose reward is credits (a `content/currency` item) times the claim 7 multiplier,
   plus a fixed module. `quest.turn_in {actor, quest}` completes it at the fixer's
   parcel; notoriety rises by the rule of claim 8.

### Death and recovery (ADR-007 C) (`sim/agents/`, `sim/items/`)

10. **A dead actor leaves a corpse.** When an actor dies, `ActorSystem` emits
    `actor.died {actor, position}` and `CorpseSystem` (system id `corpses`) creates
    a corpse entity at the position holding a container into which every item of the
    dead actor's inventory moves (an item transfer, never a spawn or a destroy: the
    conservation property of M1 claim 10 is extended over death). The corpse is in
    the snapshot and the save.
11. **Recovery, softened by law.** `corpse.loot {actor, corpse}` moves items back to
    a living actor within reach. Inside a district whose `law_index` is above
    `police_recovery_threshold` (content), a fraction of the kit is returned to the
    player's own inventory on respawn instead, at a credit cost; outside, nothing is.
    The player respawns at their plot on `actor.respawn {actor}`. Property over
    10 000 death and recovery sequences: no item is created or destroyed by death,
    looting, or the police return.

### Fixtures, save, corpus, client, verification

12. **Mutation testing** (standards §3.6, the G6 bar): `tools/mutate.py` mutates
    `sim/` scripts (integer constants, comparison operators, boolean returns, deleted
    statements) one at a time, runs the unit suite against each, and reports the
    score. Target ≥ 70 % on `sim/`; the package records the score, the surviving
    mutants by file, and the tests added in response.
13. **The client** shows the mission: the site rendered as it stands, the device as
    the only UI, the hacking pane with its progress, a run summary on completion
    (the four counters, the multiplier, the payout) and a death screen offering the
    recovery run. The world view's demo plays a full stealth run end to end.
14. **Everything is in the snapshot and survives the round trip**: terminals, run
    counters, standing, corpses. The save property's stream gains every new command.
    Save schema stays at version 1.
15. **Fixtures**: `m6-stealth.json` (the under route, the hack, the exfil, all four
    counters zero, the bonus paid), `m6-loud.json` (the front route without the
    token, detected, a guard killed, the data taken anyway, a reduced payout and
    heat raised), `m6-death.json` (killed mid-hack, the corpse holding the kit, the
    recovery run getting it back), `m6-side.json` (the upper window by the fire
    stair, proving claim 1's vertical movement in a replay).
16. **Schemas** for `site`, `terminal`, `standing_rule`, `payout_curve`, `currency`;
    `piece_kind` gains `climb` and `door_check`; `combat_profile` gains
    `fall_damage_per_level`. **Corpus** extended with every new command kind.

## Out of scope (goes to the debt log if touched)

Procgen and the route graph (M7), site binding (M7), the threat director, raids and
suspicion (M8), drones (M7), dialogue trees (the fixer is a parcel and a command at
M6, not a conversation), the economy beyond credits and one payout curve, additional
weapons or perks, non-lethal takedowns, climbing without stairs, swimming, vehicles,
and any second mission.

## Open points

- **ADR-007** must be accepted before claims 10–11. Proposed as C.
- **Vertical movement is a mechanic, not a port.** Claim 1 is the one place M6 can
  overrun. If the Deck measurement or the property tests say the fall model is
  fighting the portal graph, the fallback is stairs-only movement with no falling
  (an actor in an unstandable cell is refused the move that got it there), recorded
  as a deviation.
- **The `gate` Steam branch** the G6 bar names needs the registered app id
  (standards §12 item 4, still open). If it is still open at G6, the package records
  a sideloaded install and the Steam-install line stays unmet, which is CEOGG's call
  to accept or hold.

## Assumptions to record in the gate

- The site is one parcel with a vertical extent; the tunnel is inside its `floor_y`.
- The fixer is a parcel with a name, not a character: dialogue is M7 with quests.
- Credits are an item, not a scalar, so the save and the conservation property cover
  them without a new mechanism.
- A run is the span from accepting the contract to turning it in; the counters reset
  on accept.

## Extension exercise for Q4 (standards §11, G6)

Add a second contract (`content/quest/cold_storage_returns.json`) against the same
site with a different terminal and a different payout curve, and a second access
token, using only new content files; `tools/test.sh` passes, the new contract is
playable from the fixer, and the diff under `sim/` is empty.
`docs/extending-missions.md` records the procedure.

## Fixtures and property seeds

| Test | Cases | Fixed seed constant |
|---|---|---|
| Vertical movement: never in a solid cell or the air; a level change has a climbable face; fall damage is the levels beyond the first | 10 000 structures | `tests/agents/test_vertical_movement.gd` |
| Pathing across levels: a path exists exactly when the cells are joined through open faces and climbable steps | 10 000 | `tests/agents/test_agent_pathing.gd` (extended) |
| Scoring: counters monotone, multiplier monotone in each, a clean run scores the bonus | 10 000 event streams | `tests/quests/test_run_score.gd` |
| Standing: rules credit the named actor, decay never goes below zero | 10 000 | `tests/threat/test_standing.gd` |
| Death and recovery conserve every item | 10 000 sequences | `tests/items/test_corpse.gd` |
| Save round trip with terminals, score, standing and corpses in the stream | 10 000 | `tests/sim/test_save_file.gd` (extended) |
| Command payload fuzz, every new kind | corpus + 10 000 mutations | `tests/fuzz/commands/` |
| Mutation score on `sim/` | every mutant | `tools/mutate.py` |

A failing seed is committed as a named regression case (standards §3.2).
