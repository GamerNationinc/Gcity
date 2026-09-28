## The stealth run the world view's demo plays (M6 spec claim 13): the under route
## through Cold Storage, end to end, as a list of steps the view walks one at a time.
## Since M7 claim 10 the building stands where the contract bound it, out in the wilds,
## so the run begins with [travel]: through the gate, down the road and round the lot
## to the street, the same way `tools/make_m6_fixtures.gd` walks it.
##
## This is the same route `tools/make_m6_fixtures.gd` records as `m6-stealth`, written
## again here rather than read from it, because `tests/` is not in the export and a
## demo that only runs from a source checkout is not a demo. The fixture is what proves
## the run is clean; this is what shows it.
class_name MissionDemo extends RefCounted

const SITE: StringName = &"cold_storage"
## The cell south of the building the roamer must be past before the hall is crossed.
const HALL_LINE: int = 4
## Long enough for the roamer's loop, short enough that the demo does not stall.
const PATIENCE: int = 900

## The city side of the gate's opening.
const GATE_IN: Vector3i = Vector3i(500, 0, 500)
## How far outside the building the ring round the lot runs, in cells: well inside
## the ground its raising levelled.
const RING: int = 4
const M: int = 1000

enum Step { WALK, CLIMB, CUT, HACK, WIPE, PATCH, WAIT_CLEAR, DONE, POINT, GATE }


## The walk from the city to the building's street, as steps: to the gate and through
## it, along the graph's own road to where the building's track meets the ring round
## the lot, round the ring by its corners to its south side, and up to the street.
## POINT steps are world positions on the ground plane; `axis` walks one axis at a time.
static func travel(sim: SimRoot) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"do": Step.POINT, "at": Vector2i(GATE_IN.x, GATE_IN.z), "axis": true})
	out.append({"do": Step.GATE, "region": "wilds"})
	out.append({"do": Step.POINT, "at": Vector2i(GATE_IN.x, -GATE_IN.z)})
	for point: Vector2i in _the_road(sim):
		out.append({"do": Step.POINT, "at": point})
	var r: Array[int] = _ring(sim)
	var street: Vector3i = SimAssembly.sites_of(sim).cell_of(SITE, Vector3i(4, 0, -5))
	var track_end: Vector2i = Vector2i(GATE_IN.x, -GATE_IN.z)
	if out.size() > 3:
		var last: Dictionary = out[out.size() - 1]
		track_end = last["at"]
	var cell: Vector2i = Vector2i(clampi(Terrain._floor_div(track_end.x, M), r[0], r[2]), clampi(Terrain._floor_div(track_end.y, M), r[1], r[3]))
	# onto the ring at its nearest side, then round the corners to its south side
	var to_side: Array[int] = [cell.x - r[0], r[2] - cell.x, cell.y - r[1], r[3] - cell.y]
	match to_side.find(to_side.min()):
		0: cell.x = r[0]
		1: cell.x = r[2]
		2: cell.y = r[1]
		_: cell.y = r[3]
	out.append({"do": Step.POINT, "at": _centre_of(cell), "axis": true})
	for i: int in 4:
		if cell.y == r[1]:
			break
		cell = _next_corner(cell, r)
		out.append({"do": Step.POINT, "at": _centre_of(cell), "axis": true})
	out.append({"do": Step.POINT, "at": _centre_of(Vector2i(street.x, r[1])), "axis": true})
	return out


## Points two metres apart along the graph's roads from just outside the gate to where
## the bound site's track reaches the ring round the lot.
static func _the_road(sim: SimRoot) -> Array[Vector2i]:
	var routes: RouteGraph = SimAssembly.routes_of(sim)
	var terrain: Terrain = SimAssembly.terrain_of(sim)
	var site_node: int = SimAssembly.binder_of(sim).node_of(SITE)
	var out: Array[Vector2i] = []
	if site_node == EntityIds.NONE:
		return out
	var r: Array[int] = _ring(sim)
	var path: Array[int] = routes.path_between(1, site_node)
	for i: int in path.size() - 1:
		var a: int = path[i]
		var b: int = path[i + 1]
		var id: int = routes.edge_between(a, b)
		var rec: Dictionary = routes.edge(id)
		var length: int = rec["length"]
		var first: int = rec["a"]
		var forward: bool = first == a
		var along: int = 2 * M
		while along < length:
			var point: Vector2i = terrain.road_at(id, along if forward else length - along)
			if b == site_node and _in_ring(point, r):
				return out
			out.append(point)
			along += 2 * M
	return out


