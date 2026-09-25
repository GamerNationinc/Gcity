## The wild region (design doc §5.1, §5.5; ADR-003 B; M7 design note, regions): ground
## as 1 m voxel cells, the build grid's own cells, derived from the seed.
##
## A cell is solid below the terrain's height at its column (claim 7). Where a road of
## the graph runs, the road is cut in: the cells from the road surface up to
## ROAD_CLEARANCE are air, whether that is a cutting through a hill or a tunnel under a
## ridge, and the cell under the surface is solid, which over a ravine is a bridge deck.
## So every road the graph promises is walkable in the sim's own geometry, not only in
## the arithmetic of claim 7.
##
## Nothing here is state. The ground is a function of the seed and the graph; it is
## worked out a chunk of columns at a time when first asked for and kept in a cache
## that is thrown away whenever the graph changes. Player edits, which are state, arrive
## with claim 15 as chunk deltas on top of this.
class_name WildRegion extends Region

## Columns per chunk side. Also the edit chunk of claim 15.
const CHUNK: int = 16
## How much air a road keeps above its surface, in cells: headroom in a tunnel.
const ROAD_CLEARANCE: int = 4
## A column with no road over it.
const NO_ROAD: int = -1_000_000
## Chunks kept at once. The cache is a convenience, not memory: past this it is simply
## dropped and rebuilt as asked, which changes nothing but time.
const CACHE_CHUNKS: int = 4096

var _terrain: Terrain
var _routes: RouteGraph
var _authored: Array[Region] = []
## Vector2i chunk -> PackedInt32Array, two per column: ground cell, road cell or NO_ROAD
var _columns: Dictionary = {}
var _built_for: Vector2i = Vector2i(-1, -1)


func _init(id: StringName, terrain: Terrain, routes: RouteGraph, authored: Array[Region]) -> void:
	super(id)
	_terrain = terrain
	_routes = routes
	_authored = authored


## Everywhere no authored region covers.
func contains(x: int, z: int) -> bool:
	for region: Region in _authored:
		if region.contains(x, z):
			return false
	return true


func is_solid(cell: Vector3i) -> bool:
	var column: Vector2i = _column(cell.x, cell.z)
	var road: int = column.y
	if road != NO_ROAD:
		if cell.y >= road and cell.y < road + ROAD_CLEARANCE:
			return false
		if cell.y == road - 1:
			return true
	return cell.y < column.x


func stands_on_ground(cell: Vector3i) -> bool:
	return not is_solid(cell) and is_solid(cell - Vector3i(0, 1, 0))


## The road surface where there is a road, the ground where there is not.
func standing_cell_y(x: int, z: int) -> int:
	var column: Vector2i = _column(Terrain._floor_div(x, BuildSystem.CELL), Terrain._floor_div(z, BuildSystem.CELL))
	return column.y if column.y != NO_ROAD else column.x


## Walking uphill: a step may climb one level onto ground.
func step_levels() -> int:
	return 1


# ---------------------------------------------------------------- columns

## (ground cell, road cell) for the column of cells at (cx, cz).
func _column(cx: int, cz: int) -> Vector2i:
	var stamp: Vector2i = Vector2i(_routes.revision(), _terrain.world_seed())
	if stamp != _built_for:
		_columns.clear()
		_built_for = stamp
	var chunk: Vector2i = Vector2i(Terrain._floor_div(cx, CHUNK), Terrain._floor_div(cz, CHUNK))
	if not _columns.has(chunk):
		if _columns.size() >= CACHE_CHUNKS:
			_columns.clear()
		_columns[chunk] = _build_chunk(chunk)
	var data: PackedInt32Array = _columns[chunk]
	var i: int = ((cz - chunk.y * CHUNK) * CHUNK + (cx - chunk.x * CHUNK)) * 2
	return Vector2i(data[i], data[i + 1])


func _build_chunk(chunk: Vector2i) -> PackedInt32Array:
	var c: int = BuildSystem.CELL
	var near: Array[Array] = _roads_near(chunk)
	var data := PackedInt32Array()
	data.resize(CHUNK * CHUNK * 2)
	for dz: int in CHUNK:
		for dx: int in CHUNK:
			var x: int = (chunk.x * CHUNK + dx) * c + c / 2
			var z: int = (chunk.y * CHUNK + dz) * c + c / 2
			var i: int = (dz * CHUNK + dx) * 2
			data[i] = Terrain._floor_div(_terrain.ground_mm(x, z) + c / 2, c)
			data[i + 1] = _road_cell(near, x, z)
	return data


## The road surface cell over a ground position, from the lowest-numbered road whose
## corridor covers it, or NO_ROAD.
func _road_cell(roads: Array[Array], x: int, z: int) -> int:
	for road: Array in roads:
		var along: int = _along_if_on(road, x, z)
		if along >= 0:
			var id: int = road[0]
			return Terrain._floor_div(_terrain.road_mm(id, along) + BuildSystem.CELL / 2, BuildSystem.CELL)
	return NO_ROAD


## How far along a road a position is, if it lies within the road's corridor; else -1.
## A road is [id, a position, b position, width, length], read from the graph once a chunk.
static func _along_if_on(road: Array, x: int, z: int) -> int:
	var pa: Vector2i = road[1]
	var pb: Vector2i = road[2]
	var width: int = road[3]
	var length: int = road[4]
	if length <= 0:
		return -1
	var along: int = clampi(((x - pa.x) * (pb.x - pa.x) + (z - pa.y) * (pb.y - pa.y)) / length, 0, length)
	var px: int = pa.x + (pb.x - pa.x) * along / length
	var pz: int = pa.y + (pb.y - pa.y) * along / length
	if RouteGraph._length_mm(px, pz, x, z) * 2 > width:
		return -1
	return along


## The roads whose corridor could touch a chunk, lowest id first, each as
## [id, a position, b position, width, length].
func _roads_near(chunk: Vector2i) -> Array[Array]:
	var side: int = CHUNK * BuildSystem.CELL
	var cx: int = chunk.x * side + side / 2
	var cz: int = chunk.y * side + side / 2
	var out: Array[Array] = []
	for id: int in _routes.edge_ids():
		var rec: Dictionary = _routes.edge(id)
		var a: int = rec["a"]
		var b: int = rec["b"]
		var width: int = rec["width"]
		var length: int = rec["length"]
		var pa: Vector2i = _routes.position_of(a)
		var pb: Vector2i = _routes.position_of(b)
		if _segment_distance(pa, pb, cx, cz) <= width / 2 + side:
			out.append([id, pa, pb, width, length])
	return out


static func _segment_distance(pa: Vector2i, pb: Vector2i, x: int, z: int) -> int:
	var length: int = RouteGraph._length_mm(pa.x, pa.y, pb.x, pb.y)
	if length <= 0:
		return RouteGraph._length_mm(pa.x, pa.y, x, z)
	var along: int = clampi(((x - pa.x) * (pb.x - pa.x) + (z - pa.y) * (pb.y - pa.y)) / length, 0, length)
	var px: int = pa.x + (pb.x - pa.x) * along / length
	var pz: int = pa.y + (pb.y - pa.y) * along / length
	return RouteGraph._length_mm(px, pz, x, z)
