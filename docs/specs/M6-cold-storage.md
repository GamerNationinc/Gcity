# M6 — "Cold Storage": specification

Milestone M6 of `docs/gcity-design.md` §16, in the terms of that document. Written
before implementation (standards §2.1, §10.2). Status: **approved** as written (CEOGG,
2026-10-08).

**Preconditions.** G5 is signed in `docs/gates/M5-gate.md` (it is). **ADR-007** (death
cost) is `accepted` as **C** (CEOGG, 2026-10-08): the corpse persists with the gear, a
recovery run gets it back, and inside city limits the district's `law_index` softens
the loss. **ADR-006** (C) is accepted, and this milestone performs its verification:
the terminal hack with the device open outside a safe parcel while a guard
approaches. ADR-010 (hub interiors) does not block M6, because M6 has no hub.

**Shape, as CEOGG decided on 2026-10-08.** This is one spec and one gate (G6). The work
is ordered in four phases, each made of single-system commits that can be reviewed one
at a time (CLAUDE.md §3). The building has **real storeys**, because the design doc's
side route and the two upper-floor guards need them. G6 is **planned as Accepted with
conditions**: the Steamworks app is not registered yet, so the demo runs from a
sideloaded native Linux build on the Deck. The Steam install, Steam Input bindings,
Steam's glyphs and Cloud sync become conditions scheduled into M7 (see §Conditions).

**The claim of the milestone.** The vertical slice of design doc §15 plays on the Deck
from accepting the contract to the fixer's payout. All of it is built from the systems
M0–M5 proved, plus these additions:

- space with storeys;
- openings with state;
- sensors on the portal graph;
- a timed hack on the device;
- standing scalars;
- credits;
- a corpse that persists.

The building, its guards, its terminals, the contract and the fixer are **content**, so
a second contract at a second site needs no `sim/` diff. G6's proof (standards §11):

- the full mission is playable on the Deck;
- all three routes can be completed;
- stealth scoring is correct on a full-stealth replay fixture;
- the mutation score on `sim/` is at least 70 %.

## Phase 1 — Space (`sim/land/`, `sim/nav/`, `sim/agents/`)