## The ring round the building, [min x, min z, max x, max z] in cells.
static func _ring(sim: SimRoot) -> Array[int]:
	var sites: SiteSystem = SimAssembly.sites_of(sim)
	var t: Dictionary = SimAssembly.content_of(sim).get_entry(SiteSystem.KIND_SITE, SITE)
	var base: Vector3i = sites.base_of(SITE)
	var lo: Vector2i = Vector2i(1 << 30, 1 << 30)
	var hi: Vector2i = -lo
	for v: Variant in t["pieces"]:
		var piece: Dictionary = v
		var rel: Array = piece["rel"]
		var rx: int = rel[0]
		var rz: int = rel[2]
		lo = Vector2i(mini(lo.x, rx), mini(lo.y, rz))
		hi = Vector2i(maxi(hi.x, rx), maxi(hi.y, rz))
	return [base.x + lo.x - RING, base.z + lo.y - RING, base.x + hi.x + RING, base.z + hi.y + RING]


static func _in_ring(point: Vector2i, r: Array[int]) -> bool:
	var cx: int = Terrain._floor_div(point.x, M)
	var cz: int = Terrain._floor_div(point.y, M)
	return cx >= r[0] and cx <= r[2] and cz >= r[1] and cz <= r[3]


## The next corner of the ring going round anticlockwise from a cell on it.
static func _next_corner(cell: Vector2i, r: Array[int]) -> Vector2i:
	if cell.y == r[1] and cell.x < r[2]:
		return Vector2i(r[2], r[1])
	if cell.x == r[2] and cell.y < r[3]:
		return Vector2i(r[2], r[3])
	if cell.y == r[3] and cell.x > r[0]:
		return Vector2i(r[0], r[3])
	return Vector2i(r[0], r[1])


static func _centre_of(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x * M + M / 2, cell.y * M + M / 2)


## The run, in order. Cells are relative to the site's base.
static func steps() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"do": Step.WALK, "rel": Vector3i(4, 0, -5), "ground": true})
	out.append({"do": Step.CLIMB, "dy": 1})
	out.append({"do": Step.WALK, "rel": Vector3i(4, 1, -4)})
	out.append({"do": Step.WALK, "rel": Vector3i(4, 1, -2)})
	out.append({"do": Step.CUT})
	out.append({"do": Step.CLIMB, "dy": -1})
	for i: int in 10:
		out.append({"do": Step.WALK, "rel": Vector3i(4, 0, -1 + i)})
	out.append({"do": Step.WAIT_CLEAR})
	out.append({"do": Step.CLIMB, "dy": 1})
	out.append({"do": Step.WALK, "rel": Vector3i(3, 1, 8)})
	out.append({"do": Step.WALK, "rel": Vector3i(2, 1, 8)})
	out.append({"do": Step.WALK, "rel": Vector3i(2, 1, 9)})
	out.append({"do": Step.WALK, "rel": Vector3i(1, 1, 10)})
	out.append({"do": Step.HACK})
	out.append({"do": Step.WIPE})
	out.append({"do": Step.WAIT_CLEAR})
	out.append({"do": Step.WALK, "rel": Vector3i(2, 1, 9)})
	out.append({"do": Step.WALK, "rel": Vector3i(2, 1, 8)})
	out.append({"do": Step.WALK, "rel": Vector3i(3, 1, 8)})
	out.append({"do": Step.WALK, "rel": Vector3i(4, 1, 8)})
	out.append({"do": Step.CLIMB, "dy": -1})
	for i: int in 10:
		out.append({"do": Step.WALK, "rel": Vector3i(4, 0, 7 - i)})
	out.append({"do": Step.CLIMB, "dy": 1})
	out.append({"do": Step.PATCH})
	out.append({"do": Step.WALK, "rel": Vector3i(4, 1, -4)})
	out.append({"do": Step.DONE})
	return out


## True when every living guard on the building's ground floor is south of the hall
## line, which is when the back hall can be crossed unseen.
static func hall_is_clear(sim: SimRoot, player: int, operator: int) -> bool:
	var sites: SiteSystem = SimAssembly.sites_of(sim)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var floor_y: int = sites.cell_of(SITE, Vector3i(0, 1, 0)).y
	var line: int = sites.cell_of(SITE, Vector3i(0, 0, HALL_LINE)).z
	for id: int in actors.actor_ids():
		if id == player or id == operator or not actors.is_alive(id):
			continue
		var cell: Vector3i = BuildSystem.cell_of(actors.position_of(id))
		if cell.y == floor_y and cell.z >= line:
			return false
	return true
