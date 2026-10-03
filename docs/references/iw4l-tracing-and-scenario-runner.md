# iw4L: opt-in tracing and the approved-scenario headless runner

## Problem it solves

Performance and behaviour claims need evidence that is reproducible and attributable to a specific run,
and end-to-end tests need to survive content/catalogue changes without silently changing what they test.

## Concepts and data (conceptual only)

Tracing:
- Off by default, enabled by an environment switch (benchmark commands turn it on automatically). When
  off, nothing is written and hot paths make no instrumentation calls.
- Named spans grouped by owning subsystem; a focus switch narrows recording to one owner.
- A rule against per-item spans (no span per draw, per overlay element); semantic events are kept rare.
- Output: a standard binary trace in a bounded ring buffer plus a manifest describing the run (map,
  role, workload, source revision). Readers reject a trace that dropped or overwrote events: an
  incomplete trace fails, it is never reported as partial truth.
- Analysis is done after the run with saved SQL queries over the trace, describing where the whole run
  spent its time, not single frames. Claims must cite a pinned run id and its manifest, never "the
  latest run".
- A separate lightweight benchmark mode measures frame time as a span tree without needing a trace.

Approved scenarios:
- Permanent end-to-end scenarios, distinct from throwaway probes; adding one requires explicit owner
  approval, and the build rejects ordinary unit-test constructs in that crate so scenarios stay runs,
  not unit tests.
- A scenario is a deterministic script defined in one source file: map, spawn position and angles,
  weapons, movement durations, input sequence. Changing a scene means editing that definition, never the
  runner.
- A seed resolves random choices (map, spawn) once; the resolved set is written to a run record, and
  re-runs read the record so catalogue changes cannot change the scenario.
- The runner drives phases and observes liveness rather than asserting frame timing: map loaded, script
  program installed, players exist, simulation advanced, movement commands reached players, lifecycle
  boundaries happened in order, no script fault, quit was intentional. Movement is measured as path
  length walked, not end position.
- Each run leaves artefacts: the run record, screenshots, logs, and the trace. Cold caches are used so
  runs start fresh.
- A separate command-script mode runs scripted commands synchronously, each waiting for its state change
  before the next.
- A clip command saves the last span of play as both a demo and state dumps; hosts record authoritative
  snapshots, clients record received snapshots and their own presented state, so divergence can be
  inspected offline.

## Order of operations / tick structure

Scenario run: resolve seed to a concrete scene set and write the run record; launch with cold caches and
tracing on; step through phases, waiting on observable state rather than time; collect artefacts; check
liveness facts in order; fail with the artefacts attached.

## The trick that makes it work

Separating "resolve randomness" from "execute" (via the persisted run record) makes end-to-end runs
reproducible even as content grows, and refusing partial traces keeps performance numbers honest.

## Failure modes and fixes seen in their history

- An interior NUL in a debug string corrupted trace output; strings written to traces are escaped.
- Default binary lookup for the scenario runner had to be fixed per platform (executable suffix).
- The scenario runner checks liveness, not correctness of game values; they rely on it for "the whole
  stack still works", not for gameplay assertions.

## What a Gcity version should consider

- Gcity already has replay fixtures with hash checks, which are stronger than their liveness checks;
  copy the "resolve seed once, persist the resolved scenario, replay from the record" idea for M9
  scenario runs so adding a faction or district does not change an existing fixture's inputs.
- Opt-in tracing in the sim with zero cost when off: a per-category switch, spans per subsystem per tick
  (never per agent or per node), and tick numbers as the time axis so traces line up with replay.
- Bounded buffer; a trace that overflowed is rejected, not trimmed. Every published performance claim
  for the Deck cites a run id and manifest (device, build hash, scenario, seed).
- Judge whole-run percentiles (1% and 0.1% lows) from the trace, which matches Gcity's reporting rule.
- Scenario steps should wait on sim state (a predicate on the snapshot) rather than wall time; the
  headless runner then has no timing flakiness.
- Clip/dump of the last few seconds of authoritative state plus input log is a cheap, high-value
  debugging tool; trigger it from a controller chord, not a keyboard.
- Approval gate for permanent scenarios maps naturally onto Gcity's gate sign-off.

## Sources read (URLs only)

- https://raw.githubusercontent.com/vladtrc/iw4L/HEAD/docs/PERF.md
- https://raw.githubusercontent.com/vladtrc/iw4L/HEAD/docs/RUN.md
- https://raw.githubusercontent.com/vladtrc/iw4L/HEAD/docs/INDEX.md
- https://raw.githubusercontent.com/vladtrc/iw4L/HEAD/crates/approved_tests/README.md
- https://api.github.com/repos/vladtrc/iw4L/contents/crates/approved_tests
- https://api.github.com/repos/vladtrc/iw4L/pulls?state=all&per_page=100
- https://github.com/vladtrc/iw4L/pulls?q=is%3Apr+panic
