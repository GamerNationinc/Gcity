# Gcity — working agreement for Claude Code

Read `docs/gcity-design.md` (what) and `docs/gcity-engineering-standards.md` (how)
before touching anything. This file is the short version that must hold on every commit.

## Module boundaries

```
sim/        authoritative state. No rendering, input, UI, audio, wall-clock, OS, global RNG.
  core/     SimRoot (tick loop, seeded RNG, system + command registries, hashing, replay)
  world/ nav/ land/ agents/ progression/ items/ quests/ threat/   (see each README.md)
client/     rendering, input, camera, audio, the device. Reads sim state; submits commands.
content/    data files only. content/<kind>/<id>.json, schema registered in tools/content_schemas/.
tools/      fitness functions, validators, engine pin, test runner scripts. May import anything.
tests/      headless tests (tests/**/test_*.gd), replay fixtures, fuzz corpora.
docs/       design, standards, ADRs (docs/adr/), gate ledger (docs/gates/), specs, research.
```

## The dependency rule

`sim/` may reference `res://sim/` only, and never a `class_name` declared under
`client/`. `tools/check_dependencies.py` enforces this in CI together with the sim
deny-list (Input, DisplayServer, Control, Time., OS., Engine., randi()…). Do not work
around the checker; if the sim needs something from the client, it is a command.

The client never writes sim state. It calls `SimRoot.submit(SimCommand)`; a handler
registered in `CommandRegistry` validates the payload and applies it, or rejects it.

## Rules that fail CI

- **Typed GDScript everywhere.** `project.godot` turns untyped declarations, unsafe
  property/method access, unsafe casts and unsafe call arguments into parse errors.
  Assign a `Variant` to a typed variable instead of casting it; check `typeof()` first.
- **Content is data.** A new weapon, perk, module, district, faction or command kind is
  a file or a registration call, never an edit to a `match`/`switch` or an enum.
- **Determinism.** Sim time is integer ticks (`SimRoot.TICK_HZ`). Randomness comes from
  `sim.rng()` only. Iterate dictionaries only after sorting keys when order matters.
- **State is hashable.** Every `SimSystem.snapshot()` returns only null/bool/int/float/
  String/StringName/PackedByteArray/Array/Dictionary with int or string keys.
- **Every replay fixture in `tests/replay/` reproduces its recorded hash.** A changed
  hash is either a deliberate sim change explained in the commit, or a bug.

## Never

- Add a `sim/` → `client/` import, or a singleton / autoload holding sim state.
- Change behaviour silently to make a failing test pass, or write tests by reading the
  implementation. Tests come before or with the code.
- Leave a stub, a `TODO` in a shipped path, or a function that silently does nothing.
  Errors are handled or loudly fatal (`push_error` + a returned `Error`, or `assert`).
- Add a dependency (engine version, addon, action, Python package) without pinning it
  by exact version + hash and noting license, maintenance and transitive size.
- Encode content as code ("a perk class") when numbers in a file would do.
- Add a "temporary" special case to a generic system.
- Expand scope beyond the milestone spec. Extra findings go in the gate's debt log.
- Present work without running `tools/test.sh`. Unrun code is not a deliverable.

## Naming

- Files and directories `snake_case`; `class_name` `PascalCase`; constants `UPPER_SNAKE`.
- Private members and helpers start with `_`. Public read access is a method
  (`get_tick()`), not an exported field.
- Identifiers that name things in registries are `StringName`s written `&"kind.name"`,
  dotted by owning system: `&"counter.add"`.
- Content ids are `[a-z0-9_]+`, file name equals id.
- Test files `test_<unit>.gd`, test methods `test_<claim>`, doubles under `tests/**/doubles/`.
- One system per session; one milestone per branch; diffs reviewable in one sitting.

## How to run things

```
tools/test.sh              # everything, in CI order (fitness, scripts, unit, replay)
tools/test.sh unit         # headless test suite only
tools/test.sh replay       # every fixture twice, hashes diffed
python3 -m unittest discover -s tools/tests -t .
$(tools/godot.sh) --path . # open the project in the pinned editor
```

The pinned engine is in `tools/godot.pin`; `tools/godot.sh` downloads and verifies it.

## Milestone process

No milestone starts before the previous gate is signed by CEOGG in
`docs/gates/M<n>-gate.md`. Each milestone: spec in `docs/specs/` first, then tests and
code, then the four-part evidence package in the gate file. Open decisions are ADRs in
`docs/adr/`; a decision is closed only by a signed ADR, and a wrong one is superseded,
never edited.
