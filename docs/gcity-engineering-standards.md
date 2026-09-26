# Gcity — Engineering Standards, Stage Gates & Research Agenda

Companion to `gcity-design.md`. That document says *what* to build. This one says
*how it gets built, how it gets proven, and who signs it off.*

No milestone begins until the previous milestone's gate is signed. No exceptions, including
for "small" work.

Authority: CEOGG is the sole approver. Claude Code is the implementer. Nothing is
"done" because the implementer says so.

---

## 1. Engineering posture

The project is built as a **systems engineering exercise, not a content project**. The
governing principles, in priority order when they conflict:

1. **Correctness is demonstrated, not asserted.** Every claim about behaviour has an
   executable test that would fail if the claim were false.
2. **Invariants over examples.** Prefer a property that must hold for all inputs over a
   test case that holds for one.
3. **Determinism where affordable.** A system that replays identically from a seed and an
   input log is a system you can debug, verify, and later synchronise across a network.
4. **Extension without modification.** Adding a weapon, perk, module, district or faction
   must require zero edits to existing code. If it doesn't, the abstraction is wrong and
   the gate fails.
5. **Measure on target hardware.** A benchmark on a desktop is not evidence. The Deck is
   the only machine whose numbers count.
6. **No speculative abstraction.** Generality is justified by two existing uses or a
   written requirement, never by anticipation.

### 1.1 Rejected practices

Explicitly out of bounds, because each one destroys verifiability:

- Silent behaviour changes to satisfy a failing test.
- Tests that assert implementation details rather than observable behaviour.
- Singletons or global mutable state outside the sim's declared root.
- Content encoded as code (a perk implemented as a bespoke class when numbers would do).
- "Temporary" special cases in generic systems.
- Any `sim/` → `client/` import. CI-enforced, non-negotiable (see design doc §4.2).

---

## 2. Stage gate protocol

### 2.1 Structure of a gate

Each milestone M0–M8 ends in a gate. A gate has four parts, all of which must be delivered
together as an **evidence package** before review:

| Part | Content |
|---|---|
| **Specification** | What this milestone claims to do, written *before* implementation, in the design doc's terms. |
| **Verification report** | Test results, coverage, property test seeds, fuzz corpus size, benchmark numbers on Deck hardware. |
| **Demo script** | A numbered, reproducible sequence of actions CEOGG performs on their own Deck to see the claims hold. Includes expected observation at each step. |
| **Debt and deviation log** | Everything knowingly left incomplete, every deviation from the design doc, every assumption made in the absence of a decision. |

### 2.2 Gate outcomes

Exactly three, recorded in writing:

- **Accepted** — work proceeds to the next milestone.
- **Accepted with conditions** — proceeds, with listed items scheduled into a named later
  milestone. Conditions are tracked, not forgotten.
- **Rejected** — rework, re-verify, resubmit. No partial progression onto the next
  milestone's work in the meantime.

### 2.3 The four standing gate questions

Every gate, regardless of milestone, must answer all four. These are the acceptance axes
named in the project brief: *functions, secure, complete, expandable*.

**Q1 — Does it function?**
All declared behaviour has passing tests. All property tests pass across at least 10,000
generated cases. Deterministic replay of the milestone's demo script produces an identical
state hash on two consecutive runs.

**Q2 — Is it secure?**
Threat model for this milestone written and reviewed (§5). All external input — save files,
content files, mod data, and later network messages — is validated at the trust boundary and
has a fuzz corpus. No new dependency added without a supply-chain check.

**Q3 — Is it complete?**
No stubs, no `TODO` in shipped paths, no functions that silently do nothing. Every error
path is handled or explicitly and loudly fatal. Debt log is empty or every item is
scheduled.

**Q4 — Is it expandable?**
A written extension exercise, actually performed and demonstrated: add a second instance of
whatever this milestone introduced (a second weapon, a second module type, a second faction)
using only data files. Diff must show zero changes under `sim/`. If code changed, the gate
fails on this axis regardless of the other three.

### 2.4 Gate ledger

Maintained in the repository as `docs/gates/M<n>-gate.md`, one file per milestone, committed
before review. Includes the sign-off line, date, and outcome. The ledger is the project's
audit trail.

---

## 3. Verification strategy

Conventional unit testing is the floor, not the method. The techniques below are ordered by
how much confidence they buy per unit of effort on this specific codebase.

### 3.1 Deterministic record-and-replay — the primary integration test

Record the seed plus the input stream. Replay headless. Assert a hash of the resulting sim
state.

This single mechanism gives you:
- regression tests that are cheap to author (play the game, save the recording);
- a bug report format that is perfectly reproducible;
- proof of determinism, which is the prerequisite for co-op later (design doc D-02);
- a canary for unintended nondeterminism entering via iteration order, floating point, or
  uninitialised state.

**Requirement:** every milestone from M1 onward ships at least one replay fixture, and CI
replays all accumulated fixtures on every commit.

### 3.2 Property-based testing

For each system, state the invariants that must hold for all inputs, and generate inputs to
attack them.

| System | Invariants to assert |
|---|---|
| Land authority | `rights_at()` is total — every point in the world resolves; parcels never overlap; a point inside a parcel polygon and vertical extent always returns that parcel's owner. |
| Portal graph | Flood fill produces a partition — every interior cell belongs to exactly one volume; every volume has at least one edge to the exterior, even if it is a wall; graph is connected after any single piece removal or the structure is provably sealed. |
| Route graph | Every node is reachable from every other node; no edge crosses untraversable terrain after the terrain pass; adding a quest-bound site preserves connectivity. |
| Stat resolver | Resolution is order-independent for commutative modifier classes; removing a modifier restores the exact prior value; no modifier can mutate a base. |
| Inventory / magazines | Round count is conserved across every reload operation; no operation can duplicate or destroy an item instance. |
| Save/load | `load(save(state)) == state` for all generated states. Round-trip is the single most valuable property test in the project. |

**Requirement:** each property runs a minimum of 10,000 cases in CI, with failing seeds
committed permanently as regression cases.

### 3.3 Model checking for state machines

The base state machine (design doc §9.2), ownership transitions, and the threat director's
scheduling are small enough to model formally and consequential enough to be worth it.

Specify in TLA+ or Alloy and check for:
- **Safety:** a base can never be simultaneously `secure` and `claimed`; ownership can never
  be held by two parties; a raid can never be scheduled against a base already claimed.
- **Liveness:** an `alerted` base always eventually reaches a terminal state; no player can
  be permanently locked out of reclaiming a base.
- **Deadlock freedom:** no reachable state has no legal transition.

This is cheap — these models are tens of lines — and it catches the class of bug that
playtesting finds six months late and intermittently.

### 3.4 Metamorphic testing for AI and generation

These systems have no obvious oracle, so test *relations between outputs* instead of
outputs:

- Raise a wall's HP → the chosen breach path's cost must not decrease.
- Increase informant density → time-to-suspicion-threshold must not increase.
- Reduce agent perception → time-to-first-shot must not decrease.
- Same seed, same constraints → identical site binding, every time.
- Move a quest site further from the city → estimated travel time must increase.

Cheap to write, and they catch sign errors and inverted logic that unit tests happily
confirm.

### 3.5 Fuzzing

Mandatory fuzz targets, each with a persistent corpus in the repo:

- Save file loader (hostile and corrupted input).
- Content file parsers — weapons, perks, modules, districts, town templates.
- Build system operations (random placement/removal sequences against portal graph
  invariants).
- Later: every network message type, before the first co-op build ships.

### 3.6 Mutation testing

Run periodically, not per commit. Mutation score is the honest measure of whether the test
suite means anything. A suite with high coverage and a low mutation score is theatre.

**Target:** ≥70% mutation score on `sim/` by the M6 gate.

### 3.7 Static guarantees

- Typed GDScript everywhere; untyped declarations fail CI.
- If C# is used: nullable reference types enabled, warnings as errors.
- If Rust via GDExtension: `#![deny(warnings)]`, Clippy pedantic.
- Architectural fitness function in CI enforcing the module dependency rules (§1.1).
- Content schema validation as a build step — a malformed weapon file fails the build, not
  the playtest.

---

## 4. Performance verification

### 4.1 Frame budget contract

