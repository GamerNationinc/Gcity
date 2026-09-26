extends GcityTest

## M7 spec claim 16 (the world view half), ADR-003 option B: the wild region's chunks are
## meshed by surface nets. The mesh is closed where the ground is, faces outward, meets
## its neighbour's without a crack, and the native mesher and the GDScript port give the
## same one — the native one at least five times faster (standards §9.2's pass metric).

const S: int = SurfaceNets.S
const N: int = SurfaceNets.N


static func _block(solid: Callable) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(SurfaceNets.S3)
	var i: int = 0
	for z: int in S:
		for y: int in S:
			for x: int in S:
				var v: bool = solid.call(x, y, z)
				out[i] = 1 if v else 0
				i += 1
	return out


## A ball of ground centred on a sample, in the block's own sample coordinates.
static func _ball(cx: int, cy: int, cz: int, r: int) -> Callable:
	return func(x: int, y: int, z: int) -> bool:
		return (x - cx) * (x - cx) + (y - cy) * (y - cy) + (z - cz) * (z - cz) < r * r


## Rolling ground with an overhang and a cave, from a seed: the shapes terrain makes.
static func _hills(seed_value: int) -> Callable:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var a: float = rng.randf_range(2.0, 9.0)
	var fx: float = rng.randf_range(0.05, 0.4)
	var fz: float = rng.randf_range(0.05, 0.4)
	var base: int = rng.randi_range(8, 24)
	var cave := Vector3i(rng.randi_range(4, 30), rng.randi_range(2, base), rng.randi_range(4, 30))
	return func(x: int, y: int, z: int) -> bool:
		var h: float = base + a * sin(x * fx) * cos(z * fz)
		var in_cave: bool = (Vector3i(x, y, z) - cave).length_squared() < 16
		return y < h and not in_cave


## Each undirected edge of a triangle list, keyed by its end positions (rounded), with how
## many triangles use it: 2 everywhere on a closed surface.
static func _edge_uses(meshes: Array[Dictionary], offsets: Array[Vector3]) -> Dictionary:
	var uses: Dictionary = {}
	for m: int in meshes.size():
		var positions: PackedVector3Array = meshes[m]["positions"]
		var indices: PackedInt32Array = meshes[m]["indices"]
		for t: int in range(0, indices.size(), 3):
			for k: int in 3:
				var a: Vector3 = positions[indices[t + k]] + offsets[m]
				var b: Vector3 = positions[indices[t + (k + 1) % 3]] + offsets[m]
				var ka: Vector3i = Vector3i((a * 1000.0).round())
				var kb: Vector3i = Vector3i((b * 1000.0).round())
				var key: Array = [ka, kb] if [ka.x, ka.y, ka.z] < [kb.x, kb.y, kb.z] else [kb, ka]
				uses[key] = uses.get(key, 0) + 1
	return uses


func test_empty_and_full_ground_have_no_surface() -> void:
	for solid: bool in [false, true]:
		var mesh: Dictionary = SurfaceNets.mesh_gd(_block(func(_x: int, _y: int, _z: int) -> bool: return solid))
		var indices: PackedInt32Array = mesh["indices"]
		assert_eq(indices.size(), 0, "a block all %s has no surface" % ("ground" if solid else "air"))


func test_flat_ground_is_one_upward_quad_per_cell() -> void:
	var mesh: Dictionary = SurfaceNets.mesh_gd(_block(func(_x: int, y: int, _z: int) -> bool: return y < 10))
	var indices: PackedInt32Array = mesh["indices"]
	var normals: PackedVector3Array = mesh["normals"]
	var positions: PackedVector3Array = mesh["positions"]
	assert_eq(indices.size(), N * N * 6, "one quad over each of the chunk's cells")
	var up: int = 0
	for n: Vector3 in normals:
		up += 1 if n.y > 0.99 else 0
	assert_eq(up, normals.size(), "every normal faces up")
	# the surface sits halfway between the last solid sample (9) and the first air (10),
	# which is 8.5 in chunk coordinates (sample 1 is offset 0)
	for p: Vector3 in positions:
		if not is_equal_approx(p.y, 8.5):
			fail("a floor vertex at height %s, not 8.5" % p.y)
			return
	assert_true(true, "the floor is flat at the solid-air boundary")


