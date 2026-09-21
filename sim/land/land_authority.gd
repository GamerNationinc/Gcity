## The one spatial query under the whole game (design doc §7.1; M2 spec claims 1–5):
##   rights_at(position, actor) -> bit set over the rights content/right/ declares.
##
## Parcels are simple integer polygons in the XZ plane with a half-open vertical extent
## [floor, ceiling), in world metres (1 m voxels, ADR-003), indexed in a uniform grid of
## buckets. Membership of a voxel is decided at its centre with the half-open crossing
## rule, so adjacent parcels sharing an edge never both claim a voxel and stacked
## parcels never both claim a layer: every voxel belongs to exactly one parcel, and a
## voxel in no authored parcel belongs to the implicit wilderness parcel, which goes
## through the same policy lookup as every other one.
##
## Geometry is content; ownership is state (the overlay). Violations are events.
class_name LandAuthority extends SimSystem

const SYSTEM_ID: StringName = &"land"
const KIND_RIGHT: StringName = &"right"
const KIND_POLICY: StringName = &"rights_policy"
const KIND_DISTRICT: StringName = &"district"
const KIND_FACTION: StringName = &"faction"
const KIND_PARCEL: StringName = &"parcel"
const COMMAND_GRANT: StringName = &"land.grant"
const EVENT_VIOLATION: StringName = &"land.violation"
## The implicit parcel: everything outside every authored parcel.
const WILDERNESS: StringName = &""
const BUCKET: int = 16
const MAX_VERTICES: int = 64
const MAX_EXTENT: int = 1024
const OWNER_NONE: StringName = &"none"
const OWNER_ACTOR: StringName = &"actor"
const OWNER_FACTION: StringName = &"faction"
const REL_OWNER: String = "owner"
const REL_SAME_FACTION: String = "same_faction"
const REL_OTHER: String = "other"
const REL_UNOWNED: String = "unowned"

var _content: ContentDb
var _actors: ActorSystem
var _events: EventBus
## right id -> bit
var _bits: Dictionary = {}
var _right_names: Array[StringName] = []
## policy id -> relation -> bits
var _policies: Dictionary = {}
## parcel id -> {"district", "policy", "polygon": Array[Vector2i], "floor", "ceiling", "min": Vector2i, "max": Vector2i}
var _parcels: Dictionary = {}
## parcel id -> {"kind": StringName, "id": Variant}  (state)
var _owners: Dictionary = {}
## "bx,bz" -> Array[StringName]
var _grid: Dictionary = {}
var _wilderness_policy: StringName = &""
var _wilderness_district: StringName = &""
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
	return {"owners": _owners.duplicate(true), "violations": _violations}


## Loads rights, policies, districts and parcels from content, validating geometry the
## schema cannot, registers the system and its command.
func attach(sim: SimRoot) -> Error:
	var err: Error = validate_content()
	if err != OK:
		return err
	err = sim.register_system(self)
	if err != OK:
		return err
	return sim.commands().register(COMMAND_GRANT, _on_grant)


