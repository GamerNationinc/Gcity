## Agent movement inside structures (M4 spec claim 9): a budgeted, resumable A* on
## the 1 m build grid whose steps obey the movement rules (no cell piece ahead, no
## impassable face between), so open faces and doors join volumes and walls never
## do. Planning spends at most PATH_NODES_PER_TICK expansions per tick across every
## agent, in agent-id order, and picks up next tick where it stopped; an agent whose
## path is ready walks it with `actor.move`-sized steps through MovementSystem,
## facing the way it walks. Paths cross levels by the movement rules (M6 spec claim
## 6): a step off an edge lands where the fall ends and a climb is one transition; the
## heuristic is the horizontal distance, which neither ever overestimates. Any build change re-plans every route from where each
## agent stands. Search is bounded to SEARCH_RADIUS cells around the start, which is
## the reach of an M4 building; the portal-graph handoff for larger sites is a
## debt item, not a hidden assumption.
class_name PathingSystem extends SimSystem

const SYSTEM_ID: StringName = &"pathing"
const PATH_NODES_PER_TICK: int = 256
const SEARCH_RADIUS: int = 32
const STATE_PLANNING: String = "planning"
const STATE_FOLLOWING: String = "following"
const STATE_ARRIVED: String = "arrived"
const STATE_FAILED: String = "failed"
const STEPS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const FACING_OF_STEP: Array[int] = [0, 180, 90, 270]
## Facing degrees of MovementSystem.SIDES (px, nx, pz, nz).
const FACING_OF_SIDE: Array[int] = [0, 180, 90, 270]

var _actors: ActorSystem
var _build: BuildSystem
var _movement: MovementSystem
var _perception: PerceptionSystem
var _events: EventBus
## agent -> {"goal": [x, y, z], "state": String, "path": [[x, y, z], ...], "index": int,
##           "search": {} | {"start": [x, y, z], "open": {key: [f, g]}, "came": {key: key}, "closed": {key: true}}}
var _routes: Dictionary = {}
var _replan: bool = false
var _expanded: int = 0


func _init(actors: ActorSystem, build: BuildSystem, movement: MovementSystem, perception: PerceptionSystem, events: EventBus) -> void:
	_actors = actors
	_build = build
	_movement = movement
	_perception = perception
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func snapshot() -> Dictionary:
	return {"routes": _routes.duplicate(true), "replan": _replan, "expanded": _expanded}


func attach(sim: SimRoot) -> Error:
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	return _events.subscribe(BuildSystem.EVENT_CHANGED, _on_build_changed)


func _on_build_changed(_payload: Dictionary) -> void:
	_replan = true


# ---------------------------------------------------------------- queries

func state_of(agent: int) -> String:
	var rec: Dictionary = _route(agent)
	if rec.is_empty():
		return ""
	return rec["state"]


func goal_of(agent: int) -> Vector3i:
	var rec: Dictionary = _route(agent)
	if rec.is_empty():
		return Vector3i.ZERO
	return _vec(rec["goal"])


