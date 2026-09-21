# `sim/agents`

AI, perception, utility scoring, squads (design doc §14). At M1 only the skeleton an
actor needs to stand on a range.

| File | What |
|---|---|
| `perception_system.gd` | `PerceptionSystem` (system id `perception`): agents as actors bound to an `agent_profile`; per (observer, contact) integer awareness gained by sight (cone, range, an integer line walk over the build grid) and by hearing `combat.fire`, decayed while unseen, with a last-known position kept for the profile's memory; `perception.alerted` once per threshold crossing (design doc §14.1; M4 spec claims 1–5). Owns `agent.spawn` and `agent.set_profile` (debug-class). |
| `aim_system.gd` | `AimSystem` (system id `aim`): per agent, the visible contact it is most aware of and an error cone that settles over `settle_ticks`, resets on broken contact and swings on a new target; applied as one `aim` modifier on `hit_chance` tagged `weapon`, so the wielded weapon inherits it and `hit_roll` has no branch (design doc §14.2; M4 spec claim 6). |
| `stress_system.gd` | `StressSystem` (system id `stress`): per-agent stress raised by being fired at (a shot at it or within `near_miss_mm` of it), by being hit and by a squadmate going down, decayed per tick; one `stress` modifier on `hit_chance` tagged `weapon`; `is_broken` / `is_routed` for the stance scorer (design doc §14.3; M4 spec claim 8). |
| `pathing_system.gd` | `PathingSystem` (system id `pathing`): budgeted, resumable A* on the 1 m cell grid through open faces and doors (`PATH_NODES_PER_TICK` expansions per tick across all agents, `SEARCH_RADIUS` cells), walked with movement-rule steps, re-planned on every build change (M4 spec claim 9). |
| `actor_system.gd` | `ActorSystem` (system id `actors`): actors as entities with a combat profile, a health graph shaped by it (design doc §13.2), a wielded-weapon slot that links the weapon into the actor's modifier inheritance, and a declared range. Owns `actor.spawn` (debug-class) and `actor.wield`. |

**Allowed imports:** `sim/` only.

**Introduced at:** M1 (player and target dummies). Perception at M4; aim, stress, stances and squads follow in the same milestone.

**Extension point:** profiles and health graphs are `content/combat_profile/` files; see
[docs/extending-items.md](../../docs/extending-items.md) § Combat. Perception, aim and stress numbers are
`content/perception_profile/`, `content/aim_profile/` and `content/stress_profile/` files bound by
`content/agent_profile/`.