## Also the loader: on success the authority is fully built from content.
func validate_content() -> Error:
	_bits.clear()
	_right_names.clear()
	_policies.clear()
	_parcels.clear()
	_owners.clear()
	_grid.clear()
	var rights: Array[StringName] = _content.ids(KIND_RIGHT)
	if rights.is_empty() or rights.size() > 62:
		return _fail("between 1 and 62 rights must exist (%d)" % rights.size())
	for i: int in range(rights.size()):
		_bits[rights[i]] = 1 << i
		_right_names.append(rights[i])
	for policy: StringName in _content.ids(KIND_POLICY):
		var t: Dictionary = _content.get_entry(KIND_POLICY, policy)
		var table: Dictionary = {}
		for relation: String in [REL_OWNER, REL_SAME_FACTION, REL_OTHER, REL_UNOWNED]:
			var names: Array = t[relation]
			var bits: int = 0
			for n: Variant in names:
				var name_s: String = n
				var name: StringName = StringName(name_s)
				if not _bits.has(name):
					return _fail("rights_policy/%s names unknown right '%s'" % [policy, name])
				bits |= _bits[name]
			table[relation] = bits
		_policies[policy] = table
	var wilderness_count: int = 0
	for district: StringName in _content.ids(KIND_DISTRICT):
		var t: Dictionary = _content.get_entry(KIND_DISTRICT, district)
		var is_wild: bool = t["is_wilderness"]
		if is_wild:
			wilderness_count += 1
			_wilderness_district = district
			var policy_s: String = t["policy"]
			_wilderness_policy = StringName(policy_s)
	if wilderness_count != 1:
		return _fail("exactly one district must be the wilderness (%d are)" % wilderness_count)
	for parcel: StringName in _content.ids(KIND_PARCEL):
		var t: Dictionary = _content.get_entry(KIND_PARCEL, parcel)
		var district_s: String = t["district"]
		var district_t: Dictionary = _content.get_entry(KIND_DISTRICT, StringName(district_s))
		var policy_s: String = t.get("policy", district_t["policy"])
		var polygon: Array[Vector2i] = []
		var raw: Array = t["polygon"]
		for v: Variant in raw:
			var pair: Array = v
			var px: int = pair[0]
			var pz: int = pair[1]
			polygon.append(Vector2i(px, pz))
		var owner_t: Dictionary = t["owner"]
		var owner_kind_s: String = owner_t["kind"]
		var owner: Dictionary = {"kind": StringName(owner_kind_s), "id": null}
		if owner["kind"] == OWNER_FACTION:
			if not owner_t.has("id"):
				return _fail("parcel/%s is faction-owned but names no faction" % parcel)
			var id_s: String = owner_t["id"]
			owner["id"] = StringName(id_s)
		var floor_v: int = t["floor"]
		var ceiling_v: int = t["ceiling"]
		var err: Error = register_parcel(parcel, StringName(district_s), StringName(policy_s), polygon, floor_v, ceiling_v, owner)
		if err != OK:
			return err
	return OK


## Registers one parcel. Used by the content loader above and by tests that generate
## parcels. Rejects a non-simple or degenerate polygon, a bad vertical extent, an
## unknown policy or district, an over-large parcel, and any overlap with an existing
## parcel (a voxel belonging to both).
func register_parcel(id: StringName, district: StringName, policy: StringName, polygon: Array[Vector2i], floor_y: int, ceiling_y: int, owner: Dictionary) -> Error:
	if id.is_empty() or _parcels.has(id):
		return _fail("parcel id '%s' empty or duplicate" % id)
	if not _policies.has(policy):
		return _fail("parcel/%s uses unknown policy '%s'" % [id, policy])
	if not _content.has(KIND_DISTRICT, district):
		return _fail("parcel/%s uses unknown district '%s'" % [id, district])
	if floor_y >= ceiling_y:
		return _fail("parcel/%s floor must be below ceiling" % id)
	if polygon.size() < 3 or polygon.size() > MAX_VERTICES:
		return _fail("parcel/%s needs 3..%d vertices" % [id, MAX_VERTICES])
	if not _is_simple(polygon):
		return _fail("parcel/%s polygon is not simple (self-intersecting, repeated or collinear-degenerate)" % id)
	var kind: StringName = owner.get("kind", &"")
	if kind == OWNER_FACTION:
		var fid_v: Variant = owner.get("id")
		if typeof(fid_v) != TYPE_STRING_NAME:
			return _fail("parcel/%s owner faction must be a StringName" % id)
		var fid: StringName = fid_v
		if not _content.has(KIND_FACTION, fid):
			return _fail("parcel/%s owner faction unknown" % id)
	elif kind == OWNER_ACTOR:
		if typeof(owner.get("id")) != TYPE_INT:
			return _fail("parcel/%s actor owner needs an int id" % id)
	elif kind != OWNER_NONE:
		return _fail("parcel/%s owner kind must be none, actor or faction" % id)
	var lo: Vector2i = polygon[0]
	var hi: Vector2i = polygon[0]
	for v: Vector2i in polygon:
		lo = Vector2i(mini(lo.x, v.x), mini(lo.y, v.y))
		hi = Vector2i(maxi(hi.x, v.x), maxi(hi.y, v.y))
	if hi.x - lo.x > MAX_EXTENT or hi.y - lo.y > MAX_EXTENT:
		return _fail("parcel/%s exceeds %d m in an axis" % [id, MAX_EXTENT])
	var record: Dictionary = {"district": district, "policy": policy, "polygon": polygon.duplicate(), "floor": floor_y, "ceiling": ceiling_y, "min": lo, "max": hi}
	# overlap: any voxel in both. Bounded by the bbox intersection; exact for the membership rule.
	for other_id: StringName in _candidates_in_box(lo, hi):
		var other: Dictionary = _parcels[other_id]
		var o_floor: int = other["floor"]
		var o_ceiling: int = other["ceiling"]
		if o_ceiling <= floor_y or ceiling_y <= o_floor:
			continue
		var o_min: Vector2i = other["min"]
		var o_max: Vector2i = other["max"]
		var ix0: int = maxi(lo.x, o_min.x)
		var ix1: int = mini(hi.x, o_max.x)
		var iz0: int = maxi(lo.y, o_min.y)
		var iz1: int = mini(hi.y, o_max.y)
		for z: int in range(iz0, iz1):
			for x: int in range(ix0, ix1):
				if _contains_xz(record, x, z) and _contains_xz(other, x, z):
					return _fail("parcel/%s overlaps parcel/%s at (%d, %d)" % [id, other_id, x, z])
	_parcels[id] = record
	_owners[id] = {"kind": kind, "id": owner.get("id")}
	for bz: int in range(_bucket(lo.y), _bucket(hi.y) + 1):
		for bx: int in range(_bucket(lo.x), _bucket(hi.x) + 1):
			var key: String = "%d,%d" % [bx, bz]
			if not _grid.has(key):
				_grid[key] = [] as Array[StringName]
			var list: Array[StringName] = _grid[key]
			list.append(id)
	return OK


