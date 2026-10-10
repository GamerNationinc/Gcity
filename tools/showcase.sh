#!/usr/bin/env bash
# Renders a showcase scenario (tools/showcase/scenarios/<name>.gd) under a virtual
# display and writes an animated GIF plus a PNG of its last frame: a view of sim work
# that someone who does not read code can check (CLAUDE.md, "Screenshots").
#   tools/showcase.sh <scenario> <out.gif>
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
scenario="${1:?usage: tools/showcase.sh <scenario> <out.gif>}"
out="${2:?usage: tools/showcase.sh <scenario> <out.gif>}"
godot="${GODOT:-$(tools/godot.sh)}"
case "$out" in /*) abs="$out" ;; *) abs="$root/$out" ;; esac
mkdir -p "$(dirname "$abs")"
frames="$(mktemp -d)"
trap 'rm -rf "$frames"' EXIT
xvfb-run -a -s "-screen 0 1280x800x24" "$godot" --path . res://tools/showcase/showcase.tscn \
	--rendering-driver opengl3 --audio-driver Dummy --resolution 1280x800 \
	-- "--scenario=$scenario" "--frames=$frames" 2>&1 | grep -E "SCRIPT ERROR|ERROR" || true
count="$(find "$frames" -name 'f*.png' | wc -l)"
[[ "$count" -gt 0 ]] || { echo "showcase.sh: no frames rendered" >&2; exit 1; }
ffmpeg -loglevel error -y -framerate 10 -i "$frames/f%05d.png" \
	-vf "scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
	-loop 0 "$abs"
last="$(find "$frames" -name 'f*.png' | sort | tail -1)"
cp "$last" "${abs%.gif}-last.png"
echo "$abs ($count frames)"
