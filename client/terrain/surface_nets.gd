## Chunk meshing for the wild region (M7 spec claim 16; ADR-003 option B). The native
## `TerrainMesher` (native/terrain_mesher, built by tools/build_native.sh) is used when it
## is loaded; otherwise this file's GDScript port of the same surface nets, which gives
## the same mesh (tests/client/test_surface_nets.gd holds them to it) many times slower.
## The port exists so the game and the tests run without a Rust toolchain; the Deck build
## ships the native one.
##
## A block is S³ solid bytes (non-zero = solid), x fastest then y then z, exactly as
## `Regions.solids` returns them for a chunk's cells plus one on each side. The mesh is
## `{positions, normals, indices}`, positions relative to the chunk's first cell: sample 1
## is offset 0. Front faces are clockwise, as Godot draws them.
class_name SurfaceNets extends RefCounted

const NATIVE: StringName = &"TerrainMesher"
## Cells per chunk axis, and samples per block axis.
const N: int = 32
const S: int = N + 2
const S3: int = S * S * S
## Sample-to-sample cells per block axis.
const C: int = S - 1
const EDGES: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(2, 3), Vector2i(4, 5), Vector2i(6, 7),
	Vector2i(0, 2), Vector2i(1, 3), Vector2i(4, 6), Vector2i(5, 7),
	Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7),
]


static func native_loaded() -> bool:
	return ClassDB.class_exists(NATIVE)


## The mesh of a block, from the native mesher if it is loaded. Empty (with an error)
## for a block of the wrong size.
static func mesh(solids: PackedByteArray) -> Dictionary:
	if solids.size() != S3:
		push_error("SurfaceNets.mesh: expected %d bytes, got %d" % [S3, solids.size()])
		return {}
	if native_loaded():
		return ClassDB.class_call_static(NATIVE, &"mesh", solids)
	return mesh_gd(solids)


## The GDScript port. Empty (with an error) for a block of the wrong size.
static func mesh_gd(solids: PackedByteArray) -> Dictionary:
	if solids.size() != S3:
		push_error("SurfaceNets.mesh_gd: expected %d bytes, got %d" % [S3, solids.size()])
		return {}
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var cell_vertex := PackedInt32Array()
	cell_vertex.resize(C * C * C)
	cell_vertex.fill(-1)
	var d: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for z: int in C:
		for y: int in C:
			for x: int in C:
				var mask: int = 0
				for i: int in 8:
					var solid: bool = solids[(x + (i & 1)) + S * ((y + ((i >> 1) & 1)) + S * (z + ((i >> 2) & 1)))] != 0
					d[i] = -1.0 if solid else 1.0
					if solid:
						mask |= 1 << i
				if mask == 0 or mask == 0xff:
					continue
				var sum := Vector3.ZERO
				var count: float = 0.0
				for e: Vector2i in EDGES:
					var da: float = d[e.x]
					var db: float = d[e.y]
					if (da < 0.0) == (db < 0.0):
						continue
					var t: float = da / (da - db)
					var a := Vector3(e.x & 1, (e.x >> 1) & 1, (e.x >> 2) & 1)
					var b := Vector3(e.y & 1, (e.y >> 1) & 1, (e.y >> 2) & 1)
					sum += a + t * (b - a)
					count += 1.0
				positions.append(Vector3(x - 1, y - 1, z - 1) + sum / count)
				var g := Vector3(
					(d[1] + d[3] + d[5] + d[7]) - (d[0] + d[2] + d[4] + d[6]),
					(d[2] + d[3] + d[6] + d[7]) - (d[0] + d[1] + d[4] + d[5]),
					(d[4] + d[5] + d[6] + d[7]) - (d[0] + d[1] + d[2] + d[3]))
				normals.append(g / maxf(g.length(), 1e-12))
				cell_vertex[x + C * (y + C * z)] = positions.size() - 1
	var indices := PackedInt32Array()
	# Quads for edges whose base sample is interior (1..N on every axis): each edge of the
	# world is owned by exactly one chunk, which is what makes seams watertight.
	var steps: Array[int] = [1, S, S * S]
	# per axis, the (u, v) cell steps that make (u, v, axis) right-handed
	var us: Array[int] = [C, C * C, 1]
	var vs: Array[int] = [C * C, 1, C]
	for z: int in range(1, N + 1):
		for y: int in range(1, N + 1):
			for x: int in range(1, N + 1):
				var here: int = x + S * (y + S * z)
				var a_solid: bool = solids[here] != 0
				var cell: int = x + C * (y + C * z)
				for axis: int in 3:
					if a_solid == (solids[here + steps[axis]] != 0):
						continue
					var q0: int = cell_vertex[cell - us[axis] - vs[axis]]
					var q1: int = cell_vertex[cell - vs[axis]]
					var q2: int = cell_vertex[cell]
					var q3: int = cell_vertex[cell - us[axis]]
					# (q0,q1,q2),(q0,q2,q3) is counter-clockwise seen from +axis; Godot's
					# front face is clockwise, so the +axis-facing case (a solid) reverses
					if a_solid:
						indices.append_array([q0, q2, q1, q0, q3, q2])
					else:
						indices.append_array([q0, q1, q2, q0, q2, q3])
	return {"positions": positions, "normals": normals, "indices": indices}