40 fps target = 25 ms. Allocated as a contract, and each subsystem's budget is asserted in
CI, not hoped for:

| Subsystem | Budget (ms/frame, sustained) |
|---|---|
| Render submission | 8.0 |
| Physics + collision | 3.0 |
| Agent AI (utility + steering) | 3.0 |
| Chunk meshing / streaming (amortised) | 3.0 |
| Navigation (macro + portal) | 1.5 |
| Device UI (only on redraw) | 2.0 |
| Gameplay + progression + inventory | 2.0 |
| Headroom | 2.5 |

Numbers are provisional and get revised at the M4 gate with real measurements. What is not
provisional is that a budget exists per subsystem and that exceeding it is a gate failure.

### 4.2 Measurement requirements

- **Deck-only numbers count.** CI may run desktop benchmarks as a smoke signal; gate
  evidence must come from the Deck.
- Report **1% and 0.1% lows**, never averages. Averages hide exactly the stutter that
  meshing and pathfinding cause.
- **Thermal soak test:** 30 minutes continuous play, reporting frame times in the final 5
  minutes. Clock throttling on a 15 W part means first-minute numbers are fiction.
- **Both power profiles:** plugged and on battery, since the Deck's TDP behaviour differs.
- Automated capture via Godot's profiler or Tracy, dumped as JSON artifacts attached to the
  gate evidence package.

### 4.3 Regression gate

A commit that worsens any subsystem's 1% low by more than 10% fails CI. Performance is a
correctness property in this project, not a polish task.

---

## 5. Security model

A single-player game still has a real threat model, and getting it right now is what makes
co-op safe later.

### 5.1 Trust boundaries

| Boundary | Trust | Requirement |
|---|---|---|
| Save files | **Untrusted** | Fully validated on load. Versioned schema. Corrupt or hostile saves fail cleanly, never execute. |
| Content/data files | **Trusted at ship, untrusted if user-editable** | Schema-validated at build. If modding is enabled, they move to untrusted and need sandboxing (§5.3). |
| Steam Cloud payload | **Untrusted** | Identical treatment to local saves — cloud sync is a transport, not a trust grant. |
| Network messages (post-co-op) | **Untrusted** | Server-authoritative, validated per message, rate-limited, replay-protected. |
| Telemetry output | **Outbound only** | No PII. Path trace heatmaps are aggregate and local-first (design doc §6.4). |

### 5.2 Server authority is designed in now

Even in solo, the sim is written as though a hostile client exists. The client never asserts
state, it requests actions; the sim validates and applies. This costs nothing in solo and is
the entire difference between "co-op later" being a feature and being a rewrite.

Concretely: the client may never write to inventory, ownership, heat, or quest state.

### 5.3 Modding and sandboxing

If user content is ever supported, data-only mods (weapons, perks, modules) are the default
and require no sandbox beyond schema validation. **Script mods require a real sandbox** —
WebAssembly via a wasm runtime, with an explicit capability-limited host API. No engine
script execution from untrusted sources, ever.

This is a decision to make before announcing mod support, not after.

### 5.4 Supply chain

- All dependencies pinned to exact versions with hashes.
- No dependency added without a review noting its maintenance status, license, and
  transitive tree size.
- SBOM generated per release build.
- Build reproducibility target: identical inputs produce an identical artifact hash.

### 5.5 Explicitly out of scope

Anti-cheat and anti-tamper for a single-player game. A player editing their own save is not
a threat. This is stated so effort doesn't leak into it.

---

## 6. Expandability criteria

Axis Q4 of every gate. Concretely, a system passes if:

1. **Content is data.** New instances are files. A validator rejects malformed ones at build
   time with a useful message.
2. **No closed enums in content paths.** Weapon classes, damage types, module categories,
   signal types and faction ids are registry entries, not language enums.
3. **Schemas are versioned.** Every content and save schema carries a version. Migrations
   are additive, forward-only, and tested with fixtures from every prior version.
4. **Registration, not modification.** New subsystems register with a service locator or
   event bus. Adding one does not edit a central `switch`.
5. **Documented extension point.** Each system ships a `docs/extending-<system>.md` showing
   the minimal diff to add one more of the thing.

---

## 7. Architecture Decision Records

