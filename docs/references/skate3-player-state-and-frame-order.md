# skate-3-rust-engine: player physical states and the per-tick frame order

Provenance warning: this project is a port of logic recovered from a retail game binary. Much of its
source is shaped by that origin (it talks about native layouts and recovered behaviour). Only the
generic architectural ideas below are worth carrying over; nothing here should be used to imitate
the retail game's feel or numbers.

## Problem it solves

A skater is in exactly one of many mutually exclusive physical modes at a time (rolling, airborne,
grinding, sliding, walking off-board, wiping out, teleporting, respawning). Each mode needs its own
setup, teardown and per-tick behaviour, and the mode switch must happen at a well-defined point in
the tick so that input, physics solve and animation all agree on which mode was active. The project
also has to run the board/body solve, the skater's skeleton and the behaviour graphs in a fixed order
on a fixed timestep, with rendering decoupled.

## Concepts and data (conceptual only)

- A closed set of physical modes, each identified by a stable id. Ids are grouped into families
  (ground, air, grind, off-board, wipeout...) and the family is derivable from the id, so callers can
  ask "is this any grind mode?" without listing every member.
- One handler per mode exposing three things: its own identity, an exit action and an enter action
  (per-tick work happens in the frame phases, not in the transition hooks).
- A "current mode" slot on the player, plus a separate board-controller sub-mode (roughly
  "running" vs "stopped") that is derived from which family the new mode belongs to.
- A transition request is a command, and a completed transition is an event carrying the old and
  new mode. Both live in a small per-tick exchange record owned by the simulation tick.
- Unknown mode ids are a hard error: they are rejected before any hook runs or any field is written.
  A mode without a handler is treated as an incomplete port, not as a fallback case. One of their
  bug-fix docs is literally "this mode was refused at initialisation because its handler was missing".

## Order of operations / tick structure

- Fixed timestep driven by the engine's fixed-update schedule; rendering runs on the variable frame
  and interpolates between the previous and current fixed-tick snapshots using the leftover fraction.
- Within the fixed tick there are two ordered sets: Controls (sample the controller once, publish it as
  a tick-scoped value) then Physics (one coordinator call that runs the whole frame).
