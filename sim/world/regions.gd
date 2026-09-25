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
## is `region.enter` (claim 14): refused unless the actor stands in the gate's opening,
## and then a load window of LOAD_WINDOW_TICKS during which the actor is in transit and
## goes nowhere, before being set down on the far side. The world does not wait: the
## sim, tokens and all, keeps running while anyone is in the gate.
class_name Regions extends SimSystem

const SYSTEM_ID: StringName = &"regions"
const KIND: StringName = &"region"
const KIND_AUTHORED: String = "authored"
const KIND_WILD: String = "wild"
const COMMAND_ENTER: StringName = &"region.enter"
const COMMAND_DIG: StringName = &"ground.dig"
const COMMAND_FILL: StringName = &"ground.fill"
## How far from where an actor stands a cell can be dug or filled, to its centre.
const REACH_MM: int = 2_500
## How long taking a gate takes: the seam's load window, in ticks (two seconds).
const LOAD_WINDOW_TICKS: int = 80

var _routes: RouteGraph
var _terrain: Terrain
var _actors: ActorSystem
var _events: EventBus
var _land: LandSystem
## (cell) -> the piece in it or NONE: the build system's, held as a callable rather than
## the system itself, because the build system holds the regions (foundations ask the
## ground) and two RefCounted objects holding each other are never freed
var _piece_at: Callable = Callable()
## actor -> {"region": String (where they are going), "gate": int (graph node), "due": int (tick)}
var _transits: Dictionary = {}
var _authored: Array[Region] = []
var _wild: Region = null


func _init(routes: RouteGraph, terrain: Terrain, actors: ActorSystem = null, events: EventBus = null, land: LandSystem = null, build_system: BuildSystem = null) -> void:
	_routes = routes
	_terrain = terrain
	_actors = actors
	_events = events
	_land = land
	if build_system != null:
		_piece_at = build_system.cell_piece_at


func system_id() -> StringName:
	return SYSTEM_ID


## Sets down everyone whose load window is over, lowest actor first.
func tick(sim: SimRoot) -> void:
	var now: int = sim.get_tick()
	for actor: int in transit_ids():
		var rec: Dictionary = _transits[actor]
		if not _actors.is_alive(actor):
			_transits.erase(actor)
			continue
		var due: int = rec["due"]
		if due > now:
			continue
		_transits.erase(actor)
		var gate: int = rec["gate"]
		var here: Vector3i = _actors.position_of(actor)
		var target_s: String = rec["region"]
		var there: Vector2i = _far_side(StringName(target_s), gate, Vector2i(here.x, here.z))
		var err: Error = _actors.set_position(actor, Vector3i(there.x, standing_cell_y(there.x, there.y) * BuildSystem.CELL, there.y))
		assert(err == OK, "a gate sets you down inside the world")


## The ground is the seed's; what is state is who is in a gate and what has been dug or
## filled (claim 15), the only part of the ground a save carries.
func snapshot() -> Dictionary:
	var edits: Dictionary = {}
	if _wild is WildRegion:
		var wild: WildRegion = _wild
		edits = wild.edits()
	return {"transits": _transits.duplicate(true), "edits": edits}


func attach(sim: SimRoot) -> Error:
	var db: SimSystem = sim.get_system(ContentDb.SYSTEM_ID)
	if db == null:
		push_error("Regions: no content")
		return ERR_INVALID_DATA
	var content: ContentDb = db
	var err: Error = build(content)
	if err != OK:
		return err
	err = sim.register_system(self)
	if err != OK:
		return err
	err = _events.subscribe(ActorSystem.EVENT_REMOVED, _on_removed)
	if err != OK:
		return err
	# not pause-safe: a gate is walked through in world time
	err = sim.commands().register(COMMAND_ENTER, _on_enter, false)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_DIG, _on_dig, false)
	if err != OK:
		return err
	return sim.commands().register(COMMAND_FILL, _on_fill, false)


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


# ---------------------------------------------------------------- the seam

