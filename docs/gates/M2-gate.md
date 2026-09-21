# G2 — M2 Land authority + starter plot: gate evidence package

Milestone: M2 — Land authority + starter plot (design doc §16; standards §11 row G2)
Specification: `docs/specs/M2-land-authority-starter-plot.md` (approved 2026-09-21)
Submitted: 2026-09-21 by Claude Code, on branch `claude/relaxed-franklin-hs29t3`,
commits `f9934f8` … `3aabed4` plus this package
Outcome: **Accepted** (2026-09-21, CEOGG; see §6)

---

## 1. Specification

See `docs/specs/M2-land-authority-starter-plot.md`. Twenty-one claims; all
implemented. One deviation was made before the code it concerns and is recorded in
§4 (owners are tags, not actor ids). Two wordings were strengthened in the code and
are recorded there too: placement checks every footprint corner, not only the origin
(claim 9), and the M0/M1 fixtures were re-recorded four times as systems and content
were added (claim 21).

| Claims | Delivered by | Commit |
|---|---|---|
| 1–7 land authority | `sim/land/land_system.gd`, `district` / `parcel` content and schemas, `docs/extending-land.md` | `f9934f8` |
| 8–12 starter plot, container, modules, budget | `sim/land/structure_system.gd`, `structure` / `module` content and schemas, `power_available` / `heat_headroom` stats, `docs/extending-modules.md` | `09980e6` |
| 13–16 save and load | `sim/core/save_file.gd`, `SimRoot.restore_root()`, `SimAssembly.load_save()`, `tests/fuzz/save_file/` | `a4be426` |
| 17 command actor checks | `ItemSystem.set_actor_check()` from the assembly; progression already refused dead actors | `f49ab85` |
| 18 Steam Cloud file set | `docs/steam-cloud.md`; the client writes the slot layout | `f49ab85` |
| 19 content schemas | `tools/content_schemas/{district,parcel,structure,module}.json`; cross-references and cycles checked in the systems' `validate_content()` | `f9934f8`, `09980e6` |
| 20 client view | `client/plot_view.gd` (new main scene), `LocalHost.adopt()`, input map | `f49ab85` |
| 21 fixtures | `tests/replay/m2-starter-plot.json`, `tests/sim/test_m2_fixture.gd` (mid-run save and resume) | `f49ab85` |
| Q4 extension exercise | `content/module/hydroponics.json`, `content/district/corporate_core.json`, `tests/land/test_extension_content.gd` | `3aabed4` |

## 2. Verification report

All numbers below were produced on the development container (Linux x86_64, Godot
4.6.1-stable, Python 3.11), **not on Steam Deck hardware**. M2 makes no performance
claim (standards §4.2 applies from G4). Reproduce with `tools/test.sh`.

### Fitness functions (`tools/test.sh fitness`)

| Check | Result |
|---|---|
| Python tool tests | 37 tests, OK |
| `tools/check_dependencies.py` | clean |
| `tools/validate_content.py` | clean: 49 content entries across 15 kinds, every file structurally valid, every cross-reference resolved |

### Static analysis (`tools/test.sh scripts`)

Every `.gd` file passes `--check-only` with warnings as errors. During M2 the
analyzer rejected 31 places where a dictionary lookup was passed straight into a
typed parameter; each was rewritten with a typed local (none was silenced).

### Headless test suite (`tools/test.sh unit`)

| Suite | Tests | What it proves |
|---|---|---|
| `tests/land/test_land_system.gd` | 12 | Content parcels placed; shared edges and the three-way corner resolve to exactly one parcel; half-open vertical extent; rights per table; digging under the neighbour refused; `require()` emits exactly one event per refusal and none on success; payload contracts; polygon validity (bow tie, folded edge, sub-m²); overlap rejection (identical, partial, contained, containing, stacked, edge- and corner-sharing); diagonal split; **totality over 10 000 positions and actors**; **rectangle-oracle property: `add_parcel` and `parcel_at` agree with brute force over 10 000 adds and 10 000 queries**; restore round trip with a rejected bad restore |
| `tests/land/test_structure_system.gd` | 13 | Placement records owner and budgets; rotation; trespass at any corner is a violation; the badlands are free; footprints never overlap; three modules within budget and the fourth refused; exact budget arithmetic and exact restoration on removal; grid bounds and occupancy; dependants never orphaned; strangers refused; payload contracts; **10 000-step random install/remove property against a budget, occupancy and dependency oracle**; restore round trip through the resolver |
| `tests/sim/test_save_file.gd` | 6 | `load(save(state))` hashes equal and keeps stepping equal with queued commands; text deterministic and under 64 KiB; 64-bit RNG state and prefixed strings exact; 20 named hostile mutations (10 at parse, 10 at load); 14-file corpus; **10 000 random mutations never crash and every accepted mutant is self-consistent**; **10 000 generated sims round-trip and keep stepping identically** |
| `tests/sim/test_m2_fixture.gd` | 2 | The M2 fixture matches its recorded hash and its end state (two containers, four and one modules, one violation, two rejections); save at tick 200, load, resume equals the uninterrupted run and the recorded hash |
| `tests/land/test_extension_content.gd` | 2 | Every module installs after its dependencies on an empty container within budget; every district's rights table is exactly what `rights_at()` reports |
| M0 and M1 suites | 88 | Unchanged claims still hold; the M1 item tests now spawn their actors first (claim 17); 27 M2 cases added to the hostile command corpus (76 cases in all) |
| **Total** | **123 tests, 213 109 assertions, 0 failed** | `check_test_log: clean` |

