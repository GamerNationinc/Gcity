## Sensors (design doc §9.1; M6 spec claims 8, 10): a sensor profile is content
## (`content/sensor/<id>.json`); a site places sensors when it is raised. Each placed
## sensor is an entity (a hack names it by id) watching one of:
## - an edge: the vertical face of a cell on a side; an intruder whose cell change
##   crosses it trips it;
## - a volume: a set of cells; an intruder entering one from outside trips it;
## - a credential: a locked door's face; a `land.door_check` flagged for heat there
##   trips it (a good card in a hot hand).
## A trip emits `sensor.tripped {sensor, actor}` (heat follows through a standing rule)
## and, for a radio sensor, a report to the placing site's squad on the same tick.
## A spoofed sensor does not trip until its spoof runs out. Agents do not trip
## sensors: at M6 every sensor belongs to the site its guards keep.
class_name SensorSystem extends SimSystem

const SYSTEM_ID: StringName = &"sensors"
const KIND_SENSOR: StringName = &"sensor"
const EVENT_TRIPPED: StringName = &"sensor.tripped"
const WATCH_EDGE: String = "edge"
const WATCH_VOLUME: String = "volume"
const WATCH_CREDENTIAL: String = "credential"

var _content: ContentDb
var _ids: EntityIds
var _build: BuildSystem
var _perception: PerceptionSystem
var _squads: SquadSystem
var _events: EventBus
var _sim: SimRoot
## sensor id -> {"profile": String, "squad": int, "face": String, "cells": [cell key, ...],
##               "spoofed_until": int, "trips": int}
var _sensors: Dictionary = {}
var _tripped: int = 0


func _init(content: ContentDb, ids: EntityIds, build: BuildSystem, perception: PerceptionSystem, squads: SquadSystem, events: EventBus) -> void:
	_content = content
	_ids = ids
	_build = build
	_perception = perception
	_squads = squads
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim_root: SimRoot) -> void:
	pass


func snapshot() -> Dictionary:
	return {"sensors": _sensors.duplicate(true), "tripped": _tripped}


func attach(sim: SimRoot) -> Error:
	_sim = sim
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	err = _events.subscribe(MovementSystem.EVENT_MOVED, _on_moved)
	if err != OK:
		return err
	return _events.subscribe(MovementSystem.EVENT_DOOR_CHECK, _on_door_check)


# ---------------------------------------------------------------- placing

## Whether a site's sensor entry names a profile and gives it what it watches: a
## vertical side for an edge or a credential, at least one cell for a volume, a
## squad of 0 or more. `origin` is the site's; cells are relative to it.
func entry_is_valid(entry: Dictionary) -> bool:
	var sensor_s: String = entry["sensor"]
	if not _content.has(KIND_SENSOR, StringName(sensor_s)):
		return false
	var squad: int = entry["squad"]
	var facing: String = entry["facing"]
	var cells: Array = entry["cells"]
	if squad < 0:
		return false
	var t: Dictionary = _content.get_entry(KIND_SENSOR, StringName(sensor_s))
	var spoofable: bool = t["spoofable"]
	if spoofable and (typeof(t.get("spoof_work")) != TYPE_INT or typeof(t.get("spoof_ticks")) != TYPE_INT or typeof(t.get("spoof_requires")) != TYPE_STRING):
		return false
	var watches: String = _watches(StringName(sensor_s))
	if watches == WATCH_VOLUME:
		return not cells.is_empty()
	return MovementSystem.SIDES.has(facing)


## Places a sensor from a validated site entry. Returns its id.
func install(entry: Dictionary, origin: Vector3i) -> int:
	var sensor_s: String = entry["sensor"]
	var squad: int = entry["squad"]
	var facing: String = entry["facing"]
	var cells_in: Array = entry["cells"]
	var face: String = ""
	var cells: Array[String] = []
	if _watches(StringName(sensor_s)) == WATCH_VOLUME:
		for c: Variant in cells_in:
			cells.append(BuildSystem.cell_key(origin + SiteSystem._cell(c)))
		cells.sort()
	else:
		face = BuildSystem.face_key(origin + SiteSystem._cell(entry["cell"]), facing)
	var id: int = _ids.allocate()
	_sensors[id] = {"profile": sensor_s, "squad": squad, "face": face, "cells": cells, "spoofed_until": 0, "trips": 0}
	return id


# ---------------------------------------------------------------- queries

func sensor_ids() -> Array[int]:
	var out: Array[int] = []
	for key: Variant in _sensors:
		var id: int = key
		out.append(id)
	out.sort()
	return out


func profile_of(sensor: int) -> StringName:
	if not _sensors.has(sensor):
		return &""
	var rec: Dictionary = _sensors[sensor]
	var profile_s: String = rec["profile"]
	return StringName(profile_s)


func is_spoofable(sensor: int) -> bool:
	if not _sensors.has(sensor):
		return false
	var t: Dictionary = _content.get_entry(KIND_SENSOR, profile_of(sensor))
	return t["spoofable"]


func is_spoofed(sensor: int) -> bool:
	if not _sensors.has(sensor):
		return false
	var rec: Dictionary = _sensors[sensor]
	var until: int = rec["spoofed_until"]
	return until > _sim.get_tick()


## Keeps a spoofable sensor quiet until `until_tick` (a hack's result, M6 spec claim
## 12). False for an unknown or unspoofable sensor.
func spoof(sensor: int, until_tick: int) -> bool:
	if not is_spoofable(sensor) or until_tick < 0:
		return false
	var rec: Dictionary = _sensors[sensor]
	rec["spoofed_until"] = until_tick
	return true


