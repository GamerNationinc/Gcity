# G3 — M3 Portal graph + build system (+ claim set P): gate evidence package

Milestone: M3 — Portal graph + build system, with claim set P (design doc §16;
standards §11 row G3; `docs/specs/M3-portal-graph-build-system.md`, approved 2026-09-21)
Submitted: 2026-09-21 by Claude Code, on branch `claude/relaxed-franklin-hs29t3`,
commits `a82ed10` … `c4f9c1e` plus the screenshot commit
Outcome: _pending review_ — **needs the G3 Deck run and feel notes from CEOGG (P5)**

---

## 1. Specification

See the spec. Fifteen claims plus claim set P (P1–P5); all implemented except P5,
which is the approver's Deck run recorded in §7. Deviations recorded in §4: the
`target_value` content kind was folded into the piece's `value` field, support and
the portal graph recompute over the whole structure rather than a dirty set, and
tokens re-plan on every build change (a strengthening the killbox fixture depends on).

| Claims | Delivered by | Commit |
|---|---|---|
| 1–4 pieces, grid, placement, support | `sim/land/build_system.gd`, `piece_kind` / `material` / `tool_class` / `build_piece` content and schemas, `piece_hp` / `breach_noise` stats | `a82ed10` |
| 5–8 flood fill, edges, cheapest path, raid plan | `sim/nav/portal_graph.gd` | `3eaee7e` |
| 9 the dumb raid token | `sim/agents/raid_token_system.gd` | `9623013` |
| 10 cost measured | §2, "Rebuild cost" | this package |
| 11 save round trip | the M2 property test's stream now includes build, move and raid commands through the assembled sim; `restore()` on every new system | `a82ed10` … `9623013` |
| 12 fixtures | `tests/replay/m3-bunker.json`, `m3-killbox.json`, `m3-walk.json` (P3) and `tests/sim/test_m3_fixtures.gd` | client commit |
| 13 schemas | four new schemas; cycles, unfitting kinds and missing roots refused at assembly | `a82ed10` |
| 14 client | `client/plot_view.gd` overlay (volumes, pieces, plan, tokens) and `client/world_view.gd` (placement, removal, raid) | client commit |
| 15 corpus | 21 new hostile cases; the partition property is the build fuzz target | `a82ed10` … `9623013` |
| P1 movement | `sim/agents/movement_system.gd`, positions on actors | `9623013` |
| P2 grey-box 3D | `client/world_view.gd` + scene, input map with stick axes | client commit |
| P3 walk fixture | `tests/replay/m3-walk.json` | client commit |
| P4 feel: pistol from the 3D view, distance-based hit roll | `sim/items/combat_system.gd` (one line), `client/world_view.gd`, metamorphic test in `tests/agents/test_movement_system.gd` | `9623013` |
| Q4 extension exercise | `content/material/reinforced_concrete.json`, `content/tool_class/breacher.json`, `content/build_piece/concrete_wall.json`, `tests/land/test_extension_building.gd` | `c4f9c1e` |

## 2. Verification report

Produced on the development container (Linux x86_64, Godot 4.6.1-stable, Python
3.11), **not on Steam Deck hardware**; the Deck run is §7. Reproduce with `tools/test.sh`.

### Fitness functions

| Check | Result |
|---|---|
| Python tool tests | 37 tests, OK |
| `tools/check_dependencies.py` | clean |
| `tools/validate_content.py` | clean: 70 content entries across 19 kinds |

### Static analysis

Every `.gd` file passes `--check-only` with warnings as errors. The analyzer rejected
19 Variant-to-typed argument passes during M3; each was rewritten with a typed local.

### Headless test suite

