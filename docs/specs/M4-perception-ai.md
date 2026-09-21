# M4 — Perception AI: specification

Milestone M4 of `docs/gcity-design.md` §16, in the terms of that document. Written
before implementation (standards §2.1, §10.2). Status: **draft, awaiting approval**
(submitted 2026-09-21).

**Preconditions.** G3 is signed in `docs/gates/M3-gate.md` (it is). Two ADRs block
this milestone and are still `proposed`: **ADR-004** (sensor-gated detection, option
A) and **ADR-008** (arcade enemies are the same AI retuned, option A). This spec is
written against both proposed options because the design doc assumes them throughout
(§7.4, §14.6). **No code starts until both carry CEOGG's signature.** If either closes
otherwise, claims 1–4 (ADR-004) or claim 12 (ADR-008) are rewritten before any code.

**The claim of the milestone.** Perception is a process, not a check (§14.1). An
agent accumulates awareness of a contact over ticks, driven by exposure, distance,
the contact's movement and noise, with a detection delay before the first shot and a
memory that decays. Aim quality is separate from awareness (§14.2): an error cone
converges while the target stays visible and resets on broken contact, so peeker's
advantage falls out of the model. Stress changes behaviour, not just accuracy
(§14.3). Stance is chosen by utility scoring with hysteresis and executed by a small
state machine (§14.4). Squads coordinate on the portal graph and report by radio, not
telepathy (§14.5). Everything runs time-sliced inside the §4.1 agent budget on the
Deck (§14.6). `time_to_first_shot` is tuned here, in isolation, on a hand-built
building with four to six guards, before any level design depends on it. G4's proof
(standards §11): frame budgets in §4.1 re-derived from real Deck measurements;
`time_to_first_shot` tuned and recorded; the metamorphic AI relations pass; the
thermal soak test is clean.

## Claims

### Perception (`sim/agents/`)

1. **Perception is content.** `content/perception_profile/<id>.json` declares
   `sight_range_mm`, `fov_mdeg` (milli-degrees, integer), `gain_per_tick` (awareness
   milli-units per tick at full exposure), `decay_per_tick`, `alert_threshold`,
   `memory_ticks`, `hearing_range_mm` and `speed_gain_per_mm_per_tick` (a moving
   contact is easier to notice). `content/agent_profile/<id>.json` binds a
   `combat_profile`, a `perception_profile`, an `aim_profile` (claim 6), a
   `stress_profile` (claim 8) and the list of stances the agent may choose (claim 10).
   M4 ships two agent profiles, `guard_sim` and `guard_arcade` (claim 12), and one
   perception profile each. All numbers are integers (ADR-002); there is no float in
   the agent systems.
2. **Awareness is an integer accumulator per (observer, contact) pair** in
   `[0, AWARENESS_MAX]` (milli-units, `AWARENESS_MAX = 1_000_000`). Each tick an
   observer gains awareness of every contact it can see (claim 3) proportional to
   exposure: full inside `sight_range_mm / 2`, linear falloff to zero at the range,
   plus the contact's speed term; it decays by `decay_per_tick` toward zero when the
   contact is not seen or heard. Crossing `alert_threshold` emits
   `perception.alerted {observer, contact, tick}` once per contact until awareness
   falls back under the threshold. **`time_to_first_shot`** for a profile is the
   number of ticks from first exposure at rest at 10 m in an open room to the first
   `combat.fire` by the observer, and it is a recorded number in the gate package,
   for both agent profiles, plugged and on battery (it is deterministic, so both
   runs must agree; the Deck run confirms the feel, not the number).
3. **Line of sight is an integer walk on the build grid.** A contact is visible when
   it is inside the observer's `fov_mdeg` about its facing, inside `sight_range_mm`,
   and the 3D DDA from the observer's cell to the contact's cell crosses no face that
   a solid piece occupies (walls, floors, foundations block; doors block when closed
   and pass when open; windows pass sight and block movement, using the M3 piece
   kinds and no new flags on them). Properties over 10 000 random structures: LoS is
   symmetric; LoS never crosses a wall face; a contact in the same volume with no
   piece between the two cells is always visible inside the range and cone.
