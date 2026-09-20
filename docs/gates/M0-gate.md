# G0 — M0 Skeleton: gate evidence package

Milestone: M0 — Skeleton (design doc §16; standards §11 row G0)
Specification: `docs/specs/M0-skeleton.md`
Submitted: 2026-09-20 by Claude Code
Outcome: _pending review_

---

## 1. Specification

See `docs/specs/M0-skeleton.md`. Ten claims; all implemented. Claim 5 (tick model)
implements the proposal in ADR-002, which is not yet signed (see §4).

## 2. Verification report

All numbers below were produced on the development container (Linux x86_64, Godot
4.6.1-stable, Python 3.11), **not on Steam Deck hardware**. M0 makes no performance
claim, so no Deck measurement is required for this gate (standards §4.2 applies from
G4). Reproduce with `tools/test.sh`.

### Fitness functions (`tools/test.sh fitness`)

| Check | Result |
|---|---|
| Python unit tests for `check_dependencies.py` and `validate_content.py` | 17 tests, OK |
| `tools/check_dependencies.py` on the repository | clean |
| `tools/validate_content.py` on the repository | clean (no content at M0; zero schemas registered) |

The dependency checker's own tests include a real-repository check, so the rule is
verified both on synthetic violations (path import, scene ext_resource, client
`class_name` use, each deny-listed engine surface, code under `content/`) and on the
actual tree.

### Static analysis (`tools/test.sh scripts`)

Every `.gd` file under `sim/`, `client/`, `tests/`, `tools/` passes
`godot --check-only` with `treat_warnings_as_errors=true` and the untyped/unsafe
warnings at error level. Verified during development: an untyped `var x = 5` and an
untyped parameter are parse errors, and an unsafe `Variant` cast in the runner was
caught and rewritten.

### Headless test suite (`tools/test.sh unit`)

| Suite | Tests | What it proves |
|---|---|---|
| `tests/sim/test_state_hash.gd` | 7 | Canonical encoding: order independence (incl. 10 000 generated structures with shuffled keys), type/value sensitivity, no prefix ambiguity, loud failure on unsupported types |
| `tests/sim/test_command_registry.gd` | 3 | Registration rules, lexical `kinds()`, all four dispatch outcomes incl. handler contract violation |
| `tests/sim/test_sim_root.gd` | 10 | Exact integer tick, registration order and lock after tick 0, late-command rejection, dispatch order, rejected commands counted not fatal, inbox is state, determinism across 10 000 generated (seed, ticks, command stream) cases |
| `tests/sim/test_replay_fixture.gd` | 6 | Valid parse, hash field rules, 24 named hostile inputs, invalid UTF-8, the committed fuzz corpus (12 files), 10 000 random mutations never crash and never validate inconsistently |
| `tests/sim/test_replay.gd` | 3 | M0 fixture replays bit-identically and matches its recorded hash; mismatched/used sims refused; commands reach a registered system |
| **Total** | **29 tests, 188 assertions, 0 failed** | |

Property tests run 10 000 cases each in CI (standards §3.2). Seeds are fixed constants
in the test files; a failing seed is to be committed as a named regression case.

### Replay determinism (`tools/test.sh replay`)

`tests/replay/m0-trivial.json` (seed 20260920, 400 ticks, no commands) replayed in
two separate engine processes:

```
ok   tests/replay/m0-trivial.json 06a22cfe529f13565abac7989fd88b0a2abc75ad06cc423284549fadaa8ed1e0
```

Both runs produced the hash above, which equals the fixture's `expected_hash`.

### Fuzz corpus

`tests/fuzz/replay_fixture/`: 12 hostile fixtures (empty, truncated, overflowing
ticks, inexact seed, unknown key, wrong types, fractional tick, 5 000-deep nesting,
binary garbage, over-long name). All rejected with a message; none crash.

## 3. Demo script

Performed on any Linux x86_64 machine with `python3`, `curl`, `unzip`. Expected
observation follows each step.

1. `git clone` the repository at the tagged G0 commit and `cd` into it.
2. Run `tools/test.sh fitness`. → Ends with `check_dependencies: clean` and
   `validate_content: clean`; the Python test line reports `OK`.
3. Run `tools/test.sh scripts`. → First run downloads Godot 4.6.1 and prints its
   SHA-256 verification implicitly (a mismatch aborts). Every script line reads `ok`.
