## The sandbox's own commands (M7.6 spec claims 3–7). Each calls a public method of the
## system that owns the rule, with that system's validation, so the sim still decides.
## Registered only by `SandboxAssembly`: the game's assembly has no `sandbox.*` command.
##
## Claim 3, remove and reset:
## - `sandbox.despawn {actor, cell: [x, y, z], facing}`: removes the living actor whose body
##   is in the cell, its kit moved into the world container the way a squad member going
##   back to a token keeps its kit (M7 claim 12), so nothing is made or lost; with no actor
##   there, the piece in the cell (`facing` "") or on its face (`facing` "px" …), through
##   the build system's own removal, rights and collapse included. Never `actor` itself.
## - `sandbox.clear {actor}`: every other living actor and every piece `actor` may remove.
##   Bodies stay: the dead are traces other systems count, and nothing removes them.
class_name SandboxSystem extends SimSystem

const SYSTEM_ID: StringName = &"sandbox"
const COMMAND_DESPAWN: StringName = &"sandbox.despawn"
const COMMAND_CLEAR: StringName = &"sandbox.clear"
const FACINGS: Array[String] = ["", "px", "nx", "py", "ny", "pz", "nz"]

var _actors: ActorSystem
var _build: BuildSystem
var _movement: MovementSystem
## Actors and pieces the sandbox has removed, for the state hash.
var _removed_actors: int = 0
var _removed_pieces: int = 0


func _init(actors: ActorSystem, build: BuildSystem, movement: MovementSystem) -> void:
	_actors = actors
	_build = build
	_movement = movement


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass  # everything here happens in a command


func snapshot() -> Dictionary:
	return {"removed_actors": _removed_actors, "removed_pieces": _removed_pieces}


func attach(sim: SimRoot) -> Error:
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	for pair: Array in [[COMMAND_DESPAWN, _on_despawn], [COMMAND_CLEAR, _on_clear]]:
		var kind: StringName = pair[0]
		var handler: Callable = pair[1]
		err = sim.commands().register(kind, handler)
		if err != OK:
			return err
	return OK


## The living actor whose body takes up `cell`, or NONE.
func actor_in(cell: Vector3i) -> int:
	for actor: int in _actors.actor_ids():
		if not _actors.is_alive(actor):
			continue
		var feet: Vector3i = BuildSystem.cell_of(_actors.position_of(actor))
		if cell.x == feet.x and cell.z == feet.z and cell.y >= feet.y and cell.y < feet.y + _movement.body_cells(actor):
			return actor
	return EntityIds.NONE


func _on_despawn(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 3 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("facing")) != TYPE_STRING:
		return false
	var actor: int = payload["actor"]
	var facing: String = payload["facing"]
	var cell_v: Variant = _cell(payload.get("cell"))
	if cell_v == null or not FACINGS.has(facing) or not _actors.is_alive(actor):
		return false
	var cell: Vector3i = cell_v
	var target: int = actor_in(cell)
	if target != EntityIds.NONE:
		if target == actor or not _actors.remove(target, ItemSystem.WORLD):
			return false
		_removed_actors += 1
		return true
	var piece: int = _build.cell_piece_at(cell) if facing.is_empty() else _build.face_piece_at(BuildSystem.face_key(cell, facing))
	if piece == EntityIds.NONE:
		return false
	var removed: Array[int] = _build.remove(actor, piece)
	if removed.is_empty():
		return false
	_removed_pieces += removed.size()
	return true


func _on_clear(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 1 or typeof(payload.get("actor")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	if not _actors.is_alive(actor):
		return false
	for other: int in _actors.actor_ids():
		if other != actor and _actors.is_alive(other) and _actors.remove(other, ItemSystem.WORLD):
			_removed_actors += 1
	# a removal collapses what it held up, so the list is read again until nothing more goes
	var progress: bool = true
	while progress:
		progress = false
		for piece: int in _build.piece_ids():
			if not _build.has_piece(piece):
				continue
			var removed: Array[int] = _build.remove(actor, piece)
			if not removed.is_empty():
				_removed_pieces += removed.size()
				progress = true
	return true


## `[x, y, z]` of whole numbers as a cell, or null.
static func _cell(value: Variant) -> Variant:
	if typeof(value) != TYPE_ARRAY:
		return null
	var a: Array = value
	if a.size() != 3:
		return null
	for v: Variant in a:
		if typeof(v) != TYPE_INT:
			return null
	var x: int = a[0]
	var y: int = a[1]
	var z: int = a[2]
	return Vector3i(x, y, z)
