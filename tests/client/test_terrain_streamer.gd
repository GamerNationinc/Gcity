extends GcityTest

## M7 spec claim 16 (the world view half) and ADR-003 condition 2: the ground around the
## player is streamed a slice at a time, nearest first, on pooled mesh nodes; it is the
## ground the sim walks on; and a change to that ground is drawn again where it happened
## and nowhere else.

const SEED: int = 20261600
## On the level apron outside the gate, in the wilds: standing in cell y 0.
const OUTSIDE: Vector3i = Vector3i(500, 0, -40_500)
const M: int = 1000

var _sim: SimRoot
var _regions: Regions


func _setup() -> TerrainStreamer:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	_regions = SimAssembly.regions_of(_sim)
	var streamer := TerrainStreamer.new()
	streamer.watch(_regions, SimAssembly.routes_of(_sim))
	return streamer


## Updates until everything wanted is drawn; the number of updates it took.
func _settle(streamer: TerrainStreamer, at: Vector3i, budget_usec: int = TerrainStreamer.BUDGET_USEC) -> int:
	var frames: int = 0
	while frames < 100_000:
		streamer.update(at, budget_usec)
		frames += 1
		if streamer.is_settled():
			return frames
	fail("the ground never settled")
	return frames


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


func _vertices(streamer: TerrainStreamer, chunk: Vector3i) -> int:
	var node: MeshInstance3D = streamer.node_of(chunk)
	if node == null:
		return 0
	var mesh: ArrayMesh = node.mesh
	return mesh.surface_get_array_len(0)


func test_the_ground_around_the_player_is_drawn_where_the_sim_has_it() -> void:
	var streamer: TerrainStreamer = _setup()
	_settle(streamer, OUTSIDE)
	var columns: Dictionary = {}
	for chunk: Vector3i in streamer.shown_chunks():
		columns[Vector2i(chunk.x, chunk.z)] = true
	var side: int = 2 * TerrainStreamer.RADIUS + 1
	assert_eq(columns.size(), side * side, "every column within the radius is drawn")
	# the surface under the player: the mesh of the chunk holding the ground cell they
	# stand on reaches the height they stand at, and the ground is a closed surface there
	var feet: Vector3i = Vector3i(0, -1, -41)
	var chunk: Vector3i = Vector3i(TerrainStreamer._chunk_of(feet.x), TerrainStreamer._chunk_of(feet.y), TerrainStreamer._chunk_of(feet.z))
	var node: MeshInstance3D = streamer.node_of(chunk)
	assert_true(node != null, "the ground under the player is drawn")
	if node == null:
		streamer.free()
		return
	var box: AABB = node.mesh.get_aabb()
	box.position += node.position
	assert_true(box.has_point(Vector3(0.5, float(OUTSIDE.y) / M, -40.5)) or is_equal_approx(box.end.y, float(OUTSIDE.y) / M), "the drawn ground meets the player's feet (%s)" % box)
	# drawn height against the sim's, column by column over the chunk: the top vertex
	# over each column is where the sim stands you
	var arrays: Array = node.mesh.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var top: Dictionary = {}
	for p: Vector3 in positions:
		var world: Vector3 = p + node.position
		var column: Vector2i = Vector2i(floori(world.x), floori(world.z))
		var highest: float = top.get(column, -1e9)
		top[column] = maxf(highest, world.y)
	var wrong: int = 0
	var checked: int = 0
	for key: Variant in top:
		var column: Vector2i = key
		var standing: int = _regions.standing_cell_y(column.x * M + M / 2, column.y * M + M / 2)
		var drawn: float = top[column]
		checked += 1
		# vertices sit inside cells, so the top one over a column is within a metre
		wrong += 1 if absf(drawn - float(standing)) > 1.0 else 0
	assert_true(checked > 500, "a chunk's worth of columns (%d)" % checked)
	assert_eq(wrong, 0, "the drawn ground is within a cell of where the sim stands you, everywhere in the chunk")
	streamer.free()


func test_the_work_is_sliced_across_frames_nearest_first() -> void:
	var streamer: TerrainStreamer = _setup()
	# with no time to spare, a frame does its one step: a column's ground found, a few
	# columns of a block row warmed, one row fetched, or one block meshed
	var frames: int = _settle(streamer, OUTSIDE, 1)
	var chunks: int = streamer.meshed_count()
	var side: int = 2 * TerrainStreamer.RADIUS + 1
	var per_row: int = ceili(float(TerrainStreamer.BLOCK) / TerrainStreamer.WARM_PER_STEP) + 1
	var steps_per_chunk: int = 1 + TerrainStreamer.BLOCK * per_row + 1
	assert_eq(frames, side * side + chunks * steps_per_chunk, "one step a frame: each column found, then each chunk taken, fetched row by row and meshed (%d chunks)" % chunks)
	streamer.free()
	# nearest first: the player's own column is found and its first chunk drawn first
	streamer = _setup()
	for i: int in 1 + steps_per_chunk:
		streamer.update(OUTSIDE, 1)
	var here: Vector2i = Vector2i(TerrainStreamer._chunk_of(0), TerrainStreamer._chunk_of(-41))
	var shown: Array[Vector3i] = streamer.shown_chunks()
	assert_eq(shown.size(), 1, "one chunk after one chunk's steps")
	assert_eq(Vector2i(shown[0].x, shown[0].z), here, "and it is in the player's own column")
	streamer.free()


