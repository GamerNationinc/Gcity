# `sim/threat`

Heat, notoriety, visible wealth, signals and suspicion, the threat director and raid scheduling (design doc §7.3–7.5, §9).

**Allowed imports:** `sim/` only.

| File | What |
|---|---|
| `standing_system.gd` | `StandingSystem` (system id `standing`): per-actor scalars (`content/standing_scalar/`: heat and notoriety at M6, each with its decay per tick and max), raised by `content/standing_rule/` rules on bus events as skill xp is; cooled every tick (M6 spec claim 11). |

**Introduced at:** M6 (standing, sensors), M8 (the threat director, suspicion, raid scheduling).
