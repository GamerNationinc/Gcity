## Breaching by hand (M6 spec claim 9; ADR-011 C): an actor cuts through a build piece
## with a tool it carries. `build.breach {actor, piece, tool}` starts it when the actor
## stands in a cell the piece touches (either side of a face, or beside a cell piece)
## and the tool is in its inventory; on land where the actor may not `build` it
## proceeds and records one violation (`LandSystem.offend`).
##
## A breach takes the piece's resolved `piece_hp` × the tool class's `hp_factor`
## ticks, one per tick. It stops, keeping nothing, if the actor moves, fires or dies,
## or the piece goes. At its start and at every second of it, `noise.made` carries the
## tool's resolved `noise` (mm) scaled by the piece's resolved `breach_noise`
## (milli-units): what perception hears. At the end the piece is removed through the
## build system's breach path and `build.breached {actor, piece, removed}` is emitted.
class_name BreachSystem extends SimSystem

const SYSTEM_ID: StringName = &"breaches"
const COMMAND_BREACH: StringName = &"build.breach"
const EVENT_BREACHED: StringName = &"build.breached"
## Heard by perception beside `combat.fire`: {source: actor, x, y, z, range_mm}.
const EVENT_NOISE: StringName = &"noise.made"
const STAT_TOOL_NOISE: StringName = &"noise"
const NOISE_EVERY_TICKS: int = SimRoot.TICK_HZ

var _content: ContentDb
var _stats: StatResolver
var _items: ItemSystem
var _actors: ActorSystem
var _build: BuildSystem
var _land: LandSystem
var _events: EventBus
## actor -> {"piece": int, "tool": int, "pos": [x, y, z], "done": int, "total": int}
var _breaches: Dictionary = {}
var _completed: int = 0


func _init(content: ContentDb, stats: StatResolver, items: ItemSystem, actors: ActorSystem, build: BuildSystem, land: LandSystem, events: EventBus) -> void:
	_content = content
	_stats = stats
	_items = items
	_actors = actors
	_build = build
	_land = land
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func snapshot() -> Dictionary:
	return {"breaches": _breaches.duplicate(true), "completed": _completed}


func attach(sim: SimRoot) -> Error:
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_BREACH, _on_breach)
	if err != OK:
		return err
	return _events.subscribe(CombatSystem.EVENT_FIRE, _on_fire)


# ---------------------------------------------------------------- queries

func is_breaching(actor: int) -> bool:
	return _breaches.has(actor)


## [ticks done, ticks in all] of an actor's breach, or [] when it is not breaching.
func progress_of(actor: int) -> Array[int]:
	var out: Array[int] = []
	if not _breaches.has(actor):
		return out
	var rec: Dictionary = _breaches[actor]
	var done: int = rec["done"]
	var total: int = rec["total"]
	out.append(done)
	out.append(total)
	return out


func completed_count() -> int:
	return _completed


## Whether an actor standing in `cell` can reach the piece: a cell the piece touches
## for a face piece, one of the six beside it for a cell piece.
func is_beside(cell: Vector3i, piece: int) -> bool:
	var record: Dictionary = _build.piece(piece)
	var face: String = record["face"]
	if not face.is_empty():
		return BuildSystem.face_cells(face).has(cell)
	var d: Vector3i = cell - _build.cell_of_piece(piece)
	return absi(d.x) + absi(d.y) + absi(d.z) == 1


# ---------------------------------------------------------------- start

## Starts a breach; its first tick of work is this tick's. False, changing nothing, when the actor is
## dead or already breaching, the piece or the tool is not there, or the actor is not
## beside the piece.
func start(actor: int, piece: int, tool: int) -> bool:
	if not _actors.is_alive(actor) or _breaches.has(actor) or not _build.has_piece(piece):
		return false
	if _items.tool_class_of(tool).is_empty() or not _items.items_in(ItemSystem.inventory_of(actor)).has(tool):
		return false
	var pos: Vector3i = _actors.position_of(actor)
	if not is_beside(BuildSystem.cell_of(pos), piece):
		return false
	var tool_class: Dictionary = _content.get_entry(BuildSystem.KIND_TOOL, _items.tool_class_of(tool))
	var hp_factor: int = tool_class["hp_factor"]
	var total: int = maxi(1, _stats.resolve(piece, BuildSystem.STAT_HP) * hp_factor)
	_land.offend(BuildSystem.cell_centre(_build.cell_of_piece(piece)), actor, &"build")
	_breaches[actor] = {"piece": piece, "tool": tool, "pos": [pos.x, pos.y, pos.z] as Array[int], "done": 0, "total": total}
	return true


