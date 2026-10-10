# `sim/threat`

Heat, notoriety, visible wealth, signals and suspicion, the threat director and raid scheduling (design doc §7.3–7.5, §9).

| File | What |
|---|---|
| `sensor_system.gd` | `SensorSystem` (system id `sensors`, M6 claim 8): sensors on openings, `security.alarm` on their triggers, `sensor.install`; registers the `spoof_sensor` hack effect (claim 9). |
| `standing_system.gd` | `StandingSystem` (system id `standing`, M6 claim 11): per-actor heat and notoriety from `standing` and `standing_rule` content, raised by bus events (a rule's `violating` right makes an alert a witnessed trespass), decayed every 1000 ticks. This is the threat record's first part; visible wealth, faction suspicion and the director stay in M8. |

**Allowed imports:** `sim/` only.

**Introduced at:** M6 (sensors on openings, claim 8; standing, claim 11); the director, signals, suspicion and raids arrive at M8.