# ---------------------------------------------------------------- the query

## The parcel a voxel belongs to, or WILDERNESS ("").
func parcel_at(position: Vector3i) -> StringName:
	var key: String = "%d,%d" % [_bucket(position.x), _bucket(position.z)]
	var stored: Variant = _grid.get(key)
	if typeof(stored) != TYPE_ARRAY:
		return WILDERNESS
	var list: Array = stored
	for entry: Variant in list:
		var id: StringName = entry
		var p: Dictionary = _parcels[id]
		var floor_y: int = p["floor"]
		var ceiling_y: int = p["ceiling"]
		if position.y < floor_y or position.y >= ceiling_y:
			continue
		if _contains_xz(p, position.x, position.z):
			return id
	return WILDERNESS


## The bit set of rights `actor` holds at `position`. Total.
func rights_at(position: Vector3i, actor: int) -> int:
	return rights_of(parcel_at(position), actor)


func rights_of(parcel: StringName, actor: int) -> int:
	var policy: StringName = policy_of(parcel)
	var table: Dictionary = _policies[policy]
	return table[relation_of(parcel, actor)]


func has_right(bits: int, right: StringName) -> bool:
	var bit: int = _bits.get(right, 0)
	return bit != 0 and (bits & bit) != 0


## Asks for one right and, if denied, emits land.violation. For systems that act on land.
func check(position: Vector3i, actor: int, right: StringName) -> bool:
	if not _bits.has(right):
		push_error("LandAuthority: unknown right '%s'" % right)
		return false
	var parcel: StringName = parcel_at(position)
	if has_right(rights_of(parcel, actor), right):
		return true
	_violations += 1
	_events.emit(EVENT_VIOLATION, {"actor": actor, "right": String(right), "parcel": String(parcel),
		"position": [position.x, position.y, position.z]})
	return false


func relation_of(parcel: StringName, actor: int) -> String:
	var owner: Dictionary = owner_of(parcel)
	var kind: StringName = owner["kind"]
	match kind:
		OWNER_NONE:
			return REL_UNOWNED
		OWNER_ACTOR:
			return REL_OWNER if owner["id"] == actor else REL_OTHER
		_:
			# Actors carry no faction until M8; same_faction resolves then.
			return REL_OTHER


func owner_of(parcel: StringName) -> Dictionary:
	if parcel == WILDERNESS:
		return {"kind": OWNER_NONE, "id": null}
	if not _owners.has(parcel):
		push_error("LandAuthority: unknown parcel '%s'" % parcel)
		return {"kind": OWNER_NONE, "id": null}
	var owner: Dictionary = _owners[parcel]
	return owner.duplicate()


func policy_of(parcel: StringName) -> StringName:
	if parcel == WILDERNESS:
		return _wilderness_policy
	var p: Dictionary = _parcels[parcel]
	return p["policy"]


func district_of(parcel: StringName) -> StringName:
	if parcel == WILDERNESS:
		return _wilderness_district
	var p: Dictionary = _parcels[parcel]
	return p["district"]


func has_parcel(parcel: StringName) -> bool:
	return _parcels.has(parcel)


func parcel_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: Variant in _parcels:
		var id: StringName = key
		out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


func parcel_bounds(parcel: StringName) -> Dictionary:
	if not _parcels.has(parcel):
		return {}
	var p: Dictionary = _parcels[parcel]
	var polygon: Array[Vector2i] = p["polygon"]
	return {"min": p["min"], "max": p["max"], "floor": p["floor"], "ceiling": p["ceiling"], "polygon": polygon.duplicate()}


func right_names() -> Array[StringName]:
	return _right_names.duplicate()


func right_bit(right: StringName) -> int:
	return _bits.get(right, 0)


func violations() -> int:
	return _violations


# ---------------------------------------------------------------- command

## {"actor": int, "parcel": name}: debug-class (M2 spec claim 7). Makes the actor the owner.
func _on_grant(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT:
		return false
	var parcel_v: Variant = payload.get("parcel")
	var parcel: StringName = &""
	match typeof(parcel_v):
		TYPE_STRING:
			var s: String = parcel_v
			parcel = StringName(s)
		TYPE_STRING_NAME:
			parcel = parcel_v
		_:
			return false
	var actor: int = payload["actor"]
	if not _parcels.has(parcel) or not _actors.has_actor(actor):
		return false
	_owners[parcel] = {"kind": OWNER_ACTOR, "id": actor}
	return true


# ---------------------------------------------------------------- restore

## Ownership is the only state. Every parcel must be present, owners well-formed.
func restore(state: Dictionary) -> Error:
	if state.size() != 2 or typeof(state.get("owners")) != TYPE_DICTIONARY or typeof(state.get("violations")) != TYPE_INT:
		return _restore_fail("shape")
	var violations: int = state["violations"]
	if violations < 0:
		return _restore_fail("violations")
	var owners_in: Dictionary = state["owners"]
	if owners_in.size() != _parcels.size():
		return _restore_fail("parcel set differs from content")
	var out: Dictionary = {}
	for pk: Variant in owners_in:
		var parcel: StringName = _as_name(pk)
		if not _parcels.has(parcel) or typeof(owners_in[pk]) != TYPE_DICTIONARY:
			return _restore_fail("owner entry for '%s'" % parcel)
		var o: Dictionary = owners_in[pk]
		if o.size() != 2 or not o.has("kind") or not o.has("id"):
			return _restore_fail("owner shape for '%s'" % parcel)
		var kind: StringName = _as_name(o["kind"])
		var id_v: Variant = o["id"]
		match kind:
			OWNER_NONE:
				if id_v != null:
					return _restore_fail("none owner with an id on '%s'" % parcel)
			OWNER_ACTOR:
				if typeof(id_v) != TYPE_INT:
					return _restore_fail("actor owner of '%s' must be an int" % parcel)
				var actor_id: int = id_v
				if not _actors.has_actor(actor_id):
					return _restore_fail("actor owner of '%s' does not exist" % parcel)
			OWNER_FACTION:
				var fid: StringName = _as_name(id_v)
				if not _content.has(KIND_FACTION, fid):
					return _restore_fail("faction owner of '%s' unknown" % parcel)
				id_v = fid
			_:
				return _restore_fail("owner kind on '%s'" % parcel)
		out[parcel] = {"kind": kind, "id": id_v}
	_owners = out
	_violations = violations
	return OK


# ---------------------------------------------------------------- geometry

## Voxel (x, z) is inside the polygon iff its centre is, by the half-open crossing rule.
## Doubled integer coordinates keep the test exact: centre = (2x+1, 2z+1).
static func _contains_xz(parcel: Dictionary, x: int, z: int) -> bool:
	var lo: Vector2i = parcel["min"]
	var hi: Vector2i = parcel["max"]
	if x < lo.x or x >= hi.x or z < lo.y or z >= hi.y:
		return false
	var polygon: Array[Vector2i] = parcel["polygon"]
	var px: int = 2 * x + 1
	var pz: int = 2 * z + 1
	var inside: bool = false
	var n: int = polygon.size()
	for i: int in range(n):
		var a: Vector2i = polygon[i] * 2
		var b: Vector2i = polygon[(i + 1) % n] * 2
		if (a.y > pz) == (b.y > pz):
			continue
		# x of the edge at height pz is > px ?  a.x + (pz - a.y) * (b.x - a.x) / (b.y - a.y) > px
		var dy: int = b.y - a.y
		var num: int = (b.x - a.x) * (pz - a.y) + (a.x - px) * dy
		if (dy > 0 and num > 0) or (dy < 0 and num < 0):
			inside = not inside
	return inside


## Simple polygon: no repeated vertices, no zero-length or collinear-overlapping
## adjacent edges, no intersection between non-adjacent edges, non-zero area.
static func _is_simple(polygon: Array[Vector2i]) -> bool:
	var n: int = polygon.size()
	for i: int in range(n):
		for j: int in range(i + 1, n):
			if polygon[i] == polygon[j]:
				return false
	var area2: int = 0
	for i: int in range(n):
		var a: Vector2i = polygon[i]
		var b: Vector2i = polygon[(i + 1) % n]
		area2 += a.x * b.y - b.x * a.y
	if area2 == 0:
		return false
	for i: int in range(n):
		var a: Vector2i = polygon[i]
		var b: Vector2i = polygon[(i + 1) % n]
		for j: int in range(i + 1, n):
			var c: Vector2i = polygon[j]
			var d: Vector2i = polygon[(j + 1) % n]
			var adjacent: bool = (j == i + 1) or (i == 0 and j == n - 1)
			if adjacent:
				# adjacent edges may only meet at their shared vertex: reject a fold-back
				var shared: Vector2i = b if j == i + 1 else a
				var other1: Vector2i = a if j == i + 1 else b
				var other2: Vector2i = d if j == i + 1 else c
				if _cross(shared, other1, other2) == 0 and _dot_sign(shared, other1, other2) > 0:
					return false
				continue
			if _segments_intersect(a, b, c, d):
				return false
	return true


static func _cross(o: Vector2i, a: Vector2i, b: Vector2i) -> int:
	return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)


