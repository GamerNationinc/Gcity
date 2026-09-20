# `sim/core`

The declared root of authoritative state and the plumbing every other `sim/` module
builds on: `SimRoot` (tick loop, seeded RNG, system registry, command inbox),
`SimSystem` (base class), `SimCommand` + `CommandRegistry` (the only way a client
changes sim state), `StateHash` (canonical hashing), `ReplayFixture` + `Replay`
(record-and-replay, the primary integration test) and `ContentDb` (system id
`content`: the dictionaries the host hands in from `content/`, validated at the
boundary, frozen at the first tick, digested into the state hash).

The game's fixed system order lives one level up in `sim/assembly.gd` (`SimAssembly`),
because core must not depend on the modules that build on it.

**Allowed imports:** `sim/` only. Nothing here may reference rendering, input, UI,
wall-clock time or global randomness; `tools/check_dependencies.py` enforces it.

**Introduced at:** M0 (skeleton); `ContentDb` at M1.

**Extension point:** [docs/extending-sim-systems.md](../../docs/extending-sim-systems.md).
