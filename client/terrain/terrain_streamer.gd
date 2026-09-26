## The ground around the player, drawn (M7 spec claim 16; ADR-003 option B and its
## condition 2). Chunks of CHUNK³ cells within RADIUS chunks of the player are asked of
## the sim a few rows at a time (`Regions.solids`), meshed by surface nets
## ([SurfaceNets]) and shown on mesh nodes taken from a pool and given back to it, never
## made and freed per chunk. All of it runs inside a time budget per frame: the frame
## budget contract gives chunk meshing and streaming 3.0 ms (standards §4.1), and a
## frame that runs out stops between rows and carries on next frame.
##
## Nearest chunks first. A chunk whose ground changes — an edit, a site's levelling,
## anything `Regions` logs — is fetched and meshed again and keeps its old mesh until the
## new one is ready; a change the log cannot account for (a load, a new road) redraws
## everything the same way. Reads the sim, writes nothing to it.
class_name TerrainStreamer extends Node3D

const CHUNK: int = SurfaceNets.N
## Samples per block axis: the chunk's cells and one either side.
const BLOCK: int = SurfaceNets.S
## Chunks drawn out from the player's own, on each horizontal axis.
const RADIUS: int = 3
## Chunk and streaming budget per frame, standards §4.1.
const BUDGET_USEC: int = 3000
## Columns of a block row whose ground is looked up (and so cached) in one step.
const WARM_PER_STEP: int = 3
## A queued column not yet started, in place of a chunk y.
const SEED: int = -2147483648

var _regions: Regions
var _routes: RouteGraph
var _material: StandardMaterial3D
## Vector3i chunk -> MeshInstance3D, or null for a chunk with no surface in it
var _shown: Dictionary = {}
## Vector3i chunk -> true: shown, but its ground has changed since
var _stale: Dictionary = {}
## Vector2i column -> true: started, its ground found
var _columns: Dictionary = {}
var _pool: Array[MeshInstance3D] = []
## Chunks to fetch and columns to start (y = SEED), next last (popped from the back).
var _queue: Array[Vector3i] = []
var _centre: Vector2i = Vector2i(2147483647, 2147483647)
var _ground_seen: int = 0
var _routes_seen: int = -1
## The block being fetched: its chunk, its bytes so far, and the next row.
var _job: Vector3i = Vector3i.ZERO
var _job_bytes: PackedByteArray = PackedByteArray()
var _job_row: int = -1
## How many of the current row's columns are warmed.
var _job_warm: int = 0
## What the last frame did, for the capture and the tests.
var _last_usec: int = 0
var _meshed: int = 0


func _init() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.42, 0.38, 0.3)
	_material.roughness = 0.95


## Draws the ground of this sim from now on; a different sim (a restart, a load) starts
## the drawing afresh.
func watch(regions: Regions, routes: RouteGraph) -> void:
	if regions == _regions:
		return
	_regions = regions
	_routes = routes
	for chunk: Vector3i in _shown.keys():
		_release(chunk)
	_stale.clear()
	_columns.clear()
	_queue.clear()
	_job_row = -1
	_centre = Vector2i(2147483647, 2147483647)
	_ground_seen = regions.ground_revision()
	_routes_seen = routes.revision()


## One frame's streaming around a position in millimetres: steps of work until
## `budget_usec` is spent, and always at least one.
func update(at_mm: Vector3i, budget_usec: int = BUDGET_USEC) -> void:
	var start: int = Time.get_ticks_usec()
	if _regions == null:
		return
	_take_changes()
	var centre: Vector2i = Vector2i(_chunk_of(Terrain._floor_div(at_mm.x, BuildSystem.CELL)), _chunk_of(Terrain._floor_div(at_mm.z, BuildSystem.CELL)))
	if centre != _centre or _queue.is_empty() and _job_row < 0 and not _stale.is_empty():
		_centre = centre
		_plan()
	# at least one step a frame, however tight the budget, so the ground always arrives
	while _step():
		if Time.get_ticks_usec() - start >= budget_usec:
			break
	_last_usec = Time.get_ticks_usec() - start


