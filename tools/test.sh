#!/usr/bin/env bash
# The whole verification run, in the order CI uses it. Run before presenting any work
# (standards §10.5). Subcommands run one stage:
#   tools/test.sh            everything
#   tools/test.sh fitness    Python fitness functions + their unit tests
#   tools/test.sh scripts    engine static analysis of every .gd file
#   tools/test.sh unit       headless test suite
#   tools/test.sh replay [fixture]   replay fixtures twice each and diff the hashes
# The unit and replay stages run on GCITY_JOBS engine processes at once (default: the
# cores less two, at least one) through tools/parallel_tests.py; GCITY_JOBS=1 is the
# one-process run.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

stage_fitness() {
	echo "== fitness functions"
	python3 -m unittest discover -s tools/tests -t . -q
	python3 tools/check_dependencies.py
	python3 tools/validate_content.py
	stage_native
}

# The native terrain mesher (native/terrain_mesher): Clippy pedantic, its own tests, and a
# fresh build installed for the engine stages. Required (CEOGG, 2026-10-02): the frame
# budget the streamer is tested against is the native mesher's, and a run on the
# GDScript port fails it, so a machine without Rust cannot run the suite.
require_cargo() {
	if ! command -v cargo >/dev/null; then
		echo "test.sh: no cargo on PATH. The suite needs the pinned Rust toolchain for the native" >&2
		echo "terrain mesher: install rustup (https://rustup.rs), or run from a login shell" >&2
		echo "(bash -l) if it is installed but ~/.cargo/bin is not on this shell's PATH." >&2
		exit 1
	fi
}

stage_native() {
	require_cargo
	echo "== native mesher"
	(cd native/terrain_mesher && cargo clippy --release --locked --quiet --all-targets -- -W clippy::pedantic -D warnings \
		&& cargo test --release --locked --quiet 2>&1 | grep -E "^test result|FAILED|panicked")
	tools/build_native.sh
}

engine() {
	if [[ -z "${GODOT:-}" ]]; then
		GODOT="$(tools/godot.sh)"
		export GODOT
	fi
	# What every engine run loads besides the engine: the pinned GodotSteam binaries
	# (missing, every run logs a missing GDExtension and the log check fails) and the
	# native mesher. Both are installed once per checkout and skipped when present.
	tools/godotsteam.sh >/dev/null
	if [[ ! -f addons/terrain_mesher/linux64/libterrain_mesher.so ]]; then
		require_cargo
		tools/build_native.sh
	fi
	# Always rescan: new class_name scripts are unknown to the analyzer until the
	# engine's global class cache is rebuilt, and a stale cache fails every dependent
	# script with "could not find type".
	if [[ -z "${GCITY_IMPORTED:-}" ]]; then
		"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
		export GCITY_IMPORTED=1
	fi
}

stage_scripts() {
	echo "== script analysis"
	engine
	tools/check_scripts.sh
}

job_count() {
	local cores
	cores="$(nproc 2>/dev/null || echo 1)"
	echo "${GCITY_JOBS:-$(( cores > 3 ? cores - 2 : 1 ))}"
}

stage_unit() {
	echo "== headless tests"
	engine
	mkdir -p tests/out
	local log=tests/out/unit.log
	local status=0
	# `|| status=$?`: under `set -e` a failing run would otherwise end the script here,
	# before the log is shown or checked, and the stage would just stop printing
	if [[ "$(job_count)" -gt 1 ]]; then
		python3 tools/parallel_tests.py unit --godot "$GODOT" --jobs "$(job_count)" || status=$?
	else
		"$GODOT" --headless --path . -s tests/run_tests.gd > "$log" 2>&1 || status=$?
	fi
	grep -vE '^Godot Engine v|^$' "$log"
	# A passing assertion count is not enough: any runtime script error, or any engine
	# error that did not come from a deliberate push_error, fails the stage.
	python3 tools/check_test_log.py "$log" || status=1
	return "$status"
}

stage_replay() {
	echo "== replay determinism"
	engine
	if [[ "$(job_count)" -gt 1 ]]; then
		python3 tools/parallel_tests.py replay --godot "$GODOT" --jobs "$(job_count)" "$@"
		return
	fi
	local fixtures=("$@")
	if [[ ${#fixtures[@]} -eq 0 ]]; then
		mapfile -t fixtures < <(find tests/replay -name '*.json' | sort)
	fi
	local status=0
	for fixture in "${fixtures[@]}"; do
		local first second
		first="$("$GODOT" --headless --path . -s tools/replay_hash.gd -- "$fixture" 2>/dev/null | tail -n 1)"
		second="$("$GODOT" --headless --path . -s tools/replay_hash.gd -- "$fixture" 2>/dev/null | tail -n 1)"
		if [[ -z "$first" || "$first" != "$second" ]]; then
			echo "FAIL $fixture: run 1 = '$first', run 2 = '$second'"
			status=1
		else
			echo "ok   $fixture $first"
		fi
	done
	return "$status"
}

case "${1:-all}" in
	all) stage_fitness; stage_scripts; stage_unit; stage_replay ;;
	fitness) stage_fitness ;;
	scripts) stage_scripts ;;
	unit) stage_unit ;;
	replay) shift; stage_replay "$@" ;;
	*) echo "unknown stage: $1" >&2; exit 2 ;;
esac
echo "== all stages passed"
