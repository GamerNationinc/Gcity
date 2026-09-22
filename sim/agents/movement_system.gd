## Actor movement on the build grid (M3 claim set P1; M6 spec claim 1). `actor.move
## {actor, dx, dy, dz}` moves a live actor by integer millimetres across the level it
## stands on, capped by its profile's `speed_mm_per_tick`, and by `dy` in whole cell
## levels (-1, 0, +1). A horizontal move is rejected when it would enter a cell a
## solid piece occupies, cross a face carrying a non-passable piece, or enter a
## parcel the actor may not `enter` (a land violation). A level change is rejected
## unless a climbable face (stairs, a ladder) touches the cell left or entered and
## the cell entered is standable: you climb onto something, never into the air.
##
## Standing: a cell is standable when a solid horizontal face carries it from below,
## a solid piece fills the cell beneath, or it is the ground level of a parcel. An
## actor over nothing falls one level a tick, landing on the tick it reaches
## something and taking the profile's `fall_damage_per_level` for every level beyond
## the first. An actor on a climbable face stands on the stairs themselves.
class_name MovementSystem extends SimSystem

const SYSTEM_ID: StringName = &"movement"
const COMMAND_MOVE: StringName = &"actor.move"
const EVENT_FELL: StringName = &"actor.fell"

var _content: ContentDb
var _actors: ActorSystem
var _land: LandSystem
var _build: BuildSystem
var _events: EventBus
var _moves: int = 0
var _blocked: int = 0
var _falls: int = 0
## actor -> levels fallen so far in the current fall; cleared when it lands.
var _falling: Dictionary = {}


func _init(content: ContentDb, actors: ActorSystem, land: LandSystem, build: BuildSystem, events: EventBus) -> void:
	_content = content
	_actors = actors
	_land = land
	_build = build
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


## Gravity: every live actor over nothing descends a level, and lands with damage
## for the levels beyond the first (spec claim 1).
func tick(_sim: SimRoot) -> void:
	for actor: int in _actors.actor_ids():
		if not _actors.is_alive(actor):
			_falling.erase(actor)
			continue
		var pos: Vector3i = _actors.position_of(actor)
		if is_standable(BuildSystem.cell_of(pos)):
			_land_from_fall(actor)
			continue
		var below: Vector3i = pos - Vector3i(0, BuildSystem.CELL, 0)
		if _actors.set_position(actor, below) != OK:
			_land_from_fall(actor)
			continue
		var so_far: int = _falling.get(actor, 0)
		_falling[actor] = so_far + 1
		_falls += 1
		# landing is resolved on the tick the actor reaches something, not the next
		if is_standable(BuildSystem.cell_of(below)):
			_land_from_fall(actor)


func _land_from_fall(actor: int) -> void:
	var levels: int = _falling.get(actor, 0)
	if levels == 0:
		return
	_falling.erase(actor)
	var beyond: int = maxi(levels - 1, 0)
	if beyond == 0:
		return
	var profile: Dictionary = _actors.profile_data(actor)
	var per_level: int = profile["fall_damage_per_level"]
	var damage: int = beyond * per_level
	if damage <= 0:
		return
	var health: Dictionary = _actors.health_of(actor)
	for node: StringName in health:
		_actors.damage_node(actor, node, damage)
		break
	_events.emit(EVENT_FELL, {"actor": actor, "levels": levels, "damage": damage})


func snapshot() -> Dictionary:
	return {"moves": _moves, "blocked": _blocked, "falls": _falls, "falling": _falling.duplicate()}


func attach(sim: SimRoot) -> Error:
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	return sim.commands().register(COMMAND_MOVE, _on_move)


func move_count() -> int:
	return _moves


func blocked_count() -> int:
	return _blocked


func fall_count() -> int:
	return _falls


func is_falling(actor: int) -> bool:
	return _falling.has(actor)


## Whether an actor may stand in `cell`: a solid horizontal face under it, a solid
## piece in the cell below, or the ground level of the parcel it is over.
func is_standable(cell: Vector3i) -> bool:
	if _build.cell_piece_at(cell) != EntityIds.NONE:
		return false
	if cell.y <= BuildSystem.GROUND_CELL_Y:
		return true
	var under: Vector3i = cell - Vector3i(0, 1, 0)
	if _build.cell_piece_at(under) != EntityIds.NONE:
		return true
	# on the stairs themselves: a climbable face carries an actor
	if has_any_climb(cell):
		return true
	var floor_piece: int = _build.face_piece_at(BuildSystem.face_key(cell, "ny"))
	if floor_piece == EntityIds.NONE:
		return false
	var kind: Dictionary = _build.kind_data(floor_piece)
	var passable: bool = kind["passable"]
	return not passable