4. Run `tools/test.sh unit`. → `29 tests, 188 assertions, 0 failed`, exit code 0.
   (Lines beginning `ERROR:` between the `ok` lines are the sim's intentional loud
   rejections being exercised by tests.)
5. Run `tools/test.sh replay`. → One `ok` line with the hash
   `06a22cfe529f13565abac7989fd88b0a2abc75ad06cc423284549fadaa8ed1e0`.
6. Edit `sim/core/sim_root.gd` to add `var _ui: Control` anywhere, run
   `python3 tools/check_dependencies.py`. → One violation naming the file, line and
   `Control`. Revert.
7. Edit `tests/replay/m0-trivial.json` to change `"ticks": 400` to `401`, run
   `tools/test.sh unit`. → `test_m0_fixture_replays_identically_and_matches_its_recorded_hash`
   fails on the hash mismatch. Revert.
8. Run `$(tools/godot.sh) --path .` and press Play. → A window at 1280×800 shows
   `Gcity M0 skeleton`, a seed, a tick counter advancing at 40 per second, and a
   64-character hash changing every tick. Close it.
9. In `project.godot` set `physics_ticks_per_second=60`, press Play. → The game halts
   at startup with the assertion "physics_ticks_per_second (60) must equal
   SimRoot.TICK_HZ (40)". Revert.
10. Open `.github/workflows/ci.yml`. → Every `uses:` is a 40-character commit SHA;
    `tools/godot.pin` carries the engine version and SHA-256.

## 4. Debt and deviation log

| # | Item | Kind | Scheduled |
|---|---|---|---|
| 1 | ADR-002 (fixed tick, 40 Hz) implemented as proposed but not yet signed. G0 requires it closed. | assumption | Sign-off at this review |
| 2 | ADR-003 and ADR-009 are open and block M1 (standards §7). Not M0 scope; recorded because "everything else waits on these two". | dependency | Before M1 |
| 3 | `tools/validate_content.py` checks layout, kind registration, JSON well-formedness and `schema_version` only. Structural validation against a schema lands with the first content kind. Zero content exists, so nothing is unvalidated today. | deliberate incompleteness | M1 |
| 4 | The M0 replay fixture exercises the tick loop, RNG state and inbox only, because no sim system exists outside test doubles. Fixtures with real systems begin at M1. | scope | M1 |
| 5 | No Deck measurement. M0 has no frame-budget claim. First Deck numbers are due at G4; first Deck smoke run of the Linux export is due at G1 (standards §8.1). | scope | G1 |
| 6 | Steamworks app registration, `dev`/`gate` depot branches (standards §12 item 4) are not in the repository's control. | external action | CEOGG, before G1 |
| 7 | Mutation testing (standards §3.6) not run; target is G6. | scope | G6 |
| 8 | Renderer left at the Godot default (Forward+). The GodotSteam overlay note (standards §8.2) is to be verified at the M5 spike. | assumption | M5 |
| 9 | `tests/` and `tools/` may declare global `class_name`s (`GcityTest`, `CounterSystemDouble`). They are not shipped; the export preset at G1 must exclude `tests/` and `tools/`. | note | G1 |

## 5. The four standing questions

**Q1 — Does it function?** Yes. All declared behaviour has passing tests; the three
property tests run 10 000 cases each; the M0 fixture replays to the identical hash on
two consecutive process runs (§2).

**Q2 — Is it secure?** Threat model for M0: the only external inputs are replay
fixture files and content files. Fixtures are validated at the trust boundary with
type, range and key-set checks, a committed corpus and 10 000 random mutations per run.
Content files are layout- and schema-registration-checked (and none exist). No engine
script is loaded from data. Dependencies: Godot 4.6.1 (MIT, pinned by SHA-256), two
GitHub Actions pinned by commit SHA, Python standard library only. Telemetry: none.

**Q3 — Is it complete?** No stubs; no `TODO` anywhere in the tree; every error path
returns an `Error`, `push_error`s, or asserts. The debt log above is fully scheduled.

**Q4 — Is it expandable?** The extension exercise (spec §"Extension exercise") is
performed: `tests/sim/doubles/counter_system.gd` adds a second system and a new
command kind with zero changes under `sim/core/`. Command kinds and system ids are
`StringName` registry entries, not enums. The snapshot and fixture schemas carry
versions. `docs/extending-sim-systems.md` documents the minimal diff.

## 6. Sign-off

Approver: CEOGG
Date:
Outcome: ☐ Accepted   ☐ Accepted with conditions (list below)   ☐ Rejected
Conditions:
