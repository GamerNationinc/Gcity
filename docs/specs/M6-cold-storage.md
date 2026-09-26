# M6 — "Cold Storage": specification

Milestone M6 of `docs/gcity-design.md` §16, in the terms of that document. Written
before implementation (standards §2.1, §10.2). Status: **approved** (CEOGG,
2026-09-26), with every recommendation in the draft's open points taken (see
"Decisions at approval").

**Preconditions.** G5 is signed in `docs/gates/M5-gate.md` (it is). **ADR-007** (death
cost) is `accepted` as **C** (CEOGG, 2026-09-26): the corpse persists with the gear, a
recovery run gets it back, and the city softening is driven by district `law_index`.
**ADR-006** is `accepted` as C: the terminal hack happens with the device raised and
the world running, because the site is not a `safe` parcel. **ADR-011**
(crimes against rights) is `accepted` as **C** (CEOGG, 2026-09-26): crimes proceed and
raise heat, construction still refuses. ADR-010 (hub interiors) blocks M7, not M6.

**The claim of the milestone.** One authored contract exercises nearly every system
M1–M5 built, in one loop, with no procgen (§15): accept the job from a fixer, walk to
the site, case it, enter by one of three routes, hack a terminal while exposed, get
out, sell the data, and be scored on how unseen the run was. The mission is **content
over finished systems**: the site, the fixer, the contract, the guards, the sensors,
the terminal and the stealth counters are data files, and a second contract is a
second set of files with an empty `sim/` diff. Death is survivable and costs what
ADR-007 C says. G6's proof (standards §11): the full mission playable on the Deck
from a Steam install on the `gate` branch; all three routes completable; stealth
scoring correct on a full-stealth replay fixture; mutation score ≥ 70 % on `sim/`.

## Claims

The claims are grouped by the module that owns them, in the order they are built.
Each group is one session and one reviewable diff (CLAUDE.md §3).

### A. The site is content (`sim/quests/`, `sim/land/`)

