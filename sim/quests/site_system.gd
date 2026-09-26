## Sites (M6 spec claims 1–2; design doc §5.3): an authored place as a data record,
## `content/site/<id>.json`. Pieces, named points and agents are cells relative to the
## site's `origin`; parcels are content parcels handed to an owner tag. `site.raise
## {site}` places every piece as one batch (one `build.changed`, one portal rebuild),
## hands over every parcel and posts every agent, on one tick, once per site. It is
## debug-class like `item.spawn`: fixtures and the client's new-game path issue it.
##
## Quests name sites by id, never by coordinates; at M6 a site id is its own binding
## (one authored site per handle). M7's generator replaces that lookup, not the quest.
class_name SiteSystem extends SimSystem

const SYSTEM_ID: StringName = &"sites"
const KIND_SITE: StringName = &"site"
const COMMAND_RAISE: StringName = &"site.raise"

var _content: ContentDb
var _land: LandSystem
var _build: BuildSystem
var _perception: PerceptionSystem
## Sites raised so far, sorted by id.
var _raised: Array[StringName] = []


func _init(content: ContentDb, land: LandSystem, build: BuildSystem, perception: PerceptionSystem) -> void:
	_content = content
	_land = land
	_build = build
	_perception = perception


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


func snapshot() -> Dictionary:
	var raised: Array[String] = []
	for site: StringName in _raised:
		raised.append(String(site))
	return {"raised": raised}


func attach(sim: SimRoot) -> Error:
	var err: Error = validate_content()
	if err != OK:
		return err
	err = sim.register_system(self)
	if err != OK:
		return err
	return sim.commands().register(COMMAND_RAISE, _on_raise)


# ---------------------------------------------------------------- content validation

## What the build-time validator cannot see: parcel owner tags, piece facings against
## their kind, unique point ids, routes that exist, cells on the grid. Whether the
## pieces stand is checked by raising every shipped site in a test, and again by the
## raise itself, which refuses a site that would not.
func validate_content() -> Error:
	var owner_regex: RegEx = RegEx.create_from_string(LandSystem.OWNER_PATTERN)
	for site: StringName in _content.ids(KIND_SITE):
		var t: Dictionary = _content.get_entry(KIND_SITE, site)
		var origin: Vector3i = _cell(t["origin"])
		if not _on_grid(origin):
			return _content_fail("site/%s: origin is off the grid" % site)
		var parcels: Array = t["parcels"]
		for p: Variant in parcels:
			var pd: Dictionary = p
			var parcel_s: String = pd["parcel"]
			var owner_s: String = pd["owner"]
			if not _content.has(LandSystem.KIND_PARCEL, StringName(parcel_s)):
				return _content_fail("site/%s: no parcel/%s" % [site, parcel_s])
			if not owner_s.is_empty() and not owner_regex.search(owner_s):
				return _content_fail("site/%s: '%s' is not an owner tag" % [site, owner_s])
		var pieces: Array = t["pieces"]
		for p: Variant in pieces:
			var pd: Dictionary = p
			var piece_s: String = pd["piece"]
			var facing: String = pd["facing"]
			var cell: Vector3i = origin + _cell(pd["cell"])
			if not _content.has(BuildSystem.KIND_PIECE, StringName(piece_s)):
				return _content_fail("site/%s: no build_piece/%s" % [site, piece_s])
			if not _on_grid(cell) or not _facing_fits(StringName(piece_s), facing):
				return _content_fail("site/%s: %s at %s facing '%s' cannot be placed" % [site, piece_s, cell, facing])
		var points: Array = t["points"]
		var seen: Dictionary = {}
		for p: Variant in points:
			var pd: Dictionary = p
			var id_s: String = pd["id"]
			if seen.has(id_s):
				return _content_fail("site/%s: point '%s' twice" % [site, id_s])
			seen[id_s] = true
			if not _on_grid(origin + _cell(pd["cell"])):
				return _content_fail("site/%s: point '%s' is off the grid" % [site, id_s])
		var agents: Array = t["agents"]
		for a: Variant in agents:
			var ad: Dictionary = a
			var profile_s: String = ad["profile"]
			var route_s: String = ad["route"]
			if not _content.has(PerceptionSystem.KIND_AGENT, StringName(profile_s)):
				return _content_fail("site/%s: no agent_profile/%s" % [site, profile_s])
			if not route_s.is_empty() and not _content.has(PerceptionSystem.KIND_ROUTE, StringName(route_s)):
				return _content_fail("site/%s: no patrol_route/%s" % [site, route_s])
			if not _on_grid(origin + _cell(ad["cell"])):
				return _content_fail("site/%s: an agent is off the grid" % site)
	return OK


func _facing_fits(piece: StringName, facing: String) -> bool:
	var t: Dictionary = _content.get_entry(BuildSystem.KIND_PIECE, piece)
	var k: Dictionary = _content.get_entry(BuildSystem.KIND_PIECE_KIND, LandSystem._as_name(t["kind"]))
	var occupies: String = k["occupies"]
	if occupies != "face":
		return facing.is_empty()
	if not BuildSystem.FACINGS.has(facing):
		return false
	var orientation: String = k["orientation"]
	var vertical_axis: bool = facing.ends_with("y")
	return not (orientation == "vertical" and vertical_axis) and not (orientation == "horizontal" and not vertical_axis)


