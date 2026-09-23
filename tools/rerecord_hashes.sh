#!/usr/bin/env bash
# Re-records every replay fixture's expected_hash, which any content change makes
# necessary because the content digest is hashed into the sim state.
#
#   tools/rerecord_hashes.sh [fixture.json ...]
#
# Written because doing this by hand with a string replace destroyed four fixtures:
# a freshly generated fixture has `"expected_hash": ""`, and replacing the empty
# string inserts the new hash between every character of the file. This edits the
# JSON as JSON, so there is no empty needle to trip over.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
if [[ -z "${GODOT:-}" ]]; then
	GODOT="$(tools/godot.sh)"
fi
fixtures=("$@")
if [[ ${#fixtures[@]} -eq 0 ]]; then
	mapfile -t fixtures < <(find tests/replay -name '*.json' | sort)
fi
for fixture in "${fixtures[@]}"; do
	hash="$("$GODOT" --headless --path . -s tools/replay_hash.gd -- "$fixture" 2>/dev/null | tail -n 1)"
	if [[ ${#hash} -ne 64 ]]; then
		echo "FAIL $fixture: no hash produced" >&2
		exit 1
	fi
	python3 - "$fixture" "$hash" <<'PY'
import json, sys
path, new = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
old = data.get("expected_hash", "")
if old == new:
    print("unchanged  %s" % path)
else:
    data["expected_hash"] = new
    with open(path, "w") as f:
        json.dump(data, f, indent="\t")
        f.write("\n")
    print("re-recorded %s %s" % (path, new))
PY
done
