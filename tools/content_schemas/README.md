# Content schemas

One `<kind>.json` per content kind. The presence of the file registers the kind with
`tools/validate_content.py`, which then checks every `content/<kind>/*.json` against it.

## Dialect

A schema is an object with:

| Key | Meaning |
|---|---|
| `properties` | `{ "<field>": rule, ... }` |
| `required` | field names that must be present |
| `additional_properties` | `false` to reject fields not in `properties` (default: allowed) |
| `schema_version`, `description` | documentation of the schema itself; not enforced |

A rule has `type` (`int`, `number`, `string`, `bool`, `array`, `object`) and, by type:

| Type | Keys |
|---|---|
| `int`, `number` | `min`, `max` (inclusive). `int` rejects `1.0` and `true`. |
| `string` | `min_length`, `max_length`, `pattern` (full match), `ref`: `"<kind>"` (must be the id of an existing `content/<kind>/` file) |
| `array` | `min_length`, `max_length`, `items` (a rule for every element) |
| `object` | nested `properties`, `required`, `additional_properties` |

`{}` accepts any object. Closed sets of names (weapon classes, damage types, …) are
never expressed as an enumeration here (standards §6.2); they are `ref`s to a content
kind or free `pattern`-checked ids that a system registers at runtime.

## Kinds

| Kind | Since | Fields |
|---|---|---|
| `stat` | M1 | `default_base` (int, milli-units), `description` |
| `calibre` | M1 | `description` |
| `weapon_socket` | M1 | `description`, optional `contains` (a content kind; only `ammo` at M1) |
| `weapon_frame` | M1 | `calibre` (ref), `sockets` (refs), `tags`, `stats` (`{stat: ref, value}`) |
| `weapon_part` | M1 | `socket` (ref), `fits` (frame refs), `modifiers` (`{stat: ref, class, value}`), `capacity` + `calibre` for container sockets |
| `ammo` | M1 | `calibre` (ref), `tags`, `stats` |
| `combat_stage` | M1 | `description` (a name code may implement) |
| `perception_profile` | M4 | `sight_range_mm`, `fov_deg`, `gain_per_tick`, `speed_gain_per_mm_per_tick`, `decay_per_tick`, `alert_threshold`, `memory_ticks`, `hearing_range_mm`, `hearing_gain` (all int) |
| `aim_profile` | M4 | `cone_start_mdeg`, `cone_settled_mdeg`, `settle_ticks`, `swing_penalty_mdeg`, `swing_ticks`, `penalty_per_mdeg` (all int) |
| `agent_profile` | M4 | `combat_profile`, `perception_profile`, `aim_profile` (refs) |
| `combat_profile` | M1 | `stages` (refs), `range_falloff_per_m`, `health` (`nodes` with `id`/`max`/`fatal`, `routing` with `node`/`weight`) |
| `skill` | M1 | `xp` rules (`event`, `credit`, `tags_any`, `amount`), `levels`, `points_per_level` |
| `perk` | M1 | `skill` (ref), `prerequisites` (`level`, `perks` refs), `cost`, `tags`, `modifiers` (`{stat: ref, class, value}`) |
