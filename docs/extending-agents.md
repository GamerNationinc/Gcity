# Extending: agents, perception, aim, stress, stances, routes and squads

The minimal diff for each thing the agent layer (`sim/agents/`) can be extended with.
Design doc §14; M4 spec claims 1, 6, 8, 10, 11, 14. The G4 extension exercise is a
third agent profile (`sentry_drone`) with its own perception, aim and stress
profiles and a second patrol route, data only, empty `sim/` diff.

## Vocabulary

- **Agent**: an actor bound to an `agent_profile`; spawned by `agent.spawn` at a cell
  with a facing (whole degrees, 0 along +x, 90 along +z), a squad id (0 = none) and
  an optional patrol route.
- **Awareness**: an integer per (observer, contact) in 0..1 000 000, gained by sight
  and hearing, decayed while neither; crossing the profile's threshold is an alert
  (`perception.alerted`), once per crossing. A last-known position outlives it for
  `memory_ticks`.
- **Cone**: the agent's error cone in milli-degrees; it converges while its target
  stays visible and reaches combat as an `aim` modifier on `hit_chance`. **Stress**
  reaches combat the same way (`stress`), and its thresholds mark the agent broken
  or routed for the stance scorer.
- **Stance**: what the agent commits to (`content/stance/`), chosen by utility
  scoring with hysteresis every `SCORE_EVERY` ticks on the agent's slot, executed
  every tick: face the target, fire through `weapon.fire`, walk through the pathing
  system.
- **Squad**: agents sharing a squad id; an alert becomes a `squad.report` to the
  others after the reporter's radio latency, if it has a radio.

## A new agent profile: four files

1. `content/perception_profile/<id>.json`: `sight_range_mm`, `fov_deg`,
   `gain_per_tick`, `speed_gain_per_mm_per_tick`, `decay_per_tick`,
   `alert_threshold`, `memory_ticks`, `hearing_range_mm`, `hearing_gain`. No
   hearing is `hearing_range_mm: 0`.
2. `content/aim_profile/<id>.json`: `cone_start_mdeg`, `cone_settled_mdeg`,
   `settle_ticks`, `swing_penalty_mdeg`, `swing_ticks`, `penalty_per_mdeg`.
3. `content/stress_profile/<id>.json`: `near_miss_mm`, `gain_fired_at`, `gain_hit`,
   `gain_squadmate_down`, `decay_per_tick`, `break_threshold`, `rout_threshold`,
   `hit_penalty_at_max`. A machine that feels nothing has zero gains.
4. `content/agent_profile/<id>.json`: `combat_profile` (the health graph, the
   pipeline stages and the walking speed), the three profiles above, `stances`
   (`{stance, weight}`, 1000 is neutral; the list is the tactical-sophistication
   knob of ADR-008: no `flank` makes a duller enemy), `radio` and
   `radio_latency_ticks`.

Every id is checked at build (`tools/validate_content.py`) and every stance must have
a scorer at assembly, or the sim refuses to start. `tests/agents/test_extension_agents.gd`
spawns every profile in `content/` and checks the metamorphic relation on each.

## A new patrol route: one file

`content/patrol_route/<id>.json`: `cells`, absolute build cells walked in order and
looped. An agent with a route walks it while holding; any other stance interrupts it
and hold resumes it from the nearest waypoint index.

## A new stance: one file and one registration call

`content/stance/<id>.json` names it; a scorer `func(ctx: Dictionary) -> int` in
0..1 000 000 is registered with `StanceSystem.register_scorer(&"<id>", scorer)`
before assembly, and its execution is a branch of `_execute` (the one place the
stance's goal and firing rule live). The context carries `known`, `visible`,
`alerted`, `awareness`, `distance_mm`, `stress`, `broken`, `routed`, `in_cover`,
`route` and `current`. A stance nobody's profile names costs nothing.

## What you may not do

- Read the clock, the input, or anything under `client/` from a scorer.
- Give a profile a stance with no scorer, or a route that is not cells.
- Let the client set awareness, stance or facing: those are the sim's; the client
  submits `agent.spawn` and `agent.set_profile` (both debug-class) and reads.