1. **A site is a data record.** `content/site/<id>.json` declares, relative to an
   `origin` cell: its `parcels` (refs to `content/parcel/`, each with an owner
   faction), its `pieces` (the `build.place` payload list, as `M4Building.commands()`
   produces today), named `points` (`player_start`, `respawn`, `exfil`, a giver's
   post), `agents` (the `agent.spawn` payloads: profile, cell, facing, squad, route),
   `containers` (named item containers with seeded contents, §11.3), `terminals`
   and `sensors` (claims 8 and 10). The validator checks every reference and that
   every piece is within its support span, at build time; the assembly checks it
   again. M6 ships `home` (the starter plot, the fixer's post) and `cold_storage`.
2. **Raising a site is one command, one rebuild.** `site.raise {site}` (debug-class,
   like `item.spawn`: fixtures and the client's new-game path issue it) places every
   piece, transfers every parcel and spawns every agent in one tick, and the portal
   graph rebuilds **once** for the batch, not per piece. This closes G4 debt 7 (the
   200 ms raise hitch) and the batched half of G3 debt 2; the gate records the raise
   cost on the Deck. The M4 building keeps its client-side command list for the M4
   fixtures, whose hashes do not change.
3. **Actors spawn at points; the client never places them.** `actor.spawn` accepts
   `{profile, site, point}` alongside the existing `{profile, range_m}`. This replaces
   the world view's direct `actors.set_position()` call at setup
   (`client/world_view.gd:584`), which is a client write to sim state (invariant 2).
   The fitness function gains a rule that nothing under `client/` calls a sim setter.
4. **Quests reference site handles, never coordinates** (§5.3). A quest's `site` is a
   site id; on `quest.accept` the binding `{quest, site}` is written to the quest
   record. At M6 the lookup is the identity (one authored site per handle); M7's
   generator replaces the lookup, not the quest file.

### B. Levels (`sim/agents/`)

5. **Actors stand on floors.** An actor's cell may be above ground when the face
   below it holds a floor-like piece (`floor`, a closed `hatch`) or the cell below
   holds a solid cell piece; otherwise it falls to the next supported cell (no fall
   damage at M6). This closes G3 debt 4 (movement keeps y = 0).
6. **Changing level is a rule, not a special case.** Piece kinds gain a `climb` flag
   in `content/piece_kind/`; `actor.climb {actor, dir}` (`up` / `down`) moves one
   cell vertically when the actor's cell or the cell ahead holds a `climb` piece
   (a ladder, a crate stack) and the face crossed is passable. `ladder` is a new
   piece kind and piece; `crate` gains `climb: true`. Pathing's steps include the
   same vertical transitions, through `MovementSystem` as now. Metamorphic relation:
   adding a `climb` piece never raises the cost of any existing path.
7. **Perception, noise and aim work across levels.** The line walk runs in three
   dimensions and a floor face blocks sight as a wall does. Pathing's search bound
   (G4 debt 6) is re-decided by measurement on the site: if the site fits
   `SEARCH_RADIUS`, the bound stays and the portal-graph handoff stays in the debt log.

### C. Doors, locks and breaching (`sim/land/`)

8. **Locks are data.** A `build_piece` may declare a `lock`: `requires_tag` (an item
   tag the passer must carry, e.g. `access.cold_storage`) and `heat_max` (claim 11).
   Passing a locked face without the tag is refused; passing it with the tag while
   the actor's heat exceeds `heat_max` is allowed but emits `sensor.tripped` for the
   door's sensor (the front route "fails loudly if your heat is already high",
   §15.2). Every check emits `land.door_check {actor, piece, passed}`.
9. **The player breaches with a tool.** `tool` is a new item kind
   (`content/tool/<id>.json`, naming a `tool_class`); `build.breach {actor, piece,
   tool}` needs the tool in the actor's inventory and the actor adjacent to the
   piece, and asks `LandSystem.offend()` for `build` on the piece's parcel
   (ADR-011: it proceeds and records the violation). It takes `piece_hp × hp_factor` ticks, cancels if the actor moves or
   fires, emits the piece's `breach_noise` as a noise event on each progress step,
   and on completion removes the piece and emits `build.breached {actor, piece}`
   (the event raid tokens already use). M6 ships `cutter_handheld` and the
   `service_grate` piece (a `hatch` in a cuttable material).

### D. Sensors and standing (`sim/threat/`)

10. **Sensors watch edges** (§9.1). A site's `sensors` entry binds a sensor profile
    (`content/sensor/<id>.json`: `watches` = `edge` or `volume`, `radio` true/false,
    `spoofable`) to a piece face or a set of cells. An actor crossing a watched edge
    or entering a watched volume emits `sensor.tripped {sensor, actor}`; a radio
    sensor's trip reaches the site's squad as a `squad.report`, through the squad
    system that already carries guard reports. A spoofed sensor does not trip until
    its spoof expires. The **lobby camera** is an agent profile with a hold-only
    stance set and no weapon (the G4 sentry drone shows the pattern), so it sees
    through perception rather than tripping. The **power monitor** on the side
    window is a spoofable edge sensor.
11. **Heat and notoriety are per-actor scalars** (§7.3), held by `StandingSystem`
    (system id `standing`, milli-units), raised by content rules
    (`content/standing_rule/<id>.json`: event, the payload field naming the actor,
    optional `tags_any`, the scalar, the amount), as skill XP rules already are.
    Heat decays at a content-declared rate per tick; notoriety does not. At M6 the
    readers are the lock check (claim 8), the payout (claim 18) and the HUD. The
    threat director, factions' suspicion and visible wealth are M8. Shipped rules:
    `land.violation` and `sensor.tripped` raise heat; `contract.completed` raises
    notoriety.

### E. Hacking (`sim/items/`)

12. **A hack is a timed, stationary action gated by hardware.** A site's
    `terminals` entry declares its cell, `hack_ticks`, the `provides` tag it
    requires (`daemon_coprocessor`), the `noise` it emits per progress step, and the
    item template it yields. `hack.start {actor, terminal}` is accepted when the
    actor is alive, adjacent, and has a device equipped that provides the tag; it
    asks `offend()` for `loot` (ADR-011).
    Progress advances each tick at a rate resolved from the device's
    `memory_capacity` through the stat resolver. It cancels if the actor moves,
    fires, or is hit. On completion it spawns the data item into the actor's
    inventory, emits `hack.completed`, and leaves the terminal **logged in** until
    `hack.logout {actor, terminal}` (a few ticks; a trace until done). Neither
    command is pause-safe. `hack.spoof {actor, sensor}` is the same machinery against
    a spoofable sensor, with its own ticks and a spoof duration.
13. **The hacking app is real.** It lists terminals and spoofable sensors in range,
    shows progress and the noise the hack is making, and offers logout. It reads
    the sim and submits commands, like every pane (M5 claim 4). The drone app stays
    a placeholder until M7.

### F. Death, corpses and recovery (`sim/agents/`, `sim/items/`) — ADR-007 C

14. **Death leaves a corpse container.** When any actor dies, `DeathSystem` moves
    every item in `inv.<actor>` (magazines keep their rounds, weapons their parts) into
    a new container `corpse.<id>` at the death position, conserving item ids, and
    emits `actor.died {actor, corpse, killer, x, y, z}`. Guards leave corpses too,
    which is how a stolen token or a dropped magazine comes back into play.
15. **Recovery is a run, not a menu.** `container.take {actor, container, item}`
    moves one item from a corpse or a site container into the actor's inventory when
    the actor is adjacent. For a site container or someone else's corpse it asks
    `LandSystem.offend()` for `loot` (ADR-011: the take proceeds and a denied right
    is recorded as a violation); an actor's own corpse is always theirs. An empty corpse is removed. Scavengers taking from a corpse are the
    threat director's (M8): at M6 a corpse persists untouched.
16. **Respawn, softened by law.** `actor.respawn {actor}` is accepted only while the
    actor is dead. It restores health and places the actor at the `respawn` point of
    their home site. At the moment of death, the district's `law_index` (‰) is the
    share of the corpse's top-level items that the police fiction impounds: that
    many items, chosen with `sim.rng()`, move to `impound.<actor>` rather than the
    corpse. `impound.release {actor}` returns them for the district's new
    `impound_fee` per item in credits (claim 17). In the corporate core (950 ‰)
    nearly everything is impounded; in the badlands (low `law_index`) nearly
    nothing is. The mission's quest stays active through a death, and its data item
    is on the corpse or in the impound like anything else.

### G. Contracts (`sim/quests/`)

17. **Credits are a per-actor balance** held by `QuestSystem`'s ledger, an integer
    per actor, not an item (decided at approval): `contract` payouts add to it, `impound.release` spends it, and a
    transfer never makes it negative.
18. **A contract is a quest with a giver, a turn-in and a score.** The quest schema
    gains optional fields:
    - `giver`: a site point where the fixer (an agent profile with no weapon and
      a hold stance) stands. `quest.accept` for a quest with a giver needs the actor
      within two cells of it.
    - `lines`: the fixer's offer and turn-in text, shown in the quests and comms
      apps. There is no branching dialogue.
    - `objectives`, as at M5, with a `match` filter on payload fields
      (e.g. `hack.completed` for terminal `cs_core`; `land.entered` for the exfil
      parcel, an event `MovementSystem` now emits on a parcel change).
    - `turn_in`: an item template handed to the giver. `contract.turn_in {actor,
      quest, item}` transfers that item instance into the fixer's inventory and
      completes the contract (§15.1 "item instance transfer").
    - `score`: named counters, each an event rule that adds or subtracts for the
      actor while the contract is active.
    - `payout`: credits, a multiplier by the number of non-zero counters, and the
      bonus reward items granted only when every counter is zero.
    `contract.completed {actor, quest, counters, credits}` is emitted once.
19. **Stealth scoring is §15.4, as content.** `cold_storage.json`'s `score` declares
    exactly the four counters:
    - `times_detected`: `perception.alerted` with the actor as contact.
    - `alarms_raised`: `squad.report` with the actor as contact, and `sensor.tripped`
      by the actor on a radio sensor.
    - `bodies`: `actor.died` with the actor as killer.
    - `traces_left`: `+1` on `build.breached` and on `hack.completed`, `−1` on
      `hack.logout`, `+1` on a destroyed sensor.
    A loud run still completes, pays less and raises heat. Property: over 10 000
    generated event streams, each counter equals an independent recount of the
    stream, and the bonus is granted if and only if all four are zero.

### H. The mission, as content (`content/`)

20. **"Cold Storage" ships as data only.** It consists of the `cold_storage` site,
    the contract, the fixer's profile, five guards (a lobby post, two upper-floor
    patrols, a roamer, and one in the server room; §15.3), the lobby camera, the power
    monitor, the terminal, the data item, the access token, the handheld cutter and
    the grate. The site is two storeys plus a service tunnel, in the `corporate_core`
    district. Its ordinary windows are a new `sealed_window` kind (sight-only,
    `passable: false`); the side route's window is a passable `maintenance_window`.
    No existing piece kind changes, so no existing fixture hash changes (closes
    G4 debt 5 for this site). It has **three routes,
    all authored, all completable**:
    - **Front**: the access token, from a locker in the delivery office next door;
      looting it is a violation that raises heat, which the door then reads.
    - **Side**: a second-floor maintenance window, reached by the crate stack or a
      ladder, silent only if the power monitor is spoofed first.
    - **Under**: the service grate cut with the handheld cutter into the tunnel, the
      only route that never enters the lobby camera's cone.
    All three converge on the server room.
