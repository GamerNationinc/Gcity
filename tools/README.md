# `tools/`

Editors, validators, fitness functions and the engine pin. May import anything.

| File | Purpose |
|---|---|
| `godot.pin` | The exact engine version, its SHA-256, and the export templates' SHA-512, used by CI and locally. |
| `godotsteam.pin` | The pinned GodotSteam GDExtension: version, godot-cpp target, Steamworks SDK, URL, SHA-256, and the Steam app id the client initialises with. |
| `godotsteam.sh` | Downloads and verifies the pinned release into `addons/godotsteam/`, keeping only the Linux and Windows libraries (no editor self-updater). |
| `godot.sh` | Downloads and verifies the pinned engine into `.cache/godot/`, prints its path. |
| `check_dependencies.py` | Architectural fitness function: the `sim/` → `client/` rule and the sim's determinism deny-list. |
| `validate_content.py` | Content layout and schema-registration check for `content/`. |
| `check_scripts.sh` | Runs the engine's static analyzer (`--check-only`) over every script; typed-GDScript enforcement. |
| `check_test_log.py` | Fails the unit stage on any `SCRIPT ERROR` or any engine error not raised by `push_error`; a test that passes while the engine logs a bug underneath it is a failure. |
| `replay_hash.gd` | Replays one fixture headless against the assembled sim (`SimAssembly` over the shipped content) and prints its state hash. CI runs it twice and diffs. |
| `export.sh` | Native Linux export with the pinned engine and pinned, SHA-512-verified export templates; the preset excludes `tests/`, `tools/`, `docs/`, `spikes/`. |
| `screenshot.sh` | Renders the client demo under Xvfb and saves a PNG at a given second; every delivery carries one. |
| `bench_agents.gd` | The agent budget on the Deck (M4 claim 13): the M4 building with six armed guards for 12 000 ticks headless, per-tick sim time at the 99th and 99.9th percentiles, with and without agents, and the rebuild ticks, as JSON. |
| `make_m4_fixtures.gd` | Regenerates the six M4 replay fixtures from `M4Building`; re-record their hashes afterwards. |
| `test.sh` | The whole verification run, in the order CI uses it. Run this before presenting any work. |
| `tests/` | Unit tests for the Python tools (`python3 -m unittest discover tools/tests`). |