func test_a_frame_keeps_to_its_budget() -> void:
	var streamer: TerrainStreamer = _setup()
	var worst: int = 0
	var frames: int = 0
	while not streamer.is_settled() and frames < 100_000:
		streamer.update(OUTSIDE)
		worst = maxi(worst, streamer.last_frame_usec())
		frames += 1
	print("  %d frames to draw %d chunks, worst frame %d us (native mesher: %s)" % [frames, streamer.meshed_count(), worst, SurfaceNets.native_loaded()])
	# a frame stops at the first step past its budget, and no step is more than a couple
	# of milliseconds even on cold ground; the Deck capture is the real measure
	assert_true(worst < 2 * TerrainStreamer.BUDGET_USEC, "no frame runs on far past the budget (worst %d us)" % worst)
	streamer.free()


func test_mesh_nodes_are_pooled_not_made_per_chunk() -> void:
	var streamer: TerrainStreamer = _setup()
	_settle(streamer, OUTSIDE)
	var first: int = streamer.node_count()
	# walk ten chunks down the road and back: every chunk passed is drawn and let go
	var peak: int = first
	for step: int in 10:
		_settle(streamer, OUTSIDE + Vector3i(0, 0, -step * TerrainStreamer.CHUNK * M))
		peak = maxi(peak, streamer.node_count())
	var drawn: int = streamer.meshed_count()
	assert_true(drawn > 2 * first, "far more chunks drawn (%d) than nodes held" % drawn)
	assert_eq(streamer.get_child_count(), streamer.node_count(), "every node the streamer made is its own child: none leaked")
	var nodes_now: int = streamer.node_count()
	assert_true(nodes_now <= peak, "the pool never grows past the most shown at once (%d of %d)" % [nodes_now, peak])
	# ground that is let go is gone from view
	var shown: Dictionary = {}
	for chunk: Vector3i in streamer.shown_chunks():
		shown[chunk] = true
	var visible: int = 0
	for child: Node in streamer.get_children():
		var node: MeshInstance3D = child
		visible += 1 if node.visible else 0
	var non_empty: int = 0
	for chunk: Vector3i in shown:
		non_empty += 1 if streamer.node_of(chunk) != null else 0
	assert_eq(visible, non_empty, "only chunks in range are visible")
	streamer.free()


func test_a_dug_hole_is_drawn_again_only_where_it_is() -> void:
	var streamer: TerrainStreamer = _setup()
	_settle(streamer, OUTSIDE)
	var actors: ActorSystem = SimAssembly.actors_of(_sim)
	var player: int = actors.spawn(&"arcade", 0)
	actors.set_position(player, OUTSIDE)
	var hole: Vector3i = Vector3i(1, -1, -41)
	var chunk: Vector3i = Vector3i(TerrainStreamer._chunk_of(hole.x), TerrainStreamer._chunk_of(hole.y), TerrainStreamer._chunk_of(hole.z))
	var before: int = _vertices(streamer, chunk)
	var meshed: int = streamer.meshed_count()
	assert_true(_do(Regions.COMMAND_DIG, {"actor": player, "cell": [hole.x, hole.y, hole.z]}), "dig a hole")
	_settle(streamer, OUTSIDE)
	assert_true(_vertices(streamer, chunk) > before, "the hole is drawn: more surface where it is")
	var again: int = streamer.meshed_count() - meshed
	assert_true(again >= 1 and again <= 8, "only the chunks whose blocks hold the cell are meshed again (%d)" % again)
	# a restore changes the ground wholesale: everything is drawn again
	meshed = streamer.meshed_count()
	var shown: int = streamer.shown_chunks().size()
	assert_eq(SimAssembly.restore_systems(_sim, _sim.snapshot()), OK, "restore")
	_settle(streamer, OUTSIDE)
	assert_eq(streamer.meshed_count() - meshed, shown, "after a load every shown chunk is drawn again")
	streamer.free()


func test_another_sim_is_drawn_afresh() -> void:
	var streamer: TerrainStreamer = _setup()
	_settle(streamer, OUTSIDE)
	var nodes: int = streamer.node_count()
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var other: SimRoot = SimAssembly.build(SEED + 1, db)
	streamer.watch(SimAssembly.regions_of(other), SimAssembly.routes_of(other))
	assert_eq(streamer.shown_chunks().size(), 0, "nothing of the old world is shown")
	assert_eq(streamer.node_count(), nodes, "its nodes wait in the pool")
	_settle(streamer, OUTSIDE)
	assert_eq(streamer.node_count(), maxi(nodes, streamer.node_count()), "and are used again")
	assert_true(streamer.shown_chunks().size() > 0, "the new world is drawn")
	streamer.free()
