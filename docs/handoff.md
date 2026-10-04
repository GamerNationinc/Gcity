# Handoff: moving work from the Steam Deck to the Windows laptop (2026-09-28)

Claude Code's memory lives on the machine it runs on, so this file is how the next
session picks up. Read it first, then `CLAUDE.md`.

## Update, 2026-10-03 late, on the Deck: G7.5 submitted

- **`docs/gates/M7.5-gate.md` is submitted.** Every claim but 13's hand-played part is in;
  §6 lists the five decisions for CEOGG, §7 waits for the Deck run. Final suite 545 tests,
  0 failed, 24 replays.
- **Mutation (claim 12):** 81.8 % pass 1 on the 15 changed `sim/` files, a deeper sample on
  build and movement, 12 holes given tests, pass 2 91.2 % (`5301925`). Run it in four
  detached worktrees at once (symlink `.cache`, copy the built addons, `--import`); the
  map in `tools/mutate.py` now includes the M7.5 test files.
- **Found and fixed:** Cold Storage was open at the back since M6 (item 27); the mission
  demo played a random world (item 26: `--demo` now uses `LocalHost.DEMO_SEED`, `--seed=N`
  for any); the HUD's state hash cost 62 ms a second (item 30).
- **Q4 done:** `door_warehouse` (item 28). Every fixture hash moved again with it.
- **Deck screen tricks:** captures and screenshots need `--display-driver wayland`, the
  screen awake (`kscreen-doctor --dpms on`) and kept awake (qdbus ScreenSaver
  SimulateUserActivity every 20 s). See the scratch `capture.sh` pattern in item 29.
- **Next:** CEOGG's Deck run and sign-off; then M7.6 (the sandbox, approved), then M8.

## Update, 2026-10-03 night, on the Deck: the creator tool (claims 14–16) done

- `d9815e8` claims 14–15, `9ea4ac1` claim 16. Gate items 21–25. Full suite: 533 tests,
  0 failed, 24 replays (no fixture moved: no content changed).
- **Try it on the Deck:** in Steam, the Gcity shortcut's launch options `-- --create`
  (instead of `-- --wilds`); the export in `build/linux` was rebuilt with it. Controller
  only: D-pad cursor (relative to the camera), R1/L1 up/down a level, A place, B remove,
  X turn, Y next piece, View the save/open menu. Saved sites land in
  `~/.local/share/godot/app_userdata/Gcity/sites/`; bring one into the game with
  `tools/import_site.py <file> <id> [title]`.
- **For CEOGG:** item 21 (save/open is a creator menu, not a device app, to avoid moving
  every fixture hash) is a deviation to keep or overrule; item 10 (support cost) is worth
  watching while placing by hand on the Deck.
