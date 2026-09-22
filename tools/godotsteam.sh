#!/usr/bin/env bash
# Installs the pinned GodotSteam GDExtension binaries into addons/godotsteam/, downloading
# and verifying the release zip on first use, and keeping only what ships: the Linux and
# Windows libraries and Valve's redistributable Steam API next to them. The zip's editor
# self-updater is dropped (a pinned dependency does not update itself), and so are the
# platforms we do not build. The manifest and licence are committed; the binaries are
# not (see .gitignore). Usage: tools/godotsteam.sh
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
# shellcheck disable=SC1091
source "$here/godotsteam.pin"

cache="${GODOT_CACHE_DIR:-$root/.cache/godot}"
archive="$cache/godotsteam-${GODOTSTEAM_VERSION}-gdextension.zip"
target="$root/addons/godotsteam"
stamp="$target/.installed-${GODOTSTEAM_VERSION}"

if [[ -f "$stamp" ]]; then
	echo "$target"
	exit 0
fi
mkdir -p "$cache"
if [[ ! -f "$archive" ]]; then
	echo "godotsteam.sh: downloading $GODOTSTEAM_URL" >&2
	curl --fail --silent --show-error --location --output "$archive" "$GODOTSTEAM_URL"
fi
echo "${GODOTSTEAM_SHA256}  $archive" | sha256sum --check --status \
	|| { echo "godotsteam.sh: SHA-256 mismatch for $archive; refusing to install it" >&2; rm -f "$archive"; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
unzip -q "$archive" -d "$tmp"
mkdir -p "$target/linux64" "$target/win64"
cp "$tmp"/addons/godotsteam/linux64/*.so "$target/linux64/"
cp "$tmp"/addons/godotsteam/win64/*.dll "$target/win64/"
diff -q "$tmp/addons/godotsteam/license.md" "$target/license.md" >/dev/null \
	|| { echo "godotsteam.sh: the release's licence differs from the committed one; review addons/godotsteam/license.md" >&2; exit 1; }
rm -f "$target"/.installed-*
touch "$stamp"
echo "$target"
