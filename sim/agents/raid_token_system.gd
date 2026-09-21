## The dumb raid agent (M3 spec claim 9): a token that follows the portal graph's raid
## plan, spending an edge's cost in ticks to cross it, breaching walls as it goes, and
## replanning from its own cell after every crossing (volumes renumber when the graph
## changes). No perception, no steering, no combat: it proves the plan end to end and
## is the skeleton the M8 raid resolution grows on.
class_name RaidTokenSystem extends SimSystem

const SYSTEM_ID: StringName = &"raids"
const COMMAND_SPAWN: StringName = &"raid.spawn"
const EVENT_BREACHED: StringName = &"build.breached"
const EVENT_ARRIVED: StringName = &"raid.arrived"
## Cost units a token works through per tick: a 1 100 wall takes 110 ticks, a door 4.
const TOKEN_SPEED: int = 10
const STATE_MOVING: String = "moving"
const STATE_ARRIVED: String = "arrived"
const STATE_FAILED: String = "failed"

var _content: ContentDb
var _build: BuildSystem
var _portals: PortalGraph
var _events: EventBus
## token id (int, from 1 per run) -> {"cell": [x, y, z], "target": piece, "tool": StringName,
## "crossing": piece or 0, "progress": int, "state": String, "breached": int}
var _tokens: Dictionary = {}
var _next_token: int = 1


func _init(content: ContentDb, build: BuildSystem, portals: PortalGraph, events: EventBus) -> void:
	_content = content
	_build = build
	_portals = portals
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func snapshot() -> Dictionary:
	return {"tokens": _tokens.duplicate(true), "next_token": _next_token}


func attach(sim: SimRoot) -> Error:
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	return sim.commands().register(COMMAND_SPAWN, _on_spawn)


# ---------------------------------------------------------------- queries

func token_ids() -> Array[int]:
	var out: Array[int] = []
	out.assign(_tokens.keys())
	out.sort()
	return out


func token(id: int) -> Dictionary:
	if not _tokens.has(id):
		push_error("RaidTokenSystem: no token %d" % id)
		return {}
	var rec: Dictionary = _tokens[id]
	return rec.duplicate(true)


func state_of(id: int) -> String:
	if not _tokens.has(id):
		return ""
	var rec: Dictionary = _tokens[id]
	return rec["state"]


func cell_of(id: int) -> Vector3i:
	var rec: Dictionary = _tokens[id]
	var c: Array = rec["cell"]
	var x: int = c[0]
	var y: int = c[1]
	var z: int = c[2]
	return Vector3i(x, y, z)


# ---------------------------------------------------------------- spawning

## Plans a raid with the tool class and, if a target is reachable, spawns a token in
## the exterior cell beside the first piece it must cross. Returns the token id or 0.
func spawn(tool_class: StringName) -> int:
	if not _content.has(BuildSystem.KIND_TOOL, tool_class):
		return 0
	var plan: Dictionary = _portals.raid_plan(tool_class)
	var target: int = plan["target"]
	if target == EntityIds.NONE:
		return 0
	var pieces: Array[int] = plan["pieces"]
	var start: Vector3i = _start_cell(pieces, target)
	var id: int = _next_token
	_next_token += 1
	_tokens[id] = {"cell": [start.x, start.y, start.z] as Array[int], "target": target, "tool": tool_class,
		"crossing": EntityIds.NONE, "progress": 0, "state": STATE_MOVING, "breached": 0}
	return id


## The exterior side of the first crossing; beside the target if nothing is crossed.
func _start_cell(pieces: Array[int], target: int) -> Vector3i:
	if pieces.is_empty():
		var c: Vector3i = _build.cell_of_piece(target)
		for d: Vector3i in PortalGraph.NEIGHBOURS:
			if _portals.node_at(c + d) == PortalGraph.EXTERIOR:
				return c + d
		return c
	return _exterior_side(pieces[0])


## The cell on the exterior side of an edge piece (a face's lower cell if both sides
## are outside, which cannot happen for a plan edge).
func _exterior_side(piece: int) -> Vector3i:
	var cells: Array[Vector3i] = _sides(piece)
	for c: Vector3i in cells:
		if _portals.node_at(c) == PortalGraph.EXTERIOR:
			return c
	return cells[0]


## The two air cells an edge piece separates.
func _sides(piece: int) -> Array[Vector3i]:
	var rec: Dictionary = _build.piece(piece)
	var face: String = rec["face"]
	if not face.is_empty():
		return BuildSystem.face_cells(face)
	var c: Vector3i = _build.cell_of_piece(piece)
	var out: Array[Vector3i] = []
	for pair: Array in [[Vector3i(1, 0, 0), Vector3i(-1, 0, 0)], [Vector3i(0, 1, 0), Vector3i(0, -1, 0)], [Vector3i(0, 0, 1), Vector3i(0, 0, -1)]]:
		var d1: Vector3i = pair[0]
		var d2: Vector3i = pair[1]
		var a: int = _portals.node_at(c + d1)
		var b: int = _portals.node_at(c + d2)
		if a != PortalGraph.SOLID and b != PortalGraph.SOLID and a != b:
			out.append(c + d1)
			out.append(c + d2)
			return out
	return [c, c]