| Suite | Tests | What it proves |
|---|---|---|
| `tests/land/test_build_system.gd` | 8 | cells and canonical faces; chains; rejections (air, wrong orientation, occupied face from either side, foundation off the ground, unknown actor); build rights and violations; span limit; collapse on foundation removal with one event; payload contracts; **10 000-step random place/remove property against a breadth-first support oracle**; restore round trip |
| `tests/nav/test_portal_graph.gd` | 9 | empty graph; a walled room is one 9-cell volume with 21 edges; door 40, wall 1 100; cheapest path deterministic and symmetric; an open doorway merges the room into the exterior; sealed room breached at the lowest-id wall; the three metamorphic relations on the room and **over 10 000 random mutations**; raid plan picks the most valuable then cheapest target; **10 000-step partition property** (labelling consistent with faces, edges join distinct nodes, rebuild deterministic); restore rebuilds and refuses a differing saved graph |
| `tests/agents/test_movement_system.gd` | 6 | positions from range; capped steps; walls block, doors pass, solids impassable; `enter` rights on parcel change; payload contract; **hit chance never rises with distance over 0–145 m**; **10 000-step random walk never crosses a wall** |
| `tests/agents/test_raid_token_system.gd` | 6 | no target no token; door in four ticks with no breach; sealed room breached at the planned wall in 110 ticks; re-plan when the door vanishes; **switches to a door the player opens mid-cut**; command and restore |
| `tests/sim/test_m3_fixtures.gd` | 3 | bunker raided through the door (26 pieces, 1 volume, 0 breached, 0 rejections); killbox (token takes the new door, 0 breached); walk through the door with the refused steps into the wall as the only rejections |
| `tests/land/test_extension_building.gd` | 2 | every non-target piece places on its own foundation and every solid is priced by every tool; a material with more HP and noise costs at least as much under every tool |
| M0–M2 suites | 124 | unchanged claims; the M1 actor tests use positions instead of a declared range |
| **Total** | **158 tests, 0 failed** | `check_test_log: clean` |

### Replay determinism

Seven fixtures replayed in two processes each, identical and equal to the recorded
hashes (see `tools/test.sh replay` output in the CI log for this commit). The M0–M2
hashes moved with each new system and with the extension content, as the standards
require; every move is in the commit that caused it.

### Rebuild cost (claim 10)

The 10 000-step partition property rebuilds the graph on every change of a structure
of up to about 60 pieces in a 7×4×7 region. The whole property, including its oracle,
runs in under 15 s on the container: under 1.5 ms per rebuild including the test's
own checking, which is inside the §4.1 navigation row on a desktop CPU. Not a Deck
number; G4 measures it there.

### Fuzz corpora

`tests/fuzz/commands/hostile_payloads.json`: 91 cases (21 new for `build.*`,
`actor.move`, `raid.spawn`). The build fuzz target of standards §3.5 is the partition
and support properties (random placement and removal sequences); no failing seed was
found, so no case was added.

### Screenshots

- `docs/gates/screenshots/M3-world.png`: the grey-box world at 9 s into the demo: the
  player capsule, the ground-level bunker with its door, the raid token arrived inside,
  the dummy 18 m away, both parcels.
- `docs/gates/screenshots/M3-plot.png`: the plot view with the bunker's volume tinted,
  the plan's door in red, the token arrived.

## 3. Demo script

Steps 1–6 on any Linux x86_64 machine; steps 7–14 on the Deck (P5) from
`tools/export.sh`'s build, sideloaded or added to the Steam client as a non-store game.

1. `tools/test.sh` → `158 tests, … 0 failed`, seven `ok` replay lines, `all stages passed`.
2. `git show --stat c4f9c1e` → three content files, one test, seven fixture
   hash lines; nothing under `sim/`, `client/` or `tools/` (Q4).
3. Raise `hp` in `content/material/scrap_steel.json` to 4000; `tools/test.sh unit` →
   the portal tests that assert 1 100 fail, the metamorphic tests still pass, and every
   fixture hash moves. Revert.
4. Set `max_span` to 1 in the same file; `tools/test.sh unit` → the span test fails at
   the second wall; the property still holds (its oracle reads the file). Revert.
5. `tools/screenshot.sh /tmp/w.png 9` → a PNG matching `M3-world.png` up to seed and hash.
6. `SCENE=res://client/plot_view.tscn tools/screenshot.sh /tmp/p.png 12` → matches `M3-plot.png`.
7. Launch. → Third-person view of the plot, the capsule, the dummy ahead. Left stick
   walks, right stick turns, L3 toggles first person.
8. Press Y (wield), then RB three times. → `shots 3` and hits or misses rolled at the
   shown distance; walk closer, the shown hit chance rises.
9. Press X (reload). → `mag 15/15` after two seconds; RB during those two seconds does
   nothing (the pistol is busy).
