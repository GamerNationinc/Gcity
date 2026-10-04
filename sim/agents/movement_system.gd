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
## its `fall_free_levels`. A level is a 1 m cell, so falls are measured in metres (M7.5
## decision 5); every shipped profile frees one level until claim 6 sets a storey. An actor on a climbable face stands on the stairs themselves.
##
## The body (M7.5 spec claim 1): an actor is `body_cells` cells tall, read from its
## profile, its feet in the lowest. A step, a climb or a level change needs every one
## of those cells free of ground and of cell pieces, no solid floor between two of
## them, and every face it crosses passable at every row of the body. Standing and
## falling are still decided at the feet. `body_fits` is the one test; pathing, squads,
## raid tokens and set-downs ask it rather than keeping their own.
class_name MovementSystem extends SimSystem

const SYSTEM_ID: StringName = &"movement"
const COMMAND_MOVE: StringName = &"actor.move"
const EVENT_FELL: StringName = &"actor.fell"
## Emitted when a move or a fall carries an actor out of a parcel, carrying the tags
## of everything in its inventory: leaving somewhere with something is what an exfil
## objective is (M6 spec claim 9).
const EVENT_LEFT_PARCEL: StringName = &"actor.left_parcel"
const KIND_DOOR_CHECK: StringName = &"door_check"

## The stat behind `has_gravity`.
const STAT_GRAVITY: StringName = &"gravity"
var _content: ContentDb
var _actors: ActorSystem
var _land: LandSystem
var _build: BuildSystem
var _events: EventBus
var _items: ItemSystem
var _stats: StatResolver
var _moves: int = 0
var _blocked: int = 0
var _falls: int = 0
## actor -> levels fallen so far in the current fall; cleared when it lands.
var _falling: Dictionary = {}
## The ground (M7 spec claim 13). Wired by the assembly once the world exists; until
## then, and in a sim built without one, the ground is the flat plane it always was.
var _regions: Regions = null


func _init(content: ContentDb, actors: ActorSystem, land: LandSystem, build: BuildSystem, events: EventBus, items: ItemSystem, stats: StatResolver) -> void:
	_content = content
	_actors = actors
	_land = land
	_build = build
	_events = events
	_items = items
	_stats = stats


func system_id() -> StringName:
	return SYSTEM_ID


## Gravity: every live actor over nothing descends a level, and lands with damage
## for the levels beyond its profile's free drop (M6 spec claim 1, M7.5 claim 7).
func tick(_sim: SimRoot) -> void:
	for actor: int in _actors.actor_ids():
		if not _actors.is_alive(actor):
			_falling.erase(actor)
			continue
		if not has_gravity(actor):
			_falling.erase(actor)  # a body gravity has let go of does not fall, nor land
			continue
		var pos: Vector3i = _actors.position_of(actor)
		if is_standable(BuildSystem.cell_of(pos)) or _in_ground(BuildSystem.cell_of(pos)):
			# an actor put inside the ground stays there rather than falling through it;
			# walking never gets anyone there, only being placed there
			_land_from_fall(actor)
			continue
		var below: Vector3i = pos - Vector3i(0, BuildSystem.CELL, 0)
		if _actors.set_position(actor, below) != OK:
			_land_from_fall(actor)
			continue
		_note_parcel(actor, pos, below)
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
	var profile: Dictionary = _actors.profile_data(actor)
	var free: int = profile["fall_free_levels"]
	var beyond: int = maxi(levels - free, 0)
	if beyond == 0:
		return
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
	err = _events.subscribe(ActorSystem.EVENT_REMOVED, _on_removed)
	if err != OK:
		return err
	return sim.commands().register(COMMAND_MOVE, _on_move)


func _on_removed(payload: Dictionary) -> void:
	var actor: int = payload["actor"]
	_falling.erase(actor)


func set_regions(regions: Regions) -> void:
	_regions = regions


func move_count() -> int:
	return _moves


func blocked_count() -> int:
	return _blocked


func fall_count() -> int:
	return _falls


func is_falling(actor: int) -> bool:
	return _falling.has(actor)


## How many cells tall `actor` is (M7.5 spec claim 1): its profile's `body_cells`, or
## one for an actor without a profile.
func body_cells(actor: int) -> int:
	var t: Dictionary = _actors.profile_data(actor)
	if t.is_empty():
		return 1
	return t["body_cells"]


