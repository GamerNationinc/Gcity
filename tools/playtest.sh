#!/usr/bin/env bash
# Plays a game loop through the real client, headless, in the cloud (CLAUDE.md §8:
# Deck runs are scarce). A bot from tools/playtest/<name>.gd drives world_view's own
# stick, context button and device; the run ends on its verdict line.
#   tools/playtest.sh <name> [seed]
# Exit 0 and "PLAYTEST PASS ..." when the loop came out as the bot expects.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
name="${1:?usage: tools/playtest.sh <name> [seed]}"
godot="${GODOT:-$(tools/godot.sh)}"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
# --fixed-fps 40: one physics tick a frame, as fast as the machine runs, so the run
# does not depend on the wall clock
set +e
timeout 3600 "$godot" --headless --path . --fixed-fps 40 res://client/world_view.tscn -- "--playtest=$name" ${2:+"--seed=$2"} > "$log" 2>&1
code=$?
set -e
grep -E "^PLAYTEST|SCRIPT ERROR|ERROR:" "$log" | grep -v "resources still in use\|ObjectDB instances leaked" || true
grep -q "^PLAYTEST PASS" "$log" || { echo "playtest.sh: $name did not pass (exit $code)" >&2; exit 1; }