## The planned cells still ahead of the agent, in walking order.
func path_of(agent: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var rec: Dictionary = _route(agent)
	if rec.is_empty():
		return out
	var path: Array = rec["path"]
	var index: int = rec["index"]
	for i: int in range(index, path.size()):
		out.append(_vec(path[i]))
	return out


## A* expansions performed since assembly.
func expanded_count() -> int:
	return _expanded


func _route(agent: int) -> Dictionary:
	var stored: Variant = _routes.get(agent)
	if typeof(stored) != TYPE_DICTIONARY:
		return {}
	return stored


## Whether an actor may step from one cell into an adjacent one: the movement rules
## without the land check (agents enter what they are sent into).
func can_step(from: Vector3i, to: Vector3i) -> bool:
	var d: Vector3i = to - from
	if absi(d.x) + absi(d.y) + absi(d.z) != 1:
		return false
	if _build.cell_piece_at(to) != EntityIds.NONE:
		return false
	var facing: String = ("p" if d.x > 0 else "n") + "x" if d.x != 0 else (("p" if d.y > 0 else "n") + "y" if d.y != 0 else ("p" if d.z > 0 else "n") + "z")
	var piece: int = _build.face_piece_at(BuildSystem.face_key(from, facing))
	if piece == EntityIds.NONE:
		return true
	var kind: Dictionary = _build.kind_data(piece)
	var passable: bool = kind["passable"]
	return passable


# ---------------------------------------------------------------- requests

## Sends a live agent toward a cell. Planning starts on the next tick. False for a
## non-agent, a dead agent, or a goal beyond SEARCH_RADIUS of the agent's cell.
func request(agent: int, goal: Vector3i) -> bool:
	if not _perception.is_agent(agent) or not _actors.is_alive(agent):
		return false
	var start: Vector3i = BuildSystem.cell_of(_actors.position_of(agent))
	if _manhattan(start, goal) > SEARCH_RADIUS:
		return false
	_routes[agent] = _fresh(goal, start)
	return true


func cancel(agent: int) -> void:
	_routes.erase(agent)


func _fresh(goal: Vector3i, start: Vector3i) -> Dictionary:
	var key: String = BuildSystem.cell_key(start)
	return {"goal": _arr(goal), "state": STATE_PLANNING, "path": [] as Array, "index": 0,
		"search": {"start": _arr(start), "open": {key: [_heuristic(start, goal), 0] as Array[int]}, "came": {}, "closed": {}}}


# ---------------------------------------------------------------- the tick

func tick(_sim: SimRoot) -> void:
	var budget: int = PATH_NODES_PER_TICK
	for agent: int in _agent_order():
		if not _actors.is_alive(agent):
			_routes.erase(agent)
			continue
		var rec: Dictionary = _routes[agent]
		var goal: Vector3i = _vec(rec["goal"])
		var here: Vector3i = BuildSystem.cell_of(_actors.position_of(agent))
		if _replan and rec["state"] != STATE_ARRIVED:
			rec = _fresh(goal, here)
		if rec["state"] == STATE_PLANNING:
			budget = _plan(rec, goal, budget)
		if rec["state"] == STATE_FOLLOWING:
			_follow(agent, rec, goal)
		_routes[agent] = rec
	_replan = false


func _agent_order() -> Array[int]:
	var out: Array[int] = []
	for key: Variant in _routes:
		var id: int = key
		out.append(id)
	out.sort()
	return out


## Spends up to `budget` expansions on the route's search; returns what is left.
func _plan(rec: Dictionary, goal: Vector3i, budget: int) -> int:
	var search: Dictionary = rec["search"]
	var start: Vector3i = _vec(search["start"])
	var open: Dictionary = search["open"]
	var came: Dictionary = search["came"]
	var closed: Dictionary = search["closed"]
	var goal_key: String = BuildSystem.cell_key(goal)
	while budget > 0:
		if open.is_empty():
			rec["state"] = STATE_FAILED
			rec["search"] = {}
			return budget
		var current_key: String = _pop_best(open)
		budget -= 1
		_expanded += 1
		if current_key == goal_key:
			rec["path"] = _unwind(came, start, goal_key)
			rec["index"] = 0
			rec["state"] = STATE_FOLLOWING
			rec["search"] = {}
			return budget
		closed[current_key] = true
		var current: Vector3i = _parse(current_key)
		var g_here: int = _g_of(came, start, current_key, open, closed)
		for next: Vector3i in _neighbours(current):
			var next_key: String = BuildSystem.cell_key(next)
			if closed.has(next_key) or _manhattan(start, next) > SEARCH_RADIUS:
				continue
			var g: int = g_here + 1
			var known: Variant = open.get(next_key)
			if typeof(known) == TYPE_ARRAY:
				var entry: Array = known
				var known_g: int = entry[1]
				if known_g <= g:
					continue
			open[next_key] = [g + _heuristic(next, goal), g] as Array[int]
			came[next_key] = current_key
	return 0


## The cells one transition from `cell`: the four steps (each landing where a fall
## ends), then the climbs, in a fixed order.
func _neighbours(cell: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for step: Vector3i in STEPS:
		var next: Vector3i = cell + step
		if can_step(cell, next):
			out.append(_movement.landing_cell(next))
	out.append_array(_movement.climb_targets(cell))
	return out


## Removes and returns the open cell with the lowest f, then lowest g, then lowest key.
func _pop_best(open: Dictionary) -> String:
	var best_key: String = ""
	var best_f: int = 0
	var best_g: int = 0
	for key: Variant in open:
		var k: String = key
		var entry: Array = open[key]
		var f: int = entry[0]
		var g: int = entry[1]
		if best_key.is_empty() or f < best_f or (f == best_f and (g < best_g or (g == best_g and k < best_key))):
			best_key = k
			best_f = f
			best_g = g
	open.erase(best_key)
	return best_key


## g of a popped cell: its recorded g lives in the open entry until it is popped, so
## it is recovered by walking `came` back to the start.
func _g_of(came: Dictionary, start: Vector3i, key: String, _open: Dictionary, _closed: Dictionary) -> int:
	var start_key: String = BuildSystem.cell_key(start)
	var g: int = 0
	var k: String = key
	while k != start_key:
		var prev: Variant = came.get(k)
		if typeof(prev) != TYPE_STRING:
			break
		k = prev
		g += 1
	return g


func _unwind(came: Dictionary, start: Vector3i, goal_key: String) -> Array:
	var start_key: String = BuildSystem.cell_key(start)
	var cells: Array = []
	var k: String = goal_key
	while k != start_key:
		cells.push_front(_arr(_parse(k)))
		var prev: Variant = came.get(k)
		if typeof(prev) != TYPE_STRING:
			break
		k = prev
	return cells


## One tick of walking: a capped step toward the centre of the next cell; the next
## cell is reached when the agent stands in it. A refused step means the world
## changed under the plan: re-plan from here.
func _follow(agent: int, rec: Dictionary, goal: Vector3i) -> void:
	var path: Array = rec["path"]
	var index: int = rec["index"]
	var here: Vector3i = BuildSystem.cell_of(_actors.position_of(agent))
	while index < path.size() and _vec(path[index]) == here:
		index += 1
	rec["index"] = index
	if index >= path.size():
		rec["state"] = STATE_ARRIVED if here == goal else STATE_PLANNING
		if rec["state"] == STATE_PLANNING:
			var fresh: Dictionary = _fresh(goal, here)
			rec["search"] = fresh["search"]
		return
	var next: Vector3i = _vec(path[index])
	if next.y > here.y or (next.y < here.y and next.x == here.x and next.z == here.z):
		_climb_toward(agent, rec, goal, here, next)
		return
	var target: Vector3i = BuildSystem.cell_centre(next)
	target.y = _actors.position_of(agent).y
	var pos: Vector3i = _actors.position_of(agent)
	var speed: int = _movement.speed_of(agent)
	var dx: int = clampi(target.x - pos.x, -speed, speed)
	var dz: int = clampi(target.z - pos.z, -speed, speed)
	var step: Vector3i = Vector3i(next.x - here.x, 0, next.z - here.z)
	for i: int in STEPS.size():
		if STEPS[i] == step:
			_perception.set_facing(agent, FACING_OF_STEP[i])
	if (dx != 0 or dz != 0) and not _movement.move(agent, dx, dz):
		var fresh: Dictionary = _fresh(goal, here)
		rec["state"] = STATE_PLANNING
		rec["search"] = fresh["search"]
		rec["path"] = [] as Array
		rec["index"] = 0


## A climb transition of the path: the side whose climb lands on `next`, then the
## climb itself. A refused climb means the world changed: re-plan from here.
func _climb_toward(agent: int, rec: Dictionary, goal: Vector3i, here: Vector3i, next: Vector3i) -> void:
	var dir: String = MovementSystem.DIR_UP if next.y > here.y else MovementSystem.DIR_DOWN
	for i: int in MovementSystem.SIDES.size():
		var side: String = MovementSystem.SIDES[i]
		if _movement.climb_target(here, side, dir).has(next):
			_perception.set_facing(agent, FACING_OF_SIDE[i])
			if _movement.climb_onto(agent, next):
				return
			break
	var fresh: Dictionary = _fresh(goal, here)
	rec["state"] = STATE_PLANNING
	rec["search"] = fresh["search"]
	rec["path"] = [] as Array
	rec["index"] = 0


# ---------------------------------------------------------------- helpers

## Horizontal distance: a lower bound on the transitions left, since a climb changes
## the level alone and a fall comes free with a step.
static func _heuristic(a: Vector3i, b: Vector3i) -> int:
	return absi(a.x - b.x) + absi(a.z - b.z)


static func _manhattan(a: Vector3i, b: Vector3i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y) + absi(a.z - b.z)


static func _arr(v: Vector3i) -> Array[int]:
	return [v.x, v.y, v.z] as Array[int]


static func _vec(a: Variant) -> Vector3i:
	var arr: Array = a
	var x: int = arr[0]
	var y: int = arr[1]
	var z: int = arr[2]
	return Vector3i(x, y, z)


static func _parse(key: String) -> Vector3i:
	var parts: PackedStringArray = key.split(",")
	return Vector3i(parts[0].to_int(), parts[1].to_int(), parts[2].to_int())


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 3 or typeof(state.get("routes")) != TYPE_DICTIONARY or typeof(state.get("replan")) != TYPE_BOOL or typeof(state.get("expanded")) != TYPE_INT:
		return _restore_fail("shape")
	var expanded: int = state["expanded"]
	if expanded < 0:
		return _restore_fail("negative count")
	var routes_in: Dictionary = state["routes"]
	var routes: Dictionary = {}
	for key: Variant in routes_in:
		if typeof(key) != TYPE_INT or typeof(routes_in[key]) != TYPE_DICTIONARY:
			return _restore_fail("agent key")
		var agent: int = key
		if not _perception.is_agent(agent):
			return _restore_fail("agent %d is not an agent" % agent)
		var rec: Dictionary = routes_in[key]
		if rec.size() != 5 or not _is_cell(rec.get("goal")) or typeof(rec.get("state")) != TYPE_STRING or typeof(rec.get("path")) != TYPE_ARRAY \
				or typeof(rec.get("index")) != TYPE_INT or typeof(rec.get("search")) != TYPE_DICTIONARY:
			return _restore_fail("agent %d record" % agent)
		var st: String = rec["state"]
		if not [STATE_PLANNING, STATE_FOLLOWING, STATE_ARRIVED, STATE_FAILED].has(st):
			return _restore_fail("agent %d state" % agent)
		var path_in: Array = rec["path"]
		var path: Array = []
		for c: Variant in path_in:
			if not _is_cell(c):
				return _restore_fail("agent %d path cell" % agent)
			path.append(_arr(_vec(c)))
		var index: int = rec["index"]
		if index < 0 or index > path.size():
			return _restore_fail("agent %d index" % agent)
		var search_in: Dictionary = rec["search"]
		var search: Dictionary = {}
		if st == STATE_PLANNING:
			if search_in.size() != 4 or not _is_cell(search_in.get("start")) or typeof(search_in.get("open")) != TYPE_DICTIONARY \
					or typeof(search_in.get("came")) != TYPE_DICTIONARY or typeof(search_in.get("closed")) != TYPE_DICTIONARY:
				return _restore_fail("agent %d search" % agent)
			var open_in: Dictionary = search_in["open"]
			var open: Dictionary = {}
			for k: Variant in open_in:
				if typeof(k) != TYPE_STRING or typeof(open_in[k]) != TYPE_ARRAY:
					return _restore_fail("agent %d open" % agent)
				var entry: Array = open_in[k]
				if entry.size() != 2 or typeof(entry[0]) != TYPE_INT or typeof(entry[1]) != TYPE_INT:
					return _restore_fail("agent %d open entry" % agent)
				var f: int = entry[0]
				var g: int = entry[1]
				open[k] = [f, g] as Array[int]
			var came_in: Dictionary = search_in["came"]
			var came: Dictionary = {}
			for k: Variant in came_in:
				if typeof(k) != TYPE_STRING or typeof(came_in[k]) != TYPE_STRING:
					return _restore_fail("agent %d came" % agent)
				came[k] = came_in[k]
			var closed_in: Dictionary = search_in["closed"]
			var closed: Dictionary = {}
			for k: Variant in closed_in:
				if typeof(k) != TYPE_STRING or typeof(closed_in[k]) != TYPE_BOOL:
					return _restore_fail("agent %d closed" % agent)
				closed[k] = true
			search = {"start": _arr(_vec(search_in["start"])), "open": open, "came": came, "closed": closed}
		elif not search_in.is_empty():
			return _restore_fail("agent %d has a search while %s" % [agent, st])
		routes[agent] = {"goal": _arr(_vec(rec["goal"])), "state": st, "path": path, "index": index, "search": search}
	var replan: bool = state["replan"]
	_routes = routes
	_replan = replan
	_expanded = expanded
	return OK


static func _is_cell(v: Variant) -> bool:
	if typeof(v) != TYPE_ARRAY:
		return false
	var arr: Array = v
	if arr.size() != 3:
		return false
	for c: Variant in arr:
		if typeof(c) != TYPE_INT:
			return false
	return true


func _restore_fail(reason: String) -> Error:
	push_error("PathingSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