## Whether `actor`'s own body fits with its feet in `feet`.
func actor_fits(actor: int, feet: Vector3i) -> bool:
	return body_fits(feet, body_cells(actor))


## The body of a combat profile before anyone has it: for placing an actor not yet made.
func profile_body_cells(combat_profile: StringName) -> int:
	if not _content.has(ActorSystem.KIND_PROFILE, combat_profile):
		return 1
	var t: Dictionary = _content.get_entry(ActorSystem.KIND_PROFILE, combat_profile)
	return t["body_cells"]


## Whether a body `height` cells tall fits with its feet in `feet`: none of its cells
## holds ground or a cell piece, and no solid floor lies between two of them.
func body_fits(feet: Vector3i, height: int) -> bool:
	for row: int in height:
		var cell: Vector3i = feet + Vector3i(0, row, 0)
		if _build.cell_piece_at(cell) != EntityIds.NONE or _in_ground(cell):
			return false
		if row > 0 and not _floor_open(cell - Vector3i(0, 1, 0)):
			return false
	return true


## Whether the horizontal face over `lower` is absent or passable.
func _floor_open(lower: Vector3i) -> bool:
	var piece: int = _build.face_piece_at(BuildSystem.face_key(lower, "py"))
	if piece == EntityIds.NONE:
		return true
	var kind: Dictionary = _build.kind_data(piece)
	var passable: bool = kind["passable"]
	return passable


## Whether an actor may stand in `cell`: a solid horizontal face under it, a solid
## piece in the cell below, or the ground level of the parcel it is over.
func is_standable(cell: Vector3i) -> bool:
	if _build.cell_piece_at(cell) != EntityIds.NONE or _in_ground(cell):
		return false
	if _on_ground(cell):
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


## Whether `actor` may pass through `piece`: its kind's `passable`, or, for a door
## that checks (M6 spec claim 4), whether the actor carries an item tagged with the
## piece's access tag. A check the actor fails is a wall to it.
func passes(actor: int, piece: int) -> bool:
	var kind: Dictionary = _build.kind_data(piece)
	var passable: bool = kind["passable"]
	if passable:
		return true
	if _build.kind_of(piece) != KIND_DOOR_CHECK:
		return false
	var wanted: StringName = access_tag_of(piece)
	if wanted.is_empty():
		return false
	return carries_tag(actor, wanted)


## The item tag a door check reads, from the piece's own `access` field.
func access_tag_of(piece: int) -> StringName:
	if _build.kind_of(piece) != KIND_DOOR_CHECK:
		return &""
	var t: Dictionary = _content.get_entry(BuildSystem.KIND_PIECE, _build.template_of(piece))
	var access: String = t["access"]
	return StringName(access)


## Whether any item in the actor's inventory carries the tag.
func carries_tag(actor: int, tag: StringName) -> bool:
	for item: int in _items.items_in(ItemSystem.inventory_of(actor)):
		if _stats.get_tags(item).has(tag):
			return true
	return false


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
## Whether gravity holds the actor (M7.6 spec decision 3): `gravity`, base 1, where it is
## registered (the sandbox's content: fly, 0), else always. Without it a body neither
## falls nor needs a flight to change level; it still fits wherever it is.
func has_gravity(actor: int) -> bool:
	if not _stats.has_stat(STAT_GRAVITY):
		return true
	return _stats.resolve(actor, STAT_GRAVITY) > 0


func move(actor: int, dx: int, dz: int, dy: int = 0) -> bool:
	if not _actors.is_alive(actor):
		return false
	# somebody in a gate goes nowhere until the gate sets them down (M7 spec claim 14)
	if _regions != null and _regions.in_transit(actor):
		return false
	var speed: int = speed_of(actor)
	if absi(dx) > speed or absi(dz) > speed or absi(dy) > 1:
		return false
	var from: Vector3i = _actors.position_of(actor)
	var to: Vector3i = from
	if dy != 0:
		var here: Vector3i = BuildSystem.cell_of(from)
		var there: Vector3i = here + Vector3i(0, dy, 0)
		var flying: bool = not has_gravity(actor)
		if not flying and not has_any_climb(here) and not has_any_climb(there):
			_blocked += 1
			return false
		var height: int = body_cells(actor)
		if _build.cell_piece_at(there) != EntityIds.NONE or not body_fits(there, height):
			_blocked += 1
			return false
		# you climb onto something, never into the air: the top of a flight is the top
		if not flying and not is_standable(there):
			_blocked += 1
			return false
		# every floor a row of the body passes through must be passable or absent
		for row: int in height:
			if not _floor_open(here + Vector3i(0, row if dy > 0 else row - 1, 0)):
				_blocked += 1
				return false
		to.y += dy * BuildSystem.CELL
	for step: Vector3i in [Vector3i(dx, 0, 0), Vector3i(0, 0, dz)]:
		if step == Vector3i.ZERO:
			continue
		var next: Vector3i = to + step
		if not _can_step(actor, to, next):
			# walking uphill (M7 spec claim 13): where a step runs into the ground and the
			# region lets a step climb, it goes up onto it instead
			var up: Vector3i = next + Vector3i(0, BuildSystem.CELL, 0)
			if _climbs_onto(actor, to, next, up):
				to = up
				continue
			_blocked += 1
			return false
		to = next
	if to == from:
		return false
	if _actors.set_position(actor, to) != OK:
		return false
	_moves += 1
	_note_parcel(actor, from, to)
	return true