1. **Storeys.** A storey is one build cell: `BuildSystem.STOREY_MM = CELL` (1000 sim
   millimetres), so one wall piece spans a storey and the M4 building's roofs are
   storey 1's floor; the client draws a storey taller than a cell (about 3 m on screen)
   by a vertical scale that is presentation only. (Amended 2026-10-08 with CEOGG's
   approval: the draft's 3000 would have tripled every wall run and the portal graph
   it prices.) An actor's `y` is always a whole number of storeys, from −1 to 2. A floor piece is something an actor stands on. An actor on
   storey *n* stands on the floor face at the bottom of its cell, on the top of a cell
   piece below it, or on the ground at storey 0.
   **Gravity** (ADR-011 C; amended 2026-10-08 with CEOGG's approval, replacing the
   draft's "nobody falls"):
   - An actor, living or dead, whose cell is not standable **falls**. It drops one storey
     every `fall.ticks_per_storey` ticks of its combat profile until its cell is
     standable. There is bedrock under storey −1.
   - While falling it cannot move, climb, fire or hack.
   - On landing after *k* storeys it takes `max(0, k − fall.free_storeys) ×
     fall.damage_per_storey` on `fall.node`, through the existing damage path, so a long
     enough fall kills. It also emits `actor.landed {actor, storeys, damage}` and a
     landing noise (claim 5) of `fall.noise_per_storey × k`. All numbers are content.
   - `actor.move` steps into a cell that is not standable only when the profile has the
     `drop` capability; the player has it and guards do not, so a guard's path never
     walks off an edge.
   - A breach or a collapse under an actor is never refused: the actor falls through.
     The M6 claim 1 commit that refused `build.remove` under an actor is reverted.
     Building a cell piece into an actor's cell stays refused.
   - Property: over 10 000 generated build and move streams, every living actor stands
     on a standable cell or is falling. Every fall lands within `ticks_per_storey` × the
     storeys dropped, and the landing damage equals the formula.
2. **Climb, mantle and jump** (the §6.4 capability tags, ADR-011 C). A combat profile
   lists its `moves` from `walk`, `drop`, `climb`, `mantle` and `jump`, and a command
   whose move the profile lacks is refused.
   - **Climb.** `piece_kind` gains `climb_ticks` (0: not climbable) and `mantle`; every
     climb links *n* and *n*+1, so no offsets are needed. M6 ships `stair` (a cell
     piece placed with the facing of its foot, climbed from that side to its top) and
     `ladder` (a horizontal opening, climbed between the cell below and the cell above). `actor.climb {actor, piece}` moves an adjacent actor across
     at the piece's `climb_ticks`.
   - **Mantle.** `actor.mantle {actor, dx, dz}` (one axis, one cell) lifts the actor
     from storey *n* onto the top of the adjacent cell piece when its kind has
     `mantle: true` (M6: the crate). It needs the face between to be open or passable
     and headroom above the actor, and takes `mantle_ticks` from the profile. A
     foundation or a wall cannot be mantled.
   - **Jump.** `actor.jump {actor, dx, dz}` (one axis) crosses a one-cell gap on the same
     storey: the middle cell is not standable and holds no cell piece, both faces
     crossed are open or passable, the landing cell is standable, and it takes
     `jump_ticks`. Jumps never gain height.
   - The portal graph adds an edge for each climb, mantle and jump between the volumes
     they join, priced by its ticks and tagged with its move. Pathing filters edges by
     the agent's `moves` (the §6.4 rule that a guard never takes a move it cannot make).
     This closes G3 debt 4.
   - The client animates every move and every fall smoothly between the sim's states.
     Flips and rolls are client animation of these same moves; they arrive with a
     character rig (actors are capsules today) and are recorded as debt, not as a sim
     change.
3. **Openings have state.** Door, window, hatch and the new `grate` (a face piece; its
   material is `scrap_steel`) carry an `open` flag in the build snapshot.
   - A closed opening blocks movement and pathing.
   - A closed window does not block sight; a closed door, hatch or grate does. A window
     passes sight whether open or closed. This closes G4 debt 5: a closed window is now
     a breach, or an `open_cost` from inside.
   - `opening.open {actor, piece}` and `opening.close {actor, piece}` require an
     adjacent actor. An opening may declare a `lock: {credential}` tag; opening a locked
     piece requires an item carrying that tag in the actor's inventory, or the latch
     side (the volume declared `inside`).
   - Raid tokens keep paying `open_cost` exactly as in M3. Fixture hashes that change
     (new snapshot keys; windows no longer walkable in the M4 building) are regenerated
     in the commit that changes them, with the reason stated (invariant 9).
4. **The player can breach.** `build.breach {actor, piece}` needs the actor
   adjacent to the piece and a wielded `tool` item (a new content kind) of the
   material's breach class (`cutter` or `breacher`); the tool is read from the hand, so
   the payload does not repeat it. It takes the material's breach ticks, can be interrupted by
   moving or taking damage, and removes the piece through the existing
   `BuildSystem.breach`. It also emits `build.breached {actor, piece, removed}` with
   `actor` in place of `token`; raid tokens are unchanged.
   Breaching checks rights: it counts as `build` on the piece's parcel. A refusal is not
   allowed here, so the violation is recorded (heat, claim 11) and the breach goes ahead.
5. **Noise is an event.** `noise.emitted {source, x, y, z, loudness}` is one bus event
   that perception hears with its existing hearing model. `combat.fire` now emits
   through it, with the same numbers. The new sources are a breach (heard at the
   material's new `breach_reach_mm` every 40 ticks while it runs; `breach_noise` stays the
   portal graph's pricing weight, not a distance), a forced opening (which is a breach of
   that opening), a landing, and the hack (claim 9).
   Sound does not cross more than one storey, and each storey crossed costs a
   content-defined attenuation.
6. **Perception and pathing know storeys.** Sight is the existing line walk extended to
   3D. Floors block it, and so do openings whose kind blocks sight. Pathing searches per
   storey and joins storeys through climb edges.
   - Past `SEARCH_RADIUS`, the agent asks the portal graph for a volume-level route and
     paths cell by cell inside each volume on the way. This closes G4 debt 6.
   - Metamorphic relation: adding a closed door between an agent and a contact never
     raises the contact's awareness gain.
   - Metamorphic relation: removing a floor piece never lengthens a path that existed
     before.
7. **The portal graph rebuilds incrementally.** A `build.changed` marks only the volumes
   it touches as dirty. The flood fill reruns over the dirty set, and a whole-site spawn
   (claim 13) is one batched rebuild.
   - Budget: on the Deck, a single-piece change to the Cold Storage building costs at
     most 1.5 ms (standards §4.1, navigation), and the site spawn produces no hitch over
     one frame.
   - Property: over 10 000 build and destroy sequences, the incremental partition equals
     a full rebuild. This closes G4 debt 7.

## Phase 2 — Security (`sim/agents/`, `sim/threat/`, `sim/items/`)

8. **Cameras and sensors are agents and content.**
   - A camera is an `agent.spawn` with the new `camera` agent profile. Its perception
     profile is a 60° cone, 25 m, `gain_per_tick` 62 500, with radio. Its only stance is
     `hold`, it has no weapon, and it pans between two yaws from content.
   - A camera that crosses its alert threshold reports by radio like a guard
     (`squad.report`), so it can raise an alarm.
   - Shooting a camera kills it, and that counts as a trace.
   - `content/sensor/<id>.json` declares a sensor on an opening. M6 ships one kind,
     `power_monitor`. Opening, forcing or breaching the watched opening while the
     sensor is live emits `security.alarm {sensor, piece, squad}`, which the squad
     receives after its radio latency, as for a report.
   - A sensor is spoofed by a hack (claim 9), and a spoofed sensor stays silent for the
     rest of the run.
9. **The hack is a timed device task.**
   - `content/hack_target/<id>.json` declares `ticks`, `daemons` (its memory cost),
     `noise`, `reach_mm` and an `effect`. The effect is one of a registered set:
     `spawn_item {template}` or `spoof_sensor {sensor}`. A new effect kind is a
     registration, not a `match` (invariant 3).
   - `hack.start {actor, target}` requires all of the following: the equipped device
     provides `daemon_coprocessor`, the actor's free daemon slots
     (`memory_capacity` / 1000, minus the slots in use) cover the cost, and the actor
     is within reach on the same storey. The progress then runs once per tick, emitting
     `noise.emitted` every 40 ticks at the target's `noise`.
   - It is interrupted by the actor moving, firing, taking damage, dying, or
     `hack.cancel`. On completion it applies the effect, emits `hack.completed`, and
     leaves the terminal **logged in** until the actor submits `hack.logout` (which is
     pause-safe like the other device commands).
   - The hack is never pause-safe: pausing outside a safe parcel is refused anyway
     (ADR-006 C), and the hack does not advance while paused.
   - This replaces the M5 hacking placeholder (M5 debt 9).
10. **Credentials.** An item template may carry a `credential` tag (M6 ships
    `cold_storage_keycard`). The front door's lock names it.
    - The door also declares `check: {standing: heat, max}`. When the opener's heat is
      above `max`, the door still opens, but it emits `security.alarm` from its watching
      camera: "fails loudly if your heat is already high" (§15.2).
11. **Standing: heat and notoriety** (`sim/threat/standing_system.gd`, design doc §7.3).
    These are per-actor integer scalars. They are raised by bus events through content
    rules `{event, tags_any, amount}`, as skill XP rules already are, and they are kept
    in the snapshot.
    - M6 rules: an alarm raised against the actor and a witnessed trespass raise heat. A
      witnessed trespass is a `perception.alerted` whose contact stood in violation of
      `enter` that tick. A contract delivered raises notoriety.
    - Heat decays by a content rate per 1000 ticks; notoriety does not decay.
    - There is no visible wealth, no faction suspicion and no director. Those stay in
      M8, and `sim/threat/README.md` is amended to say this record arrives at M6.

## Phase 3 — The run (`sim/land/`, `sim/quests/`, `sim/items/`, `sim/agents/`)

12. **A site is content.** `content/site/<id>.json` declares:
    - its parcels (with vertical extents) and its district;
    - its pieces, by relative cell, kind and storey, with openings, locks, sensors and
      `inside` volumes;
    - its agents (profile, patrol route relative to the site, squad);
    - its hack targets;
    - an `exfil` polygon.

    `site.spawn {site, origin}` places all of it in one batched step owned by the
    site's owner tag, bypassing build rights in the same way the M2 plot seeding did.
    `client/m4_building.gd` is replaced by `content/site/m4_test_building.json`; the
    conversion alone does not change any M4 fixture's hash (checked in the commit that
    makes it).