func transit_ids() -> Array[int]:
	var out: Array[int] = []
	for key: Variant in _transits:
		var id: int = key
		out.append(id)
	out.sort()
	return out


## True while an actor is in a gate: it goes nowhere until it is set down.
func in_transit(actor: int) -> bool:
	return _transits.has(actor)


## The gate an actor is standing in the opening of, as a graph node, or NONE. In the
## opening means within the gate's half-width along the edge and within a cell of the
## edge on either side of it.
func gate_at(pos: Vector3i) -> int:
	for region: Region in _authored:
		for gate: Dictionary in region.gates():
			var gx: int = gate["x"]
			var gz: int = gate["z"]
			var half: int = gate["half_width_mm"]
			var along: int = absi(pos.x - gx) if _edge_runs_along_x(region, gate) else absi(pos.z - gz)
			var across: int = absi(pos.z - gz) if _edge_runs_along_x(region, gate) else absi(pos.x - gx)
			if along <= half and across < BuildSystem.CELL:
				var node: int = gate["node"]
				return node
	return EntityIds.NONE


## {"actor": int, "region": string}: take the gate you are standing in, to the region on
## the other side of it.
func _on_enter(sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("region")) != TYPE_STRING:
		return false
	var actor: int = payload["actor"]
	var target_s: String = payload["region"]
	var target: StringName = StringName(target_s)
	if not _actors.is_alive(actor) or _transits.has(actor) or not region_ids().has(target):
		return false
	var here: Vector3i = _actors.position_of(actor)
	var gate: int = gate_at(here)
	if gate == EntityIds.NONE:
		return false
	var from: Region = region_at(here.x, here.z)
	if from.id() == target:
		return false
	# the gate joins its authored region to whatever lies beyond its edge, and that is
	# the only place it goes
	var there: Vector2i = _far_side(target, gate, Vector2i(here.x, here.z))
	if region_at(there.x, there.y).id() != target:
		return false
	_transits[actor] = {"region": target_s, "gate": gate, "due": sim.get_tick() + LOAD_WINDOW_TICKS}
	return true


## Where taking a gate sets you down: straight through it, half a cell beyond its edge,
## on the side that is `target`.
func _far_side(target: StringName, gate: int, from: Vector2i) -> Vector2i:
	var at: Vector2i = _routes.position_of(gate)
	var half: int = BuildSystem.CELL / 2
	for region: Region in _authored:
		for g: Dictionary in region.gates():
			var node: int = g["node"]
			if node != gate:
				continue
			var inward: bool = target == region.id()
			if _edge_runs_along_x(region, g):
				var into_z: int = at.y + half if region.contains(at.x, at.y + half) == inward else at.y - half
				return Vector2i(from.x, into_z)
			var into_x: int = at.x + half if region.contains(at.x + half, at.y) == inward else at.x - half
			return Vector2i(into_x, from.y)
	return from


## Whether a gate's edge runs along x (a north or south edge of its box).
func _edge_runs_along_x(region: Region, gate: Dictionary) -> bool:
	var gx: int = gate["x"]
	var gz: int = gate["z"]
	# a gate on a north or south edge has the region on one side of it in z
	return region.contains(gx, gz) != region.contains(gx, gz - 1)


# ---------------------------------------------------------------- editing the ground

## {"actor": int, "cell": [x, y, z]}: dig a cell of ground out.
func _on_dig(_sim: SimRoot, payload: Dictionary) -> bool:
	var cell: Vector3i = _edit_cell(payload)
	if cell == INVALID_CELL or not is_solid(cell):
		return false
	return region_of_cell(cell).set_ground(cell, false)


## {"actor": int, "cell": [x, y, z]}: fill a cell in. Never where somebody is standing.
func _on_fill(_sim: SimRoot, payload: Dictionary) -> bool:
	var cell: Vector3i = _edit_cell(payload)
	if cell == INVALID_CELL or is_solid(cell):
		return false
	for actor: int in _actors.actor_ids():
		if _actors.is_alive(actor) and BuildSystem.cell_of(_actors.position_of(actor)) == cell:
			return false
	return region_of_cell(cell).set_ground(cell, true)


const INVALID_CELL: Vector3i = Vector3i(-2147483648, -2147483648, -2147483648)


## The cell an edit names, if the actor may edit it: alive and not in a gate, the cell
## within reach, nothing built in it, and the right to dig there.
func _edit_cell(payload: Dictionary) -> Vector3i:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("cell")) != TYPE_ARRAY:
		return INVALID_CELL
	var actor: int = payload["actor"]
	var raw: Array = payload["cell"]
	if raw.size() != 3:
		return INVALID_CELL
	for v: Variant in raw:
		if typeof(v) != TYPE_INT:
			return INVALID_CELL
		var n: int = v
		if absi(n) > BuildSystem.MAX_CELL:
			return INVALID_CELL
	var x: int = raw[0]
	var y: int = raw[1]
	var z: int = raw[2]
	var cell: Vector3i = Vector3i(x, y, z)
	if not _actors.is_alive(actor) or _transits.has(actor):
		return INVALID_CELL
	var c: int = BuildSystem.CELL
	var centre: Vector3i = Vector3i(x * c + c / 2, y * c + c / 2, z * c + c / 2)
	if PerceptionSystem.distance_mm(_actors.position_of(actor), centre) > REACH_MM:
		return INVALID_CELL
	var piece: int = _piece_at.call(cell)
	if piece != EntityIds.NONE:
		return INVALID_CELL
	if not _land.require(centre, actor, &"dig"):
		return INVALID_CELL
	return cell


func _on_removed(payload: Dictionary) -> void:
	var actor: int = payload["actor"]
	_transits.erase(actor)


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 2 or typeof(state.get("transits")) != TYPE_DICTIONARY or typeof(state.get("edits")) != TYPE_DICTIONARY:
		return _fail("restore: shape")
	var edits_in: Dictionary = state["edits"]
	var chunk_re: RegEx = RegEx.create_from_string("^-?[0-9]+,-?[0-9]+,-?[0-9]+$")
	for key: Variant in edits_in:
		if typeof(key) != TYPE_STRING or typeof(edits_in[key]) != TYPE_DICTIONARY:
			return _fail("restore: edit chunk")
		var name: String = key
		if not chunk_re.search(name):
			return _fail("restore: edit chunk")
		var chunk: Dictionary = edits_in[key]
		if chunk.is_empty():
			return _fail("restore: an empty edit chunk")
		for index: Variant in chunk:
			if typeof(index) != TYPE_INT or typeof(chunk[index]) != TYPE_INT:
				return _fail("restore: edit entry")
			var i: int = index
			var solid: int = chunk[index]
			if i < 0 or i >= WildRegion.CHUNK * WildRegion.CHUNK * WildRegion.CHUNK or (solid != 0 and solid != 1):
				return _fail("restore: edit entry")
	var in_all: Dictionary = state["transits"]
	var out: Dictionary = {}
	for key: Variant in in_all:
		if typeof(key) != TYPE_INT or typeof(in_all[key]) != TYPE_DICTIONARY:
			return _fail("restore: transit key")
		var actor: int = key
		var rec: Dictionary = in_all[key]
		if not _actors.has_actor(actor):
			return _fail("restore: actor %d in a gate is not there" % actor)
		if rec.size() != 3 or (typeof(rec.get("region")) != TYPE_STRING and typeof(rec.get("region")) != TYPE_STRING_NAME) \
				or typeof(rec.get("gate")) != TYPE_INT or typeof(rec.get("due")) != TYPE_INT:
			return _fail("restore: transit of %d" % actor)
		var target: StringName = StringName(str(rec["region"]))
		var gate: int = rec["gate"]
		var due: int = rec["due"]
		if not region_ids().has(target) or _routes.kind_of(gate) != RouteGraph.KIND_GATE or due < 0:
			return _fail("restore: transit of %d goes nowhere" % actor)
		out[actor] = {"region": String(target), "gate": gate, "due": due}
	_transits = out
	var wild: WildRegion = _wild
	wild.set_edits(edits_in)
	return OK