## Everything wanted is shown and up to date.
func is_settled() -> bool:
	return _centre.x != 2147483647 and _queue.is_empty() and _job_row < 0 and _stale.is_empty()


func last_frame_usec() -> int:
	return _last_usec


func meshed_count() -> int:
	return _meshed


func shown_chunks() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for key: Variant in _shown:
		var chunk: Vector3i = key
		out.append(chunk)
	return out


## The mesh node drawing a chunk, or null for none (nothing there, or not yet).
func node_of(chunk: Vector3i) -> MeshInstance3D:
	var node: Variant = _shown.get(chunk)
	if node == null:
		return null
	var mesh_node: MeshInstance3D = node
	return mesh_node


## Mesh nodes made, in use or waiting in the pool: the pool's whole size.
func node_count() -> int:
	var n: int = _pool.size()
	for node: Variant in _shown.values():
		n += 1 if node != null else 0
	return n


# ---------------------------------------------------------------- planning

static func _chunk_of(cell: int) -> int:
	return Terrain._floor_div(cell, CHUNK)


## What changed in the ground since the last frame marks its chunks stale: every chunk
## whose block holds the cell, which near a face or edge is up to eight. A block half
## fetched when its ground changes starts again.
func _take_changes() -> void:
	if _routes.revision() != _routes_seen or not _regions.ground_log_reaches(_ground_seen):
		_routes_seen = _routes.revision()
		for chunk: Vector3i in _shown.keys():
			_stale[chunk] = true
		_restart_job()
	else:
		for cell: Vector3i in _regions.ground_edits_since(_ground_seen):
			for dx: int in [-1, 0, 1]:
				for dy: int in [-1, 0, 1]:
					for dz: int in [-1, 0, 1]:
						var chunk: Vector3i = Vector3i(_chunk_of(cell.x + dx), _chunk_of(cell.y + dy), _chunk_of(cell.z + dz))
						if _shown.has(chunk):
							_stale[chunk] = true
						if _job_row >= 0 and chunk == _job:
							_restart_job()
	_ground_seen = _regions.ground_revision()


func _restart_job() -> void:
	if _job_row >= 0:
		_job_bytes = PackedByteArray()
		_job_row = 0
		_job_warm = 0


## The work around the centre, nearest last: a column not yet started is found (SEED),
## a stale chunk fetched again. Chunks out of range go back to the pool. Cheap: nothing
## here asks the sim anything.
func _plan() -> void:
	var order: Array[Vector3i] = []
	var in_range: Dictionary = {}
	for dx: int in range(-RADIUS, RADIUS + 1):
		for dz: int in range(-RADIUS, RADIUS + 1):
			var column: Vector2i = _centre + Vector2i(dx, dz)
			in_range[column] = true
			if not _columns.has(column):
				order.append(Vector3i(column.x, SEED, column.y))
	for chunk: Vector3i in _shown.keys():
		if not in_range.has(Vector2i(chunk.x, chunk.z)):
			_release(chunk)
		elif _stale.has(chunk):
			order.append(chunk)
	for key: Variant in _columns.keys():
		var column: Vector2i = key
		if not in_range.has(column):
			_columns.erase(column)
	var centre: Vector2i = _centre
	order.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		var da: int = (a.x - centre.x) * (a.x - centre.x) + (a.z - centre.y) * (a.z - centre.y)
		var db: int = (b.x - centre.x) * (b.x - centre.x) + (b.z - centre.y) * (b.z - centre.y)
		return da > db if da != db else [a.x, a.y, a.z] > [b.x, b.y, b.z])
	_queue = order


# ---------------------------------------------------------------- work

