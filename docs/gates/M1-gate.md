# G1 — M1 Stat resolver + one pistol: gate evidence package

Milestone: M1 — Stat resolver + one pistol (design doc §16; standards §11 row G1)
Specification: `docs/specs/M1-stat-resolver-pistol.md`
Submitted: 2026-09-20 by Claude Code, on branch `m1-stat-resolver-pistol` (PR #4)
Outcome: _pending review_

---

## 1. Specification

See `docs/specs/M1-stat-resolver-pistol.md`. Nineteen claims; all implemented. Two
amendments were made to the spec before the code they concern and are recorded in it:
additive stacking within a modifier class (claim 2) and `resolve()` rather than `get()`
(claim 1). Four wordings were tightened to what was built, none changing a claim's
substance: sockets with `contains` define magazines (7), reloads auto-chamber (8), the
round trip compares system state (10), and the per-metre falloff is profile data (11).

| Claims | Delivered by |
|---|---|
| 1–5 stat resolver | `sim/progression/stat_resolver.gd`, `content/stat/`, `docs/extending-progression.md` |
| 6–10 items, pistol, magazines, round trip | `sim/items/item_system.gd`, `sim/core/entity_ids.gd`, five content kinds, `docs/extending-items.md` |
| 11–12 combat pipeline, actors | `sim/items/combat_system.gd`, `sim/agents/actor_system.gd`, `sim/core/event_bus.gd`, `combat_stage` / `combat_profile` content |
| 13–14 skill events, the perk | `sim/progression/progression_system.gd`, `skill` / `perk` content |
| 15 structural content validation, resolver-only reads | `tools/validate_content.py` (schema dialect), `tools/check_dependencies.py` (two new rules) |
| 16 the sim never reads a file; content digest in the hash | `sim/core/content_db.gd`, `client/content_loader.gd`, `sim/assembly.gd` |
| 17 client drives the chain, writes no state | `client/main.gd` (range view), client rule in `tools/check_dependencies.py` |
| 18 Linux export runs on a Deck | `export_presets.cfg`, `tools/export.sh`, `tools/godot.pin` (templates' SHA-512) |
| 19 fixtures, hostile corpus | `tests/replay/m1-range.json`, `tests/replay/m1-perk-off.json`, `tests/fuzz/commands/` |

## 2. Verification report

All numbers below were produced **on this Steam Deck** (AMD Custom APU 0932, SteamOS,
desktop mode, Godot 4.6.1-stable, Python 3.13). M1 makes no performance claim
(standards §4.2 applies from G4). Reproduce with `tools/test.sh`.

### Fitness functions (`tools/test.sh fitness`)

| Check | Result |
|---|---|
| Python unit tests: dependency rule (incl. resolver-only and client-view rules), content schema dialect, test-log checker | 37 tests, OK |
| `tools/check_dependencies.py` on the repository | clean |
| `tools/validate_content.py` on the repository (11 kinds, 36 files, cross-references checked) | clean |

### Static analysis (`tools/test.sh scripts`)

Every `.gd` file under `sim/`, `client/`, `tests/`, `tools/` passes `--check-only` with
the typed-GDScript warnings at error level. The rule caught real defects during the
milestone (typed-array literals in ternaries, Variants into typed parameters), each
fixed before commit.

### Headless test suite (`tools/test.sh unit`)

| Suite | Tests | What it proves |
|---|---|---|
| `tests/sim/test_state_hash.gd`, `test_command_registry.gd`, `test_sim_root.gd`, `test_replay_fixture.gd` | 26 | M0 core, unchanged in substance; fixture payload ints now canonical |
| `tests/sim/test_content_db.gd`, `test_entity_ids.gd`, `test_event_bus.gd`, `test_json_numbers.gd`, `test_sim_assembly.gd` | 16 | Content boundary, id allocation, ordered events, JSON canonicalisation, fixed system order and content in the hash |
| `tests/progression/test_stat_resolver.gd` | 12 | Claims 1–5: arithmetic exact, four properties, tag inheritance, extension class, restore |
| `tests/items/test_item_system.gd` | 10 | Claims 6–10: containers, attach/detach, magazines, reloads, exact payloads, conservation, hostile payloads, round trip, hostile snapshots |
| `tests/agents/test_actor_system.gd` | 3 | Claim 12: health graph, wield linkage, restore |
| `tests/items/test_combat_system.gd` | 9 | Claim 11: one round per shot, resolved damage, kills, exact perk factor, events, determinism, stage registration, fire-only conservation |
| `tests/progression/test_progression_system.gd` | 6 | Claims 13–14: xp/levels/points, gated unlock and payout, exact factor with and without the perk, round trip, content rules, data-only perk |
| `tests/items/test_extension_content.gd` | 1 | Extension exercise: every frame × compatible round, name-agnostic |
| `tests/sim/test_replay.gd` | 6 | Claim 19: three fixtures reproduce their hashes, M1 chain end state, perk-off differs by damage only, 41-case hostile corpus |
| **Total** | **87 tests, 212 067 assertions, 0 failed** | plus `tools/check_test_log.py`: no error line outside `push_error` |

Property tests (≥10 000 cases each, fixed seed constants in the files):

| Property | Test | Seed |
|---|---|---|
| Resolution is insertion-order independent | `test_property_resolution_is_order_independent` | 20260921 |
| Add then remove restores the exact prior value (incl. inherited) | `test_property_remove_restores_prior_value` | 20260922 |
| No modifier operation mutates a base | `test_property_bases_are_never_mutated` | 20260923 |
| Cached equals fresh, snapshot included | `test_property_cache_matches_fresh_resolution` | 20260924 |
| Items conserved across random load/unload/attach/detach/reload | `test_property_items_are_conserved_across_random_command_sequences` | 20260925 |
| Random hostile item payloads never break placement | `test_property_hostile_payloads_are_rejected_without_damage` | 20260926 |
| Item count moves only by `weapon.fire`, by exactly one | `test_property_fire_is_the_only_way_a_round_leaves` | 20260927 |

### Replay determinism (`tools/test.sh replay`)

Each fixture replayed in two separate engine processes against `SimAssembly` over the
shipped content; both runs equal the recorded hash:

```
ok   tests/replay/m0-trivial.json   b44fa0a79ad9e2ba2073ee890294fcf694c79f1ab62ec9c452a26694663b83aa
ok   tests/replay/m1-perk-off.json  84e4ce6fa4e66b2ec0f8f8138b45df633fb6e73b17fbe5efa09f4f53623babf3
ok   tests/replay/m1-range.json     b961e4d54e5a2570deda1d85109ba7ab2b986899175098b16d9197df1fbf0e2d
```

The M0 fixture's hash changed from `06a22cfe…` because fixtures now replay against the
assembled system set (whose content digest is state), not a bare root. This is the
deliberate change the M0 gate's rule anticipates, and it is why a content rebalance will
move every hash in this table.

### Fuzz corpora

`tests/fuzz/replay_fixture/`: 12 hostile fixtures (M0). `tests/fuzz/commands/hostile_payloads.json`:
41 hostile payloads across all 11 command kinds and two unknown kinds; each rejected on
the standard range with the systems' state hash unchanged. In-test random mutation:
10 000 item payloads per run.

### Playtests on the Deck

The range view (`client/main.gd`) was run in `--demo` mode four times during the
milestone and read from screenshots; every count reconciled: magazines 15 → 10 → 2/15 as
shots were fired, the tactical reload kept a partial magazine, the emergency reload put
one in the world, dummy health fell by exactly 34.5 per hit and by 37.95 per hit once
the perk was unlocked, xp rose 100 per hit, level 2 at 800, one of two points spent.
One scripted shot inside a reload's busy window was rejected and shown as such.

### Deck smoke run of the Linux export (M0 debt items 5 and 9)

`tools/export.sh`: templates for 4.6.1-stable downloaded and verified against the
release's published SHA-512 (pinned in `tools/godot.pin`), installed, export produced
`build/linux/gcity.x86_64` (71 MB, embedded pack). Run from `/tmp` on this Deck in
`--demo` mode: window titled "Gcity", 36 content entries loaded, the range set up and
played (17 shots, 13 hits, level 2 reached in the screenshot), exit 0. The pack carries
no test or tool script bodies; the engine's class and uid caches inside it still list
`res://tests/` paths as metadata (see debt item 12).

## 3. Demo script

Performed on CEOGG's own Deck in desktop mode. Expected observation follows each step.

1. `git clone` the repository, `git checkout` the tagged G1 commit, `cd` in.
2. `tools/test.sh fitness` → `Ran 37 tests … OK`, `check_dependencies: clean`,
   `validate_content: clean`.
3. `tools/test.sh scripts` → every script line reads `ok`.
4. `tools/test.sh unit` → `87 tests, 212067 assertions, 0 failed` then
   `check_test_log: clean`. (`ERROR:` lines between the `ok` lines are the sim's
   deliberate rejections under test.)
5. `tools/test.sh replay` → the three `ok` lines and hashes of §2.
6. `$(tools/godot.sh) --path .` and press Play. → The range: player, dummy at 18 m,
   the G19 with its magazine, hit chance 58 % at 18 m. Press Space repeatedly: shots
   count up, the magazine counts down, the dummy's health drops by 34.50 on each HIT.
   Press R after a few shots: the seated magazine swaps and the partial one appears
   under "loose magazines". Press E: the swapped-out magazine appears under
   "dropped in world". After three or more hits the skill shows level 1 and
   `handgun_focus: available`; press P → `perks: handgun_focus`, damage/round 37.95.
7. Edit `content/perk/handgun_focus.json`, change `"value": 1000` to `2000`, run
   `tools/test.sh replay`. → `m1-range.json` fails with a different hash (the perk is
   state); `m1-perk-off.json` also fails (the content digest is state). Revert.
8. Edit `content/weapon_frame/g19.json`, remove `"magazine"` from `sockets`, run
   `tools/test.sh unit`. → `SimAssembly.build` refuses: "must declare exactly one
   container socket"; tests that build the sim fail loudly. Revert.
9. Add a file `content/perk/bogus.json` with `"class": "pow"`. → `validate_content`
   passes shape (pattern only); `tools/test.sh unit` fails at assembly: "unregistered
   modifier class". Delete it.
10. Add `sway_boost.json` under `content/perk/` copying `handgun_focus.json` with stat
    `sway`, cost 0, level 0, tags `[]`. Run `tools/test.sh`. → All stages pass; no
    `sim/` file changed; in the range (step 6) the perk is not on the HUD (it shows
    one perk by name) but `perk.unlock` for it succeeds from a fixture. Delete it.
11. `tools/export.sh` → downloads and verifies templates on first use, then
    `build/linux/gcity.x86_64`. Run it from another directory with `-- --demo`. → The
    same range plays in a window titled "Gcity" and exits after the script.
12. `python3 tools/check_dependencies.py` after adding
    `stats.set_base(1, &"damage", 1)` to `client/main.gd`. → One violation naming the
    line: "the client mutates sim state only through SimRoot.submit()". Revert.
13. Add `var _bases: Dictionary` to `sim/items/item_system.gd`, run the same. → One
    violation: "modifier/base storage is private to the resolver". Revert.

## 4. Debt and deviation log

| # | Item | Kind | Scheduled |
|---|---|---|---|
| 1 | Hit resolution is a roll against resolved `hit_chance` minus a per-metre falloff from the profile; there is no space. Replaced, not extended, when M4 brings perception and M6 geometry. | assumption (spec) | M4 |
| 2 | The combat pipeline lives under `sim/items/`; the design's module layout names no combat module. Move is mechanical if M4 wants `sim/combat/`. | assumption (spec) | M4 |
| 3 | Stat values are integer milli-units; percentages stack additively within the `mul` class. The design doc does not specify; exact compounding would need 128-bit intermediates. | spec amendment | closed |
| 4 | `actor.spawn` and `item.spawn` are debug-class commands: any client can create actors and items. Acceptable in solo; must be gated before any networked client exists. | security | before co-op (M8 gate at the latest) |
| 5 | Item and perk commands accept any positive `actor` id that names an inventory or an actor; nothing ties a command to a *player*. Ownership of commands is the land/authority work. | scope | M2 |
| 6 | The save round trip restores every system from its snapshot but not the root's tick, RNG state, inbox or dispatch counters. | scope | G2 (save/load property) |
| 7 | Reloads chamber automatically; there is no racking command, and no way to eject a chambered round without firing it. | feel decision | M6 playtest |
| 8 | `recoil`, `sway`, `ergonomics`, `aim_in_ticks` are resolved and shown but no stage reads them; only `hit_chance`, `damage`, `reload_ticks`, `cycle_ticks` act. | deliberate incompleteness | M4 (perception), M6 |
| 9 | The range view is a text HUD with fixed bindings; no device shell, no Steam Input configuration. | scope | M5 (device), G5 (Steam Input) |
| 10 | The M0 fixture hash moved (bare root → assembled sim). Recorded here; the M0 gate remains accepted as evidence of its day. | deliberate change | closed |
| 11 | Integral JSON floats are canonicalised to ints at the fixture and content boundaries, so a fixture payload `1.0` is accepted as `1`. Non-integral floats where ints belong are still rejected. | boundary decision | closed |
| 12 | The export's embedded pack excludes test and tool files, but the engine's class-name and uid caches inside it still list `res://tests/` and `res://tools/` paths as metadata. Harmless to run; worth a cleaner export at G6 (Steam install). | note | G6 |
| 13 | Export smoke run was in desktop mode from a local file, not a Steam install in gaming mode. G6 requires the latter; Steamworks app and depot branches remain CEOGG's external action (M0 debt 6). | external / scope | CEOGG before G6 |
| 14 | `tools/check_test_log.py` allows any error whose origin is `push_error`; a `push_error` the code should not have raised would pass. Assertions on specific rejections in tests cover the expected cases. | note | none |
| 15 | No fixture exercises the second frame (`m9`); the extension test covers it in-process. | note | M6 (mission fixtures) |
| 16 | `EventBus` duplicates and freezes each payload per emit. Fine at M1 volumes; not measured. | perf note | G4 |
| 17 | Mutation testing (standards §3.6) not run. | scope | G6 |
| 18 | No Deck measurement; M1 has no frame-budget claim. | scope | G4 |

## 5. The four standing questions

**Q1 — Does it function?** Yes. All nineteen claims have passing tests; seven
property tests run 10 000 cases each; three fixtures reproduce their recorded hashes in
two separate processes; the exported build plays the chain on the Deck. The end-to-end
proof of the milestone (template → instance → attachment → damage → skill event → perk)
is `test_perk_changes_applied_damage_by_exactly_the_files_factor`: same seed, same
command stream, hit-for-hit damages of 34 500 without the perk and 37 950 with it.

**Q2 — Is it secure?** Threat model: content files (trusted at ship, schema-validated
at build and re-checked at the sim boundary), replay fixtures (untrusted; 12-file
corpus plus 10 000 mutations), **command payloads** (untrusted, the client is treated as
hostile per standards §5.2: exact key sets, typed fields, ownership, calibre, capacity,
busy windows, alive checks; 41-case corpus plus 10 000 random item payloads; no case
changes state), and snapshots handed to `restore` (untrusted; every system validates
completely and stays untouched on rejection). Dependencies: Godot 4.6.1 (MIT, SHA-256),
its export templates (SHA-512 from the release's sums file), two GitHub Actions by
commit SHA, Python standard library only. No telemetry. Open: debt items 4 and 5.

**Q3 — Is it complete?** No stubs and no `TODO` in `sim/`, `client/`, `content/`,
`tools/`, `tests/`. Every error path returns an `Error`, `push_error`s, or asserts,
and the runner now fails on any error that is not a deliberate `push_error`. The debt
log above is fully scheduled.

**Q4 — Is it expandable?** The extension exercise (standards §11, G1) is performed:
`content/weapon_frame/m9.json` with `m9_barrel.json` and `m9_mag_15.json`, and
`content/ammo/9x19_jhp.json`, were added with **zero diff under `sim/`** (`grep -r "m9\|jhp" sim/`
is empty), and `tests/items/test_extension_content.gd` runs the full chain on every
frame × compatible round without naming one. A second perk node with a prerequisite on
the first (`handgun_control`) is data. Registries, not enums: stats, modifier classes,
tags, socket kinds, calibres, pipeline stages, command kinds, systems. Every content and
snapshot schema carries a version. Extension points are documented in
`docs/extending-sim-systems.md`, `docs/extending-progression.md`, `docs/extending-items.md`.

## 6. Sign-off

Approver: CEOGG
Date:
Outcome: ☐ Accepted   ☐ Accepted with conditions (list below)   ☐ Rejected
Conditions:
