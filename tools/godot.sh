#!/usr/bin/env bash
# Prints the path to the pinned Godot binary, downloading and verifying it on first use.
# Usage: GODOT=$(tools/godot.sh)
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
# shellcheck disable=SC1091
source "$here/godot.pin"

cache="${GODOT_CACHE_DIR:-$root/.cache/godot}"
binary="$cache/Godot_v${GODOT_VERSION}_linux.x86_64"
archive="$binary.zip"
url="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip"

if [[ ! -x "$binary" ]]; then
	mkdir -p "$cache"
	echo "godot.sh: downloading $url" >&2
	curl --fail --silent --show-error --location --output "$archive" "$url"
	echo "${GODOT_LINUX_SHA256}  $archive" | sha256sum --check --status \
		|| { echo "godot.sh: SHA-256 mismatch for $archive; refusing to run it" >&2; rm -f "$archive"; exit 1; }
	unzip -o -q "$archive" -d "$cache"
	rm -f "$archive"
	chmod +x "$binary"
fi
echo "$binary"