13. **Cold Storage, authored.** One site of three storeys (−1, 0, 1) on a new
    `cold_storage` parcel in a new `docklands` district (`law_index` 500; its rights
    table makes `enter` a violation for non-owners).
    - A city-owned utility parcel below the street is a separate vertical parcel
      (`floor_y` −1000, `ceiling_y` 0). It holds the service tunnel, which proves the
      vertical parcel rule of §15.2.
    - **Front:** the lobby door is locked by the `cold_storage_keycard` and watched by
      the lobby camera, with the heat check.
    - **Side:** the storey-1 maintenance window is reached by mantling onto the yard's
      crate beneath it. It
      is watched by a `power_monitor`, and the monitor's hack target is reachable from
      the ground in the yard.
    - **Under:** a street grate (cutter) leads to a ladder down to the tunnel, a grate
      into the basement, and stairs up. This is the only route that never enters the
      lobby camera's cone.
    - Five guards and one camera: a static lobby post, two patrolling storey 1, one
      roaming between storeys by the stairs, one in the basement, and the lobby camera.
      They all run `guard_sim` at low stress.
    - The server-room terminal sits on storey 1 and its effect spawns `cold_storage_data`.
    - The keycard is obtainable in the world: it lies in an unlocked crate in the yard,
      a placement the fixer's briefing names.
