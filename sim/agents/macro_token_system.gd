## Off-screen life (M7 spec claim 11; design doc §6.1 macro tier, §6.2; ADR-010 B). **An
## agent the player cannot see is a token on the route graph**, not a body in the world.
##
## A token is the design doc's `{edge_id, progress, faction, payload}`: which corridor it
## is on, how far along, whose it is, and what hydration will turn back into entities
## (claim 12). It is advanced with no navigation, no perception and no geometry. Terrain
## cannot trap it, because it never touches terrain, and it costs almost nothing, which
## is what lets everything unloaded keep moving while the player is somewhere else.
##
## A token plans its whole route once, when it is spawned, by the graph's own shortest
## path, and keeps the list of places as its schedule. It then only walks the list: at
## each place it either stops, because that was the destination, or carries on down the
## one edge to the next place on the list. The graph never invalidates a route once
## planned — binding only adds leaves, and a leaf is never a shortcut — so replanning
## would only cost a search per place and change nothing.
##
## Motion is linear, so advancing N ticks at once lands exactly where N single ticks
## would, distance left over at a place carrying onto the next edge. The macro tier
## (§6.1) is only near-free if it can be advanced in one step, and hydration (claim 12)
## only agrees with itself if the one step and the many agree.
class_name MacroTokenSystem extends SimSystem

const SYSTEM_ID: StringName = &"tokens"
const COMMAND_SPAWN: StringName = &"token.spawn"
## The fastest anything travels off-screen, in millimetres a tick: a vehicle on a good
## road, 30 m/s at 40 ticks a second. A bound, not a speed: it keeps a hostile spawn from
## asking for a token that crosses the world in a tick.
const MAX_SPEED_MM_PER_TICK: int = 750
## What a payload may hold: named counts and names, a handful of them. Hydration reads
## it; nothing in the macro tier does.
const PAYLOAD_MAX_ENTRIES: int = 16
const PAYLOAD_KEY_PATTERN: String = "^[a-z0-9_]+$"

var _routes: RouteGraph
## token id -> {"route": Array[int] of nodes, "leg": int, "progress": int, "speed": int,
## "faction": String, "payload": Dictionary, "held": bool}. The token is on the edge from
## route[leg] to route[leg + 1], `progress` millimetres from route[leg]. A held token is
## hydrated (claim 12): its squad is walking the route in the world, and the macro tier
## leaves it alone until the squad hands the route back.
var _tokens: Dictionary = {}
var _next_token: int = 1
var _faction_regex: RegEx = RegEx.create_from_string(LandSystem.OWNER_PATTERN)
var _key_regex: RegEx = RegEx.create_from_string(PAYLOAD_KEY_PATTERN)


func _init(routes: RouteGraph) -> void:
	_routes = routes


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	advance(1)


func snapshot() -> Dictionary:
	return {"tokens": _tokens.duplicate(true), "next_token": _next_token}


func attach(sim: SimRoot) -> Error:
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	return sim.commands().register(COMMAND_SPAWN, _on_spawn)


# ---------------------------------------------------------------- spawning

## Puts a token at a place, bound for another, and returns its id; NONE if the request
## is not one the macro tier can carry out.
func spawn(faction: String, from: int, to: int, speed: int, payload: Dictionary) -> int:
	if from == to or not _routes.has_node(from) or not _routes.has_node(to):
		return EntityIds.NONE
	if speed < 1 or speed > MAX_SPEED_MM_PER_TICK:
		return EntityIds.NONE
	if not _faction_regex.search(faction) or not _payload_ok(payload):
		return EntityIds.NONE
	var route: Array[int] = _routes.path_between(from, to)
	if route.size() < 2:
		return EntityIds.NONE
	var id: int = _next_token
	_next_token += 1
	_tokens[id] = {
		"route": route, "leg": 0, "progress": 0, "speed": speed,
		"faction": faction, "payload": payload.duplicate(true), "held": false,
	}
	return id


func _payload_ok(payload: Dictionary) -> bool:
	if payload.size() > PAYLOAD_MAX_ENTRIES:
		return false
	for key: Variant in payload:
		if typeof(key) != TYPE_STRING:
			return false
		var name: String = key
		if not _key_regex.search(name):
			return false
		var value: Variant = payload[key]
		if typeof(value) != TYPE_INT and typeof(value) != TYPE_STRING:
			return false
	return true


