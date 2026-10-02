# iw4L: bot perception, memory, query budget and decision pipeline

## Problem it solves

Bots must act on what they could plausibly know, for a bounded time, with a bounded number of
expensive line-of-sight queries per tick shared by all bots, and must not flip between tasks or shoot at
stale memories.

## Concepts and data (conceptual only)

- Pipeline per authority tick: observation, memory, utility, task, route, motor, command. The output
  is an ordinary player command in the same input bundle as humans.
- Dummy bots: the same physics, damage and respawn but no perception or decisions; useful for tests and
  for isolating AI cost.
- Three visibility outcomes, not two: seen; evaluated and not seen; not evaluated (budget ran out or
  the check was skipped). Only "evaluated and not seen" ends a contact. "Not evaluated" holds the
  contact briefly, and without fresh coordinates.
- Contacts carry the tick they were observed and a knowledge source (currently seen, last seen, or
  public game state).
- Memory: a currently-seen contact that stops being seen becomes "last seen" (position kept); "not
  evaluated" defers that demotion for a short grace window; every contact is forgotten entirely after a
  longer retention window. Spot and lose events are derived by diffing the previous and current contact
  lists.
- Sensor cost ladder, cheapest first: skip dead observers and teammates; field-of-view cone test; range
  cull (both too far and too near); then line-of-sight rays to a few points on the target (head first,
  since one positive settles it). The bot's committed focus target is probed first so occluded others
  cannot starve it.
- A shared query budget of tokens per tick, used by perception, route attachment, motor execution and
  tactical checks. Each subsystem declares itself before querying so denials are attributed. A denied
  query returns a distinct "denied" result that carries no collision meaning. One token buys one
  high-level query even if it internally issues several primitive traces; counters record attempts,
  grants, denials per subsystem, and primitive operations.
- Utility tasks: wander/hunt (baseline), investigate a last-seen location (scores when memory is fresh),
  fight (highest when an enemy is visible), recover (low health or ammo), play the objective (scores from
  travel time and interaction needs, and only if reachable within the nav budget).
- Hysteresis: the current task is kept unless a challenger beats it by a switching margin.
- Combat positioning: candidate firing spots (per-sector supports, or a fallback ring around the target)
  scored by travel distance and an exposure penalty from a two-way visibility check; the bot commits to
  one and keeps it while the anchor drifts slightly, abandoning it only when stale or unreachable.
- Fire gate: aiming may follow remembered positions, but firing requires the target to have been seen
  within a very short recent window, re-checked every tick.

## Order of operations / tick structure

- Thinking happens only every few ticks: ingest observations into memory, score tasks, pick task, build
  movement intent, apply weapon skill logic. Between think ticks the previous intent is reused, but fire
  authorisation is re-validated each tick.
- Every tick: intent to motor to command; motor reports executing, blocked, or budget exhausted.
- Task switches are logged with a reason (spawned, saw enemy, lost sight, path failed, low health) and a
  stage (approach, position, interact, hold, complete).
- Validation is done live by watching aggregate counters during a running match, plus approved
  scenarios (see the tracing note).

## The trick that makes it work

Separating "I checked and it is not there" from "I did not get to check" lets a hard per-tick query
budget coexist with believable behaviour: running out of budget makes bots slightly slower to update,
never wrong. Splitting what the bot may aim at (memory) from what it may shoot at (fresh sight) gives
human-like search behaviour without cheating.

## Failure modes and fixes seen in their history

- A visible weapon id does not mean the weapon is ready; the motor waits for the weapon to reach a
  settled state before treating it as usable.
- Interactions already in progress (planting, capturing) must not be interrupted by reload logic.
- Defend objectives looked wrong when bots stood on a single point; guard behaviour circles at a
  distance instead.
- Breakable obstacles needed their own movement mode rather than being routed around.
- No fuzz-specific bot bugs were documented; their bot validation is mostly live observation plus
  counters, which is a gap Gcity should not copy.

## What a Gcity version should consider

- M9 threat director: the three-outcome visibility and the shared token budget are the right
  primitives; make the budget per tick, owned by the sim, distributed in a deterministic order, and
  record denials in the snapshot or as hashed counters.
- Memory windows and think intervals as tick counts in content data (per archetype or faction), not
  constants in code. Faction-specific perception (sight range, cone, hearing) becomes a data file.
- Utility scores as integers with a switching margin; tie-break by task id. Each task kind is a
  registry entry with a scorer, so a new behaviour is a registration plus data.
- Cheapest-first sensing on the 1 m grid: a grid line-walk is a cheap first visibility test before any
  physics ray; probe a few target points, highest-value first.
- Fire/attack gating on freshness is a good anti-cheat for AI and also a nice feel lever.
- Testing beyond theirs: metamorphic relations (adding an occluding wall never makes a previously unseen
  target seen; increasing the budget never makes perception less complete), replay fixtures with bots
  enabled, and a property that "not evaluated" never ends a contact.
- Deck budget: think every few ticks with staggered phases per bot (offset derived from bot id) spreads
  the cost evenly; dummy bots give a baseline for measuring AI cost in isolation.
- Telemetry of task switches with reasons is cheap and invaluable; route it to a handheld-friendly debug
  overlay, not the console.

## Sources read (URLs only)

- https://raw.githubusercontent.com/vladtrc/iw4L/HEAD/docs/BOTS.md
- https://raw.githubusercontent.com/vladtrc/iw4L/HEAD/crates/bots/src/observation.rs
- https://raw.githubusercontent.com/vladtrc/iw4L/HEAD/crates/bots/src/memory.rs
- https://raw.githubusercontent.com/vladtrc/iw4L/HEAD/crates/bots/src/sensor.rs
- https://raw.githubusercontent.com/vladtrc/iw4L/HEAD/crates/bots/src/query.rs
- https://raw.githubusercontent.com/vladtrc/iw4L/HEAD/crates/bots/src/controller.rs