## One step of work, each a millisecond or so even on cold ground: where a column's
## ground is; a few of a block row's columns warmed; a row of a block fetched; or a block
## meshed. False when there is nothing to do.
func _step() -> bool:
	if _job_row < 0:
		if _queue.is_empty():
			return false
		var next: Vector3i = _queue.pop_back()
		if next.y == SEED:
			# the chunk the column's ground is in; the ground's full height is found
			# from there, a chunk up or down at a time, by what each block holds
			var column: Vector2i = Vector2i(next.x, next.z)
			_columns[column] = true
			var x: int = (column.x * CHUNK + CHUNK / 2) * BuildSystem.CELL
			var z: int = (column.y * CHUNK + CHUNK / 2) * BuildSystem.CELL
			_queue.append(Vector3i(column.x, _chunk_of(_regions.standing_cell_y(x, z)), column.y))
			return true
		if _shown.has(next) and not _stale.has(next):
			return true
		_job = next
		_job_bytes = PackedByteArray()
		_job_row = 0
		_job_warm = 0
		return true
	var origin: Vector3i = _job * CHUNK - Vector3i.ONE
	if _job_row < BLOCK:
		if _job_warm < BLOCK:
			# asking a column's ground once caches it: do it a few columns at a time, so
			# the row itself is read warm
			for i: int in mini(WARM_PER_STEP, BLOCK - _job_warm):
				_regions.standing_cell_y((origin.x + _job_warm + i) * BuildSystem.CELL, (origin.z + _job_row) * BuildSystem.CELL)
			_job_warm += WARM_PER_STEP
			return true
		# x fastest then y then z: rows stacked along z append as they come
		_job_bytes.append_array(_regions.solids(origin + Vector3i(0, 0, _job_row), Vector3i(BLOCK, BLOCK, 1)))
		_job_row += 1
		_job_warm = 0
		return true
	_show(_job, SurfaceNets.mesh(_job_bytes))
	_stale.erase(_job)
	_grow(_job, _job_bytes)
	_job_row = -1
	_meshed += 1
	return true


## The chunks over and under this one that the ground goes on into: above, if its top
## sample layer (the next chunk's first cells) holds any ground; below, if its bottom two
## hold any air. So a column is drawn from the lowest air to the highest ground in it —
## a cutting, a tunnel's floor, a bridge's deck — and no further.
func _grow(chunk: Vector3i, bytes: PackedByteArray) -> void:
	var plane: int = BLOCK * BLOCK
	var up: bool = false
	var down: bool = false
	for z: int in BLOCK:
		for x: int in BLOCK:
			var column: int = z * plane + x
			up = up or bytes[column + (BLOCK - 1) * BLOCK] != 0
			down = down or bytes[column] == 0 or bytes[column + BLOCK] == 0
	for next: Vector3i in [chunk + Vector3i.UP, chunk + Vector3i.DOWN]:
		var wanted: bool = up if next.y > chunk.y else down
		if wanted and not _shown.has(next) and not _queue.has(next):
			_queue.append(next)


func _show(chunk: Vector3i, mesh: Dictionary) -> void:
	var indices: PackedInt32Array = mesh.get("indices", PackedInt32Array())
	if indices.is_empty():
		_release(chunk)
		_shown[chunk] = null
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mesh["positions"]
	arrays[Mesh.ARRAY_NORMAL] = mesh["normals"]
	arrays[Mesh.ARRAY_INDEX] = indices
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node: MeshInstance3D = node_of(chunk)
	if node == null:
		node = _take()
		_shown[chunk] = node
	node.mesh = array_mesh
	# cell centres: sample 1 is the chunk's first cell, whose centre is half a metre in
	node.position = Vector3(chunk * CHUNK) + Vector3(0.5, 0.5, 0.5)
	node.visible = true


func _take() -> MeshInstance3D:
	if not _pool.is_empty():
		return _pool.pop_back()
	var node := MeshInstance3D.new()
	node.material_override = _material
	add_child(node)
	return node


func _release(chunk: Vector3i) -> void:
	var node: MeshInstance3D = node_of(chunk)
	_shown.erase(chunk)
	_stale.erase(chunk)
	if node != null:
		node.visible = false
		node.mesh = null
		_pool.append(node)
