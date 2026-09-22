# `sim/agents`

AI, perception, utility scoring, squads (design doc §14). At M1 only the skeleton an
actor needs to stand on a range.

| File | What |
|---|---|
| `perception_system.gd` | `PerceptionSystem` (system id `perception`): agents as actors bound to an `agent_profile`; per (observer, contact) integer awareness gained by sight (cone, range, an integer line walk over the build grid) and by hearing `combat.fire`, decayed while unseen, with a last-known position kept for the profile's memory; `perception.alerted` once per threshold crossing (design doc §14.1; M4 spec claims 1–5). Owns `agent.spawn` and `agent.set_profile` (debug-class). |
| `aim_system.gd` | `AimSystem` (system id `aim`): per agent, the visible contact it is most aware of and an error cone that settles over `settle_ticks`, resets on broken contact and swings on a new target; applied as one `aim` modifier on `hit_chance` tagged `weapon`, so the wielded weapon inherits it and `hit_roll` has no branch (design doc §14.2; M4 spec claim 6). |
| `stress_system.gd` | `StressSystem` (system id `stress`): per-agent stress raised by being fired at (a shot at it or within `near_miss_mm` of it), by being hit and by a squadmate going down, decayed per tick; one `stress` modifier on `hit_chance` tagged `weapon`; `is_broken` / `is_routed` for the stance scorer (design doc §14.3; M4 spec claim 8). |
| `pathing_system.gd` | `PathingSystem` (system id `pathing`): budgeted, resumable A* on the 1 m cell grid through open faces and doors (`PATH_NODES_PER_TICK` expansions per tick across all agents, `SEARCH_RADIUS` cells), walked with movement-rule steps, re-planned on every build change (M4 spec claim 9). |
| `stance_system.gd` | `StanceSystem` (system id `stances`): utility scoring over the profile's allowed stances (content `stance/` entries with a scorer registered by name), hysteresis and a minimum stance duration, time-sliced by agent id; execution faces the target, fires through `weapon.fire` at an alerted target in sight, and walks through `PathingSystem` (patrol routes on hold, advance, flank, retreat, investigate, surrender). A routed agent may only retreat or surrender (design doc §14.4; M4 spec claim 10). |
| `squad_system.gd` | `SquadSystem` (system id `squads`): a member's `perception.alerted` becomes a `squad.report` to the other members after its profile's `radio_latency_ticks`, only if it has a `radio`; receivers learn the cell and rise to their alert threshold. The planner assigns members outside the contact's volume distinct entry edges, cheapest first (design doc §14.5; M4 spec claim 11). |
| `movement_system.gd` | `MovementSystem` (system id `movement`): `actor.move {actor, dx, dz}` and, from M6, `dy` in whole cell levels; standing (a floor under the cell, a solid below, the ground, or the stairs themselves), climbable faces, and gravity: an actor over nothing falls a level a tick and takes `fall_damage_per_level` for every level beyond the first (M3 claim P1; M6 claim 1). |
| `actor_system.gd` | `ActorSystem` (system id `actors`): actors as entities with a combat profile, a health graph shaped by it (design doc §13.2), a wielded-weapon slot that links the weapon into the actor's modifier inheritance, and a declared range. Owns `actor.spawn` (debug-class) and `actor.wield`. |

**Allowed imports:** `sim/` only.

**Introduced at:** M1 (player and target dummies). Perception at M4; aim, stress, stances and squads follow in the same milestone.

**Extension point:** profiles and health graphs are `content/combat_profile/` files; see
[docs/extending-items.md](../../docs/extending-items.md) § Combat. Agents, their perception, aim,
stress, stances, routes and squads: [docs/extending-agents.md](../../docs/extending-agents.md).