func test_a_closed_shape_is_watertight_and_faces_out() -> void:
	var mesh: Dictionary = SurfaceNets.mesh_gd(_block(_ball(17, 17, 17, 10)))
	var uses: Dictionary = _edge_uses([mesh], [Vector3.ZERO])
	assert_true(uses.size() > 100, "the ball has a surface (%d edges)" % uses.size())
	var bad: int = 0
	for v: Variant in uses.values():
		var n: int = v
		bad += 1 if n != 2 else 0
	assert_eq(bad, 0, "every edge of the ball is shared by exactly two triangles")
	var positions: PackedVector3Array = mesh["positions"]
	var normals: PackedVector3Array = mesh["normals"]
	var indices: PackedInt32Array = mesh["indices"]
	var inward: int = 0
	for t: int in range(0, indices.size(), 3):
		var a: Vector3 = positions[indices[t]]
		var b: Vector3 = positions[indices[t + 1]]
		var c: Vector3 = positions[indices[t + 2]]
		var outward: Vector3 = normals[indices[t]] + normals[indices[t + 1]] + normals[indices[t + 2]]
		# clockwise seen from outside, so the right-hand normal points in
		inward += 1 if (b - a).cross(c - a).dot(outward) < 0.0 else 0
	assert_eq(inward, indices.size() / 3, "every triangle is clockwise seen from the air side, as Godot draws front faces")


func test_neighbouring_chunks_meet_without_a_crack() -> void:
	# one ball across the face between chunk 0 and chunk 1 on x: each block holds its own
	# cells plus one either side, so chunk 1's sample x is chunk 0's sample x + N
	var meshes: Array[Dictionary] = []
	var offsets: Array[Vector3] = []
	for chunk: int in 2:
		var shift: int = chunk * N
		var ball: Callable = _ball(N + 1 - shift, 17, 17, 9)
		meshes.append(SurfaceNets.mesh_gd(_block(ball)))
		offsets.append(Vector3(shift, 0.0, 0.0))
	var uses: Dictionary = _edge_uses(meshes, offsets)
	var bad: int = 0
	for v: Variant in uses.values():
		var n: int = v
		bad += 1 if n != 2 else 0
	assert_true(uses.size() > 100, "the ball has a surface (%d edges)" % uses.size())
	assert_eq(bad, 0, "the two chunks' meshes join into one closed surface: no edge is open or doubled")


func test_a_block_of_the_wrong_size_is_refused() -> void:
	var short := PackedByteArray()
	short.resize(SurfaceNets.S3 - 1)
	assert_true(SurfaceNets.mesh(short).is_empty(), "a block one byte short meshes to nothing")
	assert_true(SurfaceNets.mesh_gd(short).is_empty(), "and so does the port")


func test_the_native_mesher_and_the_port_give_the_same_mesh() -> void:
	if not SurfaceNets.native_loaded():
		# the native library is optional (tools/build_native.sh); say so rather than pass
		print("  (native TerrainMesher not loaded: the port is checked alone)")
		return
	var blocks: Array[PackedByteArray] = [_block(_ball(17, 17, 17, 10))]
	for seed_value: int in 12:
		blocks.append(_block(_hills(9000 + seed_value)))
	var native_usec: int = 0
	var port_usec: int = 0
	for block: PackedByteArray in blocks:
		var t0: int = Time.get_ticks_usec()
		var native: Dictionary = SurfaceNets.mesh(block)
		var t1: int = Time.get_ticks_usec()
		var port: Dictionary = SurfaceNets.mesh_gd(block)
		port_usec += Time.get_ticks_usec() - t1
		native_usec += t1 - t0
		var ni: PackedInt32Array = native["indices"]
		var pi: PackedInt32Array = port["indices"]
		assert_eq(ni, pi, "the same triangles")
		var np: PackedVector3Array = native["positions"]
		var pp: PackedVector3Array = port["positions"]
		var nn: PackedVector3Array = native["normals"]
		var pn: PackedVector3Array = port["normals"]
		assert_eq(np.size(), pp.size(), "the same number of vertices")
		var worst: float = 0.0
		for i: int in mini(np.size(), pp.size()):
			worst = maxf(worst, maxf((np[i] - pp[i]).length(), (nn[i] - pn[i]).length()))
		assert_true(worst < 1e-5, "the same vertices and normals, to float precision (worst %s)" % worst)
	print("  native %d us, port %d us over %d blocks" % [native_usec, port_usec, blocks.size()])
	assert_true(native_usec * 5 <= port_usec, "the native mesher is at least 5x the port (%d us vs %d us)" % [native_usec, port_usec])
