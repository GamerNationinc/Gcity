# `sim/progression`

Skills, perk trees and the stat resolver. Every number in the game reads through
`StatResolver.resolve()` (design doc §10.2).

| File | What |
|---|---|
| `stat_resolver.gd` | `StatResolver` (system id `stats`): stats registered from `content/stat/`, bases per entity, modifiers in registered classes (`add`, `mul`), tag-based inheritance from a wielder, cached resolution. |
| `progression_system.gd` | `ProgressionSystem` (system id `progression`): subscribes to the events `content/skill/` names, credits xp, raises levels and grants points; `perk.unlock` turns a `content/perk/` file into tagged resolver modifiers on the actor. |

**Allowed imports:** `sim/` only.

**Introduced at:** M1 (stat resolver, one skill, two perks).

**Extension point:** [docs/extending-progression.md](../../docs/extending-progression.md).
