# `content/`

Data files only: weapons, perks, modules, districts, town templates, quests. Systems
are few and generic; content is many and dumb (design doc §1.1, pillar 4).

Rules, enforced by `tools/validate_content.py` in CI:

- Layout is `content/<kind>/<id>.json`. `<kind>` names a schema registered under
  `tools/content_schemas/<kind>.json`; a file whose kind has no schema fails the build,
  and so does a file that breaks its schema (types, ranges, patterns, required keys,
  unexpected keys, cross-references to other kinds).
- Every file carries an integer `schema_version` (standards §6.3).
- No scripts or scenes. Content that needs behaviour is an event hook registered from
  code, and that category is kept deliberately small (design doc §10.3).

Kinds so far:

| Kind | Since | Read by |
|---|---|---|
| `stat` | M1 | `StatResolver` via `SimAssembly.build()`; see `docs/extending-progression.md` |
| `calibre`, `weapon_socket`, `weapon_frame`, `weapon_part`, `ammo` | M1 | `ItemSystem`; see `docs/extending-items.md` |
| `combat_stage`, `combat_profile` | M1 | `CombatSystem`, `ActorSystem`; see `docs/extending-items.md` § Combat |
| `skill`, `perk` | M1 | `ProgressionSystem`; see `docs/extending-progression.md` |
| `device_app` | M5 | `DeviceShell` (`client/device/README.md`) |
| `quest` | M5 | `QuestSystem` (`sim/quests/README.md`) |
| `goods` | M6 | `ItemSystem` (an item kind: carried, handed over, read by tags) |
| `tool` | M6 | `ItemSystem` (an item kind: the tool class it breaches as), `BreachSystem` |
| `sensor` | M6 | `SensorSystem` (`sim/threat/README.md`), placed by a site's `sensors` |
| `standing_scalar`, `standing_rule` | M6 | `StandingSystem` (`sim/threat/README.md`) |
| `site` | M6 | `SiteSystem` (`sim/quests/README.md`), `ActorSystem` (spawn points) |
| `device_frame`, `device_socket`, `device_module` | M5 | `ItemSystem` (a second socketed frame family), `ActorSystem` (`actor.equip_device`) |
| `perception_profile`, `aim_profile`, `stress_profile`, `stance`, `patrol_route`, `agent_profile` | M4 | `PerceptionSystem`, `AimSystem`, `StressSystem`, `StanceSystem`, `SquadSystem`; see `docs/extending-agents.md` |

Content reaches the sim as dictionaries through `client/content_loader.gd` into
`ContentDb`; the sim never opens a file. Integral JSON numbers arrive as ints.