The ten open decisions (design doc §17) become ADRs. Format, one file each in `docs/adr/`:

```
ADR-00N: <title>
Status: proposed | accepted | superseded by ADR-00M
Context: what forces are in play
Options: each with cost, risk, and what it forecloses
Decision: chosen option
Consequences: what becomes easy, what becomes hard, what is now irreversible
Verification: how we will know the decision was right
```

Rules:
- No ADR is closed without CEOGG's sign-off.
- **D-03 (terrain representation) and D-09 (magazine model) must be closed before M1**, per
  the design doc. They get more expensive weekly.
- A decision that turns out wrong is superseded by a new ADR, never edited in place. The
  history is the value.

---

## 8. Steam platform integration

### 8.1 Build target: native Linux, not Proton

Godot exports a native Linux binary and SteamOS is Arch-based, so the game runs natively on
the Deck with no compatibility layer. This removes an entire class of Verified failure
(middleware unsupported under Proton) and is the main practical reason the engine choice and
the platform choice reinforce each other.

Ship Windows and native Linux builds from day one. Test the Linux build on the Deck every
milestone, not at the end.

### 8.2 Steamworks binding

Two viable routes, decided by the language split (design doc §3):

- **GodotSteam** — the mature Godot 4.x Steamworks module/GDExtension, available as a
  precompiled drop-in or compiled into a custom engine build. Primary choice for a
  GDScript-led project. Note that its versions are pinned against specific Steamworks SDK
  versions, so the SDK and binding versions must be upgraded together and pinned in the
  build manifest like any other dependency (§5.4).
- **Steamworks.NET wrappers** — relevant only if the project goes C#-led.

Integrate the binding at **M5, alongside the device work**, not at the end. Steam
integration bolted on late is how launch slips.

> Note: GodotSteam historically had a Steam overlay issue when running from the editor under
> the Forward+ renderer, working under Compatibility and working correctly in exported
> builds. Verify current behaviour during the M5 spike rather than assuming.

### 8.3 Steam Input

Do **not** roll a custom gamepad layer. Use Steam Input and ship an official controller
configuration.

Deck Verified requires full controller support with the default configuration giving access
to all content without the player changing any in-game setting, and on-screen glyphs that
match either Deck or Xbox button names, with mouse/keyboard glyphs hidden when they aren't
the active input.

For this game specifically, the Deck's trackpads and back buttons are genuinely useful:
device navigation on a trackpad, lean and tactical reload on back buttons. Design the
default layout around them rather than shipping a generic gamepad map.

### 8.4 Deck Verified checklist as an acceptance gate

Treat Valve's four axes as gate criteria from M5 onward, not a pre-launch scramble.

| Axis | Requirement | Our commitment |
|---|---|---|
| **Input** | Full controller support by default; correct glyphs; on-screen keyboard invoked where text entry is needed | Steam Input configuration shipped; glyph set driven by active input device; OSK hooked for all text fields |
| **Display** | Native support for 1280×800, good defaults, legible text | Default resolution is the design resolution; minimum readable type size enforced in the UI system (design doc §12.4) |
| **Seamlessness** | No compatibility warnings; any launcher must be controller-navigable | No launcher. Native Linux build. |
| **System support** | Runs on SteamOS; middleware supported | Native Linux; every dependency checked for Linux support before adoption |

Valve has since extended the same out-of-box verification bar to additional hardware
targets, so passing this cleanly has more value than the Deck badge alone.

Reference: Valve's Steam Deck compatibility documentation on the Steamworks partner site.

### 8.5 Steam services to design around

- **Steam Cloud** — the save format's small size (seed + overlay) makes cloud sync trivial.
  Define the sync file set at M2 when the save format is first written. Handle conflicts
  explicitly; never silently pick one.
- **Achievements / stats** — wire to the progression event bus (design doc §10.1). Because
  progression is already event-driven, achievements are subscribers and need no gameplay
  code changes.
- **Depots and branches** — a `dev` branch and a `gate` branch on Steam from M1. Every gate
  candidate is pushed to the `gate` branch and installed on the Deck through Steam, so the
  demo script runs against a real Steam install rather than an editor session.