# ---------------------------------------------------------------- ticking

func tick(_sim: SimRoot) -> void:
	for id: int in token_ids():
		var rec: Dictionary = _tokens[id]
		if rec["state"] != STATE_MOVING:
			continue
		_advance(id, rec)


func _advance(id: int, rec: Dictionary) -> void:
	var target: int = rec["target"]
	var tool: StringName = rec["tool"]
	if not _build.has_piece(target):
		rec["state"] = STATE_FAILED
		return
	var here: Vector3i = cell_of(id)
	var here_node: int = _portals.node_at(here)
	var targets: Dictionary = _portals.targets()
	var target_node: int = targets.get(target, PortalGraph.SOLID)
	if target_node == PortalGraph.SOLID:
		rec["state"] = STATE_FAILED
		return
	if here_node == target_node:
		rec["state"] = STATE_ARRIVED
		rec["crossing"] = EntityIds.NONE
		_events.emit(EVENT_ARRIVED, {"token": id, "target": target, "x": here.x, "y": here.y, "z": here.z})
		return
	var crossing: int = rec["crossing"]
	if crossing == EntityIds.NONE or not _build.has_piece(crossing):
		var path: Dictionary = _portals.cheapest_path(here_node, target_node, tool)
		var cost: int = path["cost"]
		if cost < 0:
			rec["state"] = STATE_FAILED
			return
		var pieces: Array[int] = path["pieces"]
		if pieces.is_empty():
			rec["state"] = STATE_ARRIVED
			return
		crossing = pieces[0]
		rec["crossing"] = crossing
		rec["progress"] = 0
	var progress: int = rec["progress"] + TOKEN_SPEED
	rec["progress"] = progress
	var needed: int = _portals.edge_cost(crossing, tool)
	if progress < needed:
		return
	# cross: step to the far side, breaching if the piece is not an opening
	var sides: Array[Vector3i] = _sides(crossing)
	var far: Vector3i = sides[1] if sides[0] == here else sides[0]
	var k: Dictionary = _build.kind_data(crossing)
	var passable: bool = k["passable"]
	if not passable:
		var removed: Array[int] = _build.breach(crossing)
		var breached: int = rec["breached"]
		rec["breached"] = breached + removed.size()
		_events.emit(EVENT_BREACHED, {"token": id, "piece": crossing, "removed": removed})
	rec["cell"] = [far.x, far.y, far.z] as Array[int]
	rec["crossing"] = EntityIds.NONE
	rec["progress"] = 0


# ---------------------------------------------------------------- commands

## {"tool": string}: debug-class at M3, like actor.spawn; the threat director (M8)
## schedules real raids.
func _on_spawn(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 1 or typeof(payload.get("tool")) != TYPE_STRING:
		return false
	var tool_s: String = payload["tool"]
	return spawn(StringName(tool_s)) != 0


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 2 or typeof(state.get("tokens")) != TYPE_DICTIONARY or typeof(state.get("next_token")) != TYPE_INT:
		return _restore_fail("shape")
	var next_token: int = state["next_token"]
	if next_token < 1:
		return _restore_fail("next_token")
	var tokens_in: Dictionary = state["tokens"]
	var out: Dictionary = {}
	for tk: Variant in tokens_in:
		if typeof(tk) != TYPE_INT or tk < 1 or tk >= next_token or typeof(tokens_in[tk]) != TYPE_DICTIONARY:
			return _restore_fail("token key or record")
		var rec: Dictionary = tokens_in[tk]
		if rec.size() != 7 or typeof(rec.get("cell")) != TYPE_ARRAY or typeof(rec.get("target")) != TYPE_INT or typeof(rec.get("crossing")) != TYPE_INT \
				or typeof(rec.get("progress")) != TYPE_INT or typeof(rec.get("state")) != TYPE_STRING or typeof(rec.get("breached")) != TYPE_INT:
			return _restore_fail("token %d fields" % tk)
		var c: Array = rec["cell"]
		if c.size() != 3 or typeof(c[0]) != TYPE_INT or typeof(c[1]) != TYPE_INT or typeof(c[2]) != TYPE_INT:
			return _restore_fail("token %d cell" % tk)
		var tool: StringName = LandSystem._as_name(rec.get("tool"))
		if not _content.has(BuildSystem.KIND_TOOL, tool):
			return _restore_fail("token %d tool" % tk)
		var st: String = rec["state"]
		if not [STATE_MOVING, STATE_ARRIVED, STATE_FAILED].has(st):
			return _restore_fail("token %d state" % tk)
		var progress: int = rec["progress"]
		var breached: int = rec["breached"]
		if progress < 0 or breached < 0:
			return _restore_fail("token %d counters" % tk)
		var cx: int = c[0]
		var cy: int = c[1]
		var cz: int = c[2]
		out[tk] = {"cell": [cx, cy, cz] as Array[int], "target": rec["target"], "tool": tool, "crossing": rec["crossing"],
			"progress": progress, "state": st, "breached": breached}
	_tokens = out
	_next_token = next_token
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("RaidTokenSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