## {"faction": string, "from": int, "to": int, "speed": int, "payload": {string: int|string}}
func _on_spawn(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 5 or typeof(payload.get("faction")) != TYPE_STRING or typeof(payload.get("from")) != TYPE_INT \
			or typeof(payload.get("to")) != TYPE_INT or typeof(payload.get("speed")) != TYPE_INT \
			or typeof(payload.get("payload")) != TYPE_DICTIONARY:
		return false
	var faction: String = payload["faction"]
	var from: int = payload["from"]
	var to: int = payload["to"]
	var speed: int = payload["speed"]
	var carried: Dictionary = payload["payload"]
	return spawn(faction, from, to, speed, carried) != EntityIds.NONE


# ---------------------------------------------------------------- moving

## Moves every token on by `ticks` ticks, lowest id first. The same as calling it with 1
## that many times: distance is speed times ticks, and whatever is left at a place goes
## on down the next edge.
func advance(ticks: int) -> void:
	if ticks <= 0:
		return
	for id: int in token_ids():
		var rec: Dictionary = _tokens[id]
		var held: bool = rec["held"]
		if not held:
			_advance_one(rec, ticks)


func _advance_one(rec: Dictionary, ticks: int) -> void:
	var route: Array = rec["route"]
	var speed: int = rec["speed"]
	var leg: int = rec["leg"]
	var progress: int = rec["progress"]
	var at: Vector2i = along(route, leg, progress, speed * ticks)
	rec["leg"] = at.x
	rec["progress"] = at.y


## Where a walker on a route ends up after `distance` more millimetres from a leg and a
## progress along it, as (leg, progress): leftover distance at a place carries onto the
## next leg, and at the destination it stops. The macro tier and a hydrated squad walk
## by this one rule, which is what lets hydration hand the route back to a token without
## the two ever disagreeing about where a distance gets you.
func along(route: Array, from_leg: int, from_progress: int, distance: int) -> Vector2i:
	var budget: int = distance
	var leg: int = from_leg
	var progress: int = from_progress
	while true:
		var length: int = _leg_length(route, leg)
		if progress + budget < length:
			progress += budget
			break
		budget -= length - progress
		progress = length
		if leg + 2 >= route.size():
			# the destination: a token that has arrived stops, and the rest of the
			# tick's distance is simply not travelled
			break
		leg += 1
		progress = 0
	return Vector2i(leg, progress)


## The ground position, in millimetres, of a point on a route: `back` millimetres behind
## (leg, progress), walking back over earlier legs as far as the route's start and no
## further. How a squad in file is laid out along the road behind its lead.
func point_at(route: Array, leg: int, progress: int, back: int = 0) -> Vector2i:
	var l: int = leg
	var p: int = progress - back
	while p < 0 and l > 0:
		l -= 1
		p += _leg_length(route, l)
	p = maxi(p, 0)
	var a: int = route[l]
	var b: int = route[l + 1]
	var from: Vector2i = _routes.position_of(a)
	var to: Vector2i = _routes.position_of(b)
	var length: int = _leg_length(route, l)
	if length <= 0:
		return from
	return Vector2i(from.x + (to.x - from.x) * p / length, from.y + (to.y - from.y) * p / length)


## Where a token is on the ground, in millimetres.
func position_of(id: int) -> Vector2i:
	if not _tokens.has(id):
		return Vector2i.ZERO
	var rec: Dictionary = _tokens[id]
	var route: Array = rec["route"]
	var leg: int = rec["leg"]
	var progress: int = rec["progress"]
	return point_at(route, leg, progress)


# ---------------------------------------------------------------- hydration

## Hands a token to a hydrated squad (claim 12): the macro tier stops advancing it until
## [release]. Refuses one already held.
func hold(id: int) -> bool:
	if not _tokens.has(id):
		return false
	var rec: Dictionary = _tokens[id]
	var held: bool = rec["held"]
	if held:
		return false
	rec["held"] = true
	return true


## Takes a token back from its squad, where the squad got to and with what it has left.
## Refuses a token that is not held, or a place that is not on its route.
func release(id: int, leg: int, progress: int, payload: Dictionary) -> bool:
	if not is_held(id) or not _payload_ok(payload):
		return false
	var rec: Dictionary = _tokens[id]
	var route: Array = rec["route"]
	if leg < 0 or leg + 1 >= route.size() or progress < 0 or progress > _leg_length(route, leg):
		return false
	rec["leg"] = leg
	rec["progress"] = progress
	rec["payload"] = payload.duplicate(true)
	rec["held"] = false
	return true


## A squad that was wiped out while hydrated leaves no token behind.
func drop(id: int) -> bool:
	if not is_held(id):
		return false
	_tokens.erase(id)
	return true


func is_held(id: int) -> bool:
	if not _tokens.has(id):
		return false
	var rec: Dictionary = _tokens[id]
	return rec["held"]


func leg_of(id: int) -> int:
	if not _tokens.has(id):
		return -1
	var rec: Dictionary = _tokens[id]
	return rec["leg"]


func _leg_length(route: Array, leg: int) -> int:
	var a: int = route[leg]
	var b: int = route[leg + 1]
	var rec: Dictionary = _routes.edge(_routes.edge_between(a, b))
	return rec["length"]


# ---------------------------------------------------------------- queries

func token_ids() -> Array[int]:
	var out: Array[int] = []
	for key: Variant in _tokens:
		var id: int = key
		out.append(id)
	out.sort()
	return out


func has_token(id: int) -> bool:
	return _tokens.has(id)


## The corridor a token is on, or NONE.
func edge_of(id: int) -> int:
	if not _tokens.has(id):
		return EntityIds.NONE
	var rec: Dictionary = _tokens[id]
	var route: Array = rec["route"]
	var leg: int = rec["leg"]
	var a: int = route[leg]
	var b: int = route[leg + 1]
	return _routes.edge_between(a, b)


## The place the token last left, which its progress is measured from.
func from_of(id: int) -> int:
	return _route_node(id, 0)


## The place it is walking towards now.
func toward_of(id: int) -> int:
	return _route_node(id, 1)


func _route_node(id: int, ahead: int) -> int:
	if not _tokens.has(id):
		return EntityIds.NONE
	var rec: Dictionary = _tokens[id]
	var route: Array = rec["route"]
	var leg: int = rec["leg"]
	return route[leg + ahead]


## Millimetres along its edge from [from_of], or -1.
func progress_of(id: int) -> int:
	if not _tokens.has(id):
		return -1
	var rec: Dictionary = _tokens[id]
	return rec["progress"]


func destination_of(id: int) -> int:
	if not _tokens.has(id):
		return EntityIds.NONE
	var rec: Dictionary = _tokens[id]
	var route: Array = rec["route"]
	return route[route.size() - 1]


## The places it will pass through, in order, from where it started to where it stops.
func route_of(id: int) -> Array[int]:
	var out: Array[int] = []
	if not _tokens.has(id):
		return out
	var rec: Dictionary = _tokens[id]
	for v: Variant in rec["route"]:
		var node: int = v
		out.append(node)
	return out


func speed_of(id: int) -> int:
	if not _tokens.has(id):
		return 0
	var rec: Dictionary = _tokens[id]
	return rec["speed"]


func faction_of(id: int) -> String:
	if not _tokens.has(id):
		return ""
	var rec: Dictionary = _tokens[id]
	return rec["faction"]


func payload_of(id: int) -> Dictionary:
	if not _tokens.has(id):
		return {}
	var rec: Dictionary = _tokens[id]
	var payload: Dictionary = rec["payload"]
	return payload.duplicate(true)


## True once a token has reached its destination and stopped there.
func is_stopped(id: int) -> bool:
	if not _tokens.has(id):
		return false
	var rec: Dictionary = _tokens[id]
	var route: Array = rec["route"]
	var leg: int = rec["leg"]
	var progress: int = rec["progress"]
	return leg + 2 == route.size() and progress == _leg_length(route, leg)


# ---------------------------------------------------------------- restore

## Checked in full before anything is kept: every route runs along real corridors,
## every token is on one of them and no further along it than it is long.
func restore(state: Dictionary) -> Error:
	if state.size() != 2 or typeof(state.get("tokens")) != TYPE_DICTIONARY or typeof(state.get("next_token")) != TYPE_INT:
		return _restore_fail("shape")
	var next: int = state["next_token"]
	if next < 1:
		return _restore_fail("next token id")
	var in_all: Dictionary = state["tokens"]
	var out: Dictionary = {}
	for key: Variant in in_all:
		if typeof(key) != TYPE_INT or typeof(in_all[key]) != TYPE_DICTIONARY:
			return _restore_fail("token key")
		var id: int = key
		if id < 1 or id >= next:
			return _restore_fail("token %d is outside the ids handed out" % id)
		var rec: Dictionary = in_all[key]
		if rec.size() != 7 or typeof(rec.get("held")) != TYPE_BOOL or typeof(rec.get("route")) != TYPE_ARRAY or typeof(rec.get("leg")) != TYPE_INT \
				or typeof(rec.get("progress")) != TYPE_INT or typeof(rec.get("speed")) != TYPE_INT \
				or typeof(rec.get("faction")) != TYPE_STRING or typeof(rec.get("payload")) != TYPE_DICTIONARY:
			return _restore_fail("token %d record" % id)
		var route_in: Array = rec["route"]
		var route: Array[int] = []
		for v: Variant in route_in:
			if typeof(v) != TYPE_INT:
				return _restore_fail("token %d route" % id)
			var node: int = v
			if not _routes.has_node(node):
				return _restore_fail("token %d routes through somewhere that is not a place" % id)
			if not route.is_empty() and _routes.edge_between(route[route.size() - 1], node) == EntityIds.NONE:
				return _restore_fail("token %d routes between places no road joins" % id)
			route.append(node)
		if route.size() < 2:
			return _restore_fail("token %d has nowhere to go" % id)
		var leg: int = rec["leg"]
		if leg < 0 or leg + 1 >= route.size():
			return _restore_fail("token %d is off its route" % id)
		var progress: int = rec["progress"]
		if progress < 0 or progress > _leg_length(route, leg):
			return _restore_fail("token %d is off its edge" % id)
		var speed: int = rec["speed"]
		if speed < 1 or speed > MAX_SPEED_MM_PER_TICK:
			return _restore_fail("token %d speed" % id)
		var faction: String = rec["faction"]
		var payload: Dictionary = rec["payload"]
		var held: bool = rec["held"]
		if not _faction_regex.search(faction) or not _payload_ok(payload):
			return _restore_fail("token %d faction or payload" % id)
		out[id] = {"route": route, "leg": leg, "progress": progress, "speed": speed,
			"faction": faction, "payload": payload.duplicate(true), "held": held}
	_tokens = out
	_next_token = next
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("MacroTokenSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