## Whether a face of `cell` in `facing` carries a climbable piece (stairs, a ladder).
func has_climb(cell: Vector3i, facing: String) -> bool:
	var piece: int = _build.face_piece_at(BuildSystem.face_key(cell, facing))
	if piece == EntityIds.NONE:
		return false
	var kind: Dictionary = _build.kind_data(piece)
	return kind["climb"]


## Whether any side of `cell` carries a climbable piece.
func has_any_climb(cell: Vector3i) -> bool:
	for facing: String in ["px", "nx", "pz", "nz"]:
		if has_climb(cell, facing):
			return true
	return false


func speed_of(actor: int) -> int:
	var t: Dictionary = _actors.profile_data(actor)
	if t.is_empty():
		return 0
	return t["speed_mm_per_tick"]


## Applies the move if every rule allows it. Each axis is stepped separately so a
## diagonal move cannot cut a corner through a wall; the level change, if any, is
## applied first and needs a climbable face on the cell left or entered.
func move(actor: int, dx: int, dz: int, dy: int = 0) -> bool:
	if not _actors.is_alive(actor):
		return false
	var speed: int = speed_of(actor)
	if absi(dx) > speed or absi(dz) > speed or absi(dy) > 1:
		return false
	var from: Vector3i = _actors.position_of(actor)
	var to: Vector3i = from
	if dy != 0:
		var here: Vector3i = BuildSystem.cell_of(from)
		var there: Vector3i = here + Vector3i(0, dy, 0)
		if not has_any_climb(here) and not has_any_climb(there):
			_blocked += 1
			return false
		if _build.cell_piece_at(there) != EntityIds.NONE:
			_blocked += 1
			return false
		# you climb onto something, never into the air: the top of a flight is the top
		if not is_standable(there):
			_blocked += 1
			return false
		# the floor between the two levels must be passable or absent
		var between: String = "py" if dy > 0 else "ny"
		var floor_piece: int = _build.face_piece_at(BuildSystem.face_key(here, between))
		if floor_piece != EntityIds.NONE:
			var k: Dictionary = _build.kind_data(floor_piece)
			var passable: bool = k["passable"]
			if not passable:
				_blocked += 1
				return false
		to.y += dy * BuildSystem.CELL
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


## {"actor": int, "dx": int, "dz": int} or {"actor": int, "dx": int, "dy": int,
## "dz": int}: `dy` is whole cell levels in [-1, 1] (M6 spec claim 1).
func _on_move(_sim: SimRoot, payload: Dictionary) -> bool:
	var has_dy: bool = payload.has("dy")
	if payload.size() != (4 if has_dy else 3) or typeof(payload.get("actor")) != TYPE_INT \
			or typeof(payload.get("dx")) != TYPE_INT or typeof(payload.get("dz")) != TYPE_INT:
		return false
	if has_dy and typeof(payload.get("dy")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var dx: int = payload["dx"]
	var dz: int = payload["dz"]
	var dy: int = payload["dy"] if has_dy else 0
	return move(actor, dx, dz, dy)


func restore(state: Dictionary) -> Error:
	if state.size() != 4 or typeof(state.get("moves")) != TYPE_INT or typeof(state.get("blocked")) != TYPE_INT \
			or typeof(state.get("falls")) != TYPE_INT or typeof(state.get("falling")) != TYPE_DICTIONARY:
		push_error("MovementSystem.restore: rejected: shape")
		return ERR_INVALID_DATA
	var moves: int = state["moves"]
	var blocked: int = state["blocked"]
	var falls: int = state["falls"]
	if moves < 0 or blocked < 0 or falls < 0:
		push_error("MovementSystem.restore: rejected: negative counter")
		return ERR_INVALID_DATA
	var falling_in: Dictionary = state["falling"]
	var falling: Dictionary = {}
	for key: Variant in falling_in:
		if typeof(key) != TYPE_INT or typeof(falling_in[key]) != TYPE_INT:
			push_error("MovementSystem.restore: rejected: falling entry")
			return ERR_INVALID_DATA
		var actor: int = key
		var levels: int = falling_in[key]
		if not _actors.has_actor(actor) or levels < 0:
			push_error("MovementSystem.restore: rejected: falling actor")
			return ERR_INVALID_DATA
		falling[actor] = levels
	_moves = moves
	_blocked = blocked
	_falls = falls
	_falling = falling
	return OK
