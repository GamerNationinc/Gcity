## Build pieces on the 1 m build grid: placement, removal and structural support
## (design doc §8.3; M3 spec claims 1–4).
##
## A cell is Vector3i(floor(x / 1000), floor(y / 1000), floor(z / 1000)). Cell pieces
## (foundations, crates) occupy a cell; face pieces (walls, floors, doors, windows,
## hatches) occupy one face of a cell, stored canonically as the lower cell along the
## face's axis plus that axis, so a wall placed from either side is the same face.
##
## Support: a piece is supported if it reaches a ground-level foundation through a
## chain of touching pieces no longer than its material's `max_span`. Placement that
## would be unsupported is rejected; removal collapses whatever it left unsupported, in
## one deterministic pass on the tick of the change. Every successful change emits
## `build.changed {added, removed, actor}` for the portal graph and the quests.
class_name BuildSystem extends SimSystem

const SYSTEM_ID: StringName = &"build"
const KIND_PIECE: StringName = &"build_piece"
const KIND_PIECE_KIND: StringName = &"piece_kind"
const KIND_MATERIAL: StringName = &"material"
const KIND_TOOL: StringName = &"tool_class"
const COMMAND_PLACE: StringName = &"build.place"
const COMMAND_REMOVE: StringName = &"build.remove"
const EVENT_CHANGED: StringName = &"build.changed"
const COMMAND_BREACH: StringName = &"build.breach"
## {actor, piece, removed} from a player's breach (M6 claim 4); raid tokens emit the
## same event with `token` in place of `actor`.
const EVENT_BREACHED: StringName = &"build.breached"
const COMMAND_OPEN: StringName = &"opening.open"
const COMMAND_CLOSE: StringName = &"opening.close"
## {piece, open, actor}: an opening changed state (M6 claim 3); sensors and run records
## listen for it.
const EVENT_OPENING: StringName = &"opening.changed"
const STAT_HP: StringName = &"piece_hp"
const STAT_NOISE: StringName = &"breach_noise"
const CELL: int = 1000
const GROUND_CELL_Y: int = 0
## A storey is one build cell (M6 spec claim 1, as amended): one wall piece spans it and
## a horizontal face is the floor of the storey above. Actors stand on storeys
## MIN_STOREY..MAX_STOREY only.
const STOREY_MM: int = CELL
const MIN_STOREY: int = -1
const MAX_STOREY: int = 2
const MAX_CELL: int = 100_000
const FACINGS: Array[String] = ["px", "nx", "py", "ny", "pz", "nz"]
## Facings a cell piece of orientation `facing` may take: the side its foot is on.
const LEVEL_FACINGS: Array[String] = ["px", "nx", "pz", "nz"]
const AXES: Array[String] = ["x", "y", "z"]

var _content: ContentDb
var _stats: StatResolver
var _ids: EntityIds
var _land: LandSystem
var _actors: ActorSystem
var _events: EventBus
## piece id -> {"template": StringName, "cell": [x, y, z], "face": "" | "x,y,z|axis",
##   "facing": "" | px/nx/pz/nz (a cell piece of orientation `facing`: M6 claim 2),
##   "open": bool (openings only; M6 claim 3)}
var _pieces: Dictionary = {}
## derived: "x,y,z" -> piece id (cell pieces); "x,y,z|axis" -> piece id (face pieces)
var _occupied: Dictionary = {}
## ground faces ("x,-1,z|y") a piece has been set into: the ground there is cut for good,
## so a cut grate leaves a hole (M6 claim 3)
var _holes: Dictionary = {}
## func(actor: int, tag: StringName) -> bool: the actor carries the credential (installed
## at assembly from the item system); unset, every lock stays shut
var _credential: Callable = Callable()
## func(cell: Vector3i) -> bool: the cell is inside an enclosed volume (installed at
## assembly from the portal graph); unset, every latch stays shut
var _inside: Callable = Callable()
## func(actor: int) -> bool: the actor has its footing (installed at assembly from the
## movement system); unset, nobody can breach
var _footing: Callable = Callable()
## actor id -> {"piece": int, "ticks": ticks left, "pos": [x, y, z], "health": int}
## (a player's breach under way: M6 claim 4)
var _breaching: Dictionary = {}


