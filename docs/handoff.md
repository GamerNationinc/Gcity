# Handoff: moving work from the Steam Deck to the Windows laptop (2026-09-28)

Claude Code's memory lives on the machine it runs on, so this file is how the next
session picks up. Read it first, then `CLAUDE.md`.

## Update, 2026-09-29, on the laptop (WSL2)

- The first pass is finished: files 21–48 are `docs/gates/M7-mutation-pass1b.log` and `.json`
  (145 scored, 104 killed, 71.7 %). Over all 48 files: 257 scored, 177 killed, **68.9 %**.
- Every survivor of both halves is triaged in `docs/gates/M7-mutation-triage.md`: 53 holes,
  each with a test checked against its mutant; 24 equivalent, with reasons; 2 harness; 1 caught
  only outside its file's mapped tests.
- `tools/mutate.py` now counts `SCRIPT ERROR:` lines as diagnostics (a mutant that made the
  stress tick throw 3 309 times passed as `0 failed`), and maps `land_system.gd` to the pause
  tests. Both are in the triage note.
- The suite with all of it: 478 tests, 340 086 assertions, one failure:
  `test_terrain_streamer::test_a_frame_keeps_to_its_budget`, which fails on this laptop every
  time (worst frame 7.9–10.1 ms against a 6 ms ceiling, idle machine, native mesher loaded)
  and is left as it is for CEOGG to decide: it is a desktop wall-clock number.
- Still to do: the second pass (every `sim/` file again, with the new tests and the fixed
  harness) for the after score, then the gate.

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
