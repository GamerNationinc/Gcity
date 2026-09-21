#!/usr/bin/env bash
# Exports the native Linux build (standards §8.1) with the pinned engine and the pinned,
# hash-verified export templates. tests/, tools/, docs/ and spikes/ are excluded by the
# preset (M0 debt item 9). Usage: tools/export.sh [output path]
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
# shellcheck disable=SC1091
source tools/godot.pin
godot="$(tools/godot.sh)"
out="${1:-build/linux/gcity.x86_64}"

cache="${GODOT_CACHE_DIR:-$root/.cache/godot}"
templates_dir="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${GODOT_VERSION}"
archive="$cache/Godot_v${GODOT_VERSION}_export_templates.tpz"
if [[ ! -f "$templates_dir/linux_release.x86_64" ]]; then
	if [[ ! -f "$archive" ]]; then
		echo "export.sh: downloading export templates for ${GODOT_VERSION}" >&2
		curl --fail --silent --show-error --location --output "$archive" \
			"https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_export_templates.tpz"
	fi
	echo "${GODOT_TEMPLATES_SHA512}  $archive" | sha512sum --check --status \
		|| { echo "export.sh: SHA-512 mismatch for $archive; refusing to install it" >&2; exit 1; }
	mkdir -p "$templates_dir"
	unzip -o -q "$archive" -d "$cache/templates_extract"
	cp "$cache/templates_extract/templates/"* "$templates_dir/"
	rm -rf "$cache/templates_extract"
fi

mkdir -p "$(dirname "$out")"
"$godot" --headless --path . --import >/dev/null 2>&1 || true
"$godot" --headless --path . --export-release Linux "$out"
ls -la "$out"
