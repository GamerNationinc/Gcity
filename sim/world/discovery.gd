## Discovery (M7 spec claim 15; design doc §5.3, §5.6). **Which places the player has
## found**: part of the save's overlay on top of the seed, and what a contract asking for
## somewhere `undiscovered` is asked against (claim 8).
##
## A place is found when a player — a living actor that is not an agent — comes within
## DISCOVER_MM of it, and stays found. The gate is known from the start: everybody knows
## where the city's gate is. Checked every LOOK_EVERY ticks rather than every tick, like
## hydration, because a player cannot cover much ground in eight.
class_name Discovery extends SimSystem

const SYSTEM_ID: StringName = &"discovery"
## How close a player has to come to a place to have found it.
const DISCOVER_MM: int = 200_000
const LOOK_EVERY: int = 8

var _routes: RouteGraph
var _actors: ActorSystem
var _perception: PerceptionSystem
## node id -> the tick it was found (0 for the gate, which nobody has to find)
var _found: Dictionary = {}


func _init(routes: RouteGraph, actors: ActorSystem, perception: PerceptionSystem) -> void:
	_routes = routes
	_actors = actors
	_perception = perception


func system_id() -> StringName:
	return SYSTEM_ID


func attach(sim: SimRoot) -> Error:
	_found = {1: 0}
	return sim.register_system(self)


func snapshot() -> Dictionary:
	return {"found": _found.duplicate(true)}


func tick(sim: SimRoot) -> void:
	var now: int = sim.get_tick()
	if now % LOOK_EVERY != 0:
		return
	var players: Array[Vector2i] = []
	for actor: int in _actors.actor_ids():
		if _actors.is_alive(actor) and not _perception.is_agent(actor):
			var at: Vector3i = _actors.position_of(actor)
			players.append(Vector2i(at.x, at.z))
	if players.is_empty():
		return
	for node: int in _routes.node_ids():
		if _found.has(node):
			continue
		var place: Vector2i = _routes.position_of(node)
		for at: Vector2i in players:
			if RouteGraph._length_mm(place.x, place.y, at.x, at.y) <= DISCOVER_MM:
				_found[node] = now
				break


func is_found(node: int) -> bool:
	return _found.has(node)


## Found places, lowest first.
func found_nodes() -> Array[int]:
	var out: Array[int] = []
	for key: Variant in _found:
		var id: int = key
		out.append(id)
	out.sort()
	return out


## The slots whose place has been found, as the set [SiteConstraint] reads: somewhere
## you have been is somewhere a contract wanting somewhere new cannot send you.
func found_slots() -> Dictionary:
	var out: Dictionary = {}
	for slot: int in _routes.slot_ids():
		if _found.has(_routes.slot_node(slot)):
			out[slot] = true
	return out


func restore(state: Dictionary) -> Error:
	if state.size() != 1 or typeof(state.get("found")) != TYPE_DICTIONARY:
		return _fail("shape")
	var in_all: Dictionary = state["found"]
	var out: Dictionary = {}
	for key: Variant in in_all:
		if typeof(key) != TYPE_INT or typeof(in_all[key]) != TYPE_INT:
			return _fail("entry")
		var node: int = key
		var tick: int = in_all[key]
		if not _routes.has_node(node) or tick < 0:
			return _fail("node %d is not a place, or was found before time began" % node)
		out[node] = tick
	if not out.has(1):
		return _fail("the gate is always known")
	_found = out
	return OK


func _fail(reason: String) -> Error:
	push_error("Discovery.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
