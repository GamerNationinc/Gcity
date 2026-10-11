## Sites (M6 spec claim 12): a place in the world written as content. A site file
## declares its district and owner tag, its parcels (footprints in cells, storeys for
## floor and ceiling), the basement cells it digs, its pieces by relative cell (each
## optionally watched by a sensor for a squad), its agents (profile, cell, facing, squad,
## a patrol route measured from the site), its hack targets (optionally tied to one of
## its pieces) and an exfil polygon. `site.spawn {site, origin}` raises all of it at a
## cell origin in one step: the parcels must fit and the pieces go in as one
## all-or-nothing batch (BuildSystem.spawn_batch), so a refused spawn changes nothing.
## A site spawns once.
class_name SiteSystem extends SimSystem

const SYSTEM_ID: StringName = &"sites"
const KIND_SITE: StringName = &"site"
const COMMAND_SPAWN: StringName = &"site.spawn"
const EVENT_SPAWNED: StringName = &"site.spawned"
const M: int = 1000

var _content: ContentDb
var _land: LandSystem
var _build: BuildSystem
var _perception: PerceptionSystem
var _sensors: SensorSystem
var _hacks: HackSystem
var _events: EventBus
var _owner_regex: RegEx = RegEx.create_from_string(LandSystem.OWNER_PATTERN)
## site id -> [x, y, z] origin cell
var _spawned: Dictionary = {}


func _init(content: ContentDb, land: LandSystem, build: BuildSystem, perception: PerceptionSystem, sensors: SensorSystem, hacks: HackSystem, events: EventBus) -> void:
	_content = content
	_land = land
	_build = build
	_perception = perception
	_sensors = sensors
	_hacks = hacks
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


func attach(sim: SimRoot) -> Error:
	var err: Error = validate_content()
	if err != OK:
		return err
	err = sim.register_system(self)
	if err != OK:
		return err
	return sim.commands().register(COMMAND_SPAWN, _on_spawn)


# ---------------------------------------------------------------- content

## Every reference resolves and every number is in shape; whether the pieces stand up
## is proven by spawning each shipped site in a test.
func validate_content() -> Error:
	for id: StringName in _content.ids(KIND_SITE):
		var t: Dictionary = _content.get_entry(KIND_SITE, id)
		var reason: String = _check_site(t)
		if not reason.is_empty():
			push_error("SiteSystem: content rejected: site/%s %s" % [id, reason])
			return ERR_INVALID_DATA
	return OK


func _check_site(t: Dictionary) -> String:
	for key: String in ["district", "owner"]:
		if typeof(t.get(key)) != TYPE_STRING:
			return "needs a string %s" % key
	for key: String in ["parcels", "excavate", "pieces", "agents", "hack_targets", "exfil"]:
		if typeof(t.get(key)) != TYPE_ARRAY:
			return "needs a %s list" % key
	var district: String = t["district"]
	var owner: String = t["owner"]
	if not _content.has(&"district", StringName(district)):
		return "names unknown district '%s'" % district
	if owner.is_empty() or not _owner_regex.search(owner):
		return "has a bad owner tag '%s'" % owner
	var parcels: Array = t["parcels"]
	var names: Array[String] = []
	for v: Variant in parcels:
		if typeof(v) != TYPE_DICTIONARY:
			return "has a parcel that is not an object"
		var p: Dictionary = v
		if typeof(p.get("id")) != TYPE_STRING or typeof(p.get("footprint")) != TYPE_ARRAY or typeof(p.get("floor")) != TYPE_INT \
				or typeof(p.get("ceiling")) != TYPE_INT or typeof(p.get("district")) != TYPE_STRING or typeof(p.get("owner")) != TYPE_STRING:
			return "has a parcel without id, footprint, floor, ceiling, district and owner"
		var pid: String = p["id"]
		var pdistrict: String = p["district"]
		var powner: String = p["owner"]
		var floor_s: int = p["floor"]
		var ceiling_s: int = p["ceiling"]
		if pid.is_empty() or names.has(pid):
			return "repeats or omits a parcel id"
		names.append(pid)
		if not pdistrict.is_empty() and not _content.has(&"district", StringName(pdistrict)):
			return "parcel %s names unknown district '%s'" % [pid, pdistrict]
		if not powner.is_empty() and not _owner_regex.search(powner):
			return "parcel %s has a bad owner tag" % pid
		if floor_s >= ceiling_s or LandSystem._normalised_polygon(_scaled(p["footprint"], Vector3i.ZERO)).is_empty():
			return "parcel %s is not a volume" % pid
	if not _cells_ok(t["excavate"]):
		return "has a bad excavate cell"
	var pieces: Array = t["pieces"]
	for v: Variant in pieces:
		if typeof(v) != TYPE_DICTIONARY:
			return "has a piece that is not an object"
		var e: Dictionary = v
		if typeof(e.get("piece")) != TYPE_STRING or typeof(e.get("facing")) != TYPE_STRING or typeof(e.get("sensor")) != TYPE_STRING \
				or typeof(e.get("squad")) != TYPE_INT or not _cell_ok(e.get("cell")):
			return "has a piece without piece, cell, facing, sensor and squad"
		var piece: String = e["piece"]
		var sensor: String = e["sensor"]
		var squad: int = e["squad"]
		if not _content.has(&"build_piece", StringName(piece)):
			return "places unknown piece '%s'" % piece
		if not sensor.is_empty() and (not _content.has(SensorSystem.KIND_SENSOR, StringName(sensor)) or squad <= 0):
			return "watches a piece with unknown sensor '%s' or no squad" % sensor
	var agents: Array = t["agents"]
	for v: Variant in agents:
		if typeof(v) != TYPE_DICTIONARY:
			return "has an agent that is not an object"
		var a: Dictionary = v
		if typeof(a.get("profile")) != TYPE_STRING or typeof(a.get("facing")) != TYPE_INT or typeof(a.get("squad")) != TYPE_INT \
				or typeof(a.get("route")) != TYPE_STRING or not _cell_ok(a.get("cell")):
			return "has an agent without profile, cell, facing, squad and route"
		var profile: String = a["profile"]
		var route: String = a["route"]
		var facing: int = a["facing"]
		var asquad: int = a["squad"]
		if not _content.has(PerceptionSystem.KIND_AGENT, StringName(profile)) or facing < 0 or facing > 359 or asquad < 0:
			return "has an agent with unknown profile '%s' or a bad facing or squad" % profile
		if not route.is_empty() and not _content.has(PerceptionSystem.KIND_ROUTE, StringName(route)):
			return "has an agent with unknown route '%s'" % route
	var targets: Array = t["hack_targets"]
	for v: Variant in targets:
		if typeof(v) != TYPE_DICTIONARY:
			return "has a hack target that is not an object"
		var h: Dictionary = v
		if typeof(h.get("target")) != TYPE_STRING or typeof(h.get("piece")) != TYPE_INT or not _cell_ok(h.get("cell")):
			return "has a hack target without target, cell and piece"
		var target: String = h["target"]
		var index: int = h["piece"]
		if not _content.has(HackSystem.KIND_TARGET, StringName(target)) or index < -1 or index >= pieces.size():
			return "has a hack target with unknown target '%s' or piece index %d" % [target, index]
	if LandSystem._normalised_polygon(_scaled(t["exfil"], Vector3i.ZERO)).is_empty():
		return "has an exfil that is not a polygon"
	return ""


