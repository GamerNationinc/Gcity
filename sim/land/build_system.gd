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
## `build.changed {added, removed, removed_at, actor}` for the portal graph, the quests
## and the scoring: `removed_at` is where each removed piece stood, because the piece
## record is gone by the time anyone hears about it, and "is that gap still there?" is
## a question the scoring has to be able to ask later.
class_name BuildSystem extends SimSystem

const SYSTEM_ID: StringName = &"build"
const KIND_PIECE: StringName = &"build_piece"
const KIND_PIECE_KIND: StringName = &"piece_kind"
const KIND_MATERIAL: StringName = &"material"
const KIND_TOOL: StringName = &"tool_class"
const COMMAND_PLACE: StringName = &"build.place"
const COMMAND_REMOVE: StringName = &"build.remove"
const EVENT_CHANGED: StringName = &"build.changed"
const STAT_HP: StringName = &"piece_hp"
const STAT_NOISE: StringName = &"breach_noise"
const CELL: int = 1000
const GROUND_CELL_Y: int = 0
const MAX_CELL: int = 100_000
const FACINGS: Array[String] = ["px", "nx", "py", "ny", "pz", "nz"]
const AXES: Array[String] = ["x", "y", "z"]

var _content: ContentDb
var _stats: StatResolver
var _ids: EntityIds
var _land: LandSystem
var _actors: ActorSystem
var _events: EventBus
## piece id -> {"template": StringName, "cell": [x, y, z], "face": "" | "x,y,z|axis"}
var _pieces: Dictionary = {}
## derived: "x,y,z" -> piece id (cell pieces); "x,y,z|axis" -> piece id (face pieces)
var _occupied: Dictionary = {}
## The ground (M7 claim 10). A foundation stands on ground: in the city that is the
## ground level, as it always was; in the wilds, wherever the ground is. Unset, the
## ground level is the only ground there is.
var _regions: Regions = null


func set_regions(regions: Regions) -> void:
	_regions = regions


## Whether a foundation can go in this cell: ground directly under it and none in it.
func _on_ground(cell: Vector3i) -> bool:
	if _regions == null:
		return cell.y == GROUND_CELL_Y
	return not _regions.is_solid(cell) and _regions.is_solid(cell - Vector3i(0, 1, 0))


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
	pass


func snapshot() -> Dictionary:
	return {"pieces": _pieces.duplicate(true)}


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
	return sim.commands().register(COMMAND_REMOVE, _on_remove)


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
		if kind == &"foundation":
			has_root = true
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


## Where a piece stands: its face key, or its cell key for a cell piece. This is the
## slot it occupies, so an empty one means the gap it left is still open.
func key_of_piece(id: int) -> String:
	if not _pieces.has(id):
		return ""
	var record: Dictionary = _pieces[id]
	var face: String = record["face"]
	return face if not face.is_empty() else cell_key(cell_of_piece(id))


## True when nothing stands in that slot, whether it names a face or a cell.
func slot_is_empty(key: String) -> bool:
	return not _occupied.has(key)


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
		if kind_of(id) == &"foundation" and _on_ground(cell_of_piece(id)):
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
		if not facing.is_empty():
			return EntityIds.NONE
		if _occupied.has(cell_key(cell)):
			return EntityIds.NONE
		if kind == &"foundation" and not _on_ground(cell):
			return EntityIds.NONE
	if not _land.require(cell_centre(cell), actor, &"build"):
		return EntityIds.NONE
	var id: int = _ids.allocate()
	var lower: Vector3i = cell if face.is_empty() else face_cells(face)[0]
	_pieces[id] = {"template": template, "cell": [lower.x, lower.y, lower.z] as Array[int], "face": face}
	_occupied[face if not face.is_empty() else cell_key(cell)] = id
	if not supported_set().has(id):
		_occupied.erase(face if not face.is_empty() else cell_key(cell))
		_pieces.erase(id)
		return EntityIds.NONE
	var m: Dictionary = _content.get_entry(KIND_MATERIAL, material_of(id))
	var hp: int = m["hp"]
	var noise: int = m["breach_noise"]
	_stats.set_base(id, STAT_HP, hp)
	_stats.set_base(id, STAT_NOISE, noise)
	_events.emit(EVENT_CHANGED, {"added": [id] as Array[int], "removed": [] as Array[int], "removed_at": [] as Array[String], "actor": actor})
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


## Removes pieces without a rights check: the breach path of a raid (claim 9).
func breach(id: int) -> Array[int]:
	var none: Array[int] = []
	if not _pieces.has(id):
		return none
	return _remove_and_collapse([id], EntityIds.NONE)


## `actor` is who changed the build (NONE for a breach): the event carries it so a
## quest or a skill can credit the builder (M5 spec claim 9).
func _remove_and_collapse(ids: Array[int], actor: int) -> Array[int]:
	var went: Dictionary = {}
	for id: int in ids:
		went[id] = key_of_piece(id)
		_drop(id)
	var supported: Dictionary = supported_set()
	var removed: Array[int] = ids.duplicate()
	for id: int in piece_ids():
		if not supported.has(id):
			went[id] = key_of_piece(id)
			_drop(id)
			removed.append(id)
	removed.sort()
	var removed_at: Array[String] = []
	for id: int in removed:
		var key: String = went[id]
		removed_at.append(key)
	_events.emit(EVENT_CHANGED, {"added": [] as Array[int], "removed": removed, "removed_at": removed_at, "actor": actor})
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


## {"actor": int, "piece_id": int}
func _on_remove(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("piece_id")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var id: int = payload["piece_id"]
	return not remove(actor, id).is_empty()


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 1 or typeof(state.get("pieces")) != TYPE_DICTIONARY:
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
		if rec.size() != 3 or typeof(rec.get("cell")) != TYPE_ARRAY or typeof(rec.get("face")) != TYPE_STRING:
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
		pieces[pk] = {"template": template, "cell": [cx, cy, cz] as Array[int], "face": face}
	_pieces = pieces
	_occupied = occupied
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("BuildSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
