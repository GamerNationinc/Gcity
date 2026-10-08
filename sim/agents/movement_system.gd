## Actor movement on the build grid (M3 claim set P1). One command, `actor.move
## {actor, dx, dz}`, moves a live actor by integer millimetres, capped by its profile's
## `speed_mm_per_tick`, on its storey (y never changes here; climbing is M6 claim 2). A
## move is rejected when it would enter a cell nobody can stand in (a solid piece fills
## it, or nothing holds it up: M6 claim 1), cross a face that carries a non-passable
## piece, or enter a parcel the actor may not `enter` (a land violation). A profile with
## the `drop` move may step into a cell with nothing under it (ADR-011 C).
##
## Gravity (M6 claim 1): every tick, an actor (living or dead) whose cell is not
## standable falls one storey per `fall.ticks_per_storey` ticks of its combat profile
## until it is, with bedrock under MIN_STOREY. On landing after k storeys it takes
## max(0, k - free_storeys) * damage_per_storey on the fall node and `actor.landed`
## is emitted. A falling actor cannot move.
class_name MovementSystem extends SimSystem

const SYSTEM_ID: StringName = &"movement"
const COMMAND_MOVE: StringName = &"actor.move"
const EVENT_LANDED: StringName = &"actor.landed"
const MOVE_DROP: StringName = &"drop"

var _content: ContentDb
var _actors: ActorSystem
var _land: LandSystem
var _build: BuildSystem
var _events: EventBus
var _moves: int = 0
var _blocked: int = 0
## actor id -> {"from": storey the fall began on, "ticks": ticks since the last drop}
var _falling: Dictionary = {}


func _init(content: ContentDb, actors: ActorSystem, land: LandSystem, build: BuildSystem, events: EventBus) -> void:
	_content = content
	_actors = actors
	_land = land
	_build = build
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	for actor: int in _actors.actor_ids():
		var pos: Vector3i = _actors.position_of(actor)
		if _rests(BuildSystem.cell_of(pos)):
			if _falling.has(actor):
				# something was built under it mid-fall: it stops where it is
				_land_at(actor, pos)
			continue
		if not _falling.has(actor):
			_falling[actor] = {"from": BuildSystem.storey_of(pos), "ticks": 0}
		var rec: Dictionary = _falling[actor]
		var ticks: int = rec["ticks"]
		ticks += 1
		rec["ticks"] = ticks
		var per_storey: int = _fall_of(actor)["ticks_per_storey"]
		if ticks < per_storey:
			continue
		rec["ticks"] = 0
		var lower: Vector3i = pos - Vector3i(0, BuildSystem.STOREY_MM, 0)
		var err: Error = _actors.set_position(actor, lower)
		assert(err == OK, "a storey down from a cell in range is in range")
		if _rests(BuildSystem.cell_of(lower)):
			_land_at(actor, lower)


func snapshot() -> Dictionary:
	return {"moves": _moves, "blocked": _blocked, "falling": _falling.duplicate(true)}


func attach(sim: SimRoot) -> Error:
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	return sim.commands().register(COMMAND_MOVE, _on_move)


func move_count() -> int:
	return _moves


func blocked_count() -> int:
	return _blocked


func is_falling(actor: int) -> bool:
	return _falling.has(actor)


func has_move(actor: int, move_id: StringName) -> bool:
	var t: Dictionary = _actors.profile_data(actor)
	if t.is_empty():
		return false
	var moves: Array = t["moves"]
	return moves.has(String(move_id))


func _fall_of(actor: int) -> Dictionary:
	var t: Dictionary = _actors.profile_data(actor)
	return t["fall"]


## Whether an actor in `cell` stays put: something holds it up, or it is on bedrock.
func _rests(cell: Vector3i) -> bool:
	return cell.y <= BuildSystem.MIN_STOREY or _build.is_standable(cell)


func _land_at(actor: int, pos: Vector3i) -> void:
	var rec: Dictionary = _falling[actor]
	_falling.erase(actor)
	var from: int = rec["from"]
	var storeys: int = from - BuildSystem.storey_of(pos)
	if storeys <= 0:
		return
	var fall: Dictionary = _fall_of(actor)
	var free: int = fall["free_storeys"]
	var per: int = fall["damage_per_storey"]
	var node: String = fall["node"]
	var damage: int = 0
	if _actors.is_alive(actor):
		damage = _actors.damage_node(actor, StringName(node), maxi(0, storeys - free) * per)
	_events.emit(EVENT_LANDED, {"actor": actor, "storeys": storeys, "damage": damage})