- **Next:** 9 (close the fixture table), 12 (mutation ≥ 75 % on the changed `sim/`
  files), the claim 11 screenshots with the screen awake, then 13 (CEOGG's Deck run).

## Update, 2026-10-03 evening, on the Deck: claims 8, 10 and 11 done

- **Claim 8** (`25593f4`): the road property walks 10 000 worlds as a two-cell person
  through `MovementSystem.move`; levelling clears a storey over a bound site's top
  (`SiteSystem.top_of`, `LEVEL_HEADROOM`). No fixture moved. Gate item 18.
- **Claim 10** (`2224ab3`): saves are version 3; versions 1 and 2 are refused by name
  (`migrate_from_1` removed). Gate item 19.
- **Claim 11** (`1792e3b`): the mission demo walks Cold Storage at human scale and scores
  seen 0 / alarms 0 / bodies 0 / traces 0 with 0 rejected (it stalled before); overlays
  and the first-person eye come from the sim. Gate items 17, 20. **Still owed:** the gate
  screenshots of the M4 building, Cold Storage and the wilds, taken with the Deck screen
  awake (asleep it renders at 1 fps), and the Deck has no `xvfb-run`: run the client on
  `DISPLAY=:0` with `--screenshot=... --screenshot-at=...` instead of `tools/screenshot.sh`.
- Full suite on the Deck: 525 tests, 0 failed, 24 replays, ~25 min with 6 jobs once
  `tests/out/durations.json` exists (the first run, without it, took ~45).
- A fresh worktree needs `$(tools/godot.sh) --headless --path . --import` before
  `tests/run_tests.gd` can find `GcityTest`, plus the built addons (test.sh does both).
- **Next: claims 14–16, the creator tool**, then 9 (close the fixture table), 12
  (mutation), 13 (CEOGG's Deck run). Crouching (item 13) is still CEOGG's to place.

## Update, 2026-10-03: moving from the laptop back to the Deck — read this first

Claude Code's memory stays on the machine; this section is everything the laptop's memory
knew that the repo did not. Everything is on GitHub: branch **`m7_5-human-scale`**.

**Where M7.5 stands.** Claims 1–7 are done, verified and pushed (6 in three parts: 6a the M3
fixture generator, 6b the sites, bodies and every fixture at human scale, 6c raid tokens as
a person). Last full suite: 523 tests, 0 failed, 24 replays. CI is green on this branch.
**Next: claim 8** (the wilds against a 2-cell body: road clearance, site levelling to the
site's top plus a storey, the M7 connectivity property over 10 000 seeds with the body
rule). Then 10 (saves at schema 3), 11 (the client at scale; gate item 17: the scripted
demo has one rejected command), 14–16 (the creator tool), 9 and 12–13 to close the gate.
Expect claim 8 to find low spots: eyes at 1.6 m already showed the wilds differ (item 15).

**Also on this branch now** (merged 2026-10-03, docs only): the study-and-rebuild policy and
its CLAUDE.md rule, `docs/references/` (study 1), and the approved **M7.6 sandbox spec**
(it starts when G7.5 is signed; M8's empty-sim baseline is now G7.6).

**Getting the Deck ready**
1. `git fetch origin && git checkout m7_5-human-scale && git pull`.
2. `tools/test.sh` now runs the unit and replay stages on several engine processes
   (`GCITY_JOBS`, default: the cores less two, so 6 on the Deck; set `GCITY_JOBS=4` if it
   runs hot or short of memory, `GCITY_JOBS=1` for the old one-process run). Expect well
   under the old 80 minutes; the first run records each file's time in
   `tests/out/durations.json` and splits slow files by test method after that.
3. **Rust is required** now (CEOGG, 2026-10-02): `test.sh` stops with a message without
   `cargo`, and installs the GodotSteam binaries and builds the native mesher by itself when
   they are missing (no more `tools/godotsteam.sh` per worktree). Run it from a shell where
   `cargo` is on `PATH`.
4. A run that ends at `== headless tests` without `== all stages passed` failed; the
   per-test results are in `tests/out/unit.log`.

**How CEOGG wants answers** (the laptop's memory; carry it over)
- End every answer with a **"Buddy recap"**: 3–5 lines in the voice of Ricky from Trailer Park
  Boys — laid-back, earnest, mangled big words — with **no swearing and no references to the
  show** (no characters, places, catchphrases). The facts in it as exact as the answer's.
- **Include a screenshot** with answers (`tools/screenshot.sh`), not while a timing-sensitive
  test run is in progress; say when nothing on screen changed.
- Never read, fetch or clone reverse-engineered or decompiled source in a Gcity workspace
  (CLAUDE.md §10); design notes only (`docs/policy/study-and-rebuild.md`).

**Open decisions for CEOGG**
- Where **crouching** goes (gate §4 item 13): the M7.5 spec excludes posture.
- Two calls made in claim 6c, logged in gate item 2: a raid token never cuts a floor or a
  roof, and the far-side fix.

**Lessons from the laptop session** (gate items 14–16)
- Sight follows `passable`: every opening a person fits through is an eye-height view.
- Any tool or test that draws its own sight line or body check drifts from the game's: ask
  `PerceptionSystem.can_target`/`can_see` and `MovementSystem.body_fits`/`is_standable`.
- Tests of a rule bring their own profiles (`db.add` before `SimAssembly.build`) rather than
  borrowing the shipped ones, which are now human scale.
- Found, not fixed: an alerted squad in the wilds stands still (item 16, M9).

**The laptop** keeps scratch worktrees `~/gc2`–`~/gc14` under WSL; everything in them is on
GitHub (gc2–gc8 hold drafts of the M7 triage tests, committed under their final names).
They can be removed with `git worktree remove` whenever convenient.

## Update, 2026-10-02, on the laptop (WSL2): claims 3–5 verified

- **The first full suite on `m7_5-wip` was not green**: 515 tests, 1 failed
  (`test_quest_system.gd::test_a_build_objective_credits_the_builder` built on its own
  player's feet, which claim 2 refuses; the failure was already in `972e0b7`), and the
  log check flagged `test_run_log.gd` listing a folder that does not exist on a fresh
  machine. Both fixed in `c9240d7` (gate §4 items 4 and 8). **Watch for this:** under
  `set -e`, `tools/test.sh` used to stop without a word when the unit run failed — a log
  that ends at `== headless tests` is a failure. Success ends `== all stages passed`.
- **Claim 5, support by column, is done** (`50ba29f`): a piece resting on the one below
  takes its depth (0-1 search, `BuildSystem._slots_under`). Two 10 000-case properties
  against a geometric oracle; five hand mutants (four killed, one equivalent); no
  fixture hash moved. The M3 span test now counts five walls from a foundation (gate
  item 9). `supported_set` costs 15.5 ms at 252 pieces against 10.6 before (item 10:
  measure on the Deck when the creator tool lands).
- `m7_5-human-scale` now points at `50ba29f` (claims 1–5), verified by a full suite:
  519 tests, 341 389 assertions, 0 failed, all 24 replays, all stages passed (90 min, native mesher on).
- **CI has been red since M5** (`8e36876`, the GodotSteam pin; the last green run was
  `d5a037d`), through the G5, G6 and G7 sign-offs. CI never installed GodotSteam (every
  engine run then logs a missing GDExtension, which the log check fails), and from M7 its
  unit stage had no native mesher (the frame-budget test fails on the GDScript port).
  CEOGG chose (2026-10-02) to make Rust required: on branch `tools-parallel-tests`,
  `test.sh` installs GodotSteam and builds the mesher before any engine stage and stops
  with a message if `cargo` is missing; CI's engine job installs the pinned toolchain.
  **CI green again** on `9ca7f1f` (fitness 3 min, engine 42 min), the first since
  `8e36876`; merged into `m7_5-human-scale` with CEOGG's yes, 2026-10-02.
- **Run suites from a login shell** (`bash -l`): a plain `bash` has no `~/.cargo/bin`, and
  before that branch `test.sh` silently skipped the native mesher.
- **The parallel test runner** (same branch, `tools/parallel_tests.py`, `GCITY_JOBS`):
  serial 90 min, parallel (6 workers) 35 min on
  this laptop, same commit, with per-test results identical line by line, the same 24
  replay hashes and a clean log check. The floor is two files of about 30 min each
  (`test_route_graph`, `test_save_file`); splitting them by test method is the next step
  if the time matters. **Done** (`b3f125b`): slow files run one method per job, whole
  suite 28 min, bound by total work now. Merged into `m7_5-human-scale`.
- **M7.6, the sandbox, is approved** (`docs/specs/M7.6-sandbox.md`, branch `m7_6-spec`):
  spawner, trainer, AI and time controls, inspector, sessions as fixtures, dev builds
  only. It starts when G7.5 is signed; M8's empty-sim-diff baseline is now G7.6.
- **Study-and-rebuild policy adopted** (`docs/policy/study-and-rebuild.md`, branch
  `policy-study-rebuild`; CLAUDE.md §10 carries the rule): never read reverse-engineered
  source in a Gcity workspace; a separate study agent writes design notes, code is built
  from them. **Study 1** (iw4L, skate-3-rust-engine) is in `docs/references/` on branch
  `references-study-1`, vetted; nothing is scheduled from it yet (M8 motion, M9 AI).
- **Claim 7, falls in metres, is done** (same day, this session, at CEOGG's word): the
  `fall_free_levels` profile field, at 1 everywhere (gate item 11); claim 6's tuning is
  pinned by a test profile. All 24 hashes re-recorded for the content digest only.
- **Update, 2026-10-03: claim 6 is done in two parts** (CEOGG chose the split and its three
  decisions, gate §4 item 12). 6a `b46bc1a`: `tools/make_m3_fixtures.gd` (claim 9's tool).
  6b `4cc50e7`: every profile at human scale, both sites rebuilt by `tools/make_sites.gd`
  (two-cell slab, 2 m tunnel, storey walls, 2 m doors, sill windows, a tall maintenance
  window, a caged fire stair), a `concrete_block` piece, all 24 fixtures regenerated and
  re-proved, 19 tests that leaned on one-cell bodies fixed (gate items 14, 15). Full suite
  green: 521 tests, 348 228 assertions, 24 replays (33 min). **Lessons:** sight follows
  `passable`, so every opening a person fits is an eye-height view (item 14a); a generator
  or test that draws its own sight line drifts from the game's: ask `can_target`/`can_see`.
- **Claim 6c is done** (2026-10-03, gate item 2): raid tokens cross as a person, priced by
  `RaidTokenSystem.crossing_cost` with the movement system's rules; floors are never cut;
  a far-side bug fixed. 523 tests green. **Next: claim 8** (the wilds against a 2-cell body:
  road clearance, site levelling to the top plus a storey, the M7 connectivity property over
  10 000 seeds with the body rule), then 10, 11, 14–16, 12–13.
- *(Done; kept for the record.)* Claim 6c, raid tokens and stacked openings (gate item 2, decided: a token
  crosses an opening column only where both of its faces are open, breaching costs both).
  It touches `sim/nav/portal_graph.gd` (edge cost of a column) and
  `sim/agents/raid_token_system.gd` (crossing and breaching the face above), so plan it as
  one change or two. Then claims 8 (wilds checked against a 2-cell body), 10 (saves at
  schema 3), 11 (client at scale; gate item 17: the demo has one rejected command), 14–16
  (the creator tool), 12–13 to close. **CEOGG still to place: crouching** (gate item 13).
- *(Superseded by the update above.)* Claim 6 plan, as written before it was done
  (spec claim 6, gate §4 items 1, 2, 6, 11):
  rebuild both sites in `tools/make_sites.gd` at 3-cell storeys with 2-cell doors and
  sill windows, and in the same change flip every profile to `body_cells` 2, `eye_mm`
  1600, `centre_mm` 1000, `fall_free_levels` 3, `fall_damage_per_level` 4000; update
  `test_every_shipped_profile_still_has_one_free_level_until_claim_6`; raid tokens and
  stacked openings (item 2). Its own session: it is the largest claim, and every
  fixture's run must be re-checked for still recording what it is named for.
- Working from Windows: the file tools cannot write under `\\wsl$`; edit through a script
  run with `wsl -d Ubuntu-24.04 -e bash -lc "bash /mnt/c/.../x.sh"`. Worktrees this
  session: `~/gc9` (claims 3–4 + fixes), `~/gc10` (claim 5), `~/gc11` (a detached check
  of `972e0b7`), `~/gc12` (tools), `~/gc13` (M7.6 spec), `~/gc14` (policy, references).

## Update, 2026-10-01, on the Deck: M7.5 in progress

- **G7 is signed** (CEOGG, 2026-10-01, `68b4847` on `m7-deck-run`). The Deck run's fixes
  (strafe, facing arrow, camera, the run log in `client/run_log.gd`) are on `m7-deck-run`.
  Nothing is merged to the default branch yet: ask CEOGG before merging.
- **M7.5 — Human scale is approved** (`docs/specs/M7.5-human-scale.md`, amended with the
  creator tool, claims 14–16). Work branch: **`m7_5-human-scale`**. Gate draft:
  `docs/gates/M7.5-gate.md` (§4 has the deviations so far).
- **Pushed and verified on `m7_5-human-scale`:** claim 1 (`5785f6d`, the body rule) and
  claim 2 (`972e0b7`, nothing built or filled in a body; 10 000-step property).
- **Claims 3–4 are written but NOT verified by a full suite**: they are on branch
  **`m7_5-wip`** (one commit on top of `972e0b7`). Done there: sight eyes→eyes/centre,
  shots eyes→centre, cover the same lines (`tests/agents/test_eyes.gd`, 10 000-case
  metamorphic property, mutation-checked); reach from `ActorSystem.centre_of`; profile
  fields `eye_mm`/`centre_mm` at 0; all 24 replays proven unchanged with the fields at
  their old values, then re-recorded. Every directly affected test file passed; the full
  `tools/test.sh` was started at 15:48 and stopped unfinished when CEOGG had to leave.
  **First thing on the laptop:** check out `m7_5-wip`, run `tools/test.sh`, and if it is
  green fast-forward `m7_5-human-scale` to it and push; then continue.
- **Next: claim 5, support by column** — in `BuildSystem.supported_set`, a piece resting
  directly on a supported piece below it keeps that piece's depth (0-1 BFS), so
  `max_span` limits overhangs, not height. Then claim 7 (falls in metres), then claim 6
  (rebuild both sites in `tools/make_sites.gd` at 3-cell storeys with 2-cell doors and
  sill windows, and flip every profile to `body_cells` 2, `eye_mm` 1600, `centre_mm`
  1000 in the same change; raid tokens and stacked openings, gate §4 item 2).
- **Method that worked:** to prove a content-field change moved no behaviour, stash the
  content change, read the field with a default in code, replay all 24 against the old
  hashes, restore, then `tools/rerecord_hashes.sh`. Tests add their own tall profiles with
  `db.add` before `SimAssembly.build` (see `test_body.gd`, `test_eyes.gd`).
- Every run of the client writes `user://logs/runs/run-*.log`; read it after any Deck run.

## Update, 2026-09-29, on the laptop (WSL2)

- The first pass is finished: files 21–48 are `docs/gates/M7-mutation-pass1b.log` and `.json`
  (145 scored, 104 killed, 71.7 %). Over all 48 files: 257 scored, 177 killed, **68.9 %**.
- Every survivor of both halves is triaged in `docs/gates/M7-mutation-triage.md`: 53 holes,
  each with a test checked against its mutant; 24 equivalent, with reasons; 2 harness; 1 caught
  only outside its file's mapped tests.
- `tools/mutate.py` now counts `SCRIPT ERROR:` lines as diagnostics (a mutant that made the
  stress tick throw 3 309 times passed as `0 failed`), and maps `land_system.gd` to the pause
  tests. Both are in the triage note.
- Pass 2, every `sim/` file again with the new tests and the fixed harness: 221 of 252,
  **87.7 %**. Its 20 new survivors are triaged too, with 13 more tests; one turned up a
  defect in the squad entry planner (gate §4 item 14), since fixed. None is left open.
- `ea3937f` (another session, in `~/Gcity`) fixed why the streamer's frame-budget test
  failed here: the wild ground measured every road for each new chunk. `wild_region.gd`
  was mutated again on its new code (pass 2 with it: 86.9 %).
- The suite with all of it: 496 tests, 340 273 assertions, 0 failed, all stages passed.
- Two sessions shared `~/Gcity` for a day without knowing it. One tree per session; scratch
  worktrees are `~/gc2`–`~/gc4`.
- `docs/gates/M7-gate.md` is **submitted** (2026-09-30), awaiting CEOGG's Deck run and sign-off. Decided on
  2026-09-30: the terrain mesher dependency is accepted, the Q4 content stays in the game,
  the carried M6 debt goes to M8 but for items 5 and 7, which need `sim/` changes and go to
  M9; and the reorder is approved: M8 is look and feel, the threat director M9 (design doc
  §16 and standards §2.1 on `m8-spec`). Later the same day ADR-011 was accepted (1A; 2A,
  then 2B) and the M8 spec approved (`m8-spec`, `25d0dea`); M8 starts when G7 is signed.

## Where things stood on the Deck

- **G0–G6 signed.** M7 (route graph and procedural wilds) is on `m7-procgen`: claims
  1–17 and the Q4 extension exercise are pushed (`3be5a1e`; 433 tests, 339 534
  assertions, 0 failed, 24 replay fixtures reproduce).
- **Claim 18's mutation run is half done**, and this branch (`m7-mutation-wip`) carries
  it: 20 of 48 `sim/` files scored before the Deck had to stop. First-pass tally over
  those files: 73 killed, 39 survived, 11 invalid (not counted), about 64 % against a
  75 % bar. The raw log is `docs/gates/M7-mutation-pass1.log`; the 28 files still to
  run are `docs/gates/M7-mutation-remaining.txt`.
- **New tests already written** for seven survivors in `sim/agents/`, each checked by
  applying its mutant by hand and seeing the test fail: a revived actor's health, a
  one-member squad, a released token's leg, the slowest token pace, a solid floor
  refusing a climb (counted), a negative movement counter refused, and the pathing
  system hearing build changes and removals. They pass on their own; the full suite
  has not yet been run with them, which is why they are on this branch and not on
  `m7-procgen`.
- **Survivors judged equivalent or unreachable** (to be listed in the gate, not
  "fixed"): `actor_system.gd:227` (the integer square root's upward correction, which the
  float estimate makes unnecessary at the distances the sim computes; worth one boundary
  test if cheap), `corpse_system.gd:243` (revive cannot fail there), `:303` and
  `:307` (initial values overwritten on the first pass), `hydration_system.gd:282` (a
  squad only takes the gate partway along its last road, so the leg cannot change
  there), `pathing_system.gd:265` (a path always unwinds to its start). Every other
  survivor in the log is untriaged.
- `tools/mutate.py` now samples each file from the run seed and the file path alone,
  so the remaining files pick the same mutants they would have in one full run. The 20
  finished files were sampled the old way; say so in the gate.
- **The M7 gate package** is drafted at `docs/gates/M7-gate.md` (status: draft). Its
  `{{…}}` fields wait on the mutation score and the final suite numbers.
- **M8 is proposed, not approved:** `docs/specs/M8-look-and-feel.md` and
  `docs/adr/ADR-011-art-direction-and-assets.md` on branch `m8-spec`. CEOGG decides:
  the reorder (look and feel becomes M8, the threat director M9), the art direction,
  asset sourcing, and the quick-suite amendment to standards §3.2.
- A stray remote branch, `claude/functional-playable-requirements-0ebcjo`, is a cloud
  session redoing M6 from the M5 merge. It is not part of this line of work.

## Setting up the laptop (Windows)

Use **WSL2**, not a full virtual machine. A VirtualBox or VMware guest gets no real
GPU; WSL2 is a lightweight Linux that runs the project's bash and Python tools and the
Linux Godot build unchanged, and Claude Code runs in it natively.

1. In an administrator PowerShell: `wsl --install -d Ubuntu-24.04`, reboot, create the
   Linux user.
2. In Ubuntu: `sudo apt update && sudo apt install -y git python3 curl unzip build-essential`.
3. Optional, for the native terrain mesher: `curl https://sh.rustup.rs -sSf | sh`
   (the crate's `rust-toolchain.toml` pins 1.98.0). Without Rust the tests use the
   GDScript port and the native stage is skipped.
4. Install Claude Code in Ubuntu and sign in.
5. Clone **inside the Linux home**, not under `/mnt/c` (the Windows drive is many times
   slower from Linux):
   `git clone https://github.com/GamerNationinc/Gcity ~/Gcity && cd ~/Gcity && git checkout m7-mutation-wip`
6. Git identity for this repo: `git config user.name CEOGG` and
   `git config user.email <your email>`. Pushing needs GitHub credentials (a
   personal access token, or `gh auth login`).
7. `tools/godotsteam.sh` once per checkout (and per worktree): `tools/test.sh` does not
   install the GodotSteam binaries, and without them every engine run logs a missing
   GDExtension, which fails the unit stage's log check.
8. `tools/test.sh` downloads and verifies the pinned Godot 4.6.1 on first use, then
   runs everything. **Time it**: it took about 80 minutes on the Deck.

For looking at the game (M8 work) run the Windows build of Godot 4.6.1 and open the
project from `\\wsl$\Ubuntu-24.04\home\<user>\Gcity`, or run the Linux client through
WSLg. On Windows the native mesher is not built, so the wilds use the GDScript port:
fine for looking, slower. **The Deck stays the only machine whose frame numbers
count** (standards §4.2).

## Picking up

1. `tools/test.sh` on this branch. If it passes, the new tests can go to `m7-procgen`.
2. Finish the mutation run on the remaining files. They can be split across cores in
   two worktrees if there is memory for it:
   `python3 tools/mutate.py $(cat docs/gates/M7-mutation-remaining.txt) --json docs/gates/M7-mutation-pass1b.json`
3. Triage every survivor: a real hole gets a test that fails on the mutant; an
   equivalent one is listed with the reason. Re-run mutation on the files that gained
   tests and report **both** scores, first pass and after, as the M6 gate did.
4. Fill in `docs/gates/M7-gate.md`, push, and ask CEOGG for the G7 sign-off, the
   `native/terrain_mesher` dependency decision and the M8 decisions in one message.

Gotchas learned on the Deck:
- `pgrep -f tools/test.sh` inside a `bash -c` matches its own command line; wait on the
  process id instead.
- GDScript reference cycles are never freed; when two systems must reach each other,
  one side holds a method `Callable`.
- A new settlement kit moves every world, so every fixture hash: regenerate the M6 and
  M7 fixtures, check each still records the run it is named for, then re-record.
- Looks for M8 must live under `assets/`, never `content/`: the content digest is in
  the state hash.