static func _cell_ok(v: Variant) -> bool:
	if typeof(v) != TYPE_ARRAY:
		return false
	var a: Array = v
	if a.size() != 3:
		return false
	for e: Variant in a:
		if typeof(e) != TYPE_INT:
			return false
		var n: int = e
		if absi(n) > 1000:
			return false
	return true


static func _cells_ok(v: Variant) -> bool:
	if typeof(v) != TYPE_ARRAY:
		return false
	var list: Array = v
	for c: Variant in list:
		if not _cell_ok(c):
			return false
	return true


static func _cell(v: Variant) -> Vector3i:
	var a: Array = v
	var x: int = a[0]
	var y: int = a[1]
	var z: int = a[2]
	return Vector3i(x, y, z)


## A footprint in site cells as [x, z] millimetre pairs at a cell origin.
static func _scaled(footprint: Variant, origin: Vector3i) -> Array:
	var out: Array = []
	if typeof(footprint) != TYPE_ARRAY:
		return out
	var list: Array = footprint
	for v: Variant in list:
		if typeof(v) != TYPE_ARRAY:
			return []
		var pair: Array = v
		if pair.size() != 2 or typeof(pair[0]) != TYPE_INT or typeof(pair[1]) != TYPE_INT:
			return []
		var x: int = pair[0]
		var z: int = pair[1]
		out.append([(origin.x + x) * M, (origin.z + z) * M])
	return out


# ---------------------------------------------------------------- spawning

func is_spawned(site: StringName) -> bool:
	return _spawned.has(String(site))


func origin_of(site: StringName) -> Vector3i:
	if not is_spawned(site):
		return Vector3i.ZERO
	return _cell(_spawned[String(site)])


## The land id of a site's parcel.
static func parcel_id(site: StringName, parcel: String) -> StringName:
	return StringName("%s_%s" % [site, parcel])


## Whether a position lies in a spawned site's exfil polygon (M6 claim 14).
func in_exfil(site: StringName, position: Vector3i) -> bool:
	if not is_spawned(site):
		return false
	var t: Dictionary = _content.get_entry(KIND_SITE, site)
	var poly: Array[Vector2i] = LandSystem._normalised_polygon(_scaled(t["exfil"], origin_of(site)))
	return LandSystem._contains_half_open(poly, position.x, position.z)


