# Architecture Decision Records

The open decisions from `docs/gcity-design.md` §17, one file each, in the format from
`docs/gcity-engineering-standards.md` §7. Status is `proposed` until CEOGG
signs the file; a wrong decision is superseded by a new ADR, never edited in place.

| ADR | Decision | Blocks | Status |
|---|---|---|---|
| [ADR-001](ADR-001-codebase-origin.md) | Clean start vs existing codebase | M0 | proposed |
| [ADR-002](ADR-002-tick-model.md) | Deterministic fixed tick vs variable step | M0, co-op | **accepted** 2026-09-20 |
| [ADR-003](ADR-003-terrain-representation.md) | Heightmap carving vs volumetric voxels | M7, all terrain code | **accepted** 2026-09-20 (B, two conditions) |
| [ADR-004](ADR-004-detection-model.md) | Sensor-gated detection vs instant wanted level | M4, M8 | proposed |
| [ADR-005](ADR-005-claimed-base-structure.md) | Claimed base keeps player structure vs faction template | M8 | proposed |
| [ADR-006](ADR-006-device-time.md) | Does the device pause time? | M5, M6 | proposed |
| [ADR-007](ADR-007-death-cost.md) | Death cost / kit loss model | M6 | proposed |
| [ADR-008](ADR-008-arcade-ai.md) | Arcade enemies: same AI retuned, or simpler agent | M4 | proposed |
| [ADR-009](ADR-009-magazine-model.md) | Magazines as ordered containers | M1, item system | **accepted** 2026-09-20 |
| [ADR-010](ADR-010-hub-interior-simulation.md) | Hub interiors simulated while the player is elsewhere? | M7 | proposed |

Where the design doc already states a working assumption, the ADR records it as the
proposed decision so the assumption is visible and signable rather than implicit.

## Template

```
# ADR-00N: <title>

Status: proposed | accepted | superseded by ADR-00M
Date:
Design doc: §x.y (D-0N)

## Context
## Options
### A — ...   (cost, risk, what it forecloses)
## Decision
## Consequences
## Verification
## Sign-off
```
