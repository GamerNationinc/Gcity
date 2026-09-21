## Structures on parcels and modules in their socket grids (design doc §8.1–8.4;
## ADR-005; M2 spec claims 8–12).
##
## A structure is an owner-agnostic record on a parcel: kind, position, rotation and
## the owner tag of whoever placed it. Its power and heat budgets are stats on the
## structure's entity; each installed module contributes negative `add` modifiers, so
## headroom is resolved by the one resolver and removing a module restores the exact
## prior value. Placing and installing ask [LandSystem.require] for `build`; there is no
## no-build volume system (§8.4).
##
## Positions are integer millimetres. A structure's footprint is axis-aligned after one
## of four rotations; sockets are (col, row) cells on the template's pitch.
class_name StructureSystem extends SimSystem

const SYSTEM_ID: StringName = &"structures"
const KIND_STRUCTURE: StringName = &"structure"
const KIND_MODULE: StringName = &"module"
const COMMAND_PLACE: StringName = &"structure.place"
const COMMAND_INSTALL: StringName = &"module.install"
const COMMAND_REMOVE: StringName = &"module.remove"
const STAT_POWER: StringName = &"power_available"
const STAT_HEAT: StringName = &"heat_headroom"
const ROTATIONS: Array[int] = [0, 90, 180, 270]
const MAX_COORD: int = LandSystem.MAX_COORD

var _content: ContentDb
var _stats: StatResolver
var _ids: EntityIds
var _land: LandSystem
var _actors: ActorSystem
## structure id -> {"template": StringName, "x": int, "y": int, "z": int, "rotation": int,
## "owner_at_placement": StringName, "modules": {module id -> {"template": StringName,
## "col": int, "row": int, "handles": Array[int]}}}
var _structures: Dictionary = {}


func _init(content: ContentDb, stats: StatResolver, ids: EntityIds, land: LandSystem, actors: ActorSystem) -> void:
	_content = content
	_stats = stats
	_ids = ids
	_land = land
	_actors = actors


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


func snapshot() -> Dictionary:
	return {"structures": _structures.duplicate(true)}


func attach(sim: SimRoot) -> Error:
	var err: Error = validate_content()
	if err != OK:
		return err
	err = sim.register_system(self)
	if err != OK:
		return err
	for pair: Array in [[COMMAND_PLACE, _on_place], [COMMAND_INSTALL, _on_install], [COMMAND_REMOVE, _on_remove]]:
		var kind: StringName = pair[0]
		var handler: Callable = pair[1]
		err = sim.commands().register(kind, handler)
		if err != OK:
			return err
	return OK


# ---------------------------------------------------------------- content validation

## The budget stats exist; no module depends on itself, directly or through others;
## every module fits at least one structure's grid. Shape was checked at build time.
func validate_content() -> Error:
	for stat: StringName in [STAT_POWER, STAT_HEAT]:
		if not _stats.has_stat(stat):
			return _content_fail("stat/%s is not registered" % stat)
	var modules: Array[StringName] = _content.ids(KIND_MODULE)
	for id: StringName in modules:
		var t: Dictionary = _content.get_entry(KIND_MODULE, id)
		var seen: Array[StringName] = [id]
		var frontier: Array[StringName] = _depends_on(t)
		while not frontier.is_empty():
			var dep: StringName = frontier.pop_back()
			if dep == id:
				return _content_fail("module/%s depends on itself" % id)
			if seen.has(dep):
				continue
			seen.append(dep)
			frontier.append_array(_depends_on(_content.get_entry(KIND_MODULE, dep)))
		var fp: Dictionary = t["footprint"]
		var fits: bool = false
		for s: StringName in _content.ids(KIND_STRUCTURE):
			var st: Dictionary = _content.get_entry(KIND_STRUCTURE, s)
			var sockets: Dictionary = st["sockets"]
			if fp["cols"] <= sockets["cols"] and fp["rows"] <= sockets["rows"]:
				fits = true
		if not fits:
			return _content_fail("module/%s fits no structure's socket grid" % id)
	return OK


