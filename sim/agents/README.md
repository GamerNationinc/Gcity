# `sim/agents`

AI, perception, utility scoring, squads (design doc §14). At M1 only the skeleton an
actor needs to stand on a range.

| File | What |
|---|---|
| `actor_system.gd` | `ActorSystem` (system id `actors`): actors as entities with a combat profile, a health graph shaped by it (design doc §13.2), a wielded-weapon slot that links the weapon into the actor's modifier inheritance, and a declared range. Owns `actor.spawn` (debug-class) and `actor.wield`. |

**Allowed imports:** `sim/` only.

**Introduced at:** M1 (player and target dummies). Perception and decisions at M4.

**Extension point:** profiles and health graphs are `content/combat_profile/` files; see
[docs/extending-items.md](../../docs/extending-items.md) § Combat.