Property seeds are fixed constants in the test files. No failing seed was found.

### Replay determinism (`tools/test.sh replay`)

Each fixture replayed in two separate engine processes, hashes identical and equal
to the recorded ones:

```
ok   tests/replay/m0-trivial.json      c2d8702d7ee6ac33070ab7ebf61114a118108a9604ee2a96493ccc882e1f07dd
ok   tests/replay/m1-perk-off.json     ad97bbf299d55709bf0ebecd7866b1511c87049ad2e50c587c4a819bc6da4389
ok   tests/replay/m1-range.json        1ed8f26c5c5222b921c48bcaf5c4993e3e79795eb8810c8f654a3e4a9ba9cf61
ok   tests/replay/m2-starter-plot.json 7a6f63caf6c91da7395fa0c5e8dd99594b633b8ea2da73d2f9516a79a615cdd0
```

### Fuzz corpora

- `tests/fuzz/commands/hostile_payloads.json`: 76 cases (27 new for `land.*`,
  `structure.place`, `module.*` and actor-less item and perk commands); each rejected
  with system state untouched, against the assembled M2 sim.
- `tests/fuzz/save_file/`: 14 hostile saves (empty, garbage, wrong version, missing
  or short digest, unprefixed key, float, big-int overflow, malformed int key, unknown
  envelope key, 200-deep nesting, binary garbage, int64 edges); all rejected with a
  message; the loader's `to_int` overflow found by the corpus was replaced by an
  overflow-safe parser and the edge file committed.

### Screenshot

`docs/gates/screenshots/M2-plot.png`: the plot view at 12 s into the scripted demo:
both parcels owned, the first container with its rack, work station, sustainment and
hydroponics and the resolved budgets, the second container on the bought neighbour,
the save written.

## 3. Demo script

On any Linux x86_64 machine with `python3`, `curl`, `unzip`; steps 8–12 also on the
Deck from the Linux export. Expected observation follows each step.

1. Check out `3aabed4` (or later on the branch) and run `tools/test.sh`. →
   `123 tests, 213109 assertions, 0 failed`, four `ok` replay lines with the hashes
   above, `all stages passed`.
2. `git show --stat 3aabed4`. → Seven files: two under `content/`, one test, four
   fixture hash lines. Nothing under `sim/`, `client/` or `tools/` (Q4).
3. Edit `content/district/starter_ghetto.json` and set the `other` row's `enter` to
   `false`; run `tools/test.sh unit`. → `test_every_district_rights_table_is_what_rights_at_reports`
   still passes (it reads the table), `test_rights_follow_owner_other_and_unowned_tables`
   fails on the stranger's rights, and every fixture hash mismatch names the content
   digest change. Revert.
4. Add `"depends_on": ["hydroponics"]` to `content/module/work_station.json`; run
   `tools/test.sh unit`. → Every assembly fails with
   `StructureSystem: content rejected: module/hydroponics depends on itself` (the cycle
   is found through work_station). Revert.
5. Change `"ticks": 400` to `401` in `tests/replay/m2-starter-plot.json`; run
   `tools/test.sh unit`. → both `test_m2_fixture` tests fail on the hash. Revert.
6. `tools/screenshot.sh /tmp/plot.png 12` → a PNG matching
   `docs/gates/screenshots/M2-plot.png` up to the seed and hash text.
7. `$(tools/godot.sh) --path .` → the plot view opens at 1280×800: the L-shaped
   neighbour to the north in red, the starter plot in green, the cursor on the plot.
8. Press Space. → A container appears at the cursor; the panel shows
   `power 3000 W   heat 4000 W` for it.
9. Press Tab until `MODULE to install: power_cell_rack`, then Enter. → A green block
   fills cells (0,0)–(1,0); power reads 5500 W, heat 3400 W.
10. Move the cursor right twice, Tab to `work_station`, Enter. → Cells (2,0)–(4,0)
    fill; power 4700 W, heat 2900 W. Press R with the cursor still there. → The
    module is removed and the numbers return to 5500 / 3400 exactly.
11. Move the cursor onto `neighbour_east` (right until `parcel neighbour_east`), press
    Space. → Nothing is placed; `violations` increments by one. Press T, then Space. →
    `neighbour_east   player` in the parcel list and a second container appears.
