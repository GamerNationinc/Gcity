# skate-3-rust-engine: ground contact and board/rider orientation

Provenance warning: recovered-from-binary port. Only the general technique is noted here.

## Problem it solves

A board must know, every tick, whether it is on the ground, what "the ground" means when it is
straddling a ledge, a ramp lip or a curb, and which way is up for the rider. Getting this wrong shows
up as jitter on flat ground, snapping on ramp transitions, the rider flipping when crossing between
flat and near-vertical surfaces, or the board floating a hair above small bumps.

## Concepts and data (conceptual only)

- A small fixed set of downward probe rays, one per wheel, cast in the board's own frame. Each probe
  yields hit/miss, distance and the surface normal.
- Fallback contact sources: when wheels report nothing usable, contacts from other board parts (deck,
  each truck) are consulted in a fixed priority order.
- A reference normal (the previous accepted ground normal) that new candidate normals are compared
  against.
- A "time without wheel contact" accumulator so that brief separations can be told apart from real
  flight.
- A closing-velocity measure (how fast the board approaches the surface) kept separately from the
  binary grounded flag, used for impact response.
- For the rider's up vector: two smoothing filters running at different speeds, blended by board
  speed; a rate limit on how fast the blend target may change; and a rate/acceleration limit on the up
  vector itself.

## Order of operations / tick structure

1. Cast the wheel probes from the current board frame.
2. Gate each wheel normal: accept it only if it points sufficiently upward, is within an angular
   tolerance of the reference normal, and if enough wheels qualify that their summed normal is not
   degenerate. Average the accepted ones with equal weight.
3. If the wheel gate fails, try the other board parts in their fixed order and sum/normalise those.
4. If nothing qualifies, keep the previous wheel normal rather than resetting it (prevents a sudden
   reorientation on a single bad frame).
5. Soft snap: if a wheel is not physically touching but its probe hits geometry within a small
   distance, treat the probe as contact for normal purposes. No explicit position correction is done.
6. Grounded is "any wheel in contact"; the no-contact timer accumulates otherwise.
7. Orientation is a downstream consumer of the chosen normal: the rider's target up vector blends
   toward it under rate limits; when the surface is steep relative to world up, three candidates are
   compared (ground normal, world up, a projected compromise) and the one closest to the predicted
   orientation wins; heading (yaw) is preserved while pitch and roll are corrected; motion along the
   board's sideways axis gets extra damping; if the up vector is already moving away from where it
   should go, its rate is scaled down to stop oscillation; and the up vector is prevented from tilting
   behind the board in extreme cases. Ground blending requires a minimum wheel contact count.
8. In the ramp-transition mode, player lean input steers the velocity direction toward a lean-tilted
   up direction and the original speed magnitude is restored afterwards, so steering on a ramp never
   adds or removes energy.

## The trick that makes it work

Hysteresis everywhere instead of thresholds anywhere: the reference-normal comparison rejects
outliers, the "keep last normal" rule bridges gaps, soft snap absorbs tiny height noise, and the
dual-rate filter plus rate limits turn noisy contact into smooth orientation. The binary grounded flag
is kept dumb; the smart behaviour lives in the continuous filters.

## Failure modes and fixes seen in their history

- Ramp-transition lean was inverted because the wrong controller axis fed the lean input; with the
  wrong axis, neutral produced zero lean and the board fell back into the ramp. The fix was the input
  mapping, not the physics, which is a useful diagnostic lesson.
- Invisible walls came from trigger/zone volumes that had no surface and were still treated as
  collision; fixed by dropping surfaceless volumes from collision.
- Water needed a "shallow acts as solid, deep floats" distinction computed from distance to solid
  ground under the contact point.

## What a Gcity version should consider

- Probes and normal gating are sim work; express probe count, angular gates, snap distance and filter
  rates as data on the controller's content definition, not constants in code.
- Determinism: the averaging of normals and the dual-filter blend are float accumulation hot spots.
  Either quantise the accepted normal and the filtered up vector each tick (e.g. to a fixed precision
  before hashing and before feeding the next tick) or keep orientation in fixed-point. Sum candidate
  normals in a fixed wheel order so results never depend on query return order.
- Gcity builds on a 1 m grid; edges, steps and ramp lips are frequent. The reference-normal gate plus
  "keep last normal" plus soft snap is exactly the set of tools for walking or rolling over grid seams
  without jitter. Write metamorphic tests: lowering a step height must never increase the number of
  ticks with grounded = false; rotating the whole scene about world up must not change the outcome.
- Keep the grounded flag and a separate no-contact tick counter; let "coyote time" style rules read the
  counter instead of adding special cases.
- The speed-preserving redirection on ramps is a good general rule for steering on curved surfaces in
  an integer-tick sim: change direction, then restore magnitude, so feel tweaks do not leak energy.
- Deck budget: a handful of ray casts per controlled body per tick is cheap; avoid shape sweeps per
  wheel. Batch probes for all bodies in one pass.
- Orientation smoothing that the player sees can also be partly a client concern; keep the
  authoritative orientation in the sim simple and filtered, and let the client add purely visual lean.

## Sources read (URLs only)

- https://raw.githubusercontent.com/SK8-ENGINE/skate-3-rust-engine/HEAD/crates/skate-core/src/physics/board_ground.rs
- https://raw.githubusercontent.com/SK8-ENGINE/skate-3-rust-engine/HEAD/crates/skate-core/src/riding/ground_orientation.rs
- https://raw.githubusercontent.com/SK8-ENGINE/skate-3-rust-engine/HEAD/docs/physics/quarter-pipe-transition-input.md
- https://api.github.com/repos/SK8-ENGINE/skate-3-rust-engine/contents/crates/skate-core/src/physics
- https://api.github.com/repos/SK8-ENGINE/skate-3-rust-engine/contents/crates/skate-core/src/riding
- https://api.github.com/repos/SK8-ENGINE/skate-3-rust-engine/issues?state=all&per_page=100