21. **The guards demonstrate §15.3 in this mission.** Each behaviour is shown by a
    fixture:
    - A detection delay the player can break contact within (`m6-break-contact`).
    - A guard walking to a noise, looking, and returning to its route
      (`m6-investigate`: the cutter's noise).
    - Escalation by radio, not telepathy (`m6-alarm`).
    - An isolated, suppressed guard surrendering or retreating rather than fighting
      to the death (`m6-morale`).
    Tuning values are content changes recorded in the gate.

### I. Client (`client/`)

22. **A game, not a test scene.** The main scene becomes a title screen (New game,
    Continue, Quit; controller only, no keyboard required), and New game raises
    `home` and `cold_storage` through the same commands the fixtures use. The M1–M4
    views stay reachable from `--view=<name>` for gate work.
23. **Interaction is contextual and glyph-aware.** One prompt names the action the
    player can take where they stand: talk, take, climb, cut, hack, turn in. It is
    submitted through the same path as every action. Death shows who, where and
    what is impounded, with respawn and load.
24. **Device debt closed.** The panel scales with the viewport (G5 debt 3), inventory
    rows sort by kind and group stacks (G5 debt 11), and the quests app shows the
    live counters and the payout they imply.
25. **The M1 range demo runs on sim ticks** (G5 debt 13), not wall time.
26. **Placeholder audio on sim events**, client only (decided at approval). Cues play
    for a guard's alert and stance change, footsteps, shots, the cutter, hack progress
    and completion, a sensor trip, and death. Each is a subscriber reading sim
    state; the sim gains nothing. Sounds are generated or CC0 files under
    `client/audio/`, each with its source and licence recorded in
    `docs/dependencies.md`.

### J. Fixtures, save, corpus, tools, Deck

27. **Fixtures.** Each seeds, raises the sites and replays to a recorded hash:
    - `m6-front`, `m6-side`, `m6-under`: each route completed, full stealth, bonus
      paid. `m6-side` is the full-stealth fixture G6 names.
    - `m6-loud`: detected, alarm raised, completed, reduced payout, heat raised.
    - `m6-death`: killed mid-run, part of the kit impounded, respawned, corpse
      recovered, data turned in.
    - `m6-break-contact`, `m6-investigate`, `m6-alarm`, `m6-morale` (claim 21).
    - `m6-m9`: the second pistol frame through the mission kit (G1 debt 15).
28. **Everything is in the snapshot and survives the round trip:**
    - site bindings, corpses, impounds, standing and the ledger;
    - hack and spoof progress, logged-in terminals and contract counters.
    Save schema moves to version 2 with a migration from version 1 (standards: every
    schema versioned). A v1 save loads with an empty ledger and no standing.
    Property: the save property's stream gains every new command kind.
29. **Item conservation** (ADR-007 verification): over 10 000 generated streams of
    spawn, death, take, impound, release, turn-in and save/load, the multiset of
    item ids across all containers changes only by spawns. No item is duplicated or
    lost across death, corpse and recovery.
30. **Schemas and corpus.** New schemas: `site`, `sensor`, `standing_rule`, `tool`.
    Extended schemas:
    - `quest`: `giver`, `lines`, `match`, `turn_in`, `score`, `payout`, `site`.
    - `piece_kind`: `climb`.
    - `build_piece`: `lock`.
    - `district`: `impound_fee`.
    Every new command kind enters the fuzz corpus with hostile cases.
31. **Mutation testing.** A mutation runner under `tools/` (own code; if an external
    tool is proposed instead, it is pinned per CLAUDE.md §10 and recorded in
    `docs/dependencies.md`). The G6 target is a score of at least 70 % on `sim/`,
    with surviving mutants listed in the gate.
32. **Deck.** The mission is played by hand on the Deck from a Steam install of the
    `gate` branch (see "Still open" below). The package records:
    - 1 % and 0.1 % lows for the whole run, with the site raised and all five guards
      and the camera active;
    - the ADR-006 legibility check: the terminal hack with the device raised in the
      hostile site while a guard approaches;
    - hand-played feel notes, which replace G5's 0.35 s-per-press assumption (G5
      debt 12).

