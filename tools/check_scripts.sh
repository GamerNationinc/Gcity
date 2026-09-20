#!/usr/bin/env bash
# Runs the engine's static analyzer over every script. With the warning settings in
# project.godot this is the typed-GDScript rule (standards §3.7): an untyped
# declaration, unsafe access or unsafe cast is a parse error and fails here.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
godot="${GODOT:-$(tools/godot.sh)}"
status=0
while IFS= read -r script; do
	if ! output="$("$godot" --headless --path . --check-only -s "$script" 2>&1)"; then
		status=1
		echo "FAIL $script"
		echo "$output" | grep -E "SCRIPT ERROR|ERROR" | sed 's/^/     /'
	else
		echo "ok   $script"
	fi
done < <(find sim client tests tools -name '*.gd' | sort)
exit "$status"
