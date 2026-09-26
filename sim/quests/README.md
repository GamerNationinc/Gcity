# `sim/quests`

Quest director, site binding, objectives. Quests reference site handles, never coordinates (design doc §5.3).

**Allowed imports:** `sim/` only.

| File | What |
|---|---|
| `quest_system.gd` | `QuestSystem` (system id `quests`): quest records as content (`content/quest/`) with event objectives credited to an actor named in the payload, filtered by tags, counted; `quest.accept` and `quest.abandon` (pause-safe); the reward spawned once on completion; `quest.completed` on the bus (M5 spec claim 9). A quest naming a `site` binds it on accept (M6 spec claim 4). |
| `site_system.gd` | `SiteSystem` (system id `sites`): sites as content (`content/site/`): pieces, parcels, named points and agents relative to an origin; `site.raise` places the pieces as one batch (one portal rebuild), hands over the parcels and posts the agents, once per site; `point_position()` for spawning at a named point (M6 spec claims 1–3). |

**Introduced at:** M5 (records and objectives), M6 (sites, the site binding). Offers, dialogue and contracts: M6 group G. A generated site behind the binding: M7.
