# `sim/threat`

Heat, notoriety, visible wealth, signals and suspicion, the threat director and raid scheduling (design doc §7.3–7.5, §9).

**Allowed imports:** `sim/` only.

| File | What |
|---|---|
| `standing_system.gd` | `StandingSystem` (system id `standing`): `heat`, `notoriety` and `visible_wealth` per actor, defined by `content/standing_rule/` — an event-raised scalar credited as skill xp is and decayed on its own clock at a rate the actor's district scales, or a derived one recomputed from the resolved `value` of what the actor carries (M6 spec claim 8). |

**Introduced at:** M6 (standing). The threat director, raids, signals and suspicion are M8.