## Raises a site at a cell origin. False, changing nothing, for an unknown or already
## spawned site, parcels that do not fit, or pieces that do not (BuildSystem.spawn_batch).
func spawn(site: StringName, origin: Vector3i) -> bool:
	if not _content.has(KIND_SITE, site) or is_spawned(site):
		return false
	if absi(origin.x) > BuildSystem.MAX_CELL - 1000 or absi(origin.y) > 2 or absi(origin.z) > BuildSystem.MAX_CELL - 1000:
		return false
	var t: Dictionary = _content.get_entry(KIND_SITE, site)
	var parcels: Array = t["parcels"]
	var volumes: Array = []
	for v: Variant in parcels:
		var p: Dictionary = v
		var pid: String = p["id"]
		if _land.has_parcel(parcel_id(site, pid)):
			return false
		var floor_s: int = p["floor"]
		var ceiling_s: int = p["ceiling"]
		volumes.append({"footprint": _scaled(p["footprint"], origin), "floor_y": (origin.y + floor_s) * M, "ceiling_y": (origin.y + ceiling_s) * M})
	if not _land.parcels_fit(volumes):
		return false
	var dig: Array[Vector3i] = []
	var excavate: Array = t["excavate"]
	for c: Variant in excavate:
		dig.append(_cell(c) + origin)
	var entries: Array[Dictionary] = []
	var pieces: Array = t["pieces"]
	for v: Variant in pieces:
		var e: Dictionary = v
		var piece: String = e["piece"]
		var facing: String = e["facing"]
		entries.append({"piece": StringName(piece), "cell": _cell(e["cell"]) + origin, "facing": facing})
	var ids: Array[int] = _build.spawn_batch(dig, entries)
	if ids.size() != entries.size():
		return false
	# from here every step is a consequence of content that the batch proved fits
	var site_district: String = t["district"]
	var site_owner: String = t["owner"]
	for i: int in parcels.size():
		var p: Dictionary = parcels[i]
		var vol: Dictionary = volumes[i]
		var pid: String = p["id"]
		var pdistrict: String = p["district"]
		var powner: String = p["owner"]
		var footprint: Array = vol["footprint"]
		var floor_y: int = vol["floor_y"]
		var ceiling_y: int = vol["ceiling_y"]
		var err: Error = _land.add_parcel(parcel_id(site, pid), StringName(site_district if pdistrict.is_empty() else pdistrict),
			StringName(site_owner if powner.is_empty() else powner), footprint, floor_y, ceiling_y)
		assert(err == OK, "parcels_fit said this parcel fits")
	for i: int in pieces.size():
		var e: Dictionary = pieces[i]
		var sensor: String = e["sensor"]
		if not sensor.is_empty():
			var squad: int = e["squad"]
			var installed: bool = _sensors.install(StringName(sensor), ids[i], squad)
			assert(installed, "a sensor on a site piece installs")
	var targets: Array = t["hack_targets"]
	for v: Variant in targets:
		var h: Dictionary = v
		var target: String = h["target"]
		var index: int = h["piece"]
		var placed: int = _hacks.place(StringName(target), _cell(h["cell"]) + origin, EntityIds.NONE if index < 0 else ids[index])
		assert(placed != EntityIds.NONE, "a site's hack target places")
	var agents: Array = t["agents"]
	for v: Variant in agents:
		var a: Dictionary = v
		var profile: String = a["profile"]
		var facing: int = a["facing"]
		var squad_a: int = a["squad"]
		var route: String = a["route"]
		var agent: int = _perception.spawn(StringName(profile), _cell(a["cell"]) + origin, facing, squad_a, route, origin)
		assert(agent != EntityIds.NONE, "a site's agent stands where the site put it")
	_spawned[String(site)] = [origin.x, origin.y, origin.z]
	_events.emit(EVENT_SPAWNED, {"site": site, "x": origin.x, "y": origin.y, "z": origin.z})
	return true


## {"site": string, "origin": [x, y, z] cell}
func _on_spawn(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("site")) != TYPE_STRING or not _cell_ok_any(payload.get("origin")):
		return false
	var site: String = payload["site"]
	return spawn(StringName(site), _cell(payload["origin"]))


static func _cell_ok_any(v: Variant) -> bool:
	if typeof(v) != TYPE_ARRAY:
		return false
	var a: Array = v
	if a.size() != 3:
		return false
	for e: Variant in a:
		if typeof(e) != TYPE_INT:
			return false
	return true


# ---------------------------------------------------------------- state

func snapshot() -> Dictionary:
	return {"spawned": _spawned.duplicate(true)}


func restore(state: Dictionary) -> Error:
	if state.size() != 1 or typeof(state.get("spawned")) != TYPE_DICTIONARY:
		return _restore_fail("shape")
	var src: Dictionary = state["spawned"]
	var out: Dictionary = {}
	for k: Variant in src:
		if typeof(k) != TYPE_STRING or not _cell_ok_any(src[k]):
			return _restore_fail("entry")
		var site: String = k
		if not _content.has(KIND_SITE, StringName(site)):
			return _restore_fail("unknown site '%s'" % site)
		var o: Vector3i = _cell(src[k])
		out[site] = [o.x, o.y, o.z]
	_spawned = out
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("SiteSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
