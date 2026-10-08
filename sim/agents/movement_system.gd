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
##
## Climb, mantle and jump (M6 claim 2, ADR-011 C) are timed moves: the command checks
## the profile's `moves` and the geometry, then the actor is held for the move's ticks
## and set down at its destination; nothing else moves it meanwhile. Every move id in
## content must be one this system implements, or assembly fails.
class_name MovementSystem extends SimSystem

const SYSTEM_ID: StringName = &"movement"
const COMMAND_MOVE: StringName = &"actor.move"
const EVENT_LANDED: StringName = &"actor.landed"
const COMMAND_CLIMB: StringName = &"actor.climb"
const COMMAND_MANTLE: StringName = &"actor.mantle"
const COMMAND_JUMP: StringName = &"actor.jump"
const KIND_MOVE: StringName = &"move"
const MOVE_WALK: StringName = &"walk"
const MOVE_DROP: StringName = &"drop"
const MOVE_CLIMB: StringName = &"climb"
const MOVE_MANTLE: StringName = &"mantle"
const MOVE_JUMP: StringName = &"jump"
const IMPLEMENTED_MOVES: Array[StringName] = [MOVE_WALK, MOVE_DROP, MOVE_CLIMB, MOVE_MANTLE, MOVE_JUMP]
const UP: Vector3i = Vector3i(0, 1, 0)

var _content: ContentDb
var _actors: ActorSystem
var _land: LandSystem
var _build: BuildSystem
var _events: EventBus
var _moves: int = 0
var _blocked: int = 0
## actor id -> {"from": storey the fall began on, "ticks": ticks since the last drop}
var _falling: Dictionary = {}
## actor id -> {"move": String, "to": [x, y, z] mm, "ticks": ticks left}
var _in_move: Dictionary = {}


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
		if _in_move.has(actor):
			_advance_move(actor)
			continue
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
	return {"moves": _moves, "blocked": _blocked, "falling": _falling.duplicate(true), "in_move": _in_move.duplicate(true)}


func attach(sim: SimRoot) -> Error:
	var err: Error = validate_content()
	if err != OK:
		return err
	err = sim.register_system(self)
	if err != OK:
		return err
	for pair: Array in [[COMMAND_MOVE, _on_move], [COMMAND_CLIMB, _on_climb], [COMMAND_MANTLE, _on_mantle], [COMMAND_JUMP, _on_jump]]:
		var kind: StringName = pair[0]
		var handler: Callable = pair[1]
		err = sim.commands().register(kind, handler)
		if err != OK:
			return err
	return OK


## Every move in content is implemented here (a profile can only name content moves:
## the schema checks the refs).
func validate_content() -> Error:
	for move_id: StringName in _content.ids(KIND_MOVE):
		if not IMPLEMENTED_MOVES.has(move_id):
			push_error("MovementSystem: content rejected: move/%s has no implementation" % move_id)
			return ERR_INVALID_DATA
	return OK


func move_count() -> int:
	return _moves


func blocked_count() -> int:
	return _blocked


func is_falling(actor: int) -> bool:
	return _falling.has(actor)


func is_moving(actor: int) -> bool:
	return _in_move.has(actor)


## Starts a climb across a stair or a ladder (M6 claim 2). A stair links its foot (the
## cell on its facing side) and its top (the cell above it); a ladder links the cells
## below and above its face. Returns false, changing nothing, when the actor cannot.
func climb(actor: int, piece: int) -> bool:
	if not _can_start(actor, MOVE_CLIMB) or not _build.has_piece(piece):
		return false
	var ticks: int = _build.climb_ticks_of(piece)
	if ticks <= 0:
		return false
	var here: Vector3i = BuildSystem.cell_of(_actors.position_of(actor))
	var low: Vector3i
	var high: Vector3i
	var facing: String = _build.facing_of(piece)
	if facing.is_empty():
		var cells: Array[Vector3i] = _build.cells_of_piece(piece)
		low = cells[0]
		high = cells[1]
	else:
		var stair: Vector3i = _build.cell_of_piece(piece)
		low = stair + _direction(facing)
		high = stair + UP
		if _blocks(BuildSystem.face_key(low, _facing_toward(low, stair))):
			return false
	var to: Vector3i
	if here == low:
		to = high
	elif here == high:
		to = low
	else:
		return false
	if not _build.is_standable(to):
		return false
	return _start(actor, MOVE_CLIMB, to, ticks)