- The coordinator's frame is split around the physics solver:
  1. Establish the timestep for the world.
  2. Animation phases run (several of them), with world preparation steps interleaved, then actors
     publish their physical representation (so the solver sees this tick's pose targets).
  3. Physical entities consume input.
  4. Physical logic: a pre-state step, the mode's state step, a post-state step.
  5. The world gathers data for the solver; the solver runs (contacts, joints and drive constraints
     solved together; every solver family finishes before any body integrates).
  6. Post-solve: an adjust step applies solver results, physical outputs are published, contact
     reports and conditioners are finalised.
- Transitions: the request is buffered and only takes effect on the authoritative tick whose counter
  matches the request; the transition then runs exit-old (while old is still marked active), switch
  the active slot, enter-new. Requesting the currently active mode performs a full exit and re-enter
  (timers and latches reset).
- Animation reads only completed, published physics outputs of the tick, never render transforms.
- The frame scheduler is itself a tiny state machine: calling a phase out of order is rejected and
  puts it into a faulted state rather than continuing.
- If the solve produces a non-finite position or velocity the simulation halts with a detailed log
  instead of propagating garbage.

## The trick that makes it work

Two things. First, transition hooks are tiny (identity, exit, enter) and all continuous behaviour is
expressed as phases of one ordered frame, so the order "input, then mode logic, then solve, then
publish, then animation reads" is the same for every mode. Second, transitions are commands applied
at a single point in the tick and reported as events, which gives replay fidelity and makes "who
changed the mode and when" observable.

## Failure modes and fixes seen in their history

- A mode was refused at start-up because no handler had been written for it; the fix was adding the
  handler and a headless test that cycles through the full mode sequence without a window. Their own
  note admits the exact in-game sequence that triggered the report was not replayed, so the test proved
  the lifecycle, not the scenario.
- An input adapter fed the wrong controller axis into a ramp-transition mode, which inverted the
  player's lean on quarter pipes. Lesson: the mapping from controller to per-mode input is a separate,
  testable layer, and a wrong source can look like a physics bug.
- A slide could stay latched after input release because the released input lingered in the
  animation/action intent layers. Guarded by a scripted headless test: reach speed, apply one input
  that must not trigger the mode, apply the combination that must, release, assert exit.
- Water entry needed an immediate forced bail transition, but not when already in protected modes
  (teleporting, sleeping, already wiping out). Forced transitions need an explicit "protected modes"
  guard.
- Their replay feature is a rolling buffer of presentation poses, explicitly not a re-simulation; their
  "verification" mode is a start-up smoke test (screenshot plus a diagnostic report, timeout as
  failure) and states plainly it is not a parity verdict. Their recorded-input playback test also only
  checks that the run completes and reaches certain behavioural milestones. In other words they have no
  deterministic hash replay.

## What a Gcity version should consider

- Keep modes as registry entries (id plus a handler with enter/exit/identity), with families as data,
  so a new mode is a registration and not an edit to a match statement. Reject unknown ids loudly at
  the command boundary.
- Express a mode change as a sim command that is validated and applied at one fixed phase of the
  tick, and emit a "mode changed" event onto the progression/event bus; never let the client set it.
- Fix the per-tick phase order in one place (input consumed, mode pre/step/post, motion solve,
  publish) and assert phase ordering at runtime, as they do.
- Integer ticks: express mode timers as tick counts, reset on re-entry; make self-transition semantics
  explicit (full exit/enter) and test it.
- Treat non-finite or out-of-range motion results as a loud failure in the sim rather than letting
  them flow into the hash.
- Animation and camera belong to the client and must read only the published post-tick state, with
  interpolation between the last two ticks; on Deck this keeps the sim at the tick rate while the
  renderer runs at the frame rate.
- Unlike them, ship a real replay fixture: seed plus input log reproduces the mode sequence and state
  hash. Their scripted "reach speed, press, release, assert exit" tests are a good template for M8
  feel regressions, but should assert a hash, not just milestones.
- Forced transitions (bail, teleport, cutscene) need a declared list of modes they may not interrupt.

## Sources read (URLs only)

- https://github.com/SK8-ENGINE/skate-3-rust-engine
- https://raw.githubusercontent.com/SK8-ENGINE/skate-3-rust-engine/HEAD/docs/physics/quarter-pipe-transition-input.md
- https://raw.githubusercontent.com/SK8-ENGINE/skate-3-rust-engine/HEAD/crates/skate-core/src/player/state.rs
- https://raw.githubusercontent.com/SK8-ENGINE/skate-3-rust-engine/HEAD/crates/skate-core/src/player/lifecycle.rs
- https://raw.githubusercontent.com/SK8-ENGINE/skate-3-rust-engine/HEAD/crates/skate-core/src/player/frame.rs
- https://raw.githubusercontent.com/SK8-ENGINE/skate-3-rust-engine/HEAD/crates/skate-core/src/player/state_phase.rs
- https://raw.githubusercontent.com/SK8-ENGINE/skate-3-rust-engine/HEAD/crates/skate-core/src/physics/phase.rs
- https://raw.githubusercontent.com/SK8-ENGINE/skate-3-rust-engine/HEAD/crates/skate-core/src/physics/board_step.rs
- https://raw.githubusercontent.com/SK8-ENGINE/skate-3-rust-engine/HEAD/crates/skate-core/src/physics/board_runtime.rs
- https://raw.githubusercontent.com/SK8-ENGINE/skate-3-rust-engine/HEAD/crates/skate-game/src/physics.rs
- https://raw.githubusercontent.com/SK8-ENGINE/skate-3-rust-engine/HEAD/crates/skate-game/src/verification.rs
- https://raw.githubusercontent.com/SK8-ENGINE/skate-3-rust-engine/HEAD/crates/skate-game/src/replay.rs
- https://raw.githubusercontent.com/SK8-ENGINE/skate-3-rust-engine/HEAD/crates/skate-game/src/tests/recorded_playback.rs
- https://raw.githubusercontent.com/SK8-ENGINE/skate-3-rust-engine/HEAD/crates/skate-game/src/tests/powerslide_playback.rs
- https://api.github.com/repos/SK8-ENGINE/skate-3-rust-engine/issues?state=all&per_page=100