14. **The contract is a quest with a site, a fixer and a score.** The quest schema
    gains:
    - `giver`, a `content/fixer/<id>.json` with its position, its lines (briefing,
      turn-in and refusal text) and a payout table;
    - `site`;
    - `deliver`, the item the fixer takes;
    - `scoring`.

    The run works like this:
    - `quest.accept` for a contract requires the actor to be within reach of the fixer.
      Accepting spawns the site if it is not spawned yet and opens a **run record**.
    - The run record counts the four §15.4 counters for the accepting actor, from bus
      events only:
      - `times_detected`: `perception.alerted` with the actor as contact;
      - `alarms_raised`: a `squad.report` or `security.alarm` about the actor that
        reached its squad;
      - `bodies`: a `combat.hit` with `killed` on a site agent fired by the actor;
      - `traces_left`: a breach by the actor on the site, a camera killed by the actor,
        and, counted once at exfil, every terminal still logged in and every forced
        opening.
    - Exfil is the actor leaving the `exfil` polygon carrying the deliverable.
    - `contract.deliver {actor, quest}` at the fixer transfers the deliverable to the
      fixer's container and pays out. The payout is the base credits × the scoring
      multiplier from content (all four counters zero gives the full-stealth bonus,
      then partial tiers), plus the reward items. It also emits `contract.delivered`,
      which raises notoriety.
    - A loud run still completes and pays less (§15.4).
    - Property: over 10 000 generated event streams, the counters equal a
      straightforward recount of the stream, and the multiplier never rises when any
      counter rises.
15. **Credits.** A per-actor integer balance in a new `wallet` system in `sim/items/`,
    changed only by registered sources (`contract.deliver`, and the city fee in
    claim 17), and never negative. There are no shops in M6.
16. **Death leaves a corpse** (ADR-007 C).
    - When any actor's fatal node reaches zero, a `corpse.<n>` container is created at
      the death position. All of the actor's items move into it in container order,
      including the wielded weapon and its magazines; the equipped device is the
      exception.
    - The player keeps the device: it is the UI, and it is how the recovery run finds
      the body. That is a recorded assumption, below.
    - The corpse is a world container with a position and a storey.
    - `item.take {actor, from, item}` and `item.drop {actor, item}` move items between
      a container within reach and the actor's inventory. Taking from a corpse that is
      not the actor's own requires `loot` where it lies, and a violation is recorded
      like any other. This is the first enforcement of `loot`.
    - Guards' corpses use the same rule, so their gear is real loot.
    - G4 debt 8 is fixed: a guard firing at a target killed in the same tick does not
      produce a rejected command, because the stance system drops dead contacts before
      it acts.
17. **Respawn, recovery and the city.** `actor.respawn {actor}` brings a dead player
    back alive at its home parcel's spawn cell, with full health and an empty inventory
    apart from the device. The run record stays open, so the contract can still be
    finished.
    - **City softening:** at death, in a district whose `law_index` is at or above
      `city_recovery.min_law_index` (content: 400), each item in the corpse is
      independently returned to the player's base container with probability
      `law_index` / 1000. The draw is a fixed seeded sequence from `sim.rng()` in
      container order. Each returned item costs `city_recovery.fee` credits, and the
      return stops at the first item the wallet cannot pay for. The rest stays in the
      corpse.
    - The corpse persists until it is emptied. Scavenging by factions is M8 (the threat
      director), recorded as debt.
    - **Item conservation property** (ADR-007 verification): over 10 000 generated
      streams of spawn, transfer, death, recovery, take, drop and deliver, every item
      id exists in exactly one container at every tick, and no id appears or
      disappears except through `item.spawn`, delivery, or a magazine round being
      consumed by firing.
