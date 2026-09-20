# `sim/progression`

Skills, perk trees and the stat resolver. Every number in the game reads through
`StatResolver.resolve()` (design doc §10.2).

| File | What |
|---|---|
| `stat_resolver.gd` | `StatResolver` (system id `stats`): stats registered from `content/stat/`, bases per entity, modifiers in registered classes (`add`, `mul`), tag-based inheritance from a wielder, cached resolution. |

**Allowed imports:** `sim/` only.

**Introduced at:** M1 (stat resolver + one pistol). Skills and perks follow in M1.

**Extension point:** [docs/extending-progression.md](../../docs/extending-progression.md).