10. Tab/LB to `foundation_block`, A. → A block appears one cell ahead. Tab to
    `wall_panel`, walk beside the block, A. → A wall hangs off it. Walk into the wall. →
    The capsule stops; `blocked` increments.
11. Tab to `door_frame`, place one on another face of the block; walk through it.
12. Press Start (raid) with a crate placed inside a walled room → a yellow token
    appears outside and, four ticks later, inside if there is a door, or after 110
    ticks of cutting if there is not, and the wall it cut is gone.
13. F5, quit, relaunch, F9 → the pieces, the token and your position return.
14. Write the feel notes (§7).

## 4. Debt and deviation log

| # | Item | Kind | Scheduled |
|---|---|---|---|
| 1 | Target value lives on the piece (`build_piece.value`); no `content/target_value/` kind. One field instead of a kind with one use. | deviation | closed |
| 2 | Support propagation and the flood fill recompute over the whole structure on every change, not a dirty set; §2 records the cost. A dirty set arrives when a Deck measurement demands it. | deviation | G4 |
| 3 | Tokens re-plan on every build change, losing crossing progress; a player who toggles a door every tick stalls a token for free. The threat director owns raid tempo (M8). | strengthening with a known exploit | M8 |
| 4 | Movement keeps y = 0: no stairs, floors as walking surfaces, or falling. Roof panels are portal edges, not floors to stand on. | scope (spec P1 assumption) | M4 or M6 |
| 5 | Movement is unphysical: no capsule radius, no sliding along walls; a step is refused as a whole. Feel item for the Deck run. | scope | after feel notes |
| 6 | Client-side aim: the target is the nearest living actor within a 15° cone of the camera; the sim rolls the hit from distance only. Perception and geometry (M4, M6) replace it. | scope | M4 |
| 7 | The world view's setup places the player and dummy with `actor.spawn`'s range (x axis); the client does not write positions. | note | none |
| 8 | Demo clocks in all views run on sim ticks, not wall time, after a defect in this milestone: wall-clock demos outran the sim under software rendering, and a GDScript lambda captured its clock by value so every action was scheduled at once. The M1 range demo still uses wall time. | defect fixed; M1 residue | M4 (touches `client/main.gd`) |
| 9 | The plot view overlay draws ground-level pieces only (y = 0); the 3D view shows all. | scope | when needed |
| 10 | `raid.spawn`, `build.*` from any actor id, `actor.move` for any actor: debug-class like the M1/M2 spawn commands; gated with G1 debt 4. | security | before co-op |
| 11 | No Deck run yet (P5). This package is incomplete until CEOGG's run and feel notes are in §7. | external | G3 review |
| 12 | Mutation testing not run; target G6. Rebuild cost is a container number, not a Deck one. | scope | G6 / G4 |

## 5. The four standing questions

**Q1 — Does it function?** Yes on the container: 158 tests, five 10 000-case
properties for the new systems, three new fixtures reproduced across processes, the
metamorphic relations of the spec all held. The Deck run is outstanding.

**Q2 — Is it secure?** New untrusted inputs are four content kinds (schema-checked at
build; cycles, orientation and root rules checked at assembly) and three command
kinds (exact payloads, actor existence, rights, 21 corpus cases). Save restore
rebuilds the portal graph and refuses a saved graph the pieces do not produce. No new
dependency.

**Q3 — Is it complete?** No stubs or `TODO`s; every refusal returns an `Error` or a
false with the state untouched. Debt items are scheduled.

**Q4 — Is it expandable?** Performed: the extension commit adds a material, a tool
class and a wall piece with zero changes under `sim/`, `client/` or `tools/`; the
walking test proves every solid piece is priced by every tool and the monotone
relation holds. `docs/extending-building.md` records the procedure.

## 6. Sign-off

Approver: CEOGG
Date:
Outcome: ☐ Accepted   ☐ Accepted with conditions (list below)   ☐ Rejected
Conditions:

## 7. Deck run and feel notes (P5) — to be filled by CEOGG

Build: `tools/export.sh` output, installed via: ☐ sideload  ☐ Steam client (non-store)
Date:                    Battery / plugged:

| # | What felt wrong or right | Number changed (file, value) or debt item |
|---|---|---|
| 1 | | |
| 2 | | |
| 3 | | |
