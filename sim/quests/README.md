# `sim/quests`

Quest director, site binding, objectives. Quests reference site handles, never coordinates (design doc §5.3).

**Allowed imports:** `sim/` only.

| File | What |
|---|---|
| `quest_system.gd` | `QuestSystem` (system id `quests`): quest records as content (`content/quest/`) with event objectives credited to an actor named in the payload, filtered by tags, counted; `quest.accept` and `quest.abandon` (pause-safe); the reward spawned once on completion; `quest.completed` on the bus (M5 spec claim 9). Contracts (M6 claim 14): a quest with a fixer, a site handle, a deliverable and scoring; accepting at the fixer spawns the site at its placement and opens a run record of the four §15.4 counters from bus events; exfil; `contract.deliver` pays through the wallet and emits `contract.delivered`. |

**Introduced at:** M5 (records and objectives); contracts at M6 (Cold Storage). Site binding to world slots: M7; the director and offers: M7/M8.