static func _depends_on(t: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	var deps: Array = t["depends_on"]
	for d: Variant in deps:
		var s: String = d
		out.append(StringName(s))
	return out


func _content_fail(reason: String) -> Error:
	push_error("StructureSystem: content rejected: %s" % reason)
	return ERR_INVALID_DATA


# ---------------------------------------------------------------- queries

func has_structure(id: int) -> bool:
	return _structures.has(id)


func structure_ids() -> Array[int]:
	var out: Array[int] = []
	out.assign(_structures.keys())
	out.sort()
	return out


## A copy of the structure record, or an empty dictionary (and an error).
func structure(id: int) -> Dictionary:
	if not _structures.has(id):
		push_error("StructureSystem: no structure %d" % id)
		return {}
	var record: Dictionary = _structures[id]
	return record.duplicate(true)


func template_of(id: int) -> StringName:
	if not _structures.has(id):
		return &""
	var record: Dictionary = _structures[id]
	return record["template"]


func position_of(id: int) -> Vector3i:
	if not _structures.has(id):
		return Vector3i.ZERO
	var record: Dictionary = _structures[id]
	var x: int = record["x"]
	var y: int = record["y"]
	var z: int = record["z"]
	return Vector3i(x, y, z)


func module_ids(structure_id: int) -> Array[int]:
	var out: Array[int] = []
	if not _structures.has(structure_id):
		return out
	var record: Dictionary = _structures[structure_id]
	var modules: Dictionary = record["modules"]
	out.assign(modules.keys())
	out.sort()
	return out


func module_template(structure_id: int, module_id: int) -> StringName:
	if not _structures.has(structure_id):
		return &""
	var record: Dictionary = _structures[structure_id]
	var modules: Dictionary = record["modules"]
	if not modules.has(module_id):
		return &""
	var m: Dictionary = modules[module_id]
	return m["template"]


func power_available(structure_id: int) -> int:
	return _stats.resolve(structure_id, STAT_POWER)


func heat_headroom(structure_id: int) -> int:
	return _stats.resolve(structure_id, STAT_HEAT)


## The footprint as [min x, min z, max x, max z] after rotation, half-open.
func footprint_of(id: int) -> Array[int]:
	if not _structures.has(id):
		return [0, 0, 0, 0]
	var record: Dictionary = _structures[id]
	var template: StringName = record["template"]
	var t: Dictionary = _content.get_entry(KIND_STRUCTURE, template)
	var x: int = record["x"]
	var z: int = record["z"]
	var rotation: int = record["rotation"]
	return _footprint_rect(t, x, z, rotation)


## Socket cells occupied on the structure, as "col,row" -> module id.
func occupancy(structure_id: int) -> Dictionary:
	var out: Dictionary = {}
	if not _structures.has(structure_id):
		return out
	var record: Dictionary = _structures[structure_id]
	var modules: Dictionary = record["modules"]
	for module_id: int in modules:
		var m: Dictionary = modules[module_id]
		var mt: StringName = m["template"]
		var t: Dictionary = _content.get_entry(KIND_MODULE, mt)
		var fp: Dictionary = t["footprint"]
		var col0: int = m["col"]
		var row0: int = m["row"]
		var cols: int = fp["cols"]
		var rows: int = fp["rows"]
		for c: int in range(col0, col0 + cols):
			for r: int in range(row0, row0 + rows):
				out["%d,%d" % [c, r]] = module_id
	return out


# ---------------------------------------------------------------- operations

## Places a structure of `template` with its origin at `position` (min x / min z corner
## before rotation). Every corner of the footprint must be on land the actor may build
## on, and the footprint may not overlap another structure's. Returns the new id or
## EntityIds.NONE.
func place(actor: int, template: StringName, position: Vector3i, rotation: int) -> int:
	if not _actors.has_actor(actor) or not _content.has(KIND_STRUCTURE, template) or not ROTATIONS.has(rotation):
		return EntityIds.NONE
	if absi(position.x) > MAX_COORD or absi(position.y) > MAX_COORD or absi(position.z) > MAX_COORD:
		return EntityIds.NONE
	var t: Dictionary = _content.get_entry(KIND_STRUCTURE, template)
	var rect: Array[int] = _footprint_rect(t, position.x, position.z, rotation)
	for corner: Vector2i in [Vector2i(rect[0], rect[1]), Vector2i(rect[2] - 1, rect[1]), Vector2i(rect[0], rect[3] - 1), Vector2i(rect[2] - 1, rect[3] - 1)]:
		if not _land.require(Vector3i(corner.x, position.y, corner.y), actor, &"build"):
			return EntityIds.NONE
	for other_id: int in _structures:
		var other: Array[int] = footprint_of(other_id)
		var other_rec: Dictionary = _structures[other_id]
		var other_template: StringName = other_rec["template"]
		var other_t: Dictionary = _content.get_entry(KIND_STRUCTURE, other_template)
		var other_fp: Dictionary = other_t["footprint"]
		var other_y: int = other_rec["y"]
		var other_height: int = other_fp["height"]
		var fp: Dictionary = t["footprint"]
		var height: int = fp["height"]
		var vertical: bool = position.y < other_y + other_height and other_y < position.y + height
		if vertical and rect[0] < other[2] and other[0] < rect[2] and rect[1] < other[3] and other[1] < rect[3]:
			return EntityIds.NONE
	var id: int = _ids.allocate()
	_structures[id] = {
		"template": template, "x": position.x, "y": position.y, "z": position.z, "rotation": rotation,
		"owner_at_placement": _land.owner_tag_of_actor(actor), "modules": {},
	}
	var power_budget: int = t["power_budget"]
	var heat_budget: int = t["heat_budget"]
	_stats.set_base(id, STAT_POWER, power_budget)
	_stats.set_base(id, STAT_HEAT, heat_budget)
	return id


## Installs a module with its min corner at (col, row). Rejected when the actor may not
## build there, the cells are off-grid or occupied, a dependency is not installed, or
## either budget would go negative. Returns the module id or EntityIds.NONE.
func install(actor: int, structure_id: int, template: StringName, col: int, row: int) -> int:
	if not _actors.has_actor(actor) or not _structures.has(structure_id) or not _content.has(KIND_MODULE, template):
		return EntityIds.NONE
	var record: Dictionary = _structures[structure_id]
	if not _land.require(position_of(structure_id), actor, &"build"):
		return EntityIds.NONE
	var structure_template: StringName = record["template"]
	var st: Dictionary = _content.get_entry(KIND_STRUCTURE, structure_template)
	var sockets: Dictionary = st["sockets"]
	var t: Dictionary = _content.get_entry(KIND_MODULE, template)
	var fp: Dictionary = t["footprint"]
	var cols: int = fp["cols"]
	var rows: int = fp["rows"]
	var grid_cols: int = sockets["cols"]
	var grid_rows: int = sockets["rows"]
	if col < 0 or row < 0 or col + cols > grid_cols or row + rows > grid_rows:
		return EntityIds.NONE
	var occupied: Dictionary = occupancy(structure_id)
	for c: int in range(col, col + cols):
		for r: int in range(row, row + rows):
			if occupied.has("%d,%d" % [c, r]):
				return EntityIds.NONE
	for dep: StringName in _depends_on(t):
		if _count_of(structure_id, dep) == 0:
			return EntityIds.NONE
	var power_draw: int = t["power_draw"]
	var heat_output: int = t["heat_output"]
	if power_available(structure_id) - power_draw < 0 or heat_headroom(structure_id) - heat_output < 0:
		return EntityIds.NONE
	var id: int = _ids.allocate()
	var source: StringName = StringName("module.%d" % id)
	var handles: Array[int] = []
	handles.append(_stats.add_modifier(structure_id, {"stat": STAT_POWER, "class": StatResolver.CLASS_ADD, "value": -power_draw, "source": source}))
	handles.append(_stats.add_modifier(structure_id, {"stat": STAT_HEAT, "class": StatResolver.CLASS_ADD, "value": -heat_output, "source": source}))
	assert(not handles.has(-1), "budget modifiers must register")
	var modules: Dictionary = record["modules"]
	modules[id] = {"template": template, "col": col, "row": row, "handles": handles}
	return id


## Removes a module and its budget modifiers. Rejected when the actor may not build
## there or another installed module depends on this one's kind and it is the last.
func remove(actor: int, structure_id: int, module_id: int) -> bool:
	if not _actors.has_actor(actor) or not _structures.has(structure_id):
		return false
	var record: Dictionary = _structures[structure_id]
	var modules: Dictionary = record["modules"]
	if not modules.has(module_id):
		return false
	if not _land.require(position_of(structure_id), actor, &"build"):
		return false
	var m: Dictionary = modules[module_id]
	var template: StringName = m["template"]
	if _count_of(structure_id, template) == 1:
		for other_id: int in modules:
			if other_id == module_id:
				continue
			var other: Dictionary = modules[other_id]
			var other_template: StringName = other["template"]
			if _depends_on(_content.get_entry(KIND_MODULE, other_template)).has(template):
				return false
	var handles: Array[int] = m["handles"]
	for handle: int in handles:
		var err: Error = _stats.remove_modifier(handle)
		assert(err == OK, "budget modifier %d must exist" % handle)
	modules.erase(module_id)
	return true


func _count_of(structure_id: int, template: StringName) -> int:
	var record: Dictionary = _structures[structure_id]
	var modules: Dictionary = record["modules"]
	var n: int = 0
	for module_id: int in modules:
		var m: Dictionary = modules[module_id]
		if m["template"] == template:
			n += 1
	return n


static func _footprint_rect(t: Dictionary, x: int, z: int, rotation: int) -> Array[int]:
	var fp: Dictionary = t["footprint"]
	var sx: int = fp["x"]
	var sz: int = fp["z"]
	if rotation == 90 or rotation == 270:
		var swap: int = sx
		sx = sz
		sz = swap
	return [x, z, x + sx, z + sz]


# ---------------------------------------------------------------- commands

## {"actor": int, "template": string, "x": int, "y": int, "z": int, "rotation": int}
func _on_place(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 6 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("template")) != TYPE_STRING \
			or typeof(payload.get("x")) != TYPE_INT or typeof(payload.get("y")) != TYPE_INT or typeof(payload.get("z")) != TYPE_INT \
			or typeof(payload.get("rotation")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var template_s: String = payload["template"]
	var rotation: int = payload["rotation"]
	var x: int = payload["x"]
	var y: int = payload["y"]
	var z: int = payload["z"]
	return place(actor, StringName(template_s), Vector3i(x, y, z), rotation) != EntityIds.NONE


## {"actor": int, "structure": int, "template": string, "col": int, "row": int}
func _on_install(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 5 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("structure")) != TYPE_INT \
			or typeof(payload.get("template")) != TYPE_STRING or typeof(payload.get("col")) != TYPE_INT or typeof(payload.get("row")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var structure_id: int = payload["structure"]
	var template_s: String = payload["template"]
	var col: int = payload["col"]
	var row: int = payload["row"]
	return install(actor, structure_id, StringName(template_s), col, row) != EntityIds.NONE


## {"actor": int, "structure": int, "module": int}
func _on_remove(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 3 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("structure")) != TYPE_INT or typeof(payload.get("module")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var structure_id: int = payload["structure"]
	var module_id: int = payload["module"]
	return remove(actor, structure_id, module_id)


# ---------------------------------------------------------------- restore

## Restores structure and module records. Budget bases and modifiers live in the
## resolver and are restored by it; this only checks the records refer to real content
## and consistent handles.
func restore(state: Dictionary) -> Error:
	if state.size() != 1 or typeof(state.get("structures")) != TYPE_DICTIONARY:
		return _restore_fail("shape")
	var structures_in: Dictionary = state["structures"]
	var out: Dictionary = {}
	for sk: Variant in structures_in:
		if typeof(sk) != TYPE_INT or sk < 1 or typeof(structures_in[sk]) != TYPE_DICTIONARY:
			return _restore_fail("structure key or record")
		var rec: Dictionary = structures_in[sk]
		if rec.size() != 7 or typeof(rec.get("x")) != TYPE_INT or typeof(rec.get("y")) != TYPE_INT or typeof(rec.get("z")) != TYPE_INT \
				or typeof(rec.get("rotation")) != TYPE_INT or typeof(rec.get("modules")) != TYPE_DICTIONARY:
			return _restore_fail("structure %d fields" % sk)
		var template: StringName = LandSystem._as_name(rec.get("template"))
		if not _content.has(KIND_STRUCTURE, template):
			return _restore_fail("structure %d template" % sk)
		var rotation: int = rec["rotation"]
		if not ROTATIONS.has(rotation):
			return _restore_fail("structure %d rotation" % sk)
		var owner: StringName = LandSystem._as_name(rec.get("owner_at_placement"))
		if typeof(rec.get("owner_at_placement")) != TYPE_STRING_NAME and typeof(rec.get("owner_at_placement")) != TYPE_STRING:
			return _restore_fail("structure %d owner" % sk)
		var modules_in: Dictionary = rec["modules"]
		var modules: Dictionary = {}
		for mk: Variant in modules_in:
			if typeof(mk) != TYPE_INT or mk < 1 or typeof(modules_in[mk]) != TYPE_DICTIONARY:
				return _restore_fail("module key or record")
			var m: Dictionary = modules_in[mk]
			if m.size() != 4 or typeof(m.get("col")) != TYPE_INT or typeof(m.get("row")) != TYPE_INT or typeof(m.get("handles")) != TYPE_ARRAY:
				return _restore_fail("module %d fields" % mk)
			var mt: StringName = LandSystem._as_name(m.get("template"))
			if not _content.has(KIND_MODULE, mt):
				return _restore_fail("module %d template" % mk)
			var handles_in: Array = m["handles"]
			var handles: Array[int] = []
			for h: Variant in handles_in:
				if typeof(h) != TYPE_INT:
					return _restore_fail("module %d handle" % mk)
				handles.append(h)
			if handles.size() != 2:
				return _restore_fail("module %d handle count" % mk)
			modules[mk] = {"template": mt, "col": m["col"], "row": m["row"], "handles": handles}
		out[sk] = {"template": template, "x": rec["x"], "y": rec["y"], "z": rec["z"], "rotation": rotation, "owner_at_placement": owner, "modules": modules}
	_structures = out
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("StructureSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
