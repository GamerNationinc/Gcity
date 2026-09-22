# CLAUDE.md — Gcity

Behavioural guidelines for Claude Code on this repository: the Karpathy-derived general
guidelines merged with Gcity's architecture and verification rules. This file is the
short version that must hold on every commit.

Read alongside:
- `docs/gcity-design.md` — what the systems are and why
- `docs/gcity-engineering-standards.md` — gates, verification, security, Steam, research
- `docs/adr/` — decisions. **An open ADR is not yours to resolve.**
- `docs/specs/` — the milestone specification that every changed line traces to

**Tradeoff:** these rules bias toward caution and evidence over speed. This project is
verification-led by design. For trivial tasks, use judgment.

---

## 1. Think before coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing anything:

- State your assumptions explicitly. If uncertain, ask.
- If several readings of the request exist, present them rather than silently picking one.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop and name what's confusing.

Project-specific additions:

- **Check `docs/adr/README.md` first.** If the work depends on an ADR still marked
  `proposed`, stop and say so. Do not pick a side to keep moving. An implementation
  built on a guessed decision is worse than no implementation. (ADR-002 to 009 are accepted;
  ADR-001 and 010 remain, and 010 blocks M7.)
- **Check the design doc and the milestone spec before inventing a design.** If what
  you're about to build is already specified, follow the spec. If the spec is wrong,
  say why — don't quietly deviate.
- **Deviations go in the gate's debt log**, not into the commit message.

---

## 2. Simplicity first

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No error handling for scenarios that cannot occur.
- If it's 200 lines and could be 50, rewrite it.

### The extensibility exception — read this carefully

This project has a written extensibility requirement (standards §6, gate question Q4).
That is **not** licence to add speculative flexibility. The distinction:

