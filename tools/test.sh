#!/usr/bin/env bash
# The whole verification run, in the order CI uses it. Run before presenting any work
# (standards §10.5). Subcommands run one stage:
#   tools/test.sh            everything
#   tools/test.sh fitness    Python fitness functions + their unit tests
#   tools/test.sh scripts    engine static analysis of every .gd file
#   tools/test.sh unit       headless test suite
#   tools/test.sh replay [fixture]   replay fixtures twice each and diff the hashes
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

stage_fitness() {
	echo "== fitness functions"
	python3 -m unittest discover -s tools/tests -t . -q
	python3 tools/check_dependencies.py
	python3 tools/validate_content.py
}

engine() {
	if [[ -z "${GODOT:-}" ]]; then
		GODOT="$(tools/godot.sh)"
		export GODOT
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

stage_unit() {
	echo "== headless tests"
	engine
	mkdir -p tests/out
	local log=tests/out/unit.log
	"$GODOT" --headless --path . -s tests/run_tests.gd > "$log" 2>&1
	local status=$?
	grep -vE '^Godot Engine v|^$' "$log"
	# A passing assertion count is not enough: any runtime script error, or any engine
	# error that did not come from a deliberate push_error, fails the stage.
	python3 tools/check_test_log.py "$log" || status=1
	return "$status"
}

stage_replay() {
	echo "== replay determinism"
	engine
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