## Starts a mantle onto the top of the adjacent cell piece in (dx, dz), one axis and
## one cell: the piece's kind allows it, there is headroom above the actor, and no
## blocking face stands between it and the piece or the ledge.
func mantle(actor: int, dx: int, dz: int) -> bool:
	if not _can_start(actor, MOVE_MANTLE) or absi(dx) + absi(dz) != 1:
		return false
	var here: Vector3i = BuildSystem.cell_of(_actors.position_of(actor))
	var d: Vector3i = Vector3i(dx, 0, dz)
	var piece: int = _build.cell_piece_at(here + d)
	if piece == EntityIds.NONE or not _build.is_mantleable(piece):
		return false
	var to: Vector3i = here + d + UP
	if not _build.is_standable(to) or _build.cell_piece_at(here + UP) != EntityIds.NONE:
		return false
	if _build.face_piece_at(BuildSystem.face_key(here, "py")) != EntityIds.NONE:
		return false
	var facing: String = _facing_toward(here, here + d)
	if _blocks(BuildSystem.face_key(here, facing)) or _blocks(BuildSystem.face_key(here + UP, facing)):
		return false
	var t: Dictionary = _actors.profile_data(actor)
	var ticks: int = t["mantle_ticks"]
	return _start(actor, MOVE_MANTLE, to, ticks)


## Starts a jump across a one-cell gap in (dx, dz) on the same storey: the middle cell
## holds nobody up and is empty, the landing cell is standable, and neither face
## crossed blocks. Jumps never gain height.
func jump(actor: int, dx: int, dz: int) -> bool:
	if not _can_start(actor, MOVE_JUMP) or absi(dx) + absi(dz) != 1:
		return false
	var here: Vector3i = BuildSystem.cell_of(_actors.position_of(actor))
	var d: Vector3i = Vector3i(dx, 0, dz)
	var middle: Vector3i = here + d
	var to: Vector3i = here + d * 2
	if _build.cell_piece_at(middle) != EntityIds.NONE or _build.is_standable(middle) or not _build.is_standable(to):
		return false
	var facing: String = _facing_toward(here, middle)
	if _blocks(BuildSystem.face_key(here, facing)) or _blocks(BuildSystem.face_key(middle, facing)):
		return false
	var t: Dictionary = _actors.profile_data(actor)
	var ticks: int = t["jump_ticks"]
	return _start(actor, MOVE_JUMP, to, ticks)


func _can_start(actor: int, move_id: StringName) -> bool:
	return _actors.is_alive(actor) and not _falling.has(actor) and not _in_move.has(actor) and has_move(actor, move_id)


## Holds the actor for `ticks` and sets it down in `to`, after the `enter` right of a
## new parcel is checked (a violation refuses the move, as a step would be).
func _start(actor: int, move_id: StringName, to: Vector3i, ticks: int) -> bool:
	var c: int = BuildSystem.CELL
	var dest: Vector3i = Vector3i(to.x * c + c / 2, to.y * BuildSystem.STOREY_MM, to.z * c + c / 2)
	var from: Vector3i = _actors.position_of(actor)
	if _land.parcel_at(dest) != _land.parcel_at(from) and not _land.require(dest, actor, &"enter"):
		return false
	_in_move[actor] = {"move": String(move_id), "to": [dest.x, dest.y, dest.z] as Array[int], "ticks": ticks}
	return true


func _advance_move(actor: int) -> void:
	var rec: Dictionary = _in_move[actor]
	var ticks: int = rec["ticks"]
	ticks -= 1
	if ticks > 0 and _actors.is_alive(actor):
		rec["ticks"] = ticks
		return
	_in_move.erase(actor)
	if not _actors.is_alive(actor):
		# killed mid-move: it stays where it was and gravity takes it from there
		return
	var to: Array = rec["to"]
	var x: int = to[0]
	var y: int = to[1]
	var z: int = to[2]
	var err: Error = _actors.set_position(actor, Vector3i(x, y, z))
	assert(err == OK, "a destination cell in range is in range")