func _init(content: ContentDb, stats: StatResolver, ids: EntityIds, land: LandSystem, actors: ActorSystem, events: EventBus) -> void:
	_content = content
	_stats = stats
	_ids = ids
	_land = land
	_actors = actors
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	var actors: Array = _breaching.keys()
	actors.sort()
	for a: Variant in actors:
		var actor: int = a
		var rec: Dictionary = _breaching[actor]
		var piece: int = rec["piece"]
		var pos: Array = rec["pos"]
		var health: int = rec["health"]
		var px: int = pos[0]
		var py: int = pos[1]
		var pz: int = pos[2]
		if not _pieces.has(piece) or not _actors.is_alive(actor) or not _footing.is_valid() or not _footing.call(actor) \
				or _actors.position_of(actor) != Vector3i(px, py, pz) or _health_total(actor) < health:
			_breaching.erase(actor)
			continue
		var ticks: int = rec["ticks"]
		ticks -= 1
		if ticks > 0:
			rec["ticks"] = ticks
			continue
		_breaching.erase(actor)
		var removed: Array[int] = breach(piece)
		_events.emit(EVENT_BREACHED, {"actor": actor, "piece": piece, "removed": removed})


func snapshot() -> Dictionary:
	var holes: Array = _holes.keys()
	holes.sort()
	return {"pieces": _pieces.duplicate(true), "holes": holes, "breaching": _breaching.duplicate(true)}


func attach(sim: SimRoot) -> Error:
	var err: Error = validate_content()
	if err != OK:
		return err
	err = sim.register_system(self)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_PLACE, _on_place)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_BREACH, _on_breach)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_OPEN, _on_open)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_CLOSE, _on_close)
	if err != OK:
		return err
	return sim.commands().register(COMMAND_REMOVE, _on_remove)


func set_credential_check(check: Callable) -> void:
	_credential = check


func set_inside_check(check: Callable) -> void:
	_inside = check


func set_footing_check(check: Callable) -> void:
	_footing = check


# ---------------------------------------------------------------- content validation

## The two stats exist; at least one foundation kind exists; passable pieces are faces;
## targets are cells. Shape and references were checked at build time.
func validate_content() -> Error:
	for stat: StringName in [STAT_HP, STAT_NOISE]:
		if not _stats.has_stat(stat):
			return _content_fail("stat/%s is not registered" % stat)
	var has_root: bool = false
	for kind: StringName in _content.ids(KIND_PIECE_KIND):
		var k: Dictionary = _content.get_entry(KIND_PIECE_KIND, kind)
		var occupies: String = k["occupies"]
		var passable: bool = k["passable"]
		var target: bool = k["target"]
		if passable and occupies != "face":
			return _content_fail("piece_kind/%s is passable but not a face" % kind)
		if target and occupies != "cell":
			return _content_fail("piece_kind/%s is a target but not a cell" % kind)
		var orientation: String = k["orientation"]
		if orientation == "facing" and occupies != "cell":
			return _content_fail("piece_kind/%s takes a facing but is not a cell" % kind)
		var climb: int = k["climb_ticks"]
		if climb > 0 and not (orientation == "facing" or (occupies == "face" and orientation == "horizontal" and passable)):
			return _content_fail("piece_kind/%s is climbable but neither a stair nor a ladder" % kind)
		var mantle: bool = k["mantle"]
		if mantle and occupies != "cell":
			return _content_fail("piece_kind/%s can be mantled but is not a cell" % kind)
		var transparent: bool = k["transparent"]
		if transparent and not passable:
			return _content_fail("piece_kind/%s is transparent but not an opening" % kind)
		if kind == &"foundation":
			has_root = true
	for template: StringName in _content.ids(KIND_PIECE):
		var t: Dictionary = _content.get_entry(KIND_PIECE, template)
		var tk: Dictionary = _content.get_entry(KIND_PIECE_KIND, LandSystem._as_name(t["kind"]))
		var opening_kind: bool = tk["passable"]
		var starts_open: bool = t["starts_open"]
		var lock: String = t["lock"]
		var latched: bool = t["latched"]
		if not opening_kind and (starts_open or not lock.is_empty() or latched):
			return _content_fail("build_piece/%s has an opening's state but is not an opening" % template)
	if not has_root:
		return _content_fail("piece_kind/foundation must exist: it is the root of support")
	return OK