- **SteamPipe in CI** — automated upload on tagged builds. Manual uploads are how the wrong
  build reaches a gate review.
- **Steam Playtest** — the mechanism for external testing once M6 exists.

### 8.6 Deck-specific engineering requirements

- Suspend/resume correctness: the Deck sleeps mid-session constantly. Test that a suspended
  game resumes with correct timers, no physics explosion, and no dropped Steam session.
- Storage: assume microSD-class read speeds. Asset streaming must tolerate slow I/O without
  hitching.
- Battery-aware: optional frame cap and TDP-friendly settings profile.
- Controller-first UI everywhere, including debug menus. A debug tool that needs a keyboard
  won't be used in the place it's needed.

---

## 9. Research agenda

The brief calls for breakthrough techniques. The discipline that makes that productive
rather than destructive: **every candidate gets a timeboxed spike with a pre-declared
pass/fail metric, and is adopted only on measured evidence.** No adoption on novelty.

### 9.1 Spike protocol

```
Spike: <name>
Claim:        what improvement is expected, quantified
Timebox:      hard limit, typically 2–5 days
Pass metric:  the number that must be beaten, measured on Deck
Fallback:     what we do if it fails, and the cost of the fallback
Disposal:     spike code is deleted or promoted, never left in place
```

### 9.2 Candidates, by expected value

**Tier 1 — likely adopt, spike early**

| Candidate | Claim | Pass metric |
|---|---|---|
| **Data-oriented agent storage** (structure-of-arrays for perception, utility scoring, transforms) | Cache-friendly iteration on a Zen2 part; the AI budget is the tightest in §4.1 | ≥2× throughput vs node-per-agent at 60 agents |
| **Rust GDExtension for hot paths** (flood fill, meshing, ballistics) | Native speed without engine forking; strong correctness guarantees from the type system | ≥5× vs GDScript on the same algorithm, with equal output |
| **Job/task graph with time slicing** | Makes every heavy system interruptible, which §4.1 requires | No single frame exceeds budget under worst-case load |
| **Jolt physics backend** | Better performance and stability than the legacy backend for many-body scenes | Frame time at 200 dynamic bodies |
| **Content-addressed, hot-reloadable data pipeline** | Content iteration without restart; also underpins §6 schema versioning | Weapon/perk change visible in <1 s without restart |

**Tier 2 — plausible, spike at the relevant milestone**

| Candidate | Claim | Risk |
|---|---|---|
| **GPU compute meshing** (surface nets in a compute shader) | Moves chunk meshing off the contended CPU | Competes with rendering for the same 15 W; may be a net loss on Deck |
| **Flow fields / GPU pathfinding** for crowds | Scales to many agents where A* does not | Only pays off above an agent count we may never reach |
| **Hierarchical utility planning (HTN or GOAP hybrid)** for squad tactics | Richer coordinated behaviour than flat utility | Debuggability; opaque failures are worse than simple ones |
| **WASM sandbox for mod scripts** | Safe user scripting (§5.3) | Only worth it if modding is committed to |
| **Fixed-point deterministic math** | Bit-exact determinism across machines for co-op | Pervasive change; only needed if D-02 chooses lockstep |

**Tier 3 — evaluate, expect to reject**

- Learned/neural agent behaviour. Fails the legibility pillar (design doc §14) and is
  untestable by the standards in §3.
- Procedural animation stacks beyond IK. Cost is high, and the payoff is invisible at 7".
- Virtualised geometry equivalents. Not the bottleneck; the CPU is.
- Runtime-generated content via ML. Unverifiable output in a project whose entire method is
  verification.

### 9.3 Research inputs worth tracking

Maintain `docs/research/` with a short note per source and what was taken from it:
academic work on navigation meshes and hierarchical pathfinding, utility AI and
behaviour-selection literature, the deterministic-simulation and lockstep networking body of
work, data-oriented design practice, formal-methods-in-games write-ups, and published
postmortems from Valheim, Rust, Tarkov and Ready or Not on the specific systems we're
borrowing.

Rule: a citation in `docs/research/` without a corresponding spike or ADR is reading, not
research. It's still worth doing, but it doesn't count as progress at a gate.

---

## 10. Claude Code working agreement