| Required (build it) | Speculative (don't) |
|---|---|
| Weapons, perks, modules, districts, factions and signals defined in data files | A plugin system nobody asked for |
| Registry entries instead of closed enums on content paths | Generic managers, abstract factories, dependency injection frameworks |
| Versioned schemas with migrations | Config options with one caller |
| An event bus for progression events | Events for things only one system will ever emit |

The test: **is the extension point named in the design doc, an ADR or the milestone
spec?** If yes, build it. If you're inventing the requirement yourself, you're
speculating — don't.

---

## 3. Surgical changes

**Touch only what you must. Clean up only your own mess.**

- Don't improve adjacent code, comments or formatting.
- Don't refactor what isn't broken.
- Match the existing style even where you'd choose differently.
- Notice unrelated dead code? Mention it. Don't delete it.
- Remove imports and locals that *your* change orphaned. Leave pre-existing dead code alone.

Every changed line must trace to the request or to the milestone spec.

Additionally: **one system per session.** No change spanning multiple `sim/` modules in
a single pass. One milestone per branch. If a diff can't be reviewed in one sitting, it
should have been two pieces of work.

---

## 4. Goal-driven execution

**Define success criteria. Loop until verified.**

Turn the task into something checkable before starting:

- "Add validation" → write tests for invalid input, then make them pass
- "Fix the bug" → write a failing test that reproduces it, then make it pass
- "Refactor X" → tests pass before and after, behaviour unchanged

State a short plan for multi-step work:

```
1. [step] → verify: [check]
2. [step] → verify: [check]
```

**Unrun code is not a deliverable.** Run `tools/test.sh` before presenting anything. If
it can't run, say so — don't present the work as complete.

---

## 5. Module boundaries and the dependency rule

```
sim/        authoritative state. No rendering, input, UI, audio, wall-clock, OS, global RNG.
  assembly.gd  SimAssembly: the one place systems are registered, in one fixed order
  core/     SimRoot (tick loop, seeded RNG, system + command registries, hashing, replay, ContentDb)
  world/ nav/ land/ agents/ progression/ items/ quests/ threat/   (see each README.md)
client/     rendering, input, camera, audio, the device. Reads sim state; submits commands.
content/    data files only. content/<kind>/<id>.json, schema registered in tools/content_schemas/.
tools/      fitness functions, validators, engine pin, test runner scripts. May import anything.
tests/      headless tests (tests/**/test_*.gd), replay fixtures, fuzz corpora.
docs/       design, standards, ADRs (docs/adr/), gate ledger (docs/gates/), specs, research.
```

`sim/` may reference `res://sim/` only, and never a `class_name` declared under
`client/`. `tools/check_dependencies.py` enforces this in CI together with the sim
deny-list (Input, DisplayServer, Control, Time., OS., Engine., randi()…). Do not work
around the checker; if the sim needs something from the client, it is a command.

The client never writes sim state. It calls `SimRoot.submit(SimCommand)`; a handler
registered in `CommandRegistry` validates the payload and applies it, or rejects it.

---

## 6. Hard invariants

These are not style preferences. Violating one fails a gate regardless of anything else,
and most of them fail CI first.

1. **`sim/` never imports from `client/`.** CI enforces it. The sim holds all
   authoritative state and touches no rendering, input or UI.
2. **The client requests, the sim decides.** The client may never write inventory,
   ownership, heat, progression or quest state. This is what makes co-op possible later.
3. **Content is data.** A new weapon, perk, module, district, faction or command kind is
   a file or a registration call, never an edit to a `match`/`switch` or an enum. If
   adding one requires a `sim/` diff, the abstraction is wrong.
4. **No global mutable state** outside the sim's declared root: no singletons, no
   autoloads holding sim state.
5. **Typed GDScript everywhere.** `project.godot` turns untyped declarations, unsafe
   property/method access, unsafe casts and unsafe call arguments into parse errors.
   Assign a `Variant` to a typed variable instead of casting it; check `typeof()` first.
   C# runs with nullable reference types and warnings as errors. Rust runs Clippy pedantic.
6. **Determinism is a feature.** Sim time is integer ticks (`SimRoot.TICK_HZ`); randomness
   comes from `sim.rng()` only; same seed plus same input log produces the same state
   hash. Watch for the usual offenders: dictionary iteration order (sort keys when order
   matters), uninitialised values, floating-point accumulation, wall-clock reads inside
   the sim.
7. **State is hashable.** Every `SimSystem.snapshot()` returns only null/bool/int/float/
   String/StringName/PackedByteArray/Array/Dictionary with int or string keys.
8. **Every external input is untrusted** — save files, content files, replay fixtures,
   cloud payloads, and later network messages. Validate at the boundary.
9. **Every replay fixture in `tests/replay/` reproduces its recorded hash.** A changed
   hash is either a deliberate sim change explained in the commit, or a bug.

---

## 7. Testing requirements

Tests are written before or with the implementation. Never after, and never by reading
the implementation — that produces tests that confirm bugs.

Per system, in rough order of value here:

- **Replay fixture** — seed plus input log, replayed headless, state hash asserted. Every
  milestone from M1 ships at least one.
- **Property tests** for the invariants listed in the standards doc §3.2. Minimum 10,000
  generated cases. Commit every failing seed permanently as a regression case.
- **Round-trip property** for anything serialised: `load(save(x)) == x`.
- **Metamorphic relations** for AI and generation, which have no oracle. Raising a wall's
  HP must not lower the chosen breach path's cost, and so on.
- **Fuzz target** for every parser and every trust boundary, with a corpus in the repo.

Don't chase coverage percentages. Mutation score is the honest metric; target ≥70% on
`sim/` by the M6 gate.

---

## 8. Performance rules

Target is a locked **40 fps on Steam Deck** — 25 ms, allocated per subsystem in
standards doc §4.1.

- **Deck numbers are the only numbers that count.** Desktop benchmarks are a smoke signal.
- Report **1% and 0.1% lows**, never averages.
- Any heavy system must be **time-sliceable and interruptible**. Meshing, flood fill,
  pathfinding and utility scoring all run on a budget, not to completion.
- **Don't optimise on suspicion.** Profile, show the capture, then change code.
- **Don't reach for the fast language early.** GDScript until measurement says otherwise;
  then a Rust GDExtension via a timeboxed spike with a declared pass metric.

---

## 9. Scope and gates

- Work belongs to exactly one milestone. Anything outside the current milestone's spec
  goes in the debt log for the gate — not into the commit.
- **Nothing is done because you say it's done.** A milestone ends when CEOGG signs the
  gate in `docs/gates/M<n>-gate.md`, with a spec, a verification report, a demo script
  runnable on their own Deck, and a debt log. Each milestone: spec in `docs/specs/`
  first and approved, then tests and code, then the four-part evidence package.
- Never mark a gate item complete on your own authority.
- Never weaken or delete a failing test to make a gate pass. Report the failure.
- A decision is closed only by a signed ADR; a wrong one is superseded, never edited.

---

## 10. Never

- Resolve an open ADR yourself.
- Add a `sim/` → `client/` import, or a singleton / autoload holding sim state.
- Change behaviour to satisfy a failing test instead of fixing the cause.
- Leave a stub, a `TODO` in a shipped path, or a function that silently does nothing.
  Errors are handled or loudly fatal (`push_error` + a returned `Error`, or `assert`).
- Add a dependency (engine version, addon, action, Python package) without pinning it by
  exact version + hash and noting its maintenance status, licence and transitive size.
- Encode content as code — a perk as a bespoke class when numbers would do.
- Add a "temporary" special case inside a generic system.
- Execute untrusted script content in the engine. Script mods require a WASM sandbox
  with a capability-limited host API, or they don't ship.
- Write a debug tool that needs a keyboard. This is a handheld-first project.
- Claim something was tested when it wasn't. Present work without running `tools/test.sh`.

---

## 11. Naming

- Files and directories `snake_case`; `class_name` `PascalCase`; constants `UPPER_SNAKE`.
- Private members and helpers start with `_`. Public read access is a method
  (`get_tick()`), not an exported field.
- Identifiers that name things in registries are `StringName`s written `&"kind.name"`,
  dotted by owning system: `&"counter.add"`.
- Content ids are `[a-z0-9_]+`, file name equals id.
- Test files `test_<unit>.gd`, test methods `test_<claim>`, doubles under `tests/**/doubles/`.

---

## 12. How to run things

```
tools/test.sh              # everything, in CI order (fitness, scripts, unit, replay)
tools/test.sh unit         # headless test suite only
tools/test.sh replay       # every fixture twice, hashes diffed
tools/screenshot.sh out.png 12   # PNG of the client demo at 12 s, no GPU needed
python3 -m unittest discover -s tools/tests -t .
$(tools/godot.sh) --path . # open the project in the pinned editor
```

The pinned engine is in `tools/godot.pin`; `tools/godot.sh` downloads and verifies it.

## 13. Screenshots

Every presentation of work to the approver carries a screenshot of the running client,
captured with `tools/screenshot.sh <out.png> [seconds]` (Xvfb + Mesa software GL, the
scripted `--demo` path). Gate evidence keeps its screenshots under
`docs/gates/screenshots/M<n>-<view>.png`; a status update or a review request attaches
one in the message. A change that alters what the client shows re-captures it.

---

**These guidelines are working if:** diffs trace cleanly to a spec, clarifying questions
arrive before implementation rather than after rework, gates pass on first submission,
and adding the second instance of anything takes a data file and no code.