func _content_fail(reason: String) -> Error:
	push_error("BuildSystem: content rejected: %s" % reason)
	return ERR_INVALID_DATA


# ---------------------------------------------------------------- queries

static func cell_of(position: Vector3i) -> Vector3i:
	return Vector3i(floori(float(position.x) / CELL), floori(float(position.y) / CELL), floori(float(position.z) / CELL))


static func cell_centre(cell: Vector3i) -> Vector3i:
	return cell * CELL + Vector3i(CELL / 2, CELL / 2, CELL / 2)


static func cell_key(cell: Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]


## Canonical face key for the face of `cell` in direction `facing`: the lower cell
## along the axis, then the axis. "" if the facing is unknown.
static func face_key(cell: Vector3i, facing: String) -> String:
	if not FACINGS.has(facing):
		return ""
	var axis: String = facing.substr(1, 1)
	var lower: Vector3i = cell
	if facing.begins_with("n"):
		match axis:
			"x":
				lower.x -= 1
			"y":
				lower.y -= 1
			_:
				lower.z -= 1
	return "%s|%s" % [cell_key(lower), axis]


## The two cells a face separates: the lower one and its positive neighbour.
static func face_cells(key: String) -> Array[Vector3i]:
	var parts: PackedStringArray = key.split("|")
	var coords: PackedStringArray = parts[0].split(",")
	var lower: Vector3i = Vector3i(coords[0].to_int(), coords[1].to_int(), coords[2].to_int())
	var upper: Vector3i = lower
	match parts[1]:
		"x":
			upper.x += 1
		"y":
			upper.y += 1
		_:
			upper.z += 1
	return [lower, upper]


static func storey_of(position: Vector3i) -> int:
	return floori(float(position.y) / STOREY_MM)


static func is_storey_in_range(storey: int) -> bool:
	return storey >= MIN_STOREY and storey <= MAX_STOREY


## Whether an actor can stand in `cell` (M6 spec claim 1): the cell is free of cell
## pieces, on a storey in range, and held up by the ground (storey 0), bedrock
## (MIN_STOREY: there is no terrain before M7), a horizontal face piece under it, or a
## cell piece directly below it.
func is_standable(cell: Vector3i) -> bool:
	if not is_storey_in_range(cell.y) or _occupied.has(cell_key(cell)):
		return false
	if cell.y == MIN_STOREY:
		return true
	var under: String = face_key(cell, "ny")
	var floor_id: int = face_piece_at(under)
	if floor_id != EntityIds.NONE:
		# an open horizontal opening is a hole (M6 claim 3)
		return not is_open(floor_id)
	if cell_piece_at(cell + Vector3i(0, -1, 0)) != EntityIds.NONE:
		return true
	return cell.y == GROUND_CELL_Y and not _holes.has(under)


func has_piece(id: int) -> bool:
	return _pieces.has(id)


func piece_ids() -> Array[int]:
	var out: Array[int] = []
	out.assign(_pieces.keys())
	out.sort()
	return out


func piece(id: int) -> Dictionary:
	if not _pieces.has(id):
		push_error("BuildSystem: no piece %d" % id)
		return {}
	var record: Dictionary = _pieces[id]
	return record.duplicate(true)


func template_of(id: int) -> StringName:
	if not _pieces.has(id):
		return &""
	var record: Dictionary = _pieces[id]
	return record["template"]


