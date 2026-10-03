# iw4L: the single input -> step -> snapshot funnel, and what random command streams taught them

## Problem it solves

Server authority, client prediction and replay must all produce the same world from the same inputs,
and bots must be indistinguishable from humans downstream. Any side door that mutates the world outside
the step breaks prediction, replay and later networking at once.

## Concepts and data (conceptual only)

- One step function. Its arguments are: the world (explicitly passed, not global), the tick number, the
  bundle of all inputs for that tick, the elapsed step duration, and a "reason" tag. Its return value is
  a snapshot. Their rule: everything that can change the authoritative world enters through the input
  bundle and leaves through the snapshot; there is no second door.
- The reason tag distinguishes authoritative advance, prediction of a new tick, and replay of a recorded
  tick. Same implementation in all three cases; only bookkeeping differs.
- The input bundle holds player commands and debug/scripted actions, each tagged with the issuing
  client. Bot commands are inserted into the same list in the same format as human commands.
- Two independent world instances can coexist (authoritative and predicted) because state ownership is
  explicit; neither touches globals.
- Time is a parameter, never read from inside the world.
- Snapshot adoption has two entry points: adopt an authoritative snapshot, and reconcile a prediction
  against one. Both return a report describing what happened.
- Snapshot entity semantics come from the game's own data (players, corpses, items, missiles), with
  entity references wrapped in a typed id and invalid references resolving to an explicit sentinel.

## Order of operations / tick structure

1. Collect all inputs for the tick (network, local, bots, replay log).
2. Canonicalise the bundle: sort commands and actions by client id so delivery order cannot change the
   result.
3. Step the world with the tick number, duration and reason.
4. The returned snapshot is the only thing published: to clients, to the spectator/theatre system, to
   the demo recorder. Anything not in the snapshot does not exist for consumers.
5. On a client, the received snapshot is validated, then adopted or reconciled with the prediction.

## The trick that makes it work

Making the snapshot the return value (rather than something assembled elsewhere by reading the world)
means the snapshot is complete by construction, and making time and the reason parameters means the
same code path is re-executable for prediction and replay. Canonical input ordering removes the most
common accidental nondeterminism of multi-source input.

## Failure modes and fixes seen in their history

A group of hardening PRs shows what happens once untrusted input reaches a single funnel:
- A client could crash the host's authoritative step with two quick commands: one naming an equipment
  slot the player did not own, then a cancel referring to it. The first was cached without the
  ownership check used elsewhere; the second assumed the cached slot existed. Found by modelling the
  command path and generating a large number of random command streams. Fix: a missing referenced row
  means "no effect", not a crash.
- Non-finite aim angles in a melee command produced non-finite movement and trace endpoints, which a
  later linking step rejected by crashing. Fix: only accept finite angles, matching the validation
  already applied to other command kinds. Lesson: the same field needs the same validation on every
  command kind that carries it; centralise it.
- Finite script arguments could still create non-finite poses a few ticks later (launches from extreme
  origins overflowing trace endpoints; linked entities overflowing after their parent moves). Fix: a
  per-tick guard that cancels a body, or detaches a link, before it would publish a non-finite pose,
  preserving the last valid state. Found by code reading, not by observation.
- A modified host could send snapshots that decode fine but are internally inconsistent across sections
  (a player without its client record, an item without its ammo row, an entity in the wrong slot kind,
  an unsupported trajectory kind, an id outside the receiving catalogue). Fix: cross-section validation
  before caching or acknowledging; inconsistent snapshots are logged and dropped while valid ones in the
  same batch still apply; recovery via reset/resend.
- Smaller ones: a script number that was non-finite crashing when converted to text (now a script
  error), decoder state mutated by a failed read (now left unchanged on error), archive entry lengths
  trusted without checking, and an interior NUL breaking trace strings.

Pattern: well-formed parse is not the same as safe to adopt; validate relationships, not just syntax.

## What a Gcity version should consider

- Gcity already has the shape (client submits commands, handlers validate and apply). Copy the explicit
  "reason" parameter so authority, prediction (co-op later) and replay share one step and differ only in
  bookkeeping.
- Canonicalise the per-tick command list before applying it (stable sort by issuer, then by submission
  sequence). This should be a tested invariant: any permutation of the same tick's commands yields the
  same hash.
- Treat "snapshot as return value" as a design target for the sim's published view: the client reads
  only that view.
- Write a fuzz target over random command streams per command kind, as a property test with the seeds
  committed. Specifically include: references to things the issuer does not own; a reference followed
  by a command that assumes it; extreme and non-finite numbers in every numeric field (moot for integer
  fields but not for anything parsed from JSON); and commands arriving in the same tick in different
  orders.
- Each command kind's validator should share field validators (angles, positions, ids) from one place,
  so a new command kind cannot forget one.
- Add a post-tick guard that refuses to publish non-finite or out-of-world positions, and makes that a
  loud failure in tests.
- Save files, content and replay fixtures need cross-reference validation (every id resolves in the
  current content registry), not only schema validation; reject the bad record and keep the good ones
  where that is safe.

## Sources read (URLs only)

- https://github.com/vladtrc/iw4L
- https://raw.githubusercontent.com/vladtrc/iw4L/HEAD/docs/SIM-STEP.md
- https://raw.githubusercontent.com/vladtrc/iw4L/HEAD/docs/ENTITIES.md
- https://raw.githubusercontent.com/vladtrc/iw4L/HEAD/docs/INDEX.md
- https://api.github.com/repos/vladtrc/iw4L/pulls/24
- https://api.github.com/repos/vladtrc/iw4L/pulls/36
- https://api.github.com/repos/vladtrc/iw4L/pulls/37
- https://github.com/vladtrc/iw4L/pulls?q=is%3Apr+panic
