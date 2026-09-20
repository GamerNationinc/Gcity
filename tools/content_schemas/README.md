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
