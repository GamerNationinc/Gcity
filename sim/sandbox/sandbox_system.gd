## The sandbox's own commands (M7.6 spec claims 3–7). Each calls a public method of the
## system that owns the rule, with that system's validation, so the sim still decides.
## Registered only by `SandboxAssembly`: the game's assembly has no `sandbox.*` command.
##
## Claim 2, spawn at the cursor:
## - `sandbox.spawn_agent {actor, profile, cell: [x, y, z], facing, kit}`: an agent of any
##   `agent_profile` with its feet in `cell`, refused where its body does not fit, armed
##   with `kit` (`{}` for none, or `{frame, magazine, ammo, rounds}` as a site spawn's kit)
##   and holding it. The same public methods `agent.spawn` and a site's guards use
##   (`PerceptionSystem.spawn`, `ItemSystem.arm`, `ActorSystem.wield`), in one command so
##   a spawn is whole or refused, never a guard left half armed. Items go through
##   `item.spawn` and build pieces through the creator tool's `build.place`.
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
const COMMAND_SPAWN_AGENT: StringName = &"sandbox.spawn_agent"
const KIT_KEYS: Array[String] = ["ammo", "frame", "magazine", "rounds"]
const FACINGS: Array[String] = ["", "px", "nx", "py", "ny", "pz", "nz"]

var _content: ContentDb
var _actors: ActorSystem
var _build: BuildSystem
var _movement: MovementSystem
var _perception: PerceptionSystem
var _items: ItemSystem
## Actors and pieces the sandbox has removed, for the state hash.
var _removed_actors: int = 0
var _removed_pieces: int = 0
var _spawned: int = 0


func _init(content: ContentDb, actors: ActorSystem, build: BuildSystem, movement: MovementSystem, perception: PerceptionSystem, items: ItemSystem) -> void:
	_content = content
	_actors = actors
	_build = build
	_movement = movement
	_perception = perception
	_items = items


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass  # everything here happens in a command


func snapshot() -> Dictionary:
	return {"removed_actors": _removed_actors, "removed_pieces": _removed_pieces, "spawned": _spawned}


func attach(sim: SimRoot) -> Error:
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	for pair: Array in [[COMMAND_DESPAWN, _on_despawn], [COMMAND_CLEAR, _on_clear], [COMMAND_SPAWN_AGENT, _on_spawn_agent]]:
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


func _on_spawn_agent(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 5 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("profile")) != TYPE_STRING \
			or typeof(payload.get("facing")) != TYPE_INT or typeof(payload.get("kit")) != TYPE_DICTIONARY:
		return false
	var actor: int = payload["actor"]
	var profile_s: String = payload["profile"]
	var profile: StringName = StringName(profile_s)
	var facing: int = payload["facing"]
	var kit: Dictionary = payload["kit"]
	var cell_v: Variant = _cell(payload.get("cell"))
	if cell_v == null or not _actors.is_alive(actor) or not _content.has(PerceptionSystem.KIND_AGENT, profile) or facing < 0 or facing > 359:
		return false
	var cell: Vector3i = cell_v
	if absi(cell.x) > BuildSystem.MAX_CELL or absi(cell.y) > BuildSystem.MAX_CELL or absi(cell.z) > BuildSystem.MAX_CELL:
		return false
	if not kit.is_empty() and not _kit_ok(kit):
		return false
	var agent_t: Dictionary = _content.get_entry(PerceptionSystem.KIND_AGENT, profile)
	var combat_s: String = agent_t["combat_profile"]
	var combat_t: Dictionary = _content.get_entry(ActorSystem.KIND_PROFILE, StringName(combat_s))
	var height: int = combat_t["body_cells"]
	if not _movement.body_fits(cell, height):
		return false
	var agent: int = _perception.spawn(profile, cell, facing, 0, "")
	if agent == EntityIds.NONE:
		return false
	_spawned += 1
	if kit.is_empty():
		return true
	var frame_s: String = kit["frame"]
	var magazine_s: String = kit["magazine"]
	var ammo_s: String = kit["ammo"]
	var rounds: int = kit["rounds"]
	var weapon: int = _items.arm(agent, StringName(frame_s), StringName(magazine_s), StringName(ammo_s), rounds, agent * 1000)
	if weapon == EntityIds.NONE or not _actors.wield(agent, weapon):
		push_error("SandboxSystem: agent %d spawned but could not hold %s" % [agent, frame_s])
	return true


## A kit's exact shape, naming templates that exist; whether they fit is `ItemSystem.arm`'s.
func _kit_ok(kit: Dictionary) -> bool:
	var keys: Array = kit.keys()
	keys.sort()
	if keys != KIT_KEYS or typeof(kit["rounds"]) != TYPE_INT:
		return false
	for pair: Array in [["frame", ItemSystem.KIND_FRAME], ["magazine", ItemSystem.KIND_PART], ["ammo", ItemSystem.KIND_AMMO]]:
		var key: String = pair[0]
		var kind: StringName = pair[1]
		if typeof(kit[key]) != TYPE_STRING:
			return false
		var id_s: String = kit[key]
		if not _content.has(kind, StringName(id_s)):
			return false
	var rounds: int = kit["rounds"]
	return rounds >= 0 and rounds <= ItemSystem.MAX_SPAWN_COUNT


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