4. **Noise is an event, and hearing goes to a position, not an actor.** `combat.fire`
   carries `loudness_mm` from the weapon frame's resolved `noise` stat (content, via
   the stat resolver; the M1 frame gains one number). Every agent within
   `hearing_range_mm` and `loudness_mm` of the shot gains awareness of the shooter
   *and* records the shot's position as its last-known position, so a guard who heard
   but did not see walks to the noise (claim 10, `investigate`). Property: a shot
   farther away than both ranges changes no agent's state.
5. **Memory is a position and a timer.** When a seen contact leaves sight, the
   observer keeps the contact's last-known cell for `memory_ticks`, then forgets it;
   awareness decays throughout. A contact is never fired at unless it is visible now
   (claim 7); memory drives stances, not shots.

### Aim, stress and decisions (`sim/agents/`)

6. **Aim is an error cone converging on a curve, applied through the stat resolver.**
   `content/aim_profile/<id>.json` declares `cone_start_mdeg`, `cone_settled_mdeg`,
   `settle_ticks`, `swing_penalty_mdeg` and `swing_ticks`. Per (agent, target) the
   sim keeps `settle` in `[0, settle_ticks]`: it rises by one each tick the target is
   visible and resets to zero when sight breaks; a target that becomes visible after
   being unseen adds the swing penalty for `swing_ticks`. The current cone becomes an
   `aim` modifier on the agent's `hit_chance` (design doc §10.2) so the existing
   `hit_roll` stage needs no branch and the player's own hit chance is unaffected
   unless the player has an aim profile (they do not at M4). Metamorphic (standards
   §3.4): longer continuous exposure never lowers the agent's hit chance; a broken
   contact never raises it; a wider `cone_settled_mdeg` never raises it.
7. **Agents fire through `weapon.fire`, the same command path the client uses,** so
   the hostile corpus and the stage pipeline cover them. The sim submits the command
   on the agent's behalf in tick order by agent id. One sim change to the combat
   system: `weapon.fire` on a target that the shooter cannot see (claim 3) is a
   miss with `reason: no_los`, for players and agents alike. This replaces the
   client-side aim of G3 debt item 6 with the sim's own answer.
8. **Stress is per-agent, integer, and changes behaviour.**
   `content/stress_profile/<id>.json` declares gains for `fired_at` (a shot whose
   line passes within `near_miss_mm`), `hit`, `squadmate_down`, a `decay_per_tick`,
   a `break_threshold` (the agent prefers `retreat`) and a `rout_threshold` (the
   agent may only `retreat` or `surrender`). Stress is a `stress` modifier on
   `hit_chance` through the resolver. Metamorphic: more stress never improves aim;
   a routed agent never advances.
9. **Movement inside a volume is A\* on the 1 m cell grid; across volumes it is the
   portal graph.** Agents move with `actor.move` (claim P1) toward the next cell of a
   path planned on open build cells within the current volume, and pick the next
   volume with the M3 raid planner's edges (they never breach at M4: only open
   doors and open faces are traversable for agents). The planner is budgeted: at
   most `PATH_NODES_PER_TICK` expansions per tick across all agents, resumable on
   the next tick (standards §8, "time-sliceable and interruptible"). Property over
   10 000 random structures: a path returned never crosses a wall face; a path exists
   whenever the two cells share a volume through open faces.
10. **Stance is utility-scored with hysteresis; execution is a state machine.**
    Stances are registry entries in `content/stance/` (`hold`, `advance`, `flank`,
    `retreat`, `investigate`, `surrender`), each with a scorer registered by name in
    the sim (a registration call per stance, the M1 stage pattern) and integer
    weights in the agent profile. Every `SCORE_EVERY` ticks an agent scores its
    allowed stances from awareness, stress, distance to the contact, cover (a solid
    face between the agent's cell and the contact's) and its squad's assignment, and
    switches only if the winner beats the current stance by `HYSTERESIS` and the
    current stance has run `MIN_STANCE_TICKS`. Scoring is time-sliced: agent `i`
    scores on ticks where `tick mod SCORE_EVERY == i mod SCORE_EVERY`, so the work
    per tick is bounded by the agent count divided by `SCORE_EVERY`. Determinism: the
    order is agent id, the numbers are integers, and the slice cadence is sim
    constant, so it is part of the hash.
