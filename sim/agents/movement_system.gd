## Actor movement on the build grid (M3 claim set P1; M6 spec claims 5–6).
## `actor.move {actor, dx, dz}` moves a live actor by integer millimetres, capped by
## its profile's `speed_mm_per_tick`. A move is rejected when it would enter a cell a
## solid piece occupies, cross a face that carries a non-passable piece, or enter a
## parcel the actor may not `enter` (a land violation).
##
## Levels: an actor stands on the floor of its cell, which holds it when the cell is
## on the ground, a horizontal face piece (a floor, a hatch) is under it, or a solid
## cell piece (a foundation, a crate) is under it. A step into a cell that nothing
## holds falls to the first cell that something does. `actor.climb {actor, dir,
## facing}` changes level by the climb rule: up or down a ladder on the face ahead, or
## up onto a climbable cell piece ahead, always to a cell that holds the actor. A
## ladder holds nobody by itself: it only joins two levels that each have a floor, so
## adding one never takes a fall or a step away. The sim holds no facing for the
## player, so the command names the side.
##
## Locks (M6 spec claim 8): a door whose template declares a `lock` lets through only
## an actor carrying an item tagged with its `requires_tag`, and every attempt to pass
## one emits `land.door_check {actor, piece, passed}`. When a build change leaves an
## actor standing on nothing, it falls to where something holds it.
class_name MovementSystem extends SimSystem

const SYSTEM_ID: StringName = &"movement"
const COMMAND_MOVE: StringName = &"actor.move"
const COMMAND_CLIMB: StringName = &"actor.climb"
const SIDES: Array[String] = ["px", "nx", "pz", "nz"]
const DIR_UP: String = "up"
const DIR_DOWN: String = "down"
const EVENT_DOOR_CHECK: StringName = &"land.door_check"

var _content: ContentDb
var _actors: ActorSystem
var _land: LandSystem
var _build: BuildSystem
var _items: ItemSystem
var _stats: StatResolver
var _events: EventBus
var _moves: int = 0
var _blocked: int = 0
## Derived, not state: cell key -> true for every cell a climb could start from (both
## cells of a climbable face, the four cells beside a climbable cell piece). Rebuilt
## on every build change and on restore, so a cell outside it has no climb at one
## lookup: pathing expands every cell through [method climb_targets].
var _climb_cells: Dictionary = {}


func _init(content: ContentDb, actors: ActorSystem, land: LandSystem, build: BuildSystem, items: ItemSystem, stats: StatResolver) -> void:
	_content = content
	_actors = actors
	_land = land
	_build = build
	_items = items
	_stats = stats


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


func snapshot() -> Dictionary:
	return {"moves": _moves, "blocked": _blocked}


func attach(sim: SimRoot, events: EventBus) -> Error:
	_events = events
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	err = events.subscribe(BuildSystem.EVENT_CHANGED, _on_build_changed)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_MOVE, _on_move)
	if err != OK:
		return err
	return sim.commands().register(COMMAND_CLIMB, _on_climb)


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
	var landing: Vector3i = landing_cell(BuildSystem.cell_of(to))
	if landing != BuildSystem.cell_of(to):
		to.y = landing.y * BuildSystem.CELL
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
			if not lock_tag_of(piece).is_empty():
				var passed: bool = may_pass(actor, piece)
				_events.emit(EVENT_DOOR_CHECK, {"actor": actor, "piece": piece, "passed": passed})
				if not passed:
					return false
	if _land.parcel_at(to) != _land.parcel_at(from):
		if not _land.require(to, actor, &"enter"):
			return false
	return true


# ---------------------------------------------------------------- levels

## Whether something holds an actor standing in `cell` (see the class comment).
func is_supported(cell: Vector3i) -> bool:
	if cell.y <= BuildSystem.GROUND_CELL_Y:
		return true
	if _build.cell_piece_at(cell - Vector3i(0, 1, 0)) != EntityIds.NONE:
		return true
	var below: int = _build.face_piece_at(BuildSystem.face_key(cell, "ny"))
	if below != EntityIds.NONE:
		var k: Dictionary = _build.kind_data(below)
		var orientation: String = k["orientation"]
		if orientation == "horizontal":
			return true
	return false


## The cell an actor ends in when it steps into `cell`: the cell itself if something
## holds it there, else the first cell below that something does.
func landing_cell(cell: Vector3i) -> Vector3i:
	var c: Vector3i = cell
	while not is_supported(c):
		c.y -= 1
	return c


