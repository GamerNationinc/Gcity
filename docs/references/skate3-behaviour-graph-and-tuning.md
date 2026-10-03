# skate-3-rust-engine: data-driven behaviour graph (animation/action selection) and tuning

Provenance warning: the graphs themselves are loaded from the user's own retail game data, which the
project does not ship. Only the structure of the runtime and the tuning layer is noted here.

## Problem it solves

Choosing what the skater does and which animation plays, from physical state plus player intent,
without hardcoding a giant decision tree; and letting difficulty/feel be tuned without rebuilding.

## Concepts and data (conceptual only)

- Two graphs layered: an action graph (decisions, driven by controller intents and the previous motion
  state) and a motion graph (locomotion/animation choice, driven by the action graph's output plus
  physical conditions). High-level choices constrain low-level ones, never the reverse.
- Each graph is a hierarchical state machine: states form a tree; each state owns zero or more
  behaviours (animation or logic units); each state accumulates a timer while active.
- Transitions carry a priority tier and a list of conditions. Conditions are data: a tagged union of
  comparison kinds (equal, not equal, greater/less, absolute-value comparisons, "state is or descends
  from X", stance/mirrored/backwards checks, speed along an axis, speed combined with slope, time since
  last input, ground-normal incline).
- Each condition declares the inputs it requires. If a required input has not been produced this
  tick, evaluation is an error, never a silent default ("missing producer" is an integration bug, not
  "assume grounded and stationary").
- A per-state interruptibility setting decides what happens when no transition fires: stay, reset to
  root, or fall back through a designated interrupt ancestor.
- Tuning: a flat set of named numeric knobs grouped by domain (propulsion, air, rotation/balance,
  wipeout sensitivity). Each knob declares its maximum, its step size and whether it is a boolean. Stock
  profiles provide defaults; a user file contains only overridden keys and is layered on top.

## Order of operations / tick structure

- Physics publishes its completed outputs for the tick; the graphs read those plus sampled intents.
- Selection: for each priority tier from highest to lowest, walk from the current state up through its
  ancestors and test each transition at that tier; first transition whose own enable flag, target
  enable flag, preconditions and conditions all pass wins. No scoring, no randomness.
- Applying a transition: compute the path from source and target to the root, find their lowest common
  ancestor, run exits up to it, run transition hooks, run enters down to the target, then update the
  active behaviours. Effects of exit/hook/enter are visible to later calls in the same tick. Entering an
  ancestor re-enters its descendants; a self-transition is a full re-enter and clears the state timer.
- Animation clips advance on the fixed physical step even if the presentation clock is slowed (slow
  motion camera), so animation phase never drifts from the sim.
- Tuning is validated before it is written or applied: every value finite, within range, booleans
  exactly on/off, unknown keys rejected. Valid overrides are applied to a dedicated profile layered on
  the base one at runtime.

## The trick that makes it work

Priority tiers plus ancestor walking gives designers "global" transitions (put it on the root at high
priority, e.g. bail) and "local" ones (on a leaf at low priority) with deterministic first-match
semantics, and the explicit "required inputs" contract turns ordering bugs between physics and graph
into loud errors rather than wrong animations.

## Failure modes and fixes seen in their history

- Released inputs lingering in the action/intent layer kept the skater in a slide; fixed and guarded by
  a scripted headless test that asserts entry on the correct input combination, non-entry on a near
  miss, and exit on release.
- A floating-point subtlety: "not less than" and "greater or equal" differ when inputs are NaN; their
  comparisons are written so that unordered values fail the test the same way the original did.
  Generalised lesson: decide what a comparison does with invalid numbers and test it.
- The graph runtime depends on physics outputs that were not yet recovered; they mark the graph as not
  fully playable until those producers exist, rather than faking defaults.

## What a Gcity version should consider

- Content is data: graphs, states, transitions and conditions as content files with a registered
  schema; condition kinds as a registry of evaluators keyed by name, so a new condition kind is a
  registration, and a new move is a file.
- Integer ticks make state timers exact; express condition thresholds on time in ticks.
- Comparisons on fixed-point or integer speeds remove the NaN question entirely; if floats remain,
  reject non-finite inputs at the boundary.
- Selection must be deterministic: fixed tier order, fixed transition order within a state (file order
  or sorted id), no dictionary-order iteration.
- Split: the sim-side graph decides the authoritative action/mode (it affects gameplay); clip choice,
  blending and pose evaluation can live in the client, reading the sim's published state, so the Deck
  only pays for pose blending at render rate and the hash never includes animation.
- Tuning: a schema per knob (range, step, boolean) validated on load, layered profiles (base then
  difficulty then user), unknown keys rejected, and a round-trip test for the saved override file.
  Tuning files are untrusted input and need a fuzz target.
- Their "required inputs" contract is worth copying as a fitness check: a condition that reads an input
  nobody produces fails at load time.

## Sources read (URLs only)

- https://raw.githubusercontent.com/SK8-ENGINE/skate-3-rust-engine/HEAD/crates/skate-core/src/graph/controller.rs
- https://raw.githubusercontent.com/SK8-ENGINE/skate-3-rust-engine/HEAD/crates/skate-core/src/graph/selection.rs
- https://raw.githubusercontent.com/SK8-ENGINE/skate-3-rust-engine/HEAD/crates/skate-core/src/graph/conditions.rs
- https://raw.githubusercontent.com/SK8-ENGINE/skate-3-rust-engine/HEAD/crates/skate-game/src/graph_runtime.rs
- https://raw.githubusercontent.com/SK8-ENGINE/skate-3-rust-engine/HEAD/crates/skate-game/src/skater_animation.rs
- https://raw.githubusercontent.com/SK8-ENGINE/skate-3-rust-engine/HEAD/crates/skate-game/src/custom_difficulty.rs
- https://raw.githubusercontent.com/SK8-ENGINE/skate-3-rust-engine/HEAD/crates/skate-game/src/tests/powerslide_playback.rs
- https://api.github.com/repos/SK8-ENGINE/skate-3-rust-engine/contents/crates/skate-core/src/graph