func speed_of(actor: int) -> int:
	var t: Dictionary = _actors.profile_data(actor)
	if t.is_empty():
		return 0
	return t["speed_mm_per_tick"]


## Applies the move if every rule allows it. Each axis is stepped separately so a
## diagonal move cannot cut a corner through a wall.
func move(actor: int, dx: int, dz: int) -> bool:
	if not _actors.is_alive(actor) or _falling.has(actor):
		return false
	var speed: int = speed_of(actor)
	if absi(dx) > speed or absi(dz) > speed:
		return false
	var from: Vector3i = _actors.position_of(actor)
	var to: Vector3i = from
	for step: Vector3i in [Vector3i(dx, 0, 0), Vector3i(0, 0, dz)]:
		if step == Vector3i.ZERO:
			continue
		var next: Vector3i = to + step
		if not _can_step(actor, to, next):
			_blocked += 1
			return false
		to = next
	if to == from:
		return false
	if _actors.set_position(actor, to) != OK:
		return false
	_moves += 1
	return true


func _can_step(actor: int, from: Vector3i, to: Vector3i) -> bool:
	var from_cell: Vector3i = BuildSystem.cell_of(from)
	var to_cell: Vector3i = BuildSystem.cell_of(to)
	if to_cell != from_cell:
		if _build.cell_piece_at(to_cell) != EntityIds.NONE:
			return false
		if not _build.is_standable(to_cell) and not has_move(actor, MOVE_DROP):
			return false
		var d: Vector3i = to_cell - from_cell
		var facing: String = "px" if d.x > 0 else ("nx" if d.x < 0 else ("pz" if d.z > 0 else "nz"))
		var piece: int = _build.face_piece_at(BuildSystem.face_key(from_cell, facing))
		if piece != EntityIds.NONE:
			var k: Dictionary = _build.kind_data(piece)
			var passable: bool = k["passable"]
			if not passable:
				return false
	if _land.parcel_at(to) != _land.parcel_at(from):
		if not _land.require(to, actor, &"enter"):
			return false
	return true


## {"actor": int, "dx": int, "dz": int}
func _on_move(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 3 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("dx")) != TYPE_INT or typeof(payload.get("dz")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var dx: int = payload["dx"]
	var dz: int = payload["dz"]
	return move(actor, dx, dz)


func restore(state: Dictionary) -> Error:
	if state.size() != 3 or typeof(state.get("moves")) != TYPE_INT or typeof(state.get("blocked")) != TYPE_INT \
			or typeof(state.get("falling")) != TYPE_DICTIONARY:
		push_error("MovementSystem.restore: rejected: shape")
		return ERR_INVALID_DATA
	var moves: int = state["moves"]
	var blocked: int = state["blocked"]
	if moves < 0 or blocked < 0:
		push_error("MovementSystem.restore: rejected: negative counter")
		return ERR_INVALID_DATA
	var falling_in: Dictionary = state["falling"]
	var falling: Dictionary = {}
	for k: Variant in falling_in:
		if typeof(k) != TYPE_INT or typeof(falling_in[k]) != TYPE_DICTIONARY:
			push_error("MovementSystem.restore: rejected: falling actor")
			return ERR_INVALID_DATA
		var actor: int = k
		if not _actors.has_actor(actor):
			push_error("MovementSystem.restore: rejected: falling actor %d does not exist" % actor)
			return ERR_INVALID_DATA
		var rec: Dictionary = falling_in[k]
		if rec.size() != 2 or typeof(rec.get("from")) != TYPE_INT or typeof(rec.get("ticks")) != TYPE_INT:
			push_error("MovementSystem.restore: rejected: falling record")
			return ERR_INVALID_DATA
		var from: int = rec["from"]
		var ticks: int = rec["ticks"]
		var per_storey: int = _fall_of(actor)["ticks_per_storey"]
		if not BuildSystem.is_storey_in_range(from) or ticks < 0 or ticks >= per_storey:
			push_error("MovementSystem.restore: rejected: falling record range")
			return ERR_INVALID_DATA
		falling[actor] = {"from": from, "ticks": ticks}
	_moves = moves
	_blocked = blocked
	_falling = falling
	return OK
