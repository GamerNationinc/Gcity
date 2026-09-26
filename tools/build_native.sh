#!/usr/bin/env bash
# Builds the native terrain mesher (native/terrain_mesher, ADR-003 option B; M7 spec claim
# 16) with the pinned Rust toolchain and the locked crates, and installs it with its
# .gdextension into addons/terrain_mesher/. Neither is committed (see .gitignore): with no
# Rust toolchain the client falls back to the GDScript mesher (client/terrain/surface_nets.gd),
# which gives the same mesh, slower. Usage: tools/build_native.sh
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
crate="$root/native/terrain_mesher"
target="$root/addons/terrain_mesher"
want="$(sed -n 's/^channel = "\(.*\)"/\1/p' "$crate/rust-toolchain.toml")"
if ! command -v cargo >/dev/null; then
	echo "build_native.sh: no cargo on PATH; install Rust $want (rustup) or run without the native mesher" >&2
	exit 1
fi
have="$(cd "$crate" && rustc --version | cut -d' ' -f2)"
if [[ "$have" != "$want" ]]; then
	echo "build_native.sh: rustc $have, but native/terrain_mesher pins $want" >&2
	exit 1
fi
(cd "$crate" && cargo build --release --locked --quiet)
mkdir -p "$target/linux64"
objcopy --strip-debug "$crate/target/release/libterrain_mesher.so" "$target/linux64/libterrain_mesher.so.new"
mv "$target/linux64/libterrain_mesher.so.new" "$target/linux64/libterrain_mesher.so"
cat > "$target/terrain_mesher.gdextension" <<'GDEXT'
[configuration]
entry_symbol = "gdext_rust_init"
compatibility_minimum = 4.6
reloadable = false

[libraries]
linux.debug.x86_64 = "res://addons/terrain_mesher/linux64/libterrain_mesher.so"
linux.release.x86_64 = "res://addons/terrain_mesher/linux64/libterrain_mesher.so"
GDEXT