Constraints that keep AI-assisted implementation verifiable rather than voluminous:

1. **One system per session.** No cross-cutting changes spanning `sim/` modules in a single
   pass.
2. **Specification before code.** The milestone spec lands and is approved before
   implementation begins.
3. **Tests before or with implementation.** Never after, and never authored by reading the
   implementation — that produces tests that confirm bugs.
4. **`CLAUDE.md` at the repo root** carrying: module boundaries, the dependency rule, naming
   conventions, the typed-GDScript requirement, the "content is data" rule, and an explicit
   list of things never to do (§1.1).
5. **Headless test run is mandatory** before any work is presented. Unrun code is not a
   deliverable.
6. **No silent scope expansion.** Anything outside the milestone spec goes in the debt log
   for the gate, not into the commit.
7. **Diffs stay reviewable.** If a change can't be reviewed in one sitting, it should have
   been two milestones.

---

## 11. Gate schedule

Mapping to the design doc's build order, with the specific proof each gate demands.

| Gate | Milestone | Proof required beyond the four standing questions |
|---|---|---|
| **G0** | Skeleton | CI enforces the `sim`/`client` dependency rule; headless harness runs; a trivial replay fixture reproduces bit-identically twice. ADR-D02 closed. |
| **G1** | Stat resolver + one pistol | Full chain demonstrated. **Extension exercise: add a second weapon frame with data only, zero `sim/` diff.** ADR-D03 and D-09 closed. |
| **G2** | Land authority + starter plot | `rights_at()` totality property passes 10k cases. Save round-trip property passes. Steam Cloud file set defined. |
| **G3** | Portal graph + build system | Flood-fill partition invariants hold under 10k random build/destroy sequences. Agent A* reaches the vault by the cheapest path; raising a wall's HP never lowers that path's cost. |
| **G4** | Perception AI | Frame budgets in §4.1 re-derived from real Deck measurements. `time_to_first_shot` tuned and recorded. Metamorphic AI relations pass. Thermal soak test clean. |
| **G5** | The device | Steam Input configuration shipped; Deck Verified input and display axes self-assessed as passing; UI legible at 1280×800 handheld; GodotSteam integrated and pinned. |
| **G6** | "Cold Storage" | The full mission playable on Deck from the exported build (`tools/export.sh`); installing through Steam waits for the store phase below. All three routes completable. Stealth scoring correct on a full-stealth replay fixture. Mutation score ≥70% on `sim/`. |
| **G7** | Route graph + procgen | Connectivity property holds across 10k seeds. Same seed always produces the same world hash. Site binding is deterministic. |
| **G8** | Threat director + raids | Base state machine model-checked: safety, liveness, deadlock freedom. Absent-resolution and live-defence produce consistent outcomes from identical inputs. |

Each gate's evidence package lands in `docs/gates/` before review, and nothing proceeds
without a recorded sign-off.

**Deck testing continues at every gate; the store phase is deferred** (CEOGG,
2026-09-26, clarified the same day). Every gate is still run and measured on the Steam
Deck, as G0–G5 were: the exported build (`tools/export.sh`) and the repo checkout,
launched on the Deck, with the Steam client reached through GodotSteam under Valve's
test app id. What waits until the full game is ready is **getting onto the Steam store
to sell the game**: registering the Steamworks app, and everything that needs the
registered app id — the `dev` and `gate` branches and installs through Steam, binding
the shipped Steam Input layout, Steam's glyph API, Steam Cloud sync, SteamPipe uploads,
the store page and Valve's Deck Verified review. That is one phase at the end, with its
own gate. GodotSteam stays integrated and pinned.

---

## 12. Immediate next actions

1. Close **ADR-D03** (heightmap vs volumetric terrain) and **ADR-D09** (magazine model).
   Everything else waits on these two.
2. Write the **M0 specification** to the format in §2.1.
3. Stand up the repository skeleton, CI, the dependency fitness function, and the headless
   harness — with no gameplay code in it at all.
4. Register the Steamworks app and create the `dev` and `gate` branches, so G1 can be
   installed through Steam rather than sideloaded. *Deferred to the store phase
   (§11, CEOGG 2026-09-26); Deck testing continues at every gate.*
