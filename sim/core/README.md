# `sim/core`

The declared root of authoritative state and the plumbing every other `sim/` module
builds on: `SimRoot` (tick loop, seeded RNG, system registry, command inbox),
`SimSystem` (base class), `SimCommand` + `CommandRegistry` (the only way a client
changes sim state), `StateHash` (canonical hashing) and `ReplayFixture` + `Replay`
(record-and-replay, the primary integration test).

**Allowed imports:** `sim/` only. Nothing here may reference rendering, input, UI,
wall-clock time or global randomness; `tools/check_dependencies.py` enforces it.

**Introduced at:** M0 (skeleton).

**Extension point:** [docs/extending-sim-systems.md](../../docs/extending-sim-systems.md).
