# `sim/agents`

AI, perception, utility scoring, squads (design doc §14). At M1 only the skeleton an
actor needs to stand on a range.

| File | What |
|---|---|
| `perception_system.gd` | `PerceptionSystem` (system id `perception`): agents as actors bound to an `agent_profile`; per (observer, contact) integer awareness gained by sight (cone, range, an integer line walk over the build grid) and by hearing `combat.fire`, decayed while unseen, with a last-known position kept for the profile's memory; `perception.alerted` once per threshold crossing (design doc §14.1; M4 spec claims 1–5). Owns `agent.spawn` and `agent.set_profile` (debug-class). |
| `actor_system.gd` | `ActorSystem` (system id `actors`): actors as entities with a combat profile, a health graph shaped by it (design doc §13.2), a wielded-weapon slot that links the weapon into the actor's modifier inheritance, and a declared range. Owns `actor.spawn` (debug-class) and `actor.wield`. |

**Allowed imports:** `sim/` only.

**Introduced at:** M1 (player and target dummies). Perception at M4; aim, stress, stances and squads follow in the same milestone.

**Extension point:** profiles and health graphs are `content/combat_profile/` files; see
[docs/extending-items.md](../../docs/extending-items.md) § Combat. Perception numbers are
`content/perception_profile/` files bound by `content/agent_profile/`.
