# `tools/`

Editors, validators, fitness functions and the engine pin. May import anything.

| File | Purpose |
|---|---|
| `godot.pin` | The exact engine version and SHA-256 used by CI and locally. |
| `godot.sh` | Downloads and verifies the pinned engine into `.cache/godot/`, prints its path. |
| `check_dependencies.py` | Architectural fitness function: the `sim/` → `client/` rule and the sim's determinism deny-list. |
| `validate_content.py` | Content layout and schema-registration check for `content/`. |
| `check_scripts.sh` | Runs the engine's static analyzer (`--check-only`) over every script; typed-GDScript enforcement. |
| `replay_hash.gd` | Replays one fixture headless and prints its state hash. CI runs it twice and diffs. |
| `test.sh` | The whole verification run, in the order CI uses it. Run this before presenting any work. |
| `tests/` | Unit tests for the Python tools (`python3 -m unittest discover tools/tests`). |
