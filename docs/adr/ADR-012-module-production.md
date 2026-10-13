# ADR-012: Module production — modules that brew outputs over time

Status: proposed
Date: 2026-10-12
Design doc: §8.2 (modules are data), §10.1–10.2 (events, stat resolver). Not among
§17's open decisions — a new mechanic from CEOGG (2026-10-07): Tarkov-hideout-style
passive production, "a medic bay that gives you medical supplies over X amount of
in-game time; as you upgrade it, it does it faster" — inside a base you physically
walk through.

## Context

The structure system (M2) gives modules as content files with footprints, budgets and
dependencies, but no module does anything over time. Production needs four decisions:
the clock source, where the logic lives, how rates upgrade, and how output is held and
collected.

Constraints already decided elsewhere, not re-opened here:

- Modules stay numbers; behaviour is an event hook registered by the system that owns
  the work, keyed by module kind (`docs/extending-modules.md`, "What you may not do").
- Sim time is integer ticks; no wall-clock reads inside the sim (CLAUDE.md invariant 6).
- Every number reads through the stat resolver (§10.2).
- Device pause in owned parcels (ADR-006, C) stops gameplay systems ticking.
- Budgets refuse a module that cannot be powered at install time (M2), so there is no
  separate "unpowered module" runtime state to invent.

## Options

### A — Wall-clock accrual, including while the game is closed (the literal Tarkov model)
- Cost: a wall-clock read inside the sim, which CI's deny-list rejects; replays stop
  reproducing; save-reload and system-clock changes become production exploits.
- Risk: moot — it fails invariant 6 by construction.
- Forecloses: deterministic replay of any base with a producer on it.
- Recorded only so the rejection is visible: "over time" here means sim ticks.

### B — A production system ticks each producing module
- One new sim system (`sim/land/production_system.gd`, registered in `SimAssembly`)
  walks producing modules on a time-sliced budget, advancing an integer
  `progress_ticks` per module; a full batch moves `batch_size` of the output into the
  module's capped store. Per-module state is `{progress_ticks: int, stored: int}` in
  the structure's `modules` map — hashable, int-only (invariant 7).
- Cost: `content/module` schema_version 2 (an optional `production` block) plus the
  migration; one new system and its tests.
- Risk: minor tick cost; module counts are tens, and the walk is sliceable like
  meshing and flood fill (standards §4).
- Forecloses: nothing.

### C — Timestamp catch-up (store the batch's start tick, compute on access)
- Cost: cheaper per tick, but progress becomes a function of *when it is observed*,
  which drags access order into the hash; pause (ADR-006) and dependency-removal
  bookkeeping need partial-progress records anyway, so the "one int" saving mostly
  evaporates.
- Risk: the classic determinism hazard — two replays that read the store at different
  points must not disagree. Avoidable with care, but B avoids it by construction.
- Forecloses: nothing; observable behaviour is identical to B.

### Sub-decision — how upgrades make it faster
- **Tiered module files** (medic_bay_1 → medic_bay_2, remove + install): simple, but
  every speed influence needs a new file, and perks can never touch brew speed.
- **Rate through the resolver** (proposed): the module file carries the base
  `batch_ticks`; the effective value resolves through the stat resolver on the
  structure's entity, so an upgrade, a perk or an implant is a modifier from a named
  source — the §10.2 mechanism wearing one more hat. Tier upgrades can then be either
  a swapped module file *or* a modifier; content decides, code doesn't care.

## Decision

**Proposed: B, with rates through the resolver.**

- `content/module/<id>.json` schema_version 2 adds an optional block:
  `production {output (item id), batch_size, batch_ticks, capacity, inputs {item: count}}`.
  A module without the block behaves exactly as today (v1 files migrate untouched).
- `production_system.gd` owns all behaviour, keyed by module kind; module files stay
  numbers. Starter producers are content only: medic bay (medical supplies), galley
  (rations), work & repair (parts).
- Output lands in the module's internal store, capped at `capacity`; a full store
  halts progress. Deliberate: the base stays a place you return to and walk through,
  not a background faucet.
- `production.collect` command `{actor, structure, module}`: needs `enter` rights at
  the structure, actor present; transfers the store to the actor's inventory via the
  item system; hostile payloads rejected with no state change, like every command.
- `inputs` (optional consumables per batch) are debited when a batch starts; a module
  whose inputs are missing idles.
- Pause: production is a gameplay system, so it pauses with the sim under ADR-006 (C).
  Consequence accepted — time spent menuing in a safe parcel brews nothing, which
  mildly pushes the player back out the door.

## Consequences

Easy: new producers are files (the G-gate extension exercise extends naturally — a
fourth producer with inputs and a dependency, data only, empty `sim/` diff);
determinism and conservation are directly testable; sim-authoritative collection is
already the shape co-op needs.

Hard: the v1→v2 schema migration; the economy around it — capped stores only matter
if outputs have sinks, which is tuning work owned by whichever milestone ships this;
the client eventually needs a collect interaction and a store/progress readout on the
device (not part of this decision).

Scheduling: **not M6** — the M6 spec is approved as written and this is outside it.
This ADR records the decision so the mechanic can be specced into a later milestone
(or the debt log) wherever CEOGG slots it; implementation waits for that spec.

## Verification

- Replay fixture: seed + input log that installs a medic bay, runs N ticks, collects,
  runs on; state hash reproduces.
- Property (≥10,000 cases): over generated tick sequences and collect timings,
  `collected + stored == batch_size × floor(active_ticks / effective_batch_ticks)`
  clamped by `capacity` at every halt; store never exceeds `capacity`; removing the
  module removes exactly its modifiers (the M1 resolver invariant).
- Round-trip: `load(save(x)) == x` over structures with mid-batch producers.
- Fuzz: `production.collect` joins the hostile-payload corpus.
- Metamorphic: raising `capacity` never lowers total output over the same input log;
  a speed modifier from any source never decreases output.

## Sign-off

Approver: CEOGG
Date:
Outcome: pending
