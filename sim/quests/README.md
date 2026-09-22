# `sim/quests`

Quest director, site binding, objectives. Quests reference site handles, never coordinates (design doc §5.3).

**Allowed imports:** `sim/` only.

| File | What |
|---|---|
| `terminal_system.gd` | `TerminalSystem` (system id `terminals`): terminals a site places; `terminal.hack_start` runs a tick a tick while the actor stays in reach with the hardware the terminal requires, `terminal.hack_cancel` and walking away lose the progress, completion yields the data item and emits `terminal.hacked` with the signal the threat director will read, and a hacked terminal is a trace until `terminal.wipe` (M6 spec claim 5). |
| `run_score_system.gd` | `RunScoreSystem` (system id `score`): a run bracketed by `run.begin` and `run.end`, scored by four counters raised from events the sim already emits — detections, alarms, bodies — and a trace reading taken from the world at the end; `content/payout_curve/` turns them into a payout multiplier (M6 spec claim 7). |
| `quest_system.gd` | `QuestSystem` (system id `quests`): quest records as content (`content/quest/`) with event objectives credited to an actor named in the payload, filtered by tags, counted; `quest.accept` and `quest.abandon` (pause-safe); the reward spawned once on completion; `quest.completed` on the bus (M5 spec claim 9). |

**Introduced at:** M5 (records and objectives). The director, offers, dialogue and site binding: M6 (Cold Storage), M7 (site binding).
