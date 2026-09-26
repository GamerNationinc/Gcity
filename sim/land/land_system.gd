## Parcels, rights and ownership (design doc §7.1, §8.4; M2 spec claims 1–7).
##
## One spatial query underlies the whole game: [method rights_at]. Every position
## resolves: inside a parcel to that parcel's district table, inside no parcel to the
## district that covers unparcelled land. Unowned land is a parcel with an empty owner,
## so there is one code path, not two. Violating a right emits `land.violation` and
## nothing else; consequences are the threat director's (M8).
##
## Positions are integer millimetres. Footprints are simple polygons on the x/z plane
## with a half-open vertical extent [floor_y, ceiling_y). Membership uses the
## half-open crossing rule, so a planar subdivision assigns every point to exactly one
## parcel and parcels sharing an edge never both claim it.
##
## Owners are tags, not actor ids: the design lets the city-state, NPCs and factions own
## land (§9.4). An actor acts as the owner it is identified with (`land.identify`).
class_name LandSystem extends SimSystem

const SYSTEM_ID: StringName = &"land"
const KIND_DISTRICT: StringName = &"district"
const KIND_PARCEL: StringName = &"parcel"
const COMMAND_TRANSFER: StringName = &"land.transfer"
const COMMAND_IDENTIFY: StringName = &"land.identify"
const EVENT_VIOLATION: StringName = &"land.violation"
const RIGHTS: Array[StringName] = [&"build", &"dig", &"enter", &"carry", &"loot", &"safe"]
## Pause is a sim command the land authority gates (ADR-006 C; M5 spec claim 7): an
## actor may pause only where it holds `safe`, and only a paused sim resumes.
const COMMAND_PAUSE: StringName = &"sim.pause"
const COMMAND_RESUME: StringName = &"sim.resume"
const TABLE_OWNER: String = "owner"
const TABLE_OTHER: String = "other"
const TABLE_UNOWNED: String = "unowned"
## Parcel id returned for positions inside no parcel.
const UNPARCELLED: StringName = &""

const MAX_COORD: int = 100_000_000
const MIN_VERTICES: int = 3
const MAX_VERTICES: int = 64
## Twice the minimum footprint area, in mm²: one square metre.
const MIN_DOUBLE_AREA: int = 2_000_000
## Spatial index bucket edge, mm.
const BUCKET: int = 16_000
const OWNER_PATTERN: String = "^[a-z0-9][a-z0-9_.]*$"

var _content: ContentDb
var _actors: ActorSystem
var _events: EventBus
var _owner_regex: RegEx = RegEx.create_from_string(OWNER_PATTERN)
## parcel id -> {"district": StringName, "owner": StringName, "footprint": Array[Vector2i]
## (x, z), "floor_y": int, "ceiling_y": int}
var _parcels: Dictionary = {}
## actor id -> owner tag
var _actor_owner: Dictionary = {}
var _wild_district: StringName = &""
## Derived: "bx,bz" -> Array[StringName] of parcels whose bounding box touches the bucket
var _buckets: Dictionary = {}
var _violations: int = 0


func _init(content: ContentDb, actors: ActorSystem, events: EventBus) -> void:
	_content = content
	_actors = actors
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


func snapshot() -> Dictionary:
	var parcels: Dictionary = {}
	for id: StringName in _parcels:
		var record: Dictionary = _parcels[id]
		var footprint: Array[Vector2i] = record["footprint"]
		var pairs: Array = []
		for v: Vector2i in footprint:
			pairs.append([v.x, v.y] as Array[int])
		parcels[id] = {"district": record["district"], "owner": record["owner"], "footprint": pairs,
			"floor_y": record["floor_y"], "ceiling_y": record["ceiling_y"]}
	return {
		"parcels": parcels,
		"actor_owner": _actor_owner.duplicate(),
		"wild_district": _wild_district,
		"violations": _violations,
	}


