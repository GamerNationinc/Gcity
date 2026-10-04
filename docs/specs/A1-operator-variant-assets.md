# A1 — Operator variant assets: specification

An asset track, not a milestone: no `sim/` change, no gate of its own. Written with
the implementation in the same branch, by CEOGG's direction of 2026-10-04 (the four
tracks — pipeline, design doc, content data, placeholder models — were approved
together in session before this spec existed, which deviates from standards §10.2;
the deviation is recorded here rather than hidden). Status: **proposed** — CEOGG
accepts or rejects it with the PR.

**Preconditions.** G5 is signed (`docs/gates/M5-gate.md`). ADR-008 (arcade enemies
are the same AI retuned) is accepted: a variant is a tuning of the one agent, which
is why all four ship as content files against the existing M4 schemas, with no new
schema and no `sim/` diff.

**The claim of the track.** The enemy roster stops being two interchangeable grey
capsules. Four operator archetypes from the concept sheet
(`assets/concepts/operator_variants.png`) — Heavy Assault, Medium Operator, Light
Recon, Drone Hunter — exist as data (agent, combat, perception, aim and stress
profiles) and as low-poly placeholder models the client picks up by convention, so
that M6 Cold Storage can populate the hand-authored world from this roster without
touching code. Visual direction and roles are recorded in
`docs/operator-archetypes.md`.

## Claims

### Pipeline (`assets/`)

1. **`assets/` exists with a written contract** (`assets/README.md`): naming equals
   content id, +X facing, centre origin at 0.9 m, a `StanceChip` mesh node per agent
   model, .glb with committed `.import` files, and Deck placeholder budgets
   (≤ 2,000 triangles, ≤ 6 materials, no textures, ≤ 256 KiB per agent model).
2. **Lookup is convention, never a mapping table.** The client resolves
   `res://assets/models/agents/<agent_profile_id>.glb` and falls back to the grey-box
   capsule when the file is absent. Adding a fifth variant is one content set plus
   one .glb: zero code (CLAUDE.md §6.3).
3. **Placeholders are regenerable.** `tools/asset_gen/gen_operator_models.py`
   (Python stdlib only — nothing new to pin) writes the four .glb files
   deterministically; running it twice produces byte-identical output.

### Content (`content/`)

4. **Four agent profiles** — `op_heavy`, `op_medium`, `op_recon`,
   `op_drone_hunter` — each binding its own combat, perception, aim and stress
   profile of the same id, all valid under the existing M4 schemas
   (`tools/validate_content.py` passes). No schema changes.
5. **The tuning states the sheet's role words as numbers.** Heavy: most health,
   slowest, breaks last, favours hold/advance. Medium: the `guard_sim` baseline,
   every stance neutral. Recon: longest sight, tightest settled cone, fastest on its
   feet, breaks first and prefers flank/investigate/retreat. Drone Hunter: widest
   field of view, longest hearing, fastest aim settle at a loose cone (CQB), radio
   latency 1. Exact integers live in the content files and are tuning, not spec.

### Client (`client/world_view.gd`)

6. **The four variants are demoable today.** `GUARD_PROFILES` grows to six; D-pad up
   walks the M4 building's guards through
   `guard_sim → guard_arcade → op_heavy → op_medium → op_recon → op_drone_hunter`,
   swapping model and tuning together. Profiles without a model (the two M4 guards,
   the player) render exactly as before. For captures, `--guards=<profile>` after
   `--` starts the guards on any roster entry without touching the demo script, and
   `tools/screenshot.sh` forwards extra arguments to the client.
7. **Stance stays readable** (M4 spec claim 18 continuity): on a modelled agent the
   stance colour tints the `StanceChip` visor each frame instead of the whole body;
   on a capsule the whole-body tint is unchanged. Awareness bar, sight line and
   last-known marker are untouched.
8. **Down-state is preserved**: a dead modelled agent squashes to the same dark slab
   silhouette as a dead capsule.

## Out of scope (goes to the debt log if touched)

- Skeletons, animation, textures, LODs.
- A player model; weapon models as items; prop or building art.
- Spawning variants anywhere but the existing M4 building demo (that is M6's world
  population, against this roster).
- Any `sim/` change, any schema change, any new content kind.

## Verification

- `tools/test.sh` passes in full (fitness including content validation, script
  analysis, unit, replay — replay hashes must be byte-for-byte unchanged, since
  nothing here may touch the sim).
- `tools/screenshot.sh` of the demo with a variant profile active, attached to the
  PR per CLAUDE.md §13.
- Budget check: each .glb within the §1 budgets (triangle/material counts printed by
  the generator).

## Sign-off

- [ ] CEOGG — accepts the A1 track as implemented, including the §10.2 deviation noted above.