static func _dot_sign(o: Vector2i, a: Vector2i, b: Vector2i) -> int:
	return signi((a.x - o.x) * (b.x - o.x) + (a.y - o.y) * (b.y - o.y))


static func _on_segment(p: Vector2i, a: Vector2i, b: Vector2i) -> bool:
	return mini(a.x, b.x) <= p.x and p.x <= maxi(a.x, b.x) and mini(a.y, b.y) <= p.y and p.y <= maxi(a.y, b.y)


## Closed segments intersect (proper crossing, touching, or collinear overlap).
static func _segments_intersect(a: Vector2i, b: Vector2i, c: Vector2i, d: Vector2i) -> bool:
	var d1: int = signi(_cross(c, d, a))
	var d2: int = signi(_cross(c, d, b))
	var d3: int = signi(_cross(a, b, c))
	var d4: int = signi(_cross(a, b, d))
	if d1 * d2 < 0 and d3 * d4 < 0:
		return true
	if d1 == 0 and _on_segment(a, c, d):
		return true
	if d2 == 0 and _on_segment(b, c, d):
		return true
	if d3 == 0 and _on_segment(c, a, b):
		return true
	if d4 == 0 and _on_segment(d, a, b):
		return true
	return false


func _candidates_in_box(lo: Vector2i, hi: Vector2i) -> Array[StringName]:
	var out: Array[StringName] = []
	for bz: int in range(_bucket(lo.y), _bucket(hi.y) + 1):
		for bx: int in range(_bucket(lo.x), _bucket(hi.x) + 1):
			var stored: Variant = _grid.get("%d,%d" % [bx, bz])
			if typeof(stored) != TYPE_ARRAY:
				continue
			var list: Array = stored
			for entry: Variant in list:
				var id: StringName = entry
				if not out.has(id):
					out.append(id)
	return out


static func _bucket(v: int) -> int:
	return floori(float(v) / BUCKET) if v < 0 else v / BUCKET


func _fail(reason: String) -> Error:
	push_error("LandAuthority: content rejected: %s" % reason)
	return ERR_INVALID_DATA


func _restore_fail(reason: String) -> Error:
	push_error("LandAuthority.restore: rejected snapshot: %s" % reason)
	return ERR_INVALID_DATA


static func _as_name(v: Variant) -> StringName:
	match typeof(v):
		TYPE_STRING_NAME:
			return v
		TYPE_STRING:
			var s: String = v
			return StringName(s)
		_:
			return &""