## Out of scope (goes to the debt log if touched)

- Procgen, the route graph, region transition, travel beyond one loaded map, fog of
  war, and site binding beyond the identity (M7).
- The threat director, faction suspicion, visible wealth, and scavengers on
  corpses (M8).
- Drone control and a drone-carried line for the side route (M7).
- Digging, meaning terrain (ADR-003 B, M7). The Under route is a cut grate at M6;
  `rights_at().dig` is untouched.
- The sim combat profile stages for guards (penetration, per-limb routing, bleed):
  guards stay on the `guard` profile, as the G4 content notes.
- Lighting in perception (G4 debt 9).
- Non-lethal takedowns: at M6, avoidance is the only non-lethal answer.
- Branching dialogue, voice, and a shop or economy beyond the ledger.
- Achievements, SteamPipe upload itself (CEOGG's external action), and localisation.

## Decisions at approval (CEOGG, 2026-09-26)

The draft's open points, closed by taking each recommendation:

1. **Rights and crime.** Closed by **ADR-011 C**. `loot`, `breach` and `hack` proceed
   through `LandSystem.offend()` and record the violation, which raises heat.
   `build`, `dig` and `enter` keep refusing through `require()` (claims 9, 12, 15).
2. **Credits.** A per-actor integer balance in the quest system's ledger, not an
   item (claim 17).
3. **Windows.** New `sealed_window` and `maintenance_window` kinds; `window` is
   unchanged (claim 20).
4. **Size.** No split was recommended, so the milestone stays **one milestone, one
   gate (G6)**, as in standards §11. It is still built one group per session and
   one reviewable diff per group; splitting into M6a/M6b stays available as a spec
   amendment if a group's review runs long.
5. **Audio.** Placeholder cues in M6 (claim 26).

Still open, and external:

- **The Steamworks app id.** G6's "Steam install on the `gate` branch" (claim 32)
  needs CEOGG to register the app (standards §12 item 4; G5 debt 2, 4, 6). Until
  then, the Deck run falls back to the repo checkout and the export, as at G5, and
  the gate records that item as not met.

## Assumptions to record in the gate

- The fixer's post, the player's plot and the site are in one loaded map, a walk
  apart. Travel as a system is M7.
- Guards treat every non-agent actor as a contact; the fixer stands outside every
  guard's cone and hearing.
- The access token is the only credential. Forging one is a later contract, not a
  mechanic.
- Heat decay and every threshold are tuning values in content, judged on the Deck
  run.
- A dead guard's corpse is a `body` for scoring whether or not it was seen (§15.4).

## Extension exercise for Q4 (standards §11, G6)

Add a second contract: a `relay_station` site with one route, two guards, one terminal
and its own score counters, plus a new sensor profile (a tripwire), using only new
content files. `tools/test.sh` passes, a fixture completes the contract, and the diff
under `sim/` and `client/` is empty. `docs/extending-contracts.md` records the
procedure.

## Fixtures and property seeds

| Test | Cases | Fixed seed constant |
|---|---|---|
| Item conservation across death, corpse, impound, recovery, turn-in, save/load | 10 000 streams | `tests/items/test_conservation.gd` |
| Stealth counters equal an independent recount; bonus iff all zero | 10 000 event streams | `tests/quests/test_contract_score.gd` |
| `offend()` never changes an act's outcome; exactly one violation iff the right is denied (ADR-011) | 10 000 | `tests/land/test_offend.gd` |
| Standing: rules applied once per event; decay monotone; never negative | 10 000 | `tests/threat/test_standing.gd` |
| Hack progress: stationary completes in resolved ticks; any move, fire or hit cancels; logout clears the trace | 10 000 | `tests/items/test_hack.gd` |
| Levels: supported cells only; adding a `climb` piece never raises a path's cost (metamorphic) | 10 000 layouts | `tests/agents/test_levels.gd` |
| Site raise equals the same pieces placed one by one (graph and hash), in one rebuild | 1 000 generated sites | `tests/quests/test_site.gd` |
| Save round trip, v2, and v1 → v2 migration | 10 000 | `tests/sim/test_save_file.gd` (extended) |
| Command payload fuzz, every new kind | corpus + 10 000 mutations | `tests/fuzz/commands/` |
| Every new pane and the title screen at or above the minimum type size | walk | `tests/client/test_device_legibility.gd` (extended) |

A failing seed is committed as a named regression case (standards §3.2).
