# Study and rebuild: reference codebases, including reverse-engineered ones

**Status:** adopted by CEOGG, 2026-10-02. Merges the two drafts CEOGG gave that day
("Reverse-Engineered Sources: Study Policy" and "Study-and-Rebuild"); where they
differed, the first draft's clean-room firewall is binding.
**Applies to:** Gcity (GamerNationinc/Gcity) and every GamerNation Inc. game project, and
to every contributor and AI coding agent working on them.
**Supersedes:** the "learn, don't look" posture of the iw4L evaluation.

## 1. Position

Reverse-engineered and decompiled codebases, engine reimplementations and recompilation
projects are some of the best engineering literature there is. They show how shipped,
battle-tested systems actually solved their problems: state machines, physics loops,
data-driven tuning, animation dispatch, streaming, netcode. We study them the way a
painter studies a master's composition: to understand how something was achieved, and
then to build our own version, better, with modern tooling, AI assistance, typed GDScript
and Godot 4.

What we take is **structure, concepts and patterns**. What we never take is **their code,
their data, or a disguised copy of either**. That line is the whole policy.

## 2. The core rule: ideas in, expression out

Copyright does not protect ideas, methods or architectures; it protects their specific
expression.

**Fair game: study freely, adopt freely**
- System decomposition: how a project splits into modules (core physics, gameplay,
  data, audio).
- Architectural patterns: state dispatch through a factory, data-driven tuning files,
  per-triangle surface tags, a mod SDK as a config file and a script hook.
- Pipelines and process: replay-against-reference verification, headless test rigs,
  tracing design, agent-readable SDK documentation.