## Where climbs from `cell` on the side `facing` in direction `dir` end: none, one,
## or (up, with a ladder against a climbable piece) two cells, the ladder's first:
## - up a ladder: a climbable face piece on that side; the face above passable or
##   empty; the cell above free and something holding it;
## - down a ladder: a climbable face piece on that side of the cell below; the face
##   below passable or empty; the cell below free and something holding it;
## - up onto a climbable cell piece ahead: the face above passable or empty, the cell
##   above free, the side between the two upper cells passable or empty, and the cell
##   on top of the piece free.
## No land check: that is the command's (agents' paths plan without one).
func climb_target(cell: Vector3i, facing: String, dir: String) -> Array[Vector3i]:
	var none: Array[Vector3i] = []
	if not SIDES.has(facing):
		return none
	if dir == DIR_UP and _can_rise(cell):
		return _rise(cell, facing)
	if dir == DIR_DOWN and _can_sink(cell):
		return _sink(cell, facing)
	return none


## Every climb from `cell`, side by side (px, nx, pz, nz), up before down: the targets
## [method climb_target] gives, with the checks the sides share made once. Pathing
## asks this for every cell it expands.
func climb_targets(cell: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if not _climb_cells.has(BuildSystem.cell_key(cell)):
		return out
	var rise: bool = _can_rise(cell)
	var sink: bool = _can_sink(cell)
	if not rise and not sink:
		return out
	for side: String in SIDES:
		if rise:
			out.append_array(_rise(cell, side))
		if sink:
			out.append_array(_sink(cell, side))
	return out


func _on_build_changed(_payload: Dictionary) -> void:
	_index_climbs()
	_settle()


## Everyone a build change left standing on nothing falls, in actor order.
func _settle() -> void:
	for actor: int in _actors.actor_ids():
		if not _actors.is_alive(actor):
			continue
		var pos: Vector3i = _actors.position_of(actor)
		var cell: Vector3i = BuildSystem.cell_of(pos)
		var landing: Vector3i = landing_cell(cell)
		if landing != cell:
			pos.y = landing.y * BuildSystem.CELL
			_actors.set_position(actor, pos)


# ---------------------------------------------------------------- locks

## The tag a piece's lock asks for, or &"" when its template declares no lock.
func lock_tag_of(piece: int) -> StringName:
	var template: StringName = _build.template_of(piece)
	if template.is_empty():
		return &""
	var t: Dictionary = _content.get_entry(BuildSystem.KIND_PIECE, template)
	var lock_v: Variant = t.get("lock")
	if typeof(lock_v) != TYPE_DICTIONARY:
		return &""
	var lock: Dictionary = lock_v
	var tag_s: String = lock["requires_tag"]
	return StringName(tag_s)


## Whether an actor may pass a piece's lock: no lock, or an item in its inventory
## tagged with what the lock asks for. No event: planners ask this; a step asks
## through the move and is a door check.
func may_pass(actor: int, piece: int) -> bool:
	var tag: StringName = lock_tag_of(piece)
	if tag.is_empty():
		return true
	for item: int in _items.items_in(ItemSystem.inventory_of(actor)):
		if _stats.get_tags(item).has(tag):
			return true
	return false


## Whether the lock on the face between two adjacent cells lets an actor through (true
## where there is no face piece or no lock). Pathing plans with it.
func lock_allows(actor: int, from: Vector3i, to: Vector3i) -> bool:
	var d: Vector3i = to - from
	var facing: String = ("p" if d.x > 0 else "n") + "x" if d.x != 0 else (("p" if d.y > 0 else "n") + "y" if d.y != 0 else ("p" if d.z > 0 else "n") + "z")
	var piece: int = _build.face_piece_at(BuildSystem.face_key(from, facing))
	return piece == EntityIds.NONE or may_pass(actor, piece)


func _index_climbs() -> void:
	_climb_cells.clear()
	for id: int in _build.piece_ids():
		if not _is_climb(id):
			continue
		var record: Dictionary = _build.piece(id)
		var face: String = record["face"]
		if not face.is_empty():
			for c: Vector3i in BuildSystem.face_cells(face):
				_climb_cells[BuildSystem.cell_key(c)] = true
		else:
			var c: Vector3i = _build.cell_of_piece(id)
			for side: String in SIDES:
				_climb_cells[BuildSystem.cell_key(c + _side_step(side))] = true


## Up is possible at all: the face above passable or empty and the cell above free.
func _can_rise(cell: Vector3i) -> bool:
	return _open_face(BuildSystem.face_key(cell, "py")) and _build.cell_piece_at(cell + Vector3i(0, 1, 0)) == EntityIds.NONE


## Down is possible at all: above the ground, the face below passable or empty, the
## cell below free and something holding it.
func _can_sink(cell: Vector3i) -> bool:
	var below: Vector3i = cell - Vector3i(0, 1, 0)
	return below.y >= BuildSystem.GROUND_CELL_Y and _open_face(BuildSystem.face_key(cell, "ny")) \
		and _build.cell_piece_at(below) == EntityIds.NONE and is_supported(below)


func _rise(cell: Vector3i, facing: String) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var up: Vector3i = Vector3i(0, 1, 0)
	if _is_climb(_build.face_piece_at(BuildSystem.face_key(cell, facing))) and is_supported(cell + up):
		out.append(cell + up)
	var ahead: Vector3i = cell + _side_step(facing)
	if _is_climb(_build.cell_piece_at(ahead)) and _open_face(BuildSystem.face_key(cell + up, facing)) \
			and _build.cell_piece_at(ahead + up) == EntityIds.NONE:
		out.append(ahead + up)
	return out


func _sink(cell: Vector3i, facing: String) -> Array[Vector3i]:
	var below: Vector3i = cell - Vector3i(0, 1, 0)
	if _is_climb(_build.face_piece_at(BuildSystem.face_key(below, facing))):
		return [below] as Array[Vector3i]
	return [] as Array[Vector3i]


## Climbs a live actor on the side `facing` in direction `dir`, if the climb rule
## and the land allow it: to the first target on that side (a ladder before a piece
## it leans on). It ends at the centre of the target cell, on its floor.
func climb(actor: int, dir: String, facing: String) -> bool:
	if not _actors.is_alive(actor):
		return false
	var targets: Array[Vector3i] = climb_target(BuildSystem.cell_of(_actors.position_of(actor)), facing, dir)
	if targets.is_empty():
		_blocked += 1
		return false
	return _climb_to(actor, targets[0])


## Climbs a live agent to one exact cell of its path, when that cell is a climb from
## where it stands (pathing plans every climb a cell offers, so it names the one).
func climb_onto(actor: int, target: Vector3i) -> bool:
	if not _actors.is_alive(actor) or not climb_targets(BuildSystem.cell_of(_actors.position_of(actor))).has(target):
		_blocked += 1
		return false
	return _climb_to(actor, target)


func _climb_to(actor: int, target: Vector3i) -> bool:
	var from: Vector3i = _actors.position_of(actor)
	var c: int = BuildSystem.CELL
	var to: Vector3i = Vector3i(target.x * c + c / 2, target.y * c, target.z * c + c / 2)
	if _land.parcel_at(to) != _land.parcel_at(from) and not _land.require(to, actor, &"enter"):
		return false
	if _actors.set_position(actor, to) != OK:
		return false
	_moves += 1
	return true


func _is_climb(piece: int) -> bool:
	if piece == EntityIds.NONE:
		return false
	var k: Dictionary = _build.kind_data(piece)
	var climbable: bool = k["climb"]
	return climbable


## A face nothing blocks: empty, or carrying a passable piece.
func _open_face(key: String) -> bool:
	var piece: int = _build.face_piece_at(key)
	if piece == EntityIds.NONE:
		return true
	var k: Dictionary = _build.kind_data(piece)
	var passable: bool = k["passable"]
	return passable


static func _side_step(facing: String) -> Vector3i:
	match facing:
		"px":
			return Vector3i(1, 0, 0)
		"nx":
			return Vector3i(-1, 0, 0)
		"pz":
			return Vector3i(0, 0, 1)
		_:
			return Vector3i(0, 0, -1)


## {"actor": int, "dir": "up" | "down", "facing": "px" | "nx" | "pz" | "nz"}
func _on_climb(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 3 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("dir")) != TYPE_STRING \
			or typeof(payload.get("facing")) != TYPE_STRING:
		return false
	var actor: int = payload["actor"]
	var dir: String = payload["dir"]
	var facing: String = payload["facing"]
	if dir != DIR_UP and dir != DIR_DOWN:
		return false
	return climb(actor, dir, facing)


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
	_index_climbs()
	return OK
