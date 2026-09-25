## Regions (design doc §5.1; M7 spec claim 13; the approved regions design note). **The
## one thing movement, perception, hydration, sites and saving ask about the ground.**
##
## Every region is content (`content/region/`): exactly one wild region, everywhere no
## authored region covers, and the authored regions — the city — each a box with its
## gates. What a system asks is answered by the region the place is in, through
## [Region]; nothing outside sim/world names [AuthoredRegion] or [WildRegion], and
## `tools/check_dependencies.py` enforces that. So "one rule for both region types" is
## literal: nobody on this side of the interface can branch on which kind it is.
##
## An authored region's edge is a wall. The only way across is a gate, and taking a gate
## is `region.enter` (claim 14); a move that would cross anywhere else is refused.
class_name Regions extends SimSystem

const SYSTEM_ID: StringName = &"regions"
const KIND: StringName = &"region"
const KIND_AUTHORED: String = "authored"
const KIND_WILD: String = "wild"

var _routes: RouteGraph
var _terrain: Terrain
var _authored: Array[Region] = []
var _wild: Region = null


func _init(routes: RouteGraph, terrain: Terrain) -> void:
	_routes = routes
	_terrain = terrain


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


## The ground is the seed's; nothing about it is state until claim 15's edits.
func snapshot() -> Dictionary:
	return {}


func attach(sim: SimRoot) -> Error:
	var db: SimSystem = sim.get_system(ContentDb.SYSTEM_ID)
	if db == null:
		push_error("Regions: no content")
		return ERR_INVALID_DATA
	var content: ContentDb = db
	var err: Error = build(content)
	if err != OK:
		return err
	return sim.register_system(self)


## Builds the regions from content: every authored region's box and gates checked, and
## exactly one wild region. A gate must be a gate of the graph and stand on its region's
## edge, or the seam would be somewhere nobody can reach.
func build(content: ContentDb) -> Error:
	_authored = []
	_wild = null
	var wild_id: StringName = &""
	for id: StringName in content.ids(KIND):
		var entry: Dictionary = content.get_entry(KIND, id)
		var kind: String = entry["kind"]
		var bounds_in: Array = entry["bounds"]
		if kind == KIND_WILD:
			if wild_id != &"":
				return _fail("region/%s is a second wild region; region/%s is the wild" % [id, wild_id])
			if not bounds_in.is_empty():
				return _fail("region/%s is wild and has bounds: the wild is wherever nothing else is" % id)
			wild_id = id
			continue
		if bounds_in.size() != 4:
			return _fail("region/%s needs bounds [x0, z0, x1, z1]" % id)
		var bounds: Array[int] = []
		for v: Variant in bounds_in:
			var n: int = v
			bounds.append(n)
		if bounds[0] >= bounds[2] or bounds[1] >= bounds[3]:
			return _fail("region/%s has an empty box" % id)
		var gate_list: Array[Dictionary] = []
		for v: Variant in entry["gates"]:
			var gate: Dictionary = v
			var node: int = gate["node"]
			var x: int = gate["x"]
			var z: int = gate["z"]
			if _routes.kind_of(node) != RouteGraph.KIND_GATE or _routes.position_of(node) != Vector2i(x, z):
				return _fail("region/%s has a gate at %d,%d that is not the graph's gate %d" % [id, x, z, node])
			var on_edge: bool = (x == bounds[0] or x == bounds[2]) or (z == bounds[1] or z == bounds[3])
			if not on_edge:
				return _fail("region/%s has a gate inside it rather than on its edge" % id)
			gate_list.append(gate.duplicate(true))
		_authored.append(AuthoredRegion.new(id, bounds, gate_list))
	if wild_id == &"":
		return _fail("there is no wild region")
	_wild = WildRegion.new(wild_id, _terrain, _routes, _authored)
	return OK


func _fail(reason: String) -> Error:
	push_error("Regions: %s" % reason)
	return ERR_INVALID_DATA


# ---------------------------------------------------------------- queries

## The region a ground position is in.
func region_at(x: int, z: int) -> Region:
	for region: Region in _authored:
		if region.contains(x, z):
			return region
	return _wild


func region_of_cell(cell: Vector3i) -> Region:
	var c: int = BuildSystem.CELL
	return region_at(cell.x * c + c / 2, cell.z * c + c / 2)


func region_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for region: Region in _authored:
		out.append(region.id())
	out.append(_wild.id())
	return out


## Whether the ground fills a cell.
func is_solid(cell: Vector3i) -> bool:
	return region_of_cell(cell).is_solid(cell)


## Whether the ground carries an actor standing in a cell.
func stands_on_ground(cell: Vector3i) -> bool:
	return region_of_cell(cell).stands_on_ground(cell)


## The level an actor stands at over a ground position.
func standing_cell_y(x: int, z: int) -> int:
	return region_at(x, z).standing_cell_y(x, z)


## How many levels one step may climb onto the ground from a cell.
func step_levels(cell: Vector3i) -> int:
	return region_of_cell(cell).step_levels()


## True when going from one position to another would cross a region's edge: the wall
## everywhere but a gate, and even there the gate is taken by `region.enter`.
func crosses_edge(from: Vector3i, to: Vector3i) -> bool:
	return region_at(from.x, from.z) != region_at(to.x, to.z)


func gates_of(region: StringName) -> Array[Dictionary]:
	for r: Region in _authored:
		if r.id() == region:
			return r.gates()
	return [] as Array[Dictionary]


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if not state.is_empty():
		return _fail("restore: the ground holds no state yet")
	return OK