func kind_of(id: int) -> StringName:
	var template: StringName = template_of(id)
	if template.is_empty():
		return &""
	var t: Dictionary = _content.get_entry(KIND_PIECE, template)
	return LandSystem._as_name(t["kind"])


func kind_data(id: int) -> Dictionary:
	var kind: StringName = kind_of(id)
	if kind.is_empty():
		return {}
	return _content.get_entry(KIND_PIECE_KIND, kind)


func is_open(id: int) -> bool:
	if not _pieces.has(id):
		return false
	var record: Dictionary = _pieces[id]
	return record["open"]


## Whether the piece is an opening: a passable face whose state can change.
func is_opening(id: int) -> bool:
	var k: Dictionary = kind_data(id)
	if k.is_empty():
		return false
	return k["passable"]


## Whether the face stops a body: a solid piece, or an opening that is closed (M6
## claim 3). Movement, climbing and pathing ask this.
func blocks_passage(face: String) -> bool:
	var id: int = face_piece_at(face)
	if id == EntityIds.NONE:
		return false
	return not (is_opening(id) and is_open(id))


## Whether the face stops sight: a solid piece, or a closed opening that is not
## transparent (a window passes sight open or closed: M6 claim 3).
func blocks_sight(face: String) -> bool:
	var id: int = face_piece_at(face)
	if id == EntityIds.NONE:
		return false
	if not is_opening(id):
		return true
	var k: Dictionary = kind_data(id)
	var transparent: bool = k["transparent"]
	return not is_open(id) and not transparent


## Opens or closes an opening (M6 claim 3). The actor must be alive and stand in one of
## the two cells the face separates. Opening a locked piece needs the credential carried;
## opening a latched one, the actor's cell inside an enclosed volume. Returns false,
## changing nothing, otherwise or when the piece is already in that state.
func set_open(actor: int, id: int, open: bool) -> bool:
	if not _actors.is_alive(actor) or not _pieces.has(id) or not is_opening(id) or is_open(id) == open:
		return false
	var here: Vector3i = cell_of(_actors.position_of(actor))
	if not cells_of_piece(id).has(here):
		return false
	if open:
		var t: Dictionary = _content.get_entry(KIND_PIECE, template_of(id))
		var lock: String = t["lock"]
		var latched: bool = t["latched"]
		if not lock.is_empty():
			if not _credential.is_valid() or not _credential.call(actor, StringName(lock)):
				return false
		elif latched:
			if not _inside.is_valid() or not _inside.call(here):
				return false
	var record: Dictionary = _pieces[id]
	record["open"] = open
	_events.emit(EVENT_OPENING, {"piece": id, "open": open, "actor": actor})
	return true


## The side a stair's foot is on ("" for every other piece).
func facing_of(id: int) -> String:
	if not _pieces.has(id):
		return ""
	var record: Dictionary = _pieces[id]
	return record["facing"]


## Ticks to climb the piece (0: not climbable): a stair or a ladder (M6 claim 2).
func climb_ticks_of(id: int) -> int:
	var k: Dictionary = kind_data(id)
	if k.is_empty():
		return 0
	return k["climb_ticks"]


func is_mantleable(id: int) -> bool:
	var k: Dictionary = kind_data(id)
	if k.is_empty():
		return false
	return k["mantle"]


func material_of(id: int) -> StringName:
	var template: StringName = template_of(id)
	if template.is_empty():
		return &""
	var t: Dictionary = _content.get_entry(KIND_PIECE, template)
	return LandSystem._as_name(t["material"])


func cell_piece_at(cell: Vector3i) -> int:
	var v: Variant = _occupied.get(cell_key(cell))
	if typeof(v) != TYPE_INT:
		return EntityIds.NONE
	var id: int = v
	return id


func face_piece_at(key: String) -> int:
	var v: Variant = _occupied.get(key)
	if typeof(v) != TYPE_INT:
		return EntityIds.NONE
	var id: int = v
	return id