## The cells a sensor watches from: both cells of its face, or its volume's cells.
func cells_of(sensor: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if not _sensors.has(sensor):
		return out
	var rec: Dictionary = _sensors[sensor]
	var face: String = rec["face"]
	if not face.is_empty():
		return BuildSystem.face_cells(face)
	var cells: Array = rec["cells"]
	for key: Variant in cells:
		var k: String = key
		out.append(PathingSystem._parse(k))
	return out


func tripped_count() -> int:
	return _tripped


func _watches(profile: StringName) -> String:
	var t: Dictionary = _content.get_entry(KIND_SENSOR, profile)
	return t["watches"]


# ---------------------------------------------------------------- tripping

func _on_moved(payload: Dictionary) -> void:
	var actor: int = payload["actor"]
	if _perception.is_agent(actor):
		return
	var from: Vector3i = PathingSystem._vec(payload["from"])
	var to: Vector3i = PathingSystem._vec(payload["to"])
	var crossed: Array[String] = _faces_crossed(from, to)
	for sensor: int in sensor_ids():
		var rec: Dictionary = _sensors[sensor]
		match _watches(profile_of(sensor)):
			WATCH_EDGE:
				var face: String = rec["face"]
				if crossed.has(face):
					_trip(sensor, actor, to)
			WATCH_VOLUME:
				var cells: Array = rec["cells"]
				if cells.has(BuildSystem.cell_key(to)) and not cells.has(BuildSystem.cell_key(from)):
					_trip(sensor, actor, to)


func _on_door_check(payload: Dictionary) -> void:
	var flagged: bool = payload["flagged"]
	var actor: int = payload["actor"]
	var piece: int = payload["piece"]
	if not flagged or _perception.is_agent(actor) or not _build.has_piece(piece):
		return
	var record: Dictionary = _build.piece(piece)
	var face: String = record["face"]
	for sensor: int in sensor_ids():
		var rec: Dictionary = _sensors[sensor]
		if _watches(profile_of(sensor)) == WATCH_CREDENTIAL and rec["face"] == face:
			var cells: Array[Vector3i] = BuildSystem.face_cells(face)
			_trip(sensor, actor, cells[0])


## The vertical faces a cell change crossed: the horizontal step's face, at the level
## it started on and at the level it ended on (a step off an edge, a climb onto a
## crate).
static func _faces_crossed(from: Vector3i, to: Vector3i) -> Array[String]:
	var out: Array[String] = []
	var d: Vector3i = Vector3i(to.x - from.x, 0, to.z - from.z)
	if absi(d.x) + absi(d.z) != 1:
		return out
	var facing: String = ("p" if d.x > 0 else "n") + "x" if d.x != 0 else ("p" if d.z > 0 else "n") + "z"
	out.append(BuildSystem.face_key(from, facing))
	if to.y != from.y:
		out.append(BuildSystem.face_key(Vector3i(from.x, to.y, from.z), facing))
	return out


func _trip(sensor: int, actor: int, cell: Vector3i) -> void:
	if is_spoofed(sensor):
		return
	var rec: Dictionary = _sensors[sensor]
	var trips: int = rec["trips"]
	rec["trips"] = trips + 1
	_tripped += 1
	_events.emit(EVENT_TRIPPED, {"sensor": sensor, "actor": actor})
	var t: Dictionary = _content.get_entry(KIND_SENSOR, profile_of(sensor))
	var radio: bool = t["radio"]
	var squad: int = rec["squad"]
	if radio and squad > 0:
		_squads.report_from_outside(squad, actor, cell, _sim.get_tick())


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 2 or typeof(state.get("sensors")) != TYPE_DICTIONARY or typeof(state.get("tripped")) != TYPE_INT:
		return _restore_fail("shape")
	var tripped: int = state["tripped"]
	if tripped < 0:
		return _restore_fail("negative count")
	var in_all: Dictionary = state["sensors"]
	var out: Dictionary = {}
	for key: Variant in in_all:
		if typeof(key) != TYPE_INT or typeof(in_all[key]) != TYPE_DICTIONARY:
			return _restore_fail("sensor key")
		var id: int = key
		var rec: Dictionary = in_all[key]
		if rec.size() != 6 or typeof(rec.get("profile")) != TYPE_STRING or typeof(rec.get("squad")) != TYPE_INT \
				or typeof(rec.get("face")) != TYPE_STRING or typeof(rec.get("cells")) != TYPE_ARRAY \
				or typeof(rec.get("spoofed_until")) != TYPE_INT or typeof(rec.get("trips")) != TYPE_INT:
			return _restore_fail("sensor %d fields" % id)
		var profile_s: String = rec["profile"]
		var squad: int = rec["squad"]
		var until: int = rec["spoofed_until"]
		var trips: int = rec["trips"]
		if id < 1 or not _content.has(KIND_SENSOR, StringName(profile_s)) or squad < 0 or until < 0 or trips < 0:
			return _restore_fail("sensor %d values" % id)
		var cells_in: Array = rec["cells"]
		var cells: Array[String] = []
		for c: Variant in cells_in:
			if typeof(c) != TYPE_STRING:
				return _restore_fail("sensor %d cell" % id)
			cells.append(c)
		var face: String = rec["face"]
		out[id] = {"profile": profile_s, "squad": squad, "face": face, "cells": cells, "spoofed_until": until, "trips": trips}
	_sensors = out
	_tripped = tripped
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("SensorSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