- Algorithms at the level of a described approach ("raycast N wheel points and blend a
  target orientation"), re-derived by us.
- Anything in READMEs, documentation and PR descriptions: prose describing design.

**Never into our repositories**
- Copied or transliterated source code, in any language, from any reverse-engineered
  project.
- Hand-written copies: retyping, renaming variables, or porting line by line (Rust to
  GDScript or otherwise). A translation of protected code is still a derivative work.
- Extracted game data: tuning values, animation clips, state graphs, collision or file
  formats, audio constants, retail offsets.
- Code written by an agent that had reverse-engineered source in its context (§3).

## 3. The firewall: two documents, two workspaces (binding)

1. **Study phase, outside the Gcity workspace.** Read the target's documentation, PRs and,
   if needed, its source. The output is a **design note**: a plain-English description of
   the system's behaviour, data flow, states, tunables, edge cases and the failures its
   authors hit (their bug-fix PRs are gold). Diagrams are encouraged. **No code excerpts,
   no copied constants, no byte layouts lifted verbatim.** The note says what and why,
   never how in their words.
2. **Implementation phase, inside the Gcity workspace.** A fresh session or agent builds
   the feature **from the design note only**, in typed GDScript or our Rust GDExtension,
   against our ADRs, specs and gates. The original source is never opened in this
   session.

**Agent rule.** An AI coding agent working in a Gcity workspace never fetches, clones or
reads reverse-engineered or decompiled source. It may read design notes in
`docs/references/`, and a target's READMEs, documentation and PR descriptions. Study
agents that read source run in a separate workspace and output design notes only.
(CLAUDE.md §10 carries this rule.)

The repository is public: design notes in `docs/references/` are published with it,
which is one more reason they hold prose, never excerpts.

## 4. If it works and we have not built it yet

1. **Design note** (§3, step 1), in `docs/references/<system>.md`:
   - the problem it solves;
   - its data structures, conceptually (a graph of nodes with budgets, a ring buffer of
     snapshots);
   - its order of operations and tick structure;
   - the trick that makes it fast or robust;
   - what we would do differently with Godot 4 and our constraints.
2. **Spec our version** in the milestone process (`docs/specs/`, CEOGG's approval) against
   Gcity's constraints: the Deck's budget, the deterministic integer tick (ADR-002), the
   1 m grid, co-op readiness. A design note never overrides a signed ADR; a conflict is a
   new ADR.
3. **Implement original code from the spec**, then harden it (§5): this is where we beat
   the template.
4. **Gate it** like everything else: function, security, completeness, expandability, and
   CEOGG's sign-off.

## 5. The hardening pass (every rebuild)

- **Fuzz the inputs.** Every system that takes external or generated data (seeds, saves,
  content, route requests, later network messages) gets a seeded fuzz target with a
  corpus in the repo. Zero crashes to pass. (iw4L's PR #24 found 6 683 panics in 20 000
  random command streams; that is the failure mode this prevents.)
- **Budget everything.** Per-tick caps on search expansions, spawns and generation work;
  no system takes unbounded frame time; no allocation sized by a count read from a file.
- **Validate at the boundary.** Typed GDScript everywhere; clamp and check every value
  entering the sim; NaN and overflow guards in any integrator; fail closed and loudly.
- **Determinism is a security property.** Same seed and same inputs give the same state
  hash; a divergence is a bug of the highest severity and the foundation of co-op's
  anti-desync.
- **No trust in content or saves.** Shipped content is read-only; runtime output goes to
  `user://`; saves are versioned and validated on load.
- **Efficiency.** Profile on the Deck; move a proven hot loop to the Rust GDExtension
  only with a measurement (CLAUDE.md §8).

## 6. Study topics noted from the iw4L evaluation

Recorded so they are not lost; none is scheduled, and each enters a milestone only
through a spec. Most are already Gcity systems, which a study would only compare against.

| Reference behaviour | In Gcity today |
|---|---|
| One `input → step → snapshot` funnel for game, replay and tests | Exists: `SimRoot.step`, replay fixtures, `SimAssembly` (M0 onwards). |
| Fixed timestep independent of frame rate | Exists, decided: integer ticks at `SimRoot.TICK_HZ` (ADR-002). An engine-loop step such as `_physics_process` would break the sim's determinism rule. |
| A* with goal sets, per-tick expansion budget, memoised heuristic | Partly: `PathingSystem` plans on a per-tick budget (`PATH_NODES_PER_TICK`). Goal sets and heuristic caching are study topics. |
| Seeded, scripted headless scenarios | Exists as replay fixtures; M7.6's sandbox sessions save as fixtures. |
| Opt-in semantic tracing behind an environment variable | **Not built.** Candidate: `GCITY_PERF=1` writing semantic events (route planned, agent stuck, region generated) under `user://`. Needs a spec. |
| Fuzzed input hardening | Exists per trust boundary (standards §5); continues with every system. |

Note: "wanted level" in the iw4L notes conflicts with ADR-004 (sensor-gated detection,
not an instant wanted level). ADR-004 stands.

## 7. Checklist per rebuilt system

- [ ] Reference read in a study workspace; design note in `docs/references/<system>.md`
- [ ] Gcity design proposed as a spec; conflicts with ADRs raised as ADRs
- [ ] Implemented from the note and the spec, with no source open
- [ ] Hardening pass (§5): fuzz target, budgets, boundary validation, determinism test
- [ ] Headless tests and a replay fixture green
- [ ] Gate signed by CEOGG

## 8. Quick reference

| Action | Allowed? |
|---|---|
| Read READMEs, docs and PRs of reverse-engineered projects | Yes, anywhere |
| Read reverse-engineered source | Only in a study workspace, never a Gcity one |
| Write design notes describing their systems | Yes: that is the deliverable |
| Paste, port or transliterate their code into Gcity | Never |
| Copy tuning constants, clips, state graphs, formats, offsets | Never |
| An agent with reverse-engineered source in context writing Gcity code | Never |
| Implement from our own design note, hardened and tested | Yes: the whole point |

## Why the line matters

Gcity is a commercial product of an active corporation, headed for Steam, in a space where
studied franchises are live properties. Building from design notes costs almost nothing
extra: with AI-assisted development, reimplementing from a good note is nearly as fast as
porting, and the expensive part, working out how it should work, is exactly what we are
allowed to take. Copying would trade that for a company-ending risk. So we do not copy;
we out-build. *Study like an artist, rebuild like an engineer, harden like an adversary.*

This is engineering policy, not legal advice; before a commercial release relies on it,
counsel should review it.
