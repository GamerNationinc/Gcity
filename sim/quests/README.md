# `sim/quests`

Quest director, site binding, objectives. Quests reference site handles, never coordinates (design doc §5.3).

**Allowed imports:** `sim/` only.

| File | What |
|---|---|
| `quest_system.gd` | `QuestSystem` (system id `quests`): quest records as content (`content/quest/`) with event objectives credited to an actor named in the payload, filtered by tags, counted; `quest.accept` and `quest.abandon` (pause-safe); the reward spawned once on completion; `quest.completed` on the bus (M5 spec claim 9). |

**Introduced at:** M5 (records and objectives). The director, offers, dialogue and site binding: M6 (Cold Storage), M7 (site binding).