## Validates content, places every content parcel, registers the system and commands.
func attach(sim: SimRoot) -> Error:
	var err: Error = validate_content()
	if err != OK:
		return err
	for id: StringName in _content.ids(KIND_PARCEL):
		var t: Dictionary = _content.get_entry(KIND_PARCEL, id)
		var floor_y: int = t["floor_y"]
		var ceiling_y: int = t["ceiling_y"]
		var footprint: Array = t["footprint"]
		err = add_parcel(id, _as_name(t["district"]), _as_name(t["owner"]), footprint, floor_y, ceiling_y)
		if err != OK:
			return _content_fail("parcel/%s rejected: %s" % [id, error_string(err)])
	err = sim.register_system(self)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_TRANSFER, _on_transfer)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_IDENTIFY, _on_identify)
	if err != OK:
		return err
	# both pause-safe: a redundant pause is refused at once instead of waiting in the
	# queue to pause the sim again the moment it resumes
	err = sim.commands().register(COMMAND_PAUSE, _on_pause, true)
	if err != OK:
		return err
	return sim.commands().register(COMMAND_RESUME, _on_resume, true)


## {"actor": int}: pause where the actor holds `safe`. A refusal for lack of the right
## is a land.violation like any other, so the device can show why.
func _on_pause(sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 1 or typeof(payload.get("actor")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	if sim.is_paused() or not _actors.is_alive(actor):
		return false
	if not require(_actors.position_of(actor), actor, &"safe"):
		return false
	sim.set_paused(true)
	return true


## {"actor": int}: resume a paused sim. Pause-safe, so it dispatches while paused.
func _on_resume(sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 1 or typeof(payload.get("actor")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	if not sim.is_paused() or not _actors.is_alive(actor):
		return false
	sim.set_paused(false)
	return true


# ---------------------------------------------------------------- content validation

## Exactly one district covers unparcelled land; every parcel names a real district.
## Shape and ranges were checked by the build-time validator.
func validate_content() -> Error:
	var wild: Array[StringName] = []
	for id: StringName in _content.ids(KIND_DISTRICT):
		var t: Dictionary = _content.get_entry(KIND_DISTRICT, id)
		var covers: bool = t["covers_unparcelled"]
		if covers:
			wild.append(id)
	if wild.size() != 1:
		return _content_fail("exactly one district must set covers_unparcelled, found %d" % wild.size())
	_wild_district = wild[0]
	for id: StringName in _content.ids(KIND_PARCEL):
		var t: Dictionary = _content.get_entry(KIND_PARCEL, id)
		if not _content.has(KIND_DISTRICT, _as_name(t["district"])):
			return _content_fail("parcel/%s names unknown district '%s'" % [id, t["district"]])
	return OK


func _content_fail(reason: String) -> Error:
	push_error("LandSystem: content rejected: %s" % reason)
	return ERR_INVALID_DATA


# ---------------------------------------------------------------- parcels

## Adds a parcel from a footprint of [x, z] integer pairs. Rejected when the id is
## taken, the footprint is not a simple polygon of at least one square metre, the
## vertical extent is empty, the district or owner tag is bad, or the volume overlaps
## an existing parcel.
func add_parcel(id: StringName, district: StringName, owner: StringName, footprint: Array, floor_y: int, ceiling_y: int) -> Error:
	if id.is_empty() or _parcels.has(id):
		return ERR_ALREADY_EXISTS
	if not _content.has(KIND_DISTRICT, district):
		return ERR_INVALID_PARAMETER
	if not owner.is_empty() and not _owner_regex.search(String(owner)):
		return ERR_INVALID_PARAMETER
	if floor_y < -MAX_COORD or ceiling_y > MAX_COORD or floor_y >= ceiling_y:
		return ERR_INVALID_PARAMETER
	var poly: Array[Vector2i] = _normalised_polygon(footprint)
	if poly.is_empty():
		return ERR_INVALID_PARAMETER
	for other_id: StringName in _candidates_for_polygon(poly):
		var other: Dictionary = _parcels[other_id]
		var other_poly: Array[Vector2i] = other["footprint"]
		var other_floor: int = other["floor_y"]
		var other_ceiling: int = other["ceiling_y"]
		if _volumes_overlap(poly, floor_y, ceiling_y, other_poly, other_floor, other_ceiling):
			return ERR_ALREADY_EXISTS
	_parcels[id] = {"district": district, "owner": owner, "footprint": poly, "floor_y": floor_y, "ceiling_y": ceiling_y}
	_index(id, poly)
	return OK


func has_parcel(id: StringName) -> bool:
	return _parcels.has(id)


func parcel_ids() -> Array[StringName]:
	var names: PackedStringArray = PackedStringArray()
	for id: StringName in _parcels.keys():
		names.append(String(id))
	names.sort()
	var out: Array[StringName] = []
	for name: String in names:
		out.append(StringName(name))
	return out


## The parcel record as in [method snapshot], or an empty dictionary (and an error).
func parcel(id: StringName) -> Dictionary:
	if not _parcels.has(id):
		push_error("LandSystem: no parcel '%s'" % id)
		return {}
	var parcels: Dictionary = snapshot()["parcels"]
	return parcels[id]


func owner_of(id: StringName) -> StringName:
	if not _parcels.has(id):
		return &""
	var record: Dictionary = _parcels[id]
	return record["owner"]


func district_of(id: StringName) -> StringName:
	if not _parcels.has(id):
		return _wild_district
	var record: Dictionary = _parcels[id]
	return record["district"]


func wild_district() -> StringName:
	return _wild_district


## The parcel containing the position, or UNPARCELLED.
func parcel_at(position: Vector3i) -> StringName:
	var key: String = _bucket_key(position.x, position.z)
	if not _buckets.has(key):
		return UNPARCELLED
	var candidates: Array[StringName] = _buckets[key]
	for id: StringName in candidates:
		var record: Dictionary = _parcels[id]
		var floor_y: int = record["floor_y"]
		var ceiling_y: int = record["ceiling_y"]
		if position.y < floor_y or position.y >= ceiling_y:
			continue
		var poly: Array[Vector2i] = record["footprint"]
		if _contains_half_open(poly, position.x, position.z):
			return id
	return UNPARCELLED


# ---------------------------------------------------------------- rights

func owner_tag_of_actor(actor: int) -> StringName:
	return _as_name(_actor_owner.get(actor))


## The five rights the actor holds at the position. Total: every position and every
## actor id resolve, including unknown actors (who own nothing).
func rights_at(position: Vector3i, actor: int) -> Dictionary:
	var parcel_id: StringName = parcel_at(position)
	var district: StringName = district_of(parcel_id)
	var parcel_owner: StringName = owner_of(parcel_id)
	var table: String = TABLE_UNOWNED
	if not parcel_owner.is_empty():
		table = TABLE_OWNER if parcel_owner == owner_tag_of_actor(actor) else TABLE_OTHER
	var d: Dictionary = _content.get_entry(KIND_DISTRICT, district)
	var tables: Dictionary = d["rights"]
	var row: Dictionary = tables[table]
	var out: Dictionary = {}
	for right: StringName in RIGHTS:
		var v: bool = row[String(right)]
		out[right] = v
	return out


## True if the actor holds the right there. Otherwise emits `land.violation` and returns
## false; the caller rejects its command. This is the one path every violation takes.
func require(position: Vector3i, actor: int, right: StringName) -> bool:
	assert(RIGHTS.has(right), "unknown right '%s'" % right)
	var rights: Dictionary = rights_at(position, actor)
	var held: bool = rights[right]
	if held:
		return true
	_violations += 1
	_events.emit(EVENT_VIOLATION, {
		"actor": actor,
		"parcel": parcel_at(position),
		"right": right,
		"x": position.x, "y": position.y, "z": position.z,
	})
	return false


func violation_count() -> int:
	return _violations


# ---------------------------------------------------------------- commands

## {"parcel": string, "owner": string}: set a parcel's owner tag ('' = unowned).
## Debug-class at M2 (spec claim 7): purchase and takeover arrive with M8.
func _on_transfer(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("parcel")) != TYPE_STRING or typeof(payload.get("owner")) != TYPE_STRING:
		return false
	var parcel_s: String = payload["parcel"]
	var owner: String = payload["owner"]
	return transfer(StringName(parcel_s), owner)


## Sets a parcel's owner tag ('' = unowned): the transfer command's effect, and a
## site's parcels when it is raised (M6 spec claim 2). False, changing nothing, for an
## unknown parcel or a malformed tag.
func transfer(parcel_id: StringName, owner: String) -> bool:
	if not _parcels.has(parcel_id):
		return false
	if not owner.is_empty() and not _owner_regex.search(owner):
		return false
	var record: Dictionary = _parcels[parcel_id]
	record["owner"] = StringName(owner)
	return true


## {"actor": int, "owner": string}: the actor acts as that owner ('' = nobody). The
## actor must exist (spec claim 17).
func _on_identify(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("owner")) != TYPE_STRING:
		return false
	var actor: int = payload["actor"]
	var owner: String = payload["owner"]
	if not _actors.has_actor(actor):
		return false
	if not owner.is_empty() and not _owner_regex.search(owner):
		return false
	if owner.is_empty():
		_actor_owner.erase(actor)
	else:
		_actor_owner[actor] = StringName(owner)
	return true


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 4 or typeof(state.get("parcels")) != TYPE_DICTIONARY or typeof(state.get("actor_owner")) != TYPE_DICTIONARY \
			or typeof(state.get("violations")) != TYPE_INT:
		return _restore_fail("shape")
	if _as_name(state.get("wild_district")) != _wild_district:
		return _restore_fail("wild district")
	var violations: int = state["violations"]
	if violations < 0:
		return _restore_fail("violations")
	var parcels_in: Dictionary = state["parcels"]
	var saved_parcels: Dictionary = _parcels
	var saved_buckets: Dictionary = _buckets
	_parcels = {}
	_buckets = {}
	var keys: Array = parcels_in.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	for k: Variant in keys:
		var id: StringName = _as_name(k)
		if id.is_empty() or typeof(parcels_in[k]) != TYPE_DICTIONARY:
			return _restore_rollback(saved_parcels, saved_buckets, "parcel key or record")
		var rec: Dictionary = parcels_in[k]
		if rec.size() != 5 or typeof(rec.get("footprint")) != TYPE_ARRAY or typeof(rec.get("floor_y")) != TYPE_INT or typeof(rec.get("ceiling_y")) != TYPE_INT:
			return _restore_rollback(saved_parcels, saved_buckets, "parcel %s fields" % id)
		var floor_y: int = rec["floor_y"]
		var ceiling_y: int = rec["ceiling_y"]
		var footprint: Array = rec["footprint"]
		var err: Error = add_parcel(id, _as_name(rec.get("district")), _as_name(rec.get("owner")), footprint, floor_y, ceiling_y)
		if err != OK:
			return _restore_rollback(saved_parcels, saved_buckets, "parcel %s: %s" % [id, error_string(err)])
	var owners_in: Dictionary = state["actor_owner"]
	var owners: Dictionary = {}
	for ak: Variant in owners_in:
		var tag: StringName = _as_name(owners_in[ak])
		if typeof(ak) != TYPE_INT or ak < 1 or tag.is_empty() or not _owner_regex.search(String(tag)):
			return _restore_rollback(saved_parcels, saved_buckets, "actor owner entry")
		owners[ak] = tag
	_actor_owner = owners
	_violations = violations
	return OK


func _restore_rollback(parcels: Dictionary, buckets: Dictionary, reason: String) -> Error:
	_parcels = parcels
	_buckets = buckets
	return _restore_fail(reason)


func _restore_fail(reason: String) -> Error:
	push_error("LandSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA


static func _as_name(v: Variant) -> StringName:
	match typeof(v):
		TYPE_STRING:
			var s: String = v
			return StringName(s)
		TYPE_STRING_NAME:
			var n: StringName = v
			return n
		_:
			return &""


# ---------------------------------------------------------------- geometry

## Parses [x, z] pairs into a positively oriented simple polygon within bounds and of at
## least MIN_DOUBLE_AREA. Empty if the footprint is anything else.
static func _normalised_polygon(footprint: Array) -> Array[Vector2i]:
	var n: int = footprint.size()
	var none: Array[Vector2i] = []
	if n < MIN_VERTICES or n > MAX_VERTICES:
		return none
	var poly: Array[Vector2i] = []
	for v: Variant in footprint:
		if typeof(v) != TYPE_ARRAY:
			return none
		var pair: Array = v
		if pair.size() != 2 or typeof(pair[0]) != TYPE_INT or typeof(pair[1]) != TYPE_INT:
			return none
		var x: int = pair[0]
		var z: int = pair[1]
		if x < -MAX_COORD or x > MAX_COORD or z < -MAX_COORD or z > MAX_COORD:
			return none
		poly.append(Vector2i(x, z))
	for i: int in n:
		if poly[i] == poly[(i + 1) % n]:
			return none
	var double_area: int = _double_area(poly)
	if absi(double_area) < MIN_DOUBLE_AREA:
		return none
	if double_area < 0:
		poly.reverse()
	# simple: non-adjacent edges never meet, adjacent edges never fold back on each other
	for i: int in n:
		for j: int in range(i + 1, n):
			var adjacent: bool = j == i + 1 or (i == 0 and j == n - 1)
			var p1: Vector2i = poly[i]
			var p2: Vector2i = poly[(i + 1) % n]
			var q1: Vector2i = poly[j]
			var q2: Vector2i = poly[(j + 1) % n]
			if adjacent:
				if _adjacent_fold(p1, p2, q1, q2):
					return none
			elif _segments_touch(p1, p2, q1, q2):
				return none
	return poly


static func _double_area(poly: Array[Vector2i]) -> int:
	var total: int = 0
	var n: int = poly.size()
	for i: int in n:
		var a: Vector2i = poly[i]
		var b: Vector2i = poly[(i + 1) % n]
		var ax: int = a.x
		var az: int = a.y
		var bx: int = b.x
		var bz: int = b.y
		total += ax * bz - bx * az
	return total


## Cross product of (a - o) and (b - o), in 64-bit ints.
static func _cross(o: Vector2i, a: Vector2i, b: Vector2i) -> int:
	var ax: int = a.x - o.x
	var az: int = a.y - o.y
	var bx: int = b.x - o.x
	var bz: int = b.y - o.y
	return ax * bz - az * bx


static func _on_segment(p: Vector2i, a: Vector2i, b: Vector2i) -> bool:
	if _cross(a, b, p) != 0:
		return false
	return p.x >= mini(a.x, b.x) and p.x <= maxi(a.x, b.x) and p.y >= mini(a.y, b.y) and p.y <= maxi(a.y, b.y)


## Closed segments share at least one point.
static func _segments_touch(p1: Vector2i, p2: Vector2i, q1: Vector2i, q2: Vector2i) -> bool:
	if _segments_cross_properly(p1, p2, q1, q2):
		return true
	return _on_segment(p1, q1, q2) or _on_segment(p2, q1, q2) or _on_segment(q1, p1, p2) or _on_segment(q2, p1, p2)


## Open segments cross at a single interior point of both.
static func _segments_cross_properly(p1: Vector2i, p2: Vector2i, q1: Vector2i, q2: Vector2i) -> bool:
	var d1: int = signi(_cross(q1, q2, p1))
	var d2: int = signi(_cross(q1, q2, p2))
	var d3: int = signi(_cross(p1, p2, q1))
	var d4: int = signi(_cross(p1, p2, q2))
	return d1 * d2 < 0 and d3 * d4 < 0


## Adjacent edges p1-p2 and q1-q2 (sharing p2 == q1, or p1 == q2 for the closing pair)
## that are collinear and run back over each other.
static func _adjacent_fold(p1: Vector2i, p2: Vector2i, q1: Vector2i, q2: Vector2i) -> bool:
	if _cross(p1, p2, q1) != 0 or _cross(p1, p2, q2) != 0:
		return false
	var shared: Vector2i = p2 if p2 == q1 else p1
	var free_p: Vector2i = p1 if shared == p2 else p2
	var free_q: Vector2i = q2 if shared == p2 else q1
	var ux: int = free_p.x - shared.x
	var uz: int = free_p.y - shared.y
	var vx: int = free_q.x - shared.x
	var vz: int = free_q.y - shared.y
	return ux * vx + uz * vz > 0


## Half-open crossing rule: an edge counts when it spans the point's z half-openly and
## lies strictly to the right, so shared edges belong to exactly one polygon.
static func _contains_half_open(poly: Array[Vector2i], px: int, pz: int) -> bool:
	var inside: bool = false
	var n: int = poly.size()
	for i: int in n:
		var a: Vector2i = poly[i]
		var b: Vector2i = poly[(i + 1) % n]
		var az: int = a.y
		var bz: int = b.y
		if (az > pz) == (bz > pz):
			continue
		# px < ax + (pz - az) * (bx - ax) / (bz - az), evaluated exactly in integers
		var ax: int = a.x
		var bx: int = b.x
		var lhs: int = (px - ax) * (bz - az)
		var rhs: int = (pz - az) * (bx - ax)
		var crosses: bool = lhs < rhs if bz > az else lhs > rhs
		if crosses:
			inside = not inside
	return inside


static func _strictly_inside(poly: Array[Vector2i], p: Vector2i) -> bool:
	var n: int = poly.size()
	for i: int in n:
		if _on_segment(p, poly[i], poly[(i + 1) % n]):
			return false
	return _contains_half_open(poly, p.x, p.y)


## Interiors intersect: an edge pair crosses properly, a vertex of one lies strictly
## inside the other, or a point just inside one edge's midpoint lies strictly inside
## the other (which catches coincident polygons with no vertex of either inside).
static func _polygons_overlap(a: Array[Vector2i], b: Array[Vector2i]) -> bool:
	for i: int in a.size():
		for j: int in b.size():
			if _segments_cross_properly(a[i], a[(i + 1) % a.size()], b[j], b[(j + 1) % b.size()]):
				return true
	for probe: Vector2i in _interior_probes(a):
		if _strictly_inside(b, probe):
			return true
	for probe: Vector2i in _interior_probes(b):
		if _strictly_inside(a, probe):
			return true
	return false


## Every vertex plus, for each edge, the point one millimetre inside its midpoint.
static func _interior_probes(poly: Array[Vector2i]) -> Array[Vector2i]:
	var probes: Array[Vector2i] = []
	var n: int = poly.size()
	for i: int in n:
		var a: Vector2i = poly[i]
		var b: Vector2i = poly[(i + 1) % n]
		probes.append(a)
		var d: Vector2i = b - a
		var m: Vector2i = Vector2i((a.x + b.x) / 2, (a.y + b.y) / 2)
		# positive orientation: the inward normal of (dx, dz) is (-dz, dx)
		probes.append(Vector2i(m.x - signi(d.y), m.y + signi(d.x)))
	return probes


static func _volumes_overlap(a: Array[Vector2i], a_floor: int, a_ceiling: int, b: Array[Vector2i], b_floor: int, b_ceiling: int) -> bool:
	if a_floor >= b_ceiling or b_floor >= a_ceiling:
		return false
	return _polygons_overlap(a, b)


# ---------------------------------------------------------------- index

static func _bucket_of(v: int) -> int:
	return floori(float(v) / BUCKET)


static func _bucket_key(x: int, z: int) -> String:
	return "%d,%d" % [_bucket_of(x), _bucket_of(z)]


## [min x, min z, max x, max z]
static func _bounds(poly: Array[Vector2i]) -> Array[int]:
	var first: Vector2i = poly[0]
	var out: Array[int] = [first.x, first.y, first.x, first.y]
	for p: Vector2i in poly:
		out[0] = mini(out[0], p.x)
		out[1] = mini(out[1], p.y)
		out[2] = maxi(out[2], p.x)
		out[3] = maxi(out[3], p.y)
	return out


func _index(id: StringName, poly: Array[Vector2i]) -> void:
	var b: Array[int] = _bounds(poly)
	for bx: int in range(_bucket_of(b[0]), _bucket_of(b[2]) + 1):
		for bz: int in range(_bucket_of(b[1]), _bucket_of(b[3]) + 1):
			var key: String = "%d,%d" % [bx, bz]
			if not _buckets.has(key):
				_buckets[key] = [] as Array[StringName]
			var list: Array[StringName] = _buckets[key]
			list.append(id)


func _candidates_for_polygon(poly: Array[Vector2i]) -> Array[StringName]:
	var b: Array[int] = _bounds(poly)
	var seen: Dictionary = {}
	var out: Array[StringName] = []
	for bx: int in range(_bucket_of(b[0]), _bucket_of(b[2]) + 1):
		for bz: int in range(_bucket_of(b[1]), _bucket_of(b[3]) + 1):
			var key: String = "%d,%d" % [bx, bz]
			if not _buckets.has(key):
				continue
			var list: Array[StringName] = _buckets[key]
			for id: StringName in list:
				if not seen.has(id):
					seen[id] = true
					out.append(id)
	return out