## Whether the face carries a piece that stops a body (a wall, a closed window later).
func _blocks(face: String) -> bool:
	var piece: int = _build.face_piece_at(face)
	if piece == EntityIds.NONE:
		return false
	var k: Dictionary = _build.kind_data(piece)
	var passable: bool = k["passable"]
	return not passable


static func _direction(facing: String) -> Vector3i:
	match facing:
		"px":
			return Vector3i(1, 0, 0)
		"nx":
			return Vector3i(-1, 0, 0)
		"pz":
			return Vector3i(0, 0, 1)
		_:
			return Vector3i(0, 0, -1)


static func _facing_toward(from: Vector3i, to: Vector3i) -> String:
	var d: Vector3i = to - from
	return "px" if d.x > 0 else ("nx" if d.x < 0 else ("pz" if d.z > 0 else "nz"))


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
	if not _actors.is_alive(actor) or _falling.has(actor) or _in_move.has(actor):
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


## {"actor": int, "piece": int}
func _on_climb(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("piece")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var piece: int = payload["piece"]
	return climb(actor, piece)


## {"actor": int, "dx": int, "dz": int}
func _on_mantle(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 3 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("dx")) != TYPE_INT or typeof(payload.get("dz")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var dx: int = payload["dx"]
	var dz: int = payload["dz"]
	return mantle(actor, dx, dz)


## {"actor": int, "dx": int, "dz": int}
func _on_jump(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 3 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("dx")) != TYPE_INT or typeof(payload.get("dz")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var dx: int = payload["dx"]
	var dz: int = payload["dz"]
	return jump(actor, dx, dz)


## {"actor": int, "dx": int, "dz": int}
func _on_move(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 3 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("dx")) != TYPE_INT or typeof(payload.get("dz")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var dx: int = payload["dx"]
	var dz: int = payload["dz"]
	return move(actor, dx, dz)


func restore(state: Dictionary) -> Error:
	if state.size() != 4 or typeof(state.get("moves")) != TYPE_INT or typeof(state.get("blocked")) != TYPE_INT \
			or typeof(state.get("falling")) != TYPE_DICTIONARY or typeof(state.get("in_move")) != TYPE_DICTIONARY:
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
	var in_move_in: Dictionary = state["in_move"]
	var in_move: Dictionary = {}
	for k: Variant in in_move_in:
		if typeof(k) != TYPE_INT or typeof(in_move_in[k]) != TYPE_DICTIONARY:
			push_error("MovementSystem.restore: rejected: moving actor")
			return ERR_INVALID_DATA
		var actor: int = k
		var rec: Dictionary = in_move_in[k]
		if not _actors.has_actor(actor) or falling.has(actor) or rec.size() != 3 or typeof(rec.get("move")) != TYPE_STRING \
				or typeof(rec.get("to")) != TYPE_ARRAY or typeof(rec.get("ticks")) != TYPE_INT:
			push_error("MovementSystem.restore: rejected: move record")
			return ERR_INVALID_DATA
		var move_s: String = rec["move"]
		var ticks: int = rec["ticks"]
		var to: Array = rec["to"]
		if not [MOVE_CLIMB, MOVE_MANTLE, MOVE_JUMP].has(StringName(move_s)) or ticks < 1 or ticks > 10_000 or to.size() != 3 \
				or typeof(to[0]) != TYPE_INT or typeof(to[1]) != TYPE_INT or typeof(to[2]) != TYPE_INT:
			push_error("MovementSystem.restore: rejected: move record range")
			return ERR_INVALID_DATA
		var x: int = to[0]
		var y: int = to[1]
		var z: int = to[2]
		if absi(x) > ActorSystem.MAX_COORD or absi(z) > ActorSystem.MAX_COORD or not BuildSystem.is_storey_in_range(BuildSystem.storey_of(Vector3i(0, y, 0))):
			push_error("MovementSystem.restore: rejected: move destination")
			return ERR_INVALID_DATA
		in_move[actor] = {"move": move_s, "to": [x, y, z] as Array[int], "ticks": ticks}
	_moves = moves
	_blocked = blocked
	_falling = falling
	_in_move = in_move
	return OK