## The cell of a piece, or for a face piece the lower of its two cells.
func cell_of_piece(id: int) -> Vector3i:
	var record: Dictionary = _pieces[id]
	var c: Array = record["cell"]
	var x: int = c[0]
	var y: int = c[1]
	var z: int = c[2]
	return Vector3i(x, y, z)


## The cells a piece touches: one for a cell piece, two for a face piece.
func cells_of_piece(id: int) -> Array[Vector3i]:
	var record: Dictionary = _pieces[id]
	var face: String = record["face"]
	if face.is_empty():
		return [cell_of_piece(id)]
	return face_cells(face)


## Piece ids whose support distance from a ground foundation is within their span.
## Recomputed over the whole set on every change (M3 assumption: sizes are small;
## claim 10 records the cost).
func supported_set() -> Dictionary:
	var by_cell: Dictionary = {}
	for id: int in _pieces:
		for c: Vector3i in cells_of_piece(id):
			var key: String = cell_key(c)
			if not by_cell.has(key):
				by_cell[key] = [] as Array[int]
			var list: Array[int] = by_cell[key]
			list.append(id)
	var depth: Dictionary = {}
	var frontier: Array[int] = []
	for id: int in piece_ids():
		if kind_of(id) == &"foundation" and cell_of_piece(id).y == GROUND_CELL_Y:
			depth[id] = 0
			frontier.append(id)
	var head: int = 0
	while head < frontier.size():
		var id: int = frontier[head]
		head += 1
		var d: int = depth[id]
		var neighbours: Array[int] = []
		for c: Vector3i in cells_of_piece(id):
			for offset: Vector3i in [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				var key: String = cell_key(c + offset)
				if by_cell.has(key):
					var list: Array[int] = by_cell[key]
					for other: int in list:
						if not neighbours.has(other):
							neighbours.append(other)
		neighbours.sort()
		for other: int in neighbours:
			if depth.has(other):
				continue
			var span: int = _max_span(other)
			if d + 1 > span:
				continue
			depth[other] = d + 1
			frontier.append(other)
	return depth


func is_supported(id: int) -> bool:
	return supported_set().has(id)


func _max_span(id: int) -> int:
	var m: Dictionary = _content.get_entry(KIND_MATERIAL, material_of(id))
	return m["max_span"]


# ---------------------------------------------------------------- operations

## Places `template` in the cell containing `position` (face pieces on the face in
## `facing`). Returns the piece id or EntityIds.NONE.
func place(actor: int, template: StringName, position: Vector3i, facing: String) -> int:
	if not _actors.has_actor(actor) or not _content.has(KIND_PIECE, template):
		return EntityIds.NONE
	if absi(position.x) > MAX_CELL * CELL or absi(position.y) > MAX_CELL * CELL or absi(position.z) > MAX_CELL * CELL:
		return EntityIds.NONE
	var t: Dictionary = _content.get_entry(KIND_PIECE, template)
	var kind: StringName = LandSystem._as_name(t["kind"])
	var k: Dictionary = _content.get_entry(KIND_PIECE_KIND, kind)
	var occupies: String = k["occupies"]
	var cell: Vector3i = cell_of(position)
	var face: String = ""
	if occupies == "face":
		face = face_key(cell, facing)
		if face.is_empty():
			return EntityIds.NONE
		var orientation: String = k["orientation"]
		var axis: String = facing.substr(1, 1)
		if orientation == "vertical" and axis == "y":
			return EntityIds.NONE
		if orientation == "horizontal" and axis != "y":
			return EntityIds.NONE
		if _occupied.has(face):
			return EntityIds.NONE
	else:
		var orientation_c: String = k["orientation"]
		if orientation_c == "facing":
			if not LEVEL_FACINGS.has(facing):
				return EntityIds.NONE
		elif not facing.is_empty():
			return EntityIds.NONE
		if _occupied.has(cell_key(cell)):
			return EntityIds.NONE
		if kind == &"foundation" and cell.y != GROUND_CELL_Y:
			return EntityIds.NONE
		if _actor_in(cell):
			return EntityIds.NONE
	if not _land.require(cell_centre(cell), actor, &"build"):
		return EntityIds.NONE
	var id: int = _ids.allocate()
	var lower: Vector3i = cell if face.is_empty() else face_cells(face)[0]
	var piece_facing: String = facing if face.is_empty() else ""
	var starts_open: bool = t["starts_open"]
	_pieces[id] = {"template": template, "cell": [lower.x, lower.y, lower.z] as Array[int], "face": face, "facing": piece_facing, "open": starts_open}
	_occupied[face if not face.is_empty() else cell_key(cell)] = id
	if not supported_set().has(id):
		_occupied.erase(face if not face.is_empty() else cell_key(cell))
		_pieces.erase(id)
		return EntityIds.NONE
	if not face.is_empty() and face.ends_with("|y") and lower.y == GROUND_CELL_Y - 1:
		_holes[face] = true
	var m: Dictionary = _content.get_entry(KIND_MATERIAL, material_of(id))
	var hp: int = m["hp"]
	var noise: int = m["breach_noise"]
	_stats.set_base(id, STAT_HP, hp)
	_stats.set_base(id, STAT_NOISE, noise)
	_events.emit(EVENT_CHANGED, {"added": [id] as Array[int], "removed": [] as Array[int], "actor": actor})
	return id


## Removes a piece and collapses whatever it left unsupported. Returns the removed
## ids in ascending order, or an empty array if nothing was removed.
func remove(actor: int, id: int) -> Array[int]:
	var none: Array[int] = []
	if not _actors.has_actor(actor) or not _pieces.has(id):
		return none
	if not _land.require(cell_centre(cell_of_piece(id)), actor, &"build"):
		return none
	return _remove_and_collapse([id], actor)


## Whether a living actor stands in `cell` (M6 spec claim 1: no piece is built into one).
func _actor_in(cell: Vector3i) -> bool:
	for a: int in _actors.actor_ids():
		if _actors.is_alive(a) and cell_of(_actors.position_of(a)) == cell:
			return true
	return false


func is_breaching(actor: int) -> bool:
	return _breaching.has(actor)


## Starts a player's breach (M6 claim 4): a living actor with its footing, not already
## breaching, standing at the piece (in one of a face's two cells, or beside a cell
## piece), wielding a tool of the material's breach class. Breaching where the actor
## lacks `build` is recorded as a violation and goes ahead. The piece comes out after
## the material's breach_ticks unless the actor moves, is hurt, dies or loses its footing.
func start_breach(actor: int, id: int) -> bool:
	if not _actors.is_alive(actor) or _breaching.has(actor) or not _pieces.has(id):
		return false
	if not _footing.is_valid() or not _footing.call(actor):
		return false
	var here: Vector3i = cell_of(_actors.position_of(actor))
	var face: String = _pieces[id]["face"]
	if face.is_empty():
		var d: Vector3i = here - cell_of_piece(id)
		if absi(d.x) + absi(d.y) + absi(d.z) != 1:
			return false
	elif not cells_of_piece(id).has(here):
		return false
	var m: Dictionary = _content.get_entry(KIND_MATERIAL, material_of(id))
	if _actors.wielded_tool_class(actor) != LandSystem._as_name(m["breach_tool"]):
		return false
	_land.require(cell_centre(cell_of_piece(id)), actor, &"build")
	var ticks: int = m["breach_ticks"]
	var pos: Vector3i = _actors.position_of(actor)
	_breaching[actor] = {"piece": id, "ticks": ticks, "pos": [pos.x, pos.y, pos.z] as Array[int], "health": _health_total(actor)}
	return true


func _health_total(actor: int) -> int:
	var total: int = 0
	var health: Dictionary = _actors.health_of(actor)
	for node: Variant in health:
		var v: int = health[node]
		total += v
	return total


## Removes pieces without a rights check: the breach path of a raid (claim 9).
func breach(id: int) -> Array[int]:
	var none: Array[int] = []
	if not _pieces.has(id):
		return none
	return _remove_and_collapse([id], EntityIds.NONE)


## `actor` is who changed the build (NONE for a breach): the event carries it so a
## quest or a skill can credit the builder (M5 spec claim 9).
func _remove_and_collapse(ids: Array[int], actor: int) -> Array[int]:
	for id: int in ids:
		_drop(id)
	var supported: Dictionary = supported_set()
	var removed: Array[int] = ids.duplicate()
	for id: int in piece_ids():
		if not supported.has(id):
			_drop(id)
			removed.append(id)
	removed.sort()
	_events.emit(EVENT_CHANGED, {"added": [] as Array[int], "removed": removed, "actor": actor})
	return removed


func _drop(id: int) -> void:
	var record: Dictionary = _pieces[id]
	var face: String = record["face"]
	_occupied.erase(face if not face.is_empty() else cell_key(cell_of_piece(id)))
	_pieces.erase(id)
	_stats.forget_entity(id)


# ---------------------------------------------------------------- commands

## {"actor": int, "piece": string, "x": int, "y": int, "z": int, "facing": string}
## Positions are millimetres; facing is "" for cell pieces, px/nx/py/ny/pz/nz for faces.
func _on_place(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 6 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("piece")) != TYPE_STRING \
			or typeof(payload.get("x")) != TYPE_INT or typeof(payload.get("y")) != TYPE_INT or typeof(payload.get("z")) != TYPE_INT \
			or typeof(payload.get("facing")) != TYPE_STRING:
		return false
	var actor: int = payload["actor"]
	var piece_s: String = payload["piece"]
	var x: int = payload["x"]
	var y: int = payload["y"]
	var z: int = payload["z"]
	var facing: String = payload["facing"]
	return place(actor, StringName(piece_s), Vector3i(x, y, z), facing) != EntityIds.NONE


## {"actor": int, "piece": int}
func _on_breach(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("piece")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var id: int = payload["piece"]
	return start_breach(actor, id)


## {"actor": int, "piece": int}
func _on_open(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("piece")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var id: int = payload["piece"]
	return set_open(actor, id, true)


## {"actor": int, "piece": int}
func _on_close(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("piece")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var id: int = payload["piece"]
	return set_open(actor, id, false)


## {"actor": int, "piece_id": int}
func _on_remove(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("piece_id")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var id: int = payload["piece_id"]
	return not remove(actor, id).is_empty()


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 3 or typeof(state.get("pieces")) != TYPE_DICTIONARY or typeof(state.get("holes")) != TYPE_ARRAY \
			or typeof(state.get("breaching")) != TYPE_DICTIONARY:
		return _restore_fail("shape")
	var pieces_in: Dictionary = state["pieces"]
	var pieces: Dictionary = {}
	var occupied: Dictionary = {}
	var keys: Array = pieces_in.keys()
	keys.sort()
	for pk: Variant in keys:
		if typeof(pk) != TYPE_INT or pk < 1 or typeof(pieces_in[pk]) != TYPE_DICTIONARY:
			return _restore_fail("piece key or record")
		var rec: Dictionary = pieces_in[pk]
		if rec.size() != 5 or typeof(rec.get("cell")) != TYPE_ARRAY or typeof(rec.get("face")) != TYPE_STRING \
				or typeof(rec.get("facing")) != TYPE_STRING or typeof(rec.get("open")) != TYPE_BOOL:
			return _restore_fail("piece %d fields" % pk)
		var template: StringName = LandSystem._as_name(rec.get("template"))
		if not _content.has(KIND_PIECE, template):
			return _restore_fail("piece %d template" % pk)
		var c: Array = rec["cell"]
		if c.size() != 3 or typeof(c[0]) != TYPE_INT or typeof(c[1]) != TYPE_INT or typeof(c[2]) != TYPE_INT:
			return _restore_fail("piece %d cell" % pk)
		var cx: int = c[0]
		var cy: int = c[1]
		var cz: int = c[2]
		if absi(cx) > MAX_CELL or absi(cy) > MAX_CELL or absi(cz) > MAX_CELL:
			return _restore_fail("piece %d cell range" % pk)
		var face: String = rec["face"]
		var t: Dictionary = _content.get_entry(KIND_PIECE, template)
		var k: Dictionary = _content.get_entry(KIND_PIECE_KIND, LandSystem._as_name(t["kind"]))
		var occupies: String = k["occupies"]
		var orientation: String = k["orientation"]
		var piece_facing: String = rec["facing"]
		if (orientation == "facing") != LEVEL_FACINGS.has(piece_facing) or (orientation != "facing" and not piece_facing.is_empty()):
			return _restore_fail("piece %d facing" % pk)
		var piece_open: bool = rec["open"]
		var opening: bool = k["passable"]
		if piece_open and not opening:
			return _restore_fail("piece %d is open but not an opening" % pk)
		var key: String = ""
		if occupies == "face":
			var parts: PackedStringArray = face.split("|")
			if parts.size() != 2 or parts[0] != "%d,%d,%d" % [cx, cy, cz] or not AXES.has(parts[1]):
				return _restore_fail("piece %d face" % pk)
			key = face
		else:
			if not face.is_empty():
				return _restore_fail("piece %d is a cell piece with a face" % pk)
			key = "%d,%d,%d" % [cx, cy, cz]
		if occupied.has(key):
			return _restore_fail("piece %d overlaps" % pk)
		occupied[key] = pk
		pieces[pk] = {"template": template, "cell": [cx, cy, cz] as Array[int], "face": face, "facing": piece_facing, "open": piece_open}
	var holes_in: Array = state["holes"]
	var holes: Dictionary = {}
	for h: Variant in holes_in:
		if typeof(h) != TYPE_STRING:
			return _restore_fail("hole key")
		var hk: String = h
		var parts: PackedStringArray = hk.split("|")
		var coords: PackedStringArray = parts[0].split(",") if parts.size() == 2 else PackedStringArray()
		if parts.size() != 2 or parts[1] != "y" or coords.size() != 3 or not coords[0].is_valid_int() or coords[1] != str(GROUND_CELL_Y - 1) \
				or not coords[2].is_valid_int() or absi(coords[0].to_int()) > MAX_CELL or absi(coords[2].to_int()) > MAX_CELL \
				or hk != "%d,%d,%d|y" % [coords[0].to_int(), GROUND_CELL_Y - 1, coords[2].to_int()] or holes.has(hk):
			return _restore_fail("hole %s is not a ground face" % hk)
		holes[hk] = true
	var breaching_in: Dictionary = state["breaching"]
	var breaching: Dictionary = {}
	for k: Variant in breaching_in:
		if typeof(k) != TYPE_INT or typeof(breaching_in[k]) != TYPE_DICTIONARY:
			return _restore_fail("breaching actor")
		var actor: int = k
		var rec: Dictionary = breaching_in[k]
		if not _actors.has_actor(actor) or rec.size() != 4 or typeof(rec.get("piece")) != TYPE_INT or typeof(rec.get("ticks")) != TYPE_INT \
				or typeof(rec.get("pos")) != TYPE_ARRAY or typeof(rec.get("health")) != TYPE_INT:
			return _restore_fail("breach record")
		var piece: int = rec["piece"]
		var ticks: int = rec["ticks"]
		var health: int = rec["health"]
		var pos: Array = rec["pos"]
		if not pieces.has(piece) or ticks < 1 or ticks > 1_000_000 or health < 0 or pos.size() != 3 \
				or typeof(pos[0]) != TYPE_INT or typeof(pos[1]) != TYPE_INT or typeof(pos[2]) != TYPE_INT:
			return _restore_fail("breach record range")
		var px: int = pos[0]
		var py: int = pos[1]
		var pz: int = pos[2]
		breaching[actor] = {"piece": piece, "ticks": ticks, "pos": [px, py, pz] as Array[int], "health": health}
	_pieces = pieces
	_occupied = occupied
	_holes = holes
	_breaching = breaching
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("BuildSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