18. **The player has an aim and a stress profile** (G4 debt 10): `content/aim_profile/player.json`
    and `content/stress_profile/player.json`, applied through the existing resolver. Hits
    on the player raise stress like any agent's, and stress widens the player's aim
    cone. Data only.

## Phase 4 — Client, fixtures and evidence

19. **Client.**
    - The world view draws storeys (cutaway above the player's storey), openings
      (open and closed), cameras with their cone, corpses, the fixer, the exfil zone,
      and the site from content.
    - The device gains the **hacking** pane (target list in reach, slots, a progress bar
      that keeps the world visible behind it, cancel and logout), a **contract** view in
      the quests app (briefing, the four counters live, payout tier), and the credit
      balance on the shell bar.
    - Interacting (open, take, climb, breach, deliver) is one context button that names
      its target with its glyph.
    - The device panel scales to the viewport at 1280×800 and at one other resolution
      (M5 debt 3). The inventory app sorts by kind and name (M5 debt 11).
    - The M1 range demo runs on ticks (M5 debt 13).
    - Screenshots of every new pane and of each route.
20. **Fixtures**, generated by `tools/make_m6_fixtures.gd`:
    - `m6-stealth`: under route, all four counters zero, bonus paid. This is G6's
      stealth-scoring proof.
    - `m6-front`: keycard, low heat, door opens silently.
    - `m6-front-hot`: high heat, the camera alarm.
    - `m6-side`: mantle onto the crate, monitor spoofed, silent window.
    - `m6-fall`: a drop off the roof edge, a jump across a gap, and a floor breached
      under a guard, who falls and takes the content's damage.
    - `m6-loud`: breach the lobby, alarm, a body, reduced payout, heat raised.
    - `m6-death`: death mid-run, corpse, respawn, recovery, deliver.
    - `m6-city-death`: the law-index softening and the fee.
    - `m6-hack-interrupt`: hit during the hack, progress lost.
21. **Everything is in the snapshot and survives the round trip**: storeys, opening
    state, sensors, hack progress and logins, standing, wallets, corpses, run records,
    and spawned sites. The save property's stream gains every new command kind. Save
    schema **version 2**, with a tested migration from version 1 (an empty corpse, wallet
    and standing set) and the round-trip property over both versions.
22. **Schemas** for `site`, `fixer`, `sensor`, `hack_target`, `standing_rule` and the
    `city_recovery` block. The district, quest and `piece_kind` schemas are extended.
    The **corpus** is extended with every new command kind and with hostile site files
    (overlapping pieces, an agent outside the site, a patrol off the floor, an unknown
    effect).
23. **Mutation testing.** `tools/mutate.py` is a GDScript mutation runner over `sim/`
    (pinned, no new dependency beyond the standard library).
    - Operators: comparison flip, ±1 on integer constants, boolean negation, `and`/`or`
      swap, and an early `return` at the top of a function body.
    - Each mutant runs the test directories mapped to its module. The runner samples at
      least 400 mutants with a fixed seed, at least 30 per module, and reports the
      score with a 95 % interval.
    - The gate requires the point estimate to be at least 70 % and records the
      survivors that tests were added for. It runs on a scheduled CI job, not per
      commit (standards §3.6).
24. **The Deck run.** A native Linux export is sideloaded on the Deck. The gate records:
    - the frame budget with all six security agents active in the building, as 1 % and
      0.1 % lows;
    - a 30-minute thermal soak running the stealth fixture in a loop;
    - the ADR-006 legibility check (hack outside a safe parcel with a guard approaching);
    - a suspend and resume during a hack (standards §8.6);
    - one hand-played run of each route, with feel notes (it closes M5 debt 12's
      assumption with a real hand).

## Out of scope (goes to the debt log if touched)

- Travel and region transition (the route graph, macro nav and danger tier are M7): the
  site is reached on foot in the same loaded world.
- Site binding (M7); the quest director (M7).
- The drone-carried line on the side route (drones are M7).
- Digging, because terrain is M7 under ADR-003; the under route is a grate cut.
- Faction suspicion, signals, visible wealth, scavengers and raids (M8).
- The sim combat stages: Cold Storage is inside the city, where §13.1 uses the arcade
  profile; the sim stages arrive with the badlands in M7.
- Non-lethal takedowns, because the stealth bonus is reached by avoidance.
- Shops and an economy beyond the fixer.
- Dialogue beyond the fixer's fixed lines.
- Lighting (G4 debt 9).
- The on-screen keyboard: nothing in M6 takes text (M5 debt 5, rescheduled to the first
  milestone that does).
- Free physics movement: continuous jumping, climbing any ledge, parkour (ADR-011 C:
  a later milestone after a spike). Flips and rolls wait for a character rig.

## Conditions planned for G6 (CEOGG, 2026-10-08: the Steamworks app is not registered)

G6 is submitted as **Accepted with conditions**, and the conditions are scheduled into
**M7**. Each one closes when the Steamworks app is registered:

1. The gate build is installed on the Deck through Steam on the `gate` branch, with a
   SteamPipe upload from CI.
2. The Steam Input layout is bound and the action sets are activated (M5 debt 2, 4).
3. Steam's own glyph API replaces the bundled set (M5 debt 4).
4. The Steam Cloud file set is synced (M5 debt 6).

Every other G6 proof is met without them.

## Open points

- **Scale.** M6 is the largest milestone so far: 24 claims across seven `sim/` modules,
  in roughly 25–30 single-system commits. If a phase grows past one sitting, it splits
  at a commit boundary; the spec does not change.
- **Order of guards on storeys.** §15.3 says "two patrol the upper floor". The fifth
  guard (in the basement) is within §15.3's "four to six" and keeps the under route from
  being free. CEOGG may remove it with one content change.
- **The city recovery numbers** (`min_law_index` 400, the fee) are first values to be
  tuned in the hand-played run, not design.

## Assumptions to record in the gate

- The player keeps the device on death (claim 16). Losing it would leave no UI to find
  the body.
- A dead player respawns at home immediately. A respawn timer or a choice of safehouse
  waits for a hub (ADR-010).
- Storeys are one build cell high in the sim and there is no free vertical movement; ramps and terrain
  height are M7.
- One run record per accepted contract per actor; re-accepting an abandoned contract
  opens a fresh record.
- Exfil requires leaving the polygon with the deliverable; no extraction timer.
- Storey −1 is solid earth except the cells a site excavates (there is no terrain or dig
  before M7); excavated cells stand on bedrock, and the only ways down are climb pieces
  and cut ground faces. (Amended at claim 6: the claim-2 draft had bedrock everywhere,
  which made the whole underground walkable.)

## Extension exercise for Q4 (standards §11)

Add a second contract at a second, smaller site (`content/site/kiosk.json`, two storeys,
one guard, one camera, one hack target with a new `spoof_sensor` use) with its own
fixer lines and payout table, using only new content files. `tools/test.sh` passes, a
fixture completes it full-stealth, and the diff under `sim/` is empty. The procedure is
recorded in `docs/extending-sites.md`.

## Fixtures and property seeds

| Test | Cases | Fixed seed constant |
|---|---|---|
| Every living actor standing or falling; falls land on time with the formula's damage | 10 000 build/move streams | `tests/agents/test_storey_movement.gd` |
| Climb, mantle and jump: refused without the move or the geometry; never gain more than one storey | 10 000 | `tests/agents/test_moves.gd` |
| Incremental portal rebuild equals full rebuild | 10 000 build/destroy sequences | `tests/nav/test_portal_incremental.gd` |
| Closed door never raises awareness gain; removing a floor never lengthens a path | 10 000 each (metamorphic) | `tests/agents/test_storey_metamorphic.gd` |
| Hack: completes once, interrupted on every listed cause, slots never over-committed | 10 000 | `tests/items/test_hack.gd` |
| Run counters equal a recount; multiplier monotone | 10 000 event streams | `tests/quests/test_contract_run.gd` |
| Item conservation across death, corpse, recovery, take, drop, deliver | 10 000 | `tests/items/test_item_conservation.gd` |
| Standing never negative; heat decay exact | 10 000 | `tests/threat/test_standing.gd` |
| Save round trip over v1 and v2 with every new command kind | 10 000 | `tests/sim/test_save_file.gd` (extended) |
| Command payload fuzz, every new kind; hostile site files | corpus + 10 000 mutations | `tests/fuzz/commands/`, `tests/fuzz/content/` |
| Mutation score on `sim/` | ≥ 400 sampled mutants | `tools/mutate.py` |

A failing seed is committed as a named regression case (standards §3.2).