11. **Squads coordinate on the portal graph and report by radio.** A squad is a set
    of agents with a shared id; `perception.alerted` on one member becomes
    `squad.report {squad, contact, cell}` delivered to the others after
    `radio_latency_ticks` (content on the agent profile) **only if** the reporter's
    `radio` flag is set, which is the minimal form of the §7.4 signal machinery and
    the hook for jamming later. The squad planner assigns members distinct entry
    edges of the contact's volume (the cheapest `k` edges of the M3 plan), so one
    agent takes the door while another covers the window. Metamorphic: removing a
    radio never makes the squad alert sooner; adding a member never raises the
    alert latency of the others.
12. **Arcade is the same AI with different numbers (ADR-008 A).** `guard_arcade`
    binds the `arcade` combat profile, a perception profile with a shorter detection
    delay, an aim profile with a wider cone, a stress profile with low sensitivity,
    and a stance list without `flank` (the tactical-sophistication knob ADR-008's
    consequences ask for). There is no code branch on the profile; the fixture of
    claim 14 runs the same building under both.

### Budget and Deck measurement

13. **The agent budget is measured on the Deck, not asserted.** `tools/bench_agents.gd`
    runs the M4 building fixture headless with 6 agents for 12 000 ticks (five
    minutes of sim) and prints per-tick sim time, 1 % and 0.1 % lows, as JSON. The
    client gains `--capture=<path>` (frame times to JSON, the §4.2 artefact) and
    `--demo-loop` (the demo repeats until quit, for the soak). The gate package
    records, from the export on the Deck, plugged and on battery: the agent row of
    §4.1 (target 3.0 ms), the navigation row (the M3 rebuild cost, G3 debt items 2
    and 12), and the thermal soak (30 minutes of `--demo-loop`, frame-time lows from
    the final 5 minutes). The §4.1 table is revised in the same package with the
    measured numbers. `MAX_SIMULATED_AGENTS` is a sim constant set from that
    measurement; agents beyond it are refused at spawn (the macro token model of
    §6.2 is M7).

### Save, fixtures, content, client

14. **Replay fixtures** on a hand-built single-storey building of M3 pieces (a lobby
    with a door, a corridor, two rooms with windows), built by the fixture's own
    command stream, with a static post, two patrollers on a `content/patrol_route/`
    (a list of cells, a registry kind) and one roamer:
    `m4-detect.json` (the player walks into the lobby guard's view and stands; the
    first shot lands exactly `time_to_first_shot` ticks after first exposure);
    `m4-break-contact.json` (seen for a moment, back behind the wall; awareness
    decays, no shot, the guard investigates and returns to post);
    `m4-noise.json` (one player shot outside; the roamer walks to the noise, looks,
    returns);
    `m4-radio.json` (the lobby guard spots the player; the upper-room guards react
    after the radio latency; the same stream with the radio flag off leaves them on
    patrol);
    `m4-arcade.json` (the `m4-detect` stream under `guard_arcade`: fewer ticks to
    the first shot, recorded).
15. **Everything is in the snapshot and survives the save round trip**: awareness,
    memory, settle, stress, stance, path progress, squads, reports in flight. The
    save property (10 000 generated sims) gains agent spawns and both player
    commands in its stream. Save schema stays at version 1.
16. **Schemas** for `perception_profile`, `aim_profile`, `stress_profile`,
    `agent_profile`, `stance`, `patrol_route`; cross-references checked at build and
    stance scorers checked at assembly (a profile naming a stance with no scorer
    fails assembly, not the playtest).
