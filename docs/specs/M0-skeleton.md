# M0 — Skeleton: specification

Milestone M0 of `docs/gcity-design.md` §16, in the terms of that document. Written
before implementation (standards §2.1, §10.2). No gameplay.

## Claims

1. **Module layout exists** as in design doc §4.2: `sim/` (with `core/` plus the eight
   named modules), `client/` (with `device/`, `hud/`), `content/`, `tools/`, plus
   `tests/` and `docs/`. Each module directory states its responsibility and allowed
   imports in a README.
2. **The dependency rule is CI-enforced.** No file under `sim/` references a
   `res://` path outside `sim/`, nor a `class_name` declared under `client/`, nor any
   engine surface for input, rendering, UI, audio, wall-clock time, OS or unseeded
   randomness. `content/` contains no scripts or scenes. A violation fails CI with the
   file and line.
3. **Typed GDScript is enforced by the engine.** Untyped declarations and unsafe
   accesses are parse errors (project settings), and CI runs the analyzer over every
   script.
4. **A headless test harness runs in CI** and locally with one command, discovers
   `tests/**/test_*.gd`, runs each `test_*` method on a fresh instance, and fails the
   build on any failure or on zero tests.
5. **A deterministic tick loop exists.** `SimRoot(seed)` advances in integer ticks at
   `TICK_HZ`, owns the only RNG, dispatches queued commands on their tick in
   submission order, then ticks registered systems in registration order. Late
   commands, duplicate registrations and registration after tick 0 are rejected with
   an `Error`, never silently.
6. **State is canonically hashable.** `SimRoot.state_hash()` is a SHA-256 over an
   encoding independent of dictionary insertion order; equal states hash equal,
   changed values or types hash differently, unsupported types fail loudly.
7. **Record-and-replay works.** A fixture (`seed + ticks + commands + expected_hash`)
   is untrusted input: fully validated, rejected with a message on any malformed or
   hostile content, backed by a committed fuzz corpus. Replaying the M0 fixture twice
   in-process and twice across processes yields the identical recorded hash.
8. **The client runs against the sim without owning state.** A `LocalHost` node steps
   the sim on the physics tick and asserts the tick rates agree; the main scene reads
   tick, seed and hash and displays them. The client submits commands and reads; it
   never writes sim state.
9. **The engine and every CI action are pinned** by exact version and hash.
10. **The ten open decisions are ADRs** in `docs/adr/`, in the standards §7 format,
    status proposed, with ADR-002 (tick model) carrying the proposal M0 implements.

## Out of scope (goes to the debt log if touched)

Any gameplay system, any content kind, the stat resolver, Steam integration,
performance measurement, the content schema language, save/load beyond the replay
fixture, C#/Rust hot paths.

## Extension exercise for Q4

Add a second sim system and a second command kind using only a new file under `sim/`
or `tests/` and a registration call; the diff under `sim/core/` must be empty.
`docs/extending-sim-systems.md` records the procedure; `tests/sim/doubles/counter_system.gd`
is the performed instance.