12. Press F5, quit, relaunch, press F9. → `loaded tick N`; both containers and their
    modules are back with the same numbers; `state` shows the same 16 hex characters
    as before quitting once the tick counts match (compare after F5 without stepping:
    the demo's `--demo-quit=0.1` is the reproducible way, see `tools/screenshot.sh`).

## 4. Debt and deviation log

| # | Item | Kind | Scheduled |
|---|---|---|---|
| 1 | **Owners are tags** (`player`, `npc.<name>`, `faction.<id>`), not actor ids; actors act as the owner they are identified with (`land.identify`). The spec said actor ids; the design (§9.4) has factions and the city-state own land, which actor ids cannot express. | deviation (spec §"Assumptions" amended in this package) | closed |
| 2 | `land.identify` is a debug-class command like `land.transfer` and `actor.spawn`: any client can make any actor the player. Gated with G1 debt 4 before co-op. | security | before co-op (M8 gate at the latest) |
| 3 | Placement checks `build` at all four footprint corners, not only the origin as the spec wrote; a container straddling a boundary is refused. Stronger, not weaker. | strengthening | closed |
| 4 | Structure footprints are axis-aligned rectangles after quarter turns; parcels are polygons. A rotated parcel boundary crossing a container's edge between corners is not detected. | scope | M3 (building pieces bring edge tests) |
| 5 | Water is carried and validated but not budgeted; no stat exists for it. | deliberate incompleteness (spec out of scope) | when a system reads it |
| 6 | Structures on unparcelled land record an empty `owner_at_placement`. Reclaim and takeover (ADR-005) read that field from M8. | note | M8 |
| 7 | `SaveFile` round-trips String and StringName both as JSON strings; restored state uses StringName where the systems do. Hash equality after load is the proof it does not matter; a system that stored a String where it later compares a StringName would be caught by that same test. | note | none |
| 8 | Saves carry only the root snapshot; chunk deltas (M7) will extend the schema additively (`save_schema_version` 2). | scope | M7 |
| 9 | The client's save/load writes and reads `user://saves/plot/`; no slot list, no conflict UI, no meta validation on load beyond `world.json`. The document defines them; the device (M5) implements them. | scope | M5 |
| 10 | The demo and screenshot run one scripted action per frame under software GL; on the Deck the same script runs faster. Steps 8–12 of the demo script are the manual equivalent. | note | none |
| 11 | No Deck run of this milestone's export. G1's export preset is unchanged and still excludes tests, tools and docs. | scope | CEOGG, G2 review or G3 |
| 12 | The unit stage now takes about two minutes on the container, almost all of it the two 10 000-case save properties. Acceptable for CI; if it grows, the per-case sim can be assembled once per seed. | perf note | G4 |
| 13 | The M1 gate's recorded hashes are those of its day; they moved four times during M2 (new systems, new content). Each move is in the commit that caused it. | deliberate change | closed |
| 14 | G1 debt 5 (commands tied to any positive actor id) and 6 (root state not restored) are closed by claims 17 and 13. G1 debt 4 (debug-class spawn) remains and gains `land.identify` and `land.transfer`. | closure | see 2 |
| 15 | Mutation testing not run; target G6. No Deck measurement; M2 has no frame-budget claim. | scope | G6 / G4 |

## 5. The four standing questions

**Q1 — Does it function?** Yes. Every claim has passing tests; five property tests
run 10 000 cases each; the M2 fixture replays bit-identically across two processes,
and a save taken at tick 200 resumes to the same hash as the uninterrupted run.

**Q2 — Is it secure?** Threat model for M2: new untrusted inputs are save files
(local and, later, cloud) and four new content kinds. Saves are validated in three
layers (envelope, every system's `restore()`, the root) with a corpus and 10 000
mutations per run; the corpus found one real defect (integer overflow in the engine's
`to_int`) which is fixed and pinned by a corpus file. Content is schema-checked at
build and semantically checked at assembly (cycles, unknown districts, unfitting
modules). Every command names a live actor. No new dependency.

**Q3 — Is it complete?** No stubs, no `TODO` in the tree; every error path returns
an `Error` or a message, or asserts. Every debt item above is scheduled or closed.

**Q4 — Is it expandable?** Performed: commit `3aabed4` adds a fourth module (with a
dependency and water) and a third district (stricter table) with zero changes under
`sim/`, `client/` or `tools/`; the walking test proves both without naming either.
Districts, parcels, structures and modules are files; owners, rights and signals are
registry-style tags; the save and snapshot schemas carry versions.
`docs/extending-land.md` and `docs/extending-modules.md` record the procedure.

## 6. Sign-off

Approver: CEOGG
Date: 2026-09-21
Outcome: ☑ Accepted   ☐ Accepted with conditions (list below)   ☐ Rejected
Conditions:
