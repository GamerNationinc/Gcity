# `sim/quests`

Quest director, site binding, objectives. Quests reference site handles, never coordinates (design doc §5.3).

**Allowed imports:** `sim/` only.

| File | What |
|---|---|
| `terminal_system.gd` | `TerminalSystem` (system id `terminals`): terminals a site places; `terminal.hack_start` runs a tick a tick while the actor stays in reach with the hardware the terminal requires, `terminal.hack_cancel` and walking away lose the progress, completion yields the data item and emits `terminal.hacked` with the signal the threat director will read, and a hacked terminal is a trace until `terminal.wipe` (M6 spec claim 5). |
| `run_score_system.gd` | `RunScoreSystem` (system id `score`): a run bracketed by `run.begin` and `run.end`, scored by four counters raised from events the sim already emits — detections, alarms, bodies — and a trace reading taken from the world at the end; `content/payout_curve/` turns them into a payout multiplier (M6 spec claim 7). |
| `site_constraint.gd` | `SiteConstraint`: what a contract asks of the place it happens at — `{tags_any, min_km, max_km, undiscovered}` — instead of naming one. Reads a quest's `site` block and answers whether a slot satisfies it; holds no state and picks nothing, so the same question can be asked of a hypothetical as of the save (M7 spec claim 8). |
| `site_binder.gd` | `SiteBinder` (system id `bindings`): turns a contract's handle into a place when it is accepted. Picks one of the free matching slots by a hash of the world seed and the quest — never `sim.rng()`, never the tick — stitches a site onto the graph there, and records `[quest, slot]` in binding order. Permanent: abandoning a contract keeps its place, and a bound slot is never offered to another. The record is the save's overlay; restore stitches the sites again from it (M7 spec claim 9). |
| `quest_system.gd` | `QuestSystem` (system id `quests`): quest records as content (`content/quest/`) with event objectives credited to an actor named in the payload, filtered by tags, counted; `quest.accept` and `quest.abandon` (pause-safe); the reward spawned once on completion; `quest.completed` on the bus (M5 spec claim 9). A quest with a `site` block binds its place on `quest.accept` through a Callable the assembly wires to `SiteBinder`, and is refused if nowhere fits (M7 spec claim 9). A quest with a `turn_in` block stops at `ready` when its objectives are done and is paid by `quest.turn_in` inside the named parcel instead, its money scaled by the run's payout curve through a Callable the assembly wires to `RunScoreSystem` (M6 spec claim 9). |

**Introduced at:** M5 (records and objectives). The director, offers, dialogue and site binding: M6 (Cold Storage), M7 (site binding).