## Emits `actor.left_parcel` when the step took the actor out of a parcel. Crossing
## straight from one parcel into another is a leaving too: the parcel named is the one
## left, and what the actor carries rides on the payload so an objective can filter it.
func _note_parcel(actor: int, from: Vector3i, to: Vector3i) -> void:
	var left: StringName = _land.parcel_at(from)
	if left.is_empty() or left == _land.parcel_at(to):
		return
	_events.emit(EVENT_LEFT_PARCEL, {"actor": actor, "parcel": left, "tags": carried_tags(actor)})


## Every tag on every item in the actor's inventory, lexically sorted and without
## repeats. A fitted part's tags stay on the part, not on what holds it.
func carried_tags(actor: int) -> Array[String]:
	var seen: Dictionary = {}
	for item: int in _items.items_in(ItemSystem.inventory_of(actor)):
		for tag: StringName in _stats.get_tags(item):
			seen[String(tag)] = true
	var out: Array[String] = []
	for key: Variant in seen:
		var text: String = key
		out.append(text)
	out.sort()
	return out


func _can_step(actor: int, from: Vector3i, to: Vector3i) -> bool:
	var from_cell: Vector3i = BuildSystem.cell_of(from)
	var to_cell: Vector3i = BuildSystem.cell_of(to)
	if _regions != null:
		# a region's edge is a wall; the gate is taken by region.enter, never walked
		if _regions.crosses_edge(from, to) or _regions.is_solid(to_cell):
			return false
	if to_cell != from_cell:
		var height: int = body_cells(actor)
		if not body_fits(to_cell, height):
			return false
		var d: Vector3i = to_cell - from_cell
		var facing: String = "px" if d.x > 0 else ("nx" if d.x < 0 else ("pz" if d.z > 0 else "nz"))
		for row: int in height:
			var piece: int = _build.face_piece_at(BuildSystem.face_key(from_cell + Vector3i(0, row, 0), facing))
			if piece != EntityIds.NONE and not passes(actor, piece):
				return false
	if _land.parcel_at(to) != _land.parcel_at(from):
		if not _land.require(to, actor, &"enter"):
			return false
	return true


## Whether a step that ran into the ground can climb onto it: the region allows a step
## to climb, the cell in the way really is ground and not something built, there is
## headroom above the actor, and the cell above the ground is somewhere to stand.
func _climbs_onto(actor: int, from: Vector3i, blocked: Vector3i, up: Vector3i) -> bool:
	if _regions == null:
		return false
	var from_cell: Vector3i = BuildSystem.cell_of(from)
	if _regions.step_levels(from_cell) < 1 or not _regions.is_solid(BuildSystem.cell_of(blocked)):
		return false
	var above: Vector3i = from + Vector3i(0, BuildSystem.CELL, 0)
	var height: int = body_cells(actor)
	# rising a level: the body's cells one up are clear, and so is the floor over its head
	if not body_fits(BuildSystem.cell_of(above), height) or not _floor_open(from_cell + Vector3i(0, height - 1, 0)):
		return false
	return _can_step(actor, above, up) and is_standable(BuildSystem.cell_of(up))


func _on_ground(cell: Vector3i) -> bool:
	if _regions == null:
		return cell.y <= BuildSystem.GROUND_CELL_Y
	return _regions.stands_on_ground(cell)


func _in_ground(cell: Vector3i) -> bool:
	return _regions != null and _regions.is_solid(cell)


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