## {"actor": int, "piece": int, "tool": int}
func _on_breach(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 3 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("piece")) != TYPE_INT \
			or typeof(payload.get("tool")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var piece: int = payload["piece"]
	var tool: int = payload["tool"]
	return start(actor, piece, tool)


# ---------------------------------------------------------------- the tick

func tick(_sim: SimRoot) -> void:
	var actors: Array[int] = []
	for key: Variant in _breaches:
		var id: int = key
		actors.append(id)
	actors.sort()
	for actor: int in actors:
		if not _breaches.has(actor):
			continue
		var rec: Dictionary = _breaches[actor]
		var piece: int = rec["piece"]
		var here: Vector3i = _actors.position_of(actor)
		var pos: Array = rec["pos"]
		var x: int = pos[0]
		var y: int = pos[1]
		var z: int = pos[2]
		var started_at: Vector3i = Vector3i(x, y, z)
		if not _actors.is_alive(actor) or not _build.has_piece(piece) or here != started_at:
			_breaches.erase(actor)
			continue
		_advance(actor)


## One tick of work: the noise when a second starts, the piece's end when it is done.
func _advance(actor: int) -> void:
	var rec: Dictionary = _breaches[actor]
	var done: int = rec["done"]
	var total: int = rec["total"]
	var piece: int = rec["piece"]
	var tool: int = rec["tool"]
	if done % NOISE_EVERY_TICKS == 0:
		var here: Vector3i = _actors.position_of(actor)
		var range_mm: int = maxi(0, _stats.resolve(tool, STAT_TOOL_NOISE)) * maxi(0, _stats.resolve(piece, BuildSystem.STAT_NOISE)) / 1000
		_events.emit(EVENT_NOISE, {"source": actor, "x": here.x, "y": here.y, "z": here.z, "range_mm": range_mm})
	done += 1
	rec["done"] = done
	if done < total:
		return
	_breaches.erase(actor)
	_completed += 1
	var removed: Array[int] = _build.breach(piece)
	_events.emit(EVENT_BREACHED, {"actor": actor, "piece": piece, "removed": removed})


func _on_fire(payload: Dictionary) -> void:
	var shooter_v: Variant = payload.get("shooter")
	if typeof(shooter_v) == TYPE_INT:
		var shooter: int = shooter_v
		_breaches.erase(shooter)


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 2 or typeof(state.get("breaches")) != TYPE_DICTIONARY or typeof(state.get("completed")) != TYPE_INT:
		return _restore_fail("shape")
	var completed: int = state["completed"]
	if completed < 0:
		return _restore_fail("negative count")
	var in_all: Dictionary = state["breaches"]
	var out: Dictionary = {}
	for key: Variant in in_all:
		if typeof(key) != TYPE_INT or typeof(in_all[key]) != TYPE_DICTIONARY:
			return _restore_fail("actor key")
		var actor: int = key
		var rec: Dictionary = in_all[key]
		if rec.size() != 5 or typeof(rec.get("piece")) != TYPE_INT or typeof(rec.get("tool")) != TYPE_INT or typeof(rec.get("pos")) != TYPE_ARRAY \
				or typeof(rec.get("done")) != TYPE_INT or typeof(rec.get("total")) != TYPE_INT:
			return _restore_fail("breach %d fields" % actor)
		var piece: int = rec["piece"]
		var tool: int = rec["tool"]
		var done: int = rec["done"]
		var total: int = rec["total"]
		var pos: Array = rec["pos"]
		if not _actors.has_actor(actor) or not _build.has_piece(piece) or _items.tool_class_of(tool).is_empty():
			return _restore_fail("breach %d references" % actor)
		if done < 0 or total < 1 or done >= total or pos.size() != 3:
			return _restore_fail("breach %d progress" % actor)
		for v: Variant in pos:
			if typeof(v) != TYPE_INT:
				return _restore_fail("breach %d position" % actor)
		var x: int = pos[0]
		var y: int = pos[1]
		var z: int = pos[2]
		out[actor] = {"piece": piece, "tool": tool, "pos": [x, y, z] as Array[int], "done": done, "total": total}
	_breaches = out
	_completed = completed
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("BreachSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