17. **Commands**: `agent.spawn {profile, cell, facing, squad, route}` and
    `agent.set_profile {agent, profile}` (the demo's profile toggle), both
    debug-class like `actor.spawn` (G1 debt item 4). Hostile corpus extended with
    every new kind and payload.
18. **Client**: the world view loads the M4 building and shows guards as capsules
    coloured by stance, an awareness bar and a last-known-position marker per guard,
    and the LoS line to the player when a guard sees them; a Deck-operable debug
    overlay (D-pad, no keyboard) toggles the profile of all guards and the
    awareness/LoS drawing. The M1 range demo moves to sim ticks (G3 debt item 8,
    the one `client/main.gd` touch). Screenshots of both profiles in the gate
    package.

## Out of scope (goes to the debt log if touched)

Suspicion, informant density and faction-held knowledge (§7.4, M8; ADR-004's own
metamorphic relation on `informant_density` is verified there, since signals do not
exist before M8), the threat director and raid scheduling (M8), breaching by agents
(M8), stairs, floors and vertical movement (G3 debt item 4: stays at y = 0 through
M4; M6 decides), a navmesh or capsule steering (agents step cell to cell with the M3
movement rules), non-lethal takedowns and surrender consequences beyond the stance
(M6), drones and macro tokens (M7), the player's own aim profile, and any number
claimed as a budget before the Deck measured it.

## Open points

- **ADR-004 and ADR-008** must be accepted before code (see Preconditions). Both are
  proposed as A and this spec assumes A.
- **Initial `time_to_first_shot`** to tune from: 32 ticks (0.8 s at 40 Hz) for
  `guard_sim`, 12 ticks (0.3 s) for `guard_arcade`, at rest at 10 m in an open room.
  The Deck run moves these numbers; the gate records the final values.
- **Cadence constants** proposed: `SCORE_EVERY = 8` (5 Hz, the top of §14.6's
  2–5 Hz), `MIN_STANCE_TICKS = 40`, `PATH_NODES_PER_TICK = 256`. Revised at G4 from
  the measurement of claim 13.

## Assumptions to record in the gate

- Lighting is not modelled at M4 (§14.1 lists it): exposure is distance, cone and
  movement only. A `light` term joins the gain when the world has lights (M6/M7).
- Agents at M4 wield the M1 pistol; there is no second weapon.
- Cover is a solid face between two cells, not a height model; crouching does not
  exist.
- A closed door blocks sight and movement; doors have no lock state before §9.1 (M8).

## Extension exercise for Q4 (standards §11, G4)

Add a third agent profile, `sentry_drone` (`content/agent_profile/sentry_drone.json`
with its own perception, aim and stress profiles: wide cone, long range, no hearing,
stance list `hold` and `retreat` only) and a second patrol route, using only new
files under `content/`; `tools/test.sh` passes, the metamorphic relations hold with
the new profile in the mix, and the diff under `sim/` is empty.
`docs/extending-agents.md` records the procedure.

## Fixtures and property seeds

| Test | Cases | Fixed seed constant |
|---|---|---|
| LoS symmetric, never through a wall, always within a clear volume | 10 000 structures | `tests/agents/test_perception_system.gd` |
| Awareness in range; gain monotone in exposure; noise beyond range is a no-op | 10 000 | `tests/agents/test_perception_system.gd` |
| Metamorphic: reduced perception never lowers `time_to_first_shot`; exposure never lowers hit chance; broken contact never raises it; stress never improves aim | 10 000 | `tests/agents/test_aim_and_stress.gd` |
| Path never crosses a wall; exists within a volume; budget resumes correctly | 10 000 structures | `tests/agents/test_agent_pathing.gd` |
| Stance always from the allowed list; hysteresis holds; routed never advances | 10 000 | `tests/agents/test_stance_scoring.gd` |
| Radio: no radio never alerts sooner; more members never raise latency | 10 000 | `tests/agents/test_squad.gd` |
| Save round trip with agent state and commands in the stream | 10 000 | `tests/sim/test_save_file.gd` (extended) |
| Command payload fuzz, every new kind | corpus + 10 000 mutations | `tests/fuzz/commands/` |

A failing seed is committed as a named regression case (standards §3.2).
