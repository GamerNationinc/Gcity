# ADR-002: Deterministic fixed tick vs variable step

Status: proposed
Date: 2026-09-20
Design doc: §4.1 (D-02); standards §1 principle 3, §3.1

## Context

The sim must be testable headless by replaying a seed plus an input log and asserting
a state hash (standards §3.1), and must later synchronise across a network for co-op
(§4.1). Both are far easier with a fixed integer tick. The cost is that engine physics
cannot be used as sim state, because Godot's physics is not deterministic across
machines or even across runs with different frame timing.

## Options

### A — Fixed integer tick, sim owns time
- The sim advances in whole ticks; no float delta exists inside `sim/`. Randomness comes
  from one seeded RNG owned by the sim root.
- Cost: sim-relevant physics (ballistics, structural support, flood fill) is written or
  driven by the sim, not by the physics server. Presentation interpolates between ticks.
- Risk: temptation to leak engine state into the sim; mitigated by the deny-list in
  `tools/check_dependencies.py`.
- Forecloses: using Godot physics as authority for anything the hash covers.

### B — Variable step, engine-driven
- Cost: none upfront.
- Risk: replay is approximate at best; co-op needs full state sync instead of input
  sync; nondeterminism bugs are found by playtesting, late.
- Forecloses: input-replay as the primary integration test; lockstep co-op.

### C — Fixed tick with fixed-point math
- Bit-exact across CPUs (needed for lockstep between different machines).
- Cost: pervasive; every float in the sim becomes a fixed type. Listed as a Tier 2
  research candidate (standards §9.2), only if co-op chooses lockstep.

## Decision

Proposed: **A**, at **40 Hz** (`SimRoot.TICK_HZ`), with C held open as a possible
later extension. 40 Hz gives an exact integer tick of 25 000 µs and one sim tick per
rendered frame at the locked 40 fps target, so presentation needs no interpolation at
target frame rate. The project's physics tick rate is set to the same value and
`LocalHost` asserts the two agree at startup.

Same-machine determinism (same binary, same seed, same inputs → same hash) is the M0
requirement. Cross-machine bit-exactness is deferred to the co-op decision.

## Consequences

Easy: record-and-replay, property tests over generated input streams, a hash-stable
save format. Hard: anything physical that the sim must be authoritative about is sim
code, not a physics node.

Irreversible once systems are written against integer ticks: switching to B later
means rewriting every system's time handling.

## Verification

- G0: a trivial fixture replays to an identical hash on two consecutive process runs
  (`tools/test.sh replay`), and a 10 000-case property test over random seeds and
  command streams finds no divergence (`tests/sim/test_sim_root.gd`).
- G1 onward: every milestone adds a fixture; CI replays all of them on every commit.
- If any fixture ever diverges between two runs of the same commit on the same
  machine, this ADR's premise has been violated and the cause is a gate-blocking bug.

## Sign-off

Approver: Lukas Williams — _pending_
