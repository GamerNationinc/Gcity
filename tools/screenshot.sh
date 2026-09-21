#!/usr/bin/env bash
# Renders the client under a virtual display (Xvfb + Mesa software GL) and saves a
# PNG of the demo at a given second. Every presentation of work to the approver
# carries one of these (CLAUDE.md, "Screenshots").
#   tools/screenshot.sh <out.png> [seconds-into-demo, default 12]
# SCENE=<res path> selects a scene other than the project main scene (e.g. the M1 range).
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
out="${1:?usage: tools/screenshot.sh <out.png> [seconds]}"
at="${2:-12}"
godot="${GODOT:-$(tools/godot.sh)}"
mkdir -p "$(dirname "$out")"
case "$out" in /*) abs="$out" ;; *) abs="$root/$out" ;; esac
quit_at="$(python3 -c "print(float('$at') + 1.0)")"
xvfb-run -a -s "-screen 0 1280x800x24" "$godot" --path . ${SCENE:+"$SCENE"} \
	--rendering-driver opengl3 --audio-driver Dummy --resolution 1280x800 \
	-- --demo "--demo-quit=$quit_at" "--screenshot=$abs" "--screenshot-at=$at" 2>&1 \
	| grep -E "screenshot|SCRIPT ERROR|ERROR: screenshot" || true
[[ -s "$abs" ]] || { echo "screenshot.sh: no file written at $abs" >&2; exit 1; }
echo "$abs"