func _content_fail(reason: String) -> Error:
	push_error("SiteSystem: content rejected: %s" % reason)
	return ERR_INVALID_DATA


static func _on_grid(cell: Vector3i) -> bool:
	return absi(cell.x) <= BuildSystem.MAX_CELL and absi(cell.y) <= BuildSystem.MAX_CELL and absi(cell.z) <= BuildSystem.MAX_CELL


## A validated `[x, y, z]` array as a cell.
static func _cell(v: Variant) -> Vector3i:
	var a: Array = v
	var x: int = a[0]
	var y: int = a[1]
	var z: int = a[2]
	return Vector3i(x, y, z)


# ---------------------------------------------------------------- queries

func is_raised(site: StringName) -> bool:
	return _raised.has(site)


func raised_sites() -> Array[StringName]:
	return _raised.duplicate()


static func has_point(content: ContentDb, site: StringName, point: StringName) -> bool:
	return not _point_cell(content, site, point).is_empty()


## Where an actor stands at a site's named point, in millimetres: the centre of the
## point's cell, on the floor of that cell. Vector3i.ZERO with an error if there is no
## such point; ask [method has_point] first.
static func point_position(content: ContentDb, site: StringName, point: StringName) -> Vector3i:
	var found: Array = _point_cell(content, site, point)
	if found.is_empty():
		push_error("SiteSystem: no point '%s' at site/%s" % [point, site])
		return Vector3i.ZERO
	var cell: Vector3i = found[0]
	var c: int = BuildSystem.CELL
	return Vector3i(cell.x * c + c / 2, cell.y * c, cell.z * c + c / 2)


## [absolute cell] or [] when the site or point does not exist.
static func _point_cell(content: ContentDb, site: StringName, point: StringName) -> Array:
	if not content.has(KIND_SITE, site):
		return []
	var t: Dictionary = content.get_entry(KIND_SITE, site)
	var points: Array = t["points"]
	for p: Variant in points:
		var pd: Dictionary = p
		var id_s: String = pd["id"]
		if StringName(id_s) == point:
			return [_cell(t["origin"]) + _cell(pd["cell"])]
	return []


# ---------------------------------------------------------------- raise

## Raises a site: its pieces as one batch, then its parcels, then its agents. False,
## changing nothing, when the site is unknown, already raised, or its pieces would
## not stand (the batch refuses whole).
func raise(site: StringName) -> bool:
	if not _content.has(KIND_SITE, site) or _raised.has(site):
		return false
	var t: Dictionary = _content.get_entry(KIND_SITE, site)
	var origin: Vector3i = _cell(t["origin"])
	var pieces: Array = t["pieces"]
	var entries: Array[Array] = []
	for p: Variant in pieces:
		var pd: Dictionary = p
		var piece_s: String = pd["piece"]
		var facing: String = pd["facing"]
		entries.append([StringName(piece_s), origin + _cell(pd["cell"]), facing])
	if not entries.is_empty() and _build.place_batch(entries).size() != entries.size():
		return false
	var parcels: Array = t["parcels"]
	for p: Variant in parcels:
		var pd: Dictionary = p
		var parcel_s: String = pd["parcel"]
		var owner_s: String = pd["owner"]
		var moved: bool = _land.transfer(StringName(parcel_s), owner_s)
		assert(moved, "site parcels and owners were validated at assembly")
	var agents: Array = t["agents"]
	for a: Variant in agents:
		var ad: Dictionary = a
		var profile_s: String = ad["profile"]
		var route_s: String = ad["route"]
		var facing: int = ad["facing"]
		var squad: int = ad["squad"]
		var agent: int = _perception.spawn(StringName(profile_s), origin + _cell(ad["cell"]), facing, squad, route_s)
		assert(agent != EntityIds.NONE, "site agents were validated at assembly")
	_raised.append(site)
	_raised.sort_custom(func(x: StringName, y: StringName) -> bool: return String(x) < String(y))
	return true


## {"site": string}
func _on_raise(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 1 or typeof(payload.get("site")) != TYPE_STRING:
		return false
	var site_s: String = payload["site"]
	return raise(StringName(site_s))


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 1 or typeof(state.get("raised")) != TYPE_ARRAY:
		return _restore_fail("shape")
	var raised_in: Array = state["raised"]
	var raised: Array[StringName] = []
	for v: Variant in raised_in:
		if typeof(v) != TYPE_STRING and typeof(v) != TYPE_STRING_NAME:
			return _restore_fail("site id")
		var site: StringName = StringName(str(v))
		if not _content.has(KIND_SITE, site) or raised.has(site):
			return _restore_fail("site '%s'" % site)
		raised.append(site)
	raised.sort_custom(func(x: StringName, y: StringName) -> bool: return String(x) < String(y))
	_raised = raised
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("SiteSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
