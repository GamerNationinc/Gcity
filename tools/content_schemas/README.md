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
| `device_app` | M5 | `title`, `icon`, `order`, `requires` (a module's `provides` tag or empty) |
| `quest` | M5 | `title`, `text`, `objectives` (`{description, event, credit, tags_any, count}`), `reward` (`{kind, template, count}`); optional `site` (ref, M6) |
| `tool` | M6 | `tool_class` (ref), `tags`, `stats` (`{stat: ref, value}`; `noise` is how far a breach carries, mm) |
| `site` | M6 | `origin` (cell), `parcels` (`{parcel: ref, owner}`), `pieces` (`{piece: ref, cell, facing}`), `points` (`{id, cell}`), `agents` (`{profile: ref, cell, facing, squad, route}`); cells relative to `origin` |
| `device_frame` | M5 | `sockets` (device_socket refs), `tags`, `stats` |
| `device_socket` | M5 | `description` |
| `device_module` | M5 | `socket` (ref), `fits` (device_frame refs), `modifiers`, `provides` (tags) |
| `combat_stage` | M1 | `description` (a name code may implement) |
| `perception_profile` | M4 | `sight_range_mm`, `fov_deg`, `gain_per_tick`, `speed_gain_per_mm_per_tick`, `decay_per_tick`, `alert_threshold`, `memory_ticks`, `hearing_range_mm`, `hearing_gain` (all int) |
| `aim_profile` | M4 | `cone_start_mdeg`, `cone_settled_mdeg`, `settle_ticks`, `swing_penalty_mdeg`, `swing_ticks`, `penalty_per_mdeg` (all int) |
| `stress_profile` | M4 | `near_miss_mm`, `gain_fired_at`, `gain_hit`, `gain_squadmate_down`, `decay_per_tick`, `break_threshold`, `rout_threshold`, `hit_penalty_at_max` (all int) |
| `stance` | M4 | `description` (a name the sim registers a scorer for) |
| `patrol_route` | M4 | `cells` (arrays of three ints) |
| `agent_profile` | M4 | `combat_profile`, `perception_profile`, `aim_profile`, `stress_profile` (refs), `stances` (`{stance: ref, weight}`), `radio` (bool), `radio_latency_ticks` |
| `combat_profile` | M1 | `stages` (refs), `range_falloff_per_m`, `health` (`nodes` with `id`/`max`/`fatal`, `routing` with `node`/`weight`) |
| `skill` | M1 | `xp` rules (`event`, `credit`, `tags_any`, `amount`), `levels`, `points_per_level` |
| `perk` | M1 | `skill` (ref), `prerequisites` (`level`, `perks` refs), `cost`, `tags`, `modifiers` (`{stat: ref, class, value}`) |
