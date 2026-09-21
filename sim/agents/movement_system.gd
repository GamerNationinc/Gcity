## Actor movement on the build grid (M3 claim set P1). One command, `actor.move
## {actor, dx, dz}`, moves a live actor by integer millimetres, capped by its profile's
## `speed_mm_per_tick`, on flat ground (y stays 0 at M3). A move is rejected when it
## would enter a cell a solid piece occupies, cross a face that carries a non-passable
## piece, or enter a parcel the actor may not `enter` (a land violation).
class_name MovementSystem extends SimSystem

const SYSTEM_ID: StringName = &"movement"
const COMMAND_MOVE: StringName = &"actor.move"

var _content: ContentDb
var _actors: ActorSystem
var _land: LandSystem
var _build: BuildSystem
var _moves: int = 0
var _blocked: int = 0


func _init(content: ContentDb, actors: ActorSystem, land: LandSystem, build: BuildSystem) -> void:
	_content = content
	_actors = actors
	_land = land
	_build = build


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


func snapshot() -> Dictionary:
	return {"moves": _moves, "blocked": _blocked}


func attach(sim: SimRoot) -> Error:
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	return sim.commands().register(COMMAND_MOVE, _on_move)


func move_count() -> int:
	return _moves


func blocked_count() -> int:
	return _blocked


func speed_of(actor: int) -> int:
	var t: Dictionary = _actors.profile_data(actor)
	if t.is_empty():
		return 0
	return t["speed_mm_per_tick"]


## Applies the move if every rule allows it. Each axis is stepped separately so a
## diagonal move cannot cut a corner through a wall.
func move(actor: int, dx: int, dz: int) -> bool:
	if not _actors.is_alive(actor):
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
	if state.size() != 2 or typeof(state.get("moves")) != TYPE_INT or typeof(state.get("blocked")) != TYPE_INT:
		push_error("MovementSystem.restore: rejected: shape")
		return ERR_INVALID_DATA
	var moves: int = state["moves"]
	var blocked: int = state["blocked"]
	if moves < 0 or blocked < 0:
		push_error("MovementSystem.restore: rejected: negative counter")
		return ERR_INVALID_DATA
	_moves = moves
	_blocked = blocked
	return OK
