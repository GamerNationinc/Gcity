extends GcityTest

const SEED: int = 20260920
const PROPERTY_CASES: int = 10_000
const SEED_TOTAL: int = 20260928
const SEED_OVERLAP: int = 20260929
const SEED_INSIDE: int = 20260930

var _sim: SimRoot
var _land: LandAuthority
var _actors: ActorSystem


func _content() -> ContentDb:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	return db


func _build() -> void:
	_sim = SimAssembly.build(SEED, _content())
	assert_true(_sim != null, "assembly")
	_land = SimAssembly.land_of(_sim)
	_actors = SimAssembly.actors_of(_sim)


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


func _bits(land: LandAuthority, names: Array[StringName]) -> int:
	var b: int = 0
	for n: StringName in names:
		b |= land.right_bit(n)
	return b


## A bare authority over the shipped content, for geometry tests that add parcels.
func _bare() -> LandAuthority:
	var db: ContentDb = _content()
	var actors := ActorSystem.new(db, StatResolver.new(), EntityIds.new(), ItemSystem.new(db, StatResolver.new(), EntityIds.new()))
	var land := LandAuthority.new(db, actors, EventBus.new())
	assert_eq(land.validate_content(), OK, "content loads")
	return land


# ---------------------------------------------------------------- units

func test_rights_from_content_for_owner_other_and_wilderness() -> void:
	_build()
	assert_eq(_land.right_names(), [&"build", &"carry", &"dig", &"enter", &"loot"] as Array[StringName], "rights in lexical order")
	assert_eq(_land.parcel_ids(), [&"starter_plot", &"starter_street"] as Array[StringName], "authored parcels")
	var player: int = _actors.spawn(&"arcade", 0)
	var stranger: int = _actors.spawn(&"arcade", 0)
	var inside: Vector3i = Vector3i(5, 0, 5)
	assert_eq(_land.parcel_at(inside), &"starter_plot", "inside the plot")
	assert_eq(_land.owner_of(&"starter_plot"), {"kind": &"none", "id": null}, "unowned at start")
	assert_eq(_land.rights_at(inside, player), _bits(_land, [&"enter", &"carry"]), "unowned private parcel: enter and carry")
	assert_true(_do(&"land.grant", {"actor": player, "parcel": "starter_plot"}), "grant")
	assert_eq(_land.owner_of(&"starter_plot"), {"kind": &"actor", "id": player}, "owned by the player")
	assert_eq(_land.rights_at(inside, player), _bits(_land, [&"build", &"dig", &"enter", &"carry", &"loot"]), "owner: everything")
	assert_eq(_land.rights_at(inside, stranger), _bits(_land, [&"carry"]), "stranger on private land: carry only")
	assert_true(_land.has_right(_land.rights_at(inside, player), &"build"), "has_right")
	assert_false(_land.has_right(_land.rights_at(inside, stranger), &"build"), "stranger cannot build")
	var street: Vector3i = Vector3i(5, 0, -3)
	assert_eq(_land.parcel_at(street), &"starter_street", "street parcel")
	assert_eq(_land.owner_of(&"starter_street"), {"kind": &"faction", "id": &"city_state"}, "city owns the street")
	assert_eq(_land.rights_at(street, player), _bits(_land, [&"enter", &"carry"]), "public policy override: enter and carry")
	assert_eq(_land.policy_of(&"starter_street"), &"city_public", "parcel policy override")
	assert_eq(_land.district_of(&"starter_plot"), &"starter_ghetto", "district")
	var far: Vector3i = Vector3i(1000, 0, 1000)
	assert_eq(_land.parcel_at(far), LandAuthority.WILDERNESS, "wilderness")
	assert_eq(_land.rights_at(far, stranger), _bits(_land, [&"build", &"dig", &"enter", &"carry", &"loot"]), "wilderness is permissive")
	assert_eq(_land.district_of(LandAuthority.WILDERNESS), &"wilds", "wilderness district from content")


func test_vertical_extent_and_shared_edges() -> void:
	_build()
	var player: int = _actors.spawn(&"arcade", 0)
	_do(&"land.grant", {"actor": player, "parcel": "starter_plot"})
	assert_eq(_land.parcel_at(Vector3i(5, -4, 5)), &"starter_plot", "floor is inclusive")
	assert_eq(_land.parcel_at(Vector3i(5, -5, 5)), LandAuthority.WILDERNESS, "below the floor is nobody's: tunnelling under is not trespass on this parcel")
	assert_eq(_land.parcel_at(Vector3i(5, 7, 5)), &"starter_plot", "just under the ceiling")
	assert_eq(_land.parcel_at(Vector3i(5, 8, 5)), LandAuthority.WILDERNESS, "ceiling is exclusive")
	# plot z in [0,12) and street z in [-6,0) share the edge z = 0
	assert_eq(_land.parcel_at(Vector3i(5, 0, 0)), &"starter_plot", "voxel row on the shared edge belongs to the plot")
	assert_eq(_land.parcel_at(Vector3i(5, 0, -1)), &"starter_street", "the row below belongs to the street")
	assert_eq(_land.parcel_at(Vector3i(0, 0, 0)), &"starter_plot", "corner voxel")
	assert_eq(_land.parcel_at(Vector3i(12, 0, 0)), LandAuthority.WILDERNESS, "x = 12 is outside a 12-wide plot")
	assert_eq(_land.parcel_at(Vector3i(-1, 0, 5)), LandAuthority.WILDERNESS, "west of the plot")


func test_check_emits_a_violation_and_grant_is_validated() -> void:
	_build()
	var player: int = _actors.spawn(&"arcade", 0)
	var stranger: int = _actors.spawn(&"arcade", 0)
	var seen: Array[Dictionary] = []
	assert_eq(SimAssembly.combat_of(_sim).events().subscribe(LandAuthority.EVENT_VIOLATION, func(p: Dictionary) -> void: seen.append(p)), OK, "subscribe")
	assert_true(_do(&"land.grant", {"actor": player, "parcel": "starter_plot"}), "grant")
	assert_true(_land.check(Vector3i(3, 0, 3), player, &"build"), "owner may build")
	assert_false(_land.check(Vector3i(3, 0, 3), stranger, &"build"), "stranger may not")
	assert_eq(seen.size(), 1, "one violation event")
	assert_eq(seen[0]["actor"], stranger, "who")
	assert_eq(seen[0]["right"], "build", "what")
	assert_eq(seen[0]["parcel"], "starter_plot", "where")
	assert_eq(seen[0]["position"], [3, 0, 3], "exactly where")
	assert_eq(_land.violations(), 1, "counted in state")
	assert_false(_land.check(Vector3i(3, 0, 3), stranger, &"fly"), "unknown right is refused loudly")
	assert_false(_do(&"land.grant", {"actor": player, "parcel": "nope"}), "unknown parcel")
	assert_false(_do(&"land.grant", {"actor": 99, "parcel": "starter_plot"}), "unknown actor")
	assert_false(_do(&"land.grant", {"actor": player, "parcel": 7}), "parcel must be a name")
	assert_false(_do(&"land.grant", {"actor": player, "parcel": "starter_plot", "x": 1}), "extra key")
	assert_true(_do(&"land.grant", {"actor": stranger, "parcel": "starter_plot"}), "ownership can pass (debug-class)")
	assert_eq(_land.owner_of(&"starter_plot"), {"kind": &"actor", "id": stranger}, "now the stranger's")


func test_content_geometry_rules_at_assembly() -> void:
	var bad: Array[Dictionary] = [
		{"polygon": [[0, 0], [1, 0]], "why": "two vertices"},
		{"polygon": [[0, 0], [4, 4], [4, 0], [0, 4]], "why": "self-intersecting bow-tie"},
		{"polygon": [[0, 0], [4, 0], [4, 0], [0, 4]], "why": "repeated vertex"},
		{"polygon": [[0, 0], [4, 0], [8, 0]], "why": "zero area"},
		{"polygon": [[0, 0], [4, 0], [2, 0], [2, 4]], "why": "fold-back on a collinear neighbour"},
		{"polygon": [[6, 6], [20, 6], [20, 20], [6, 20]], "why": "overlaps the starter plot"},
		{"polygon": [[2000, 0], [4000, 0], [4000, 10], [2000, 10]], "why": "wider than the extent cap"},
	]
	var i: int = 0
	for b: Dictionary in bad:
		var db: ContentDb = _content()
		assert_eq(db.add(&"parcel", &"zz_bad", {"schema_version": 1, "description": b["why"], "district": "starter_ghetto",
			"polygon": b["polygon"], "floor": -4, "ceiling": 8, "owner": {"kind": "none"}}), OK, "shape accepted %d" % i)
		assert_true(SimAssembly.build(SEED, db) == null, "assembly refuses: %s" % b["why"])
		i += 1
	var db2: ContentDb = _content()
	assert_eq(db2.add(&"parcel", &"zz_stacked", {"schema_version": 1, "description": "same footprint, above the ceiling", "district": "starter_ghetto",
		"polygon": [[0, 0], [12, 0], [12, 12], [0, 12]], "floor": 8, "ceiling": 20, "owner": {"kind": "none"}}), OK, "stacked shape")
	assert_true(SimAssembly.build(SEED, db2) != null, "a parcel stacked above another (half-open extents) does not overlap")
	var db3: ContentDb = _content()
	assert_eq(db3.add(&"district", &"zz_wild2", {"schema_version": 1, "description": "x", "policy": "wilderness", "law_index": 0,
		"wealth_index": 0, "informant_density": 0, "is_wilderness": true}), OK, "district shape")
	assert_true(SimAssembly.build(SEED, db3) == null, "two wilderness districts refused")
	var db4: ContentDb = _content()
	assert_eq(db4.add(&"rights_policy", &"zz_fly", {"schema_version": 1, "description": "x", "owner": ["fly"], "same_faction": [], "other": [], "unowned": []}), OK, "policy shape")
	assert_true(SimAssembly.build(SEED, db4) == null, "unknown right in a policy refused")


func test_restore_round_trip_and_rejections() -> void:
	_build()
	var player: int = _actors.spawn(&"arcade", 0)
	_do(&"land.grant", {"actor": player, "parcel": "starter_plot"})
	_land.check(Vector3i(5, 0, -3), player, &"build")
	var full: Dictionary = _sim.snapshot()
	var fresh: SimRoot = SimAssembly.build(SEED, _content())
	assert_eq(SimAssembly.restore_systems(fresh, full), OK, "restore")
	var fl: LandAuthority = SimAssembly.land_of(fresh)
	assert_eq(fl.owner_of(&"starter_plot"), {"kind": &"actor", "id": player}, "owner restored")
	assert_eq(fl.violations(), 1, "violations restored")
	var a: Dictionary = _sim.snapshot()["systems"]
	var b: Dictionary = fresh.snapshot()["systems"]
	assert_eq(StateHash.of(b), StateHash.of(a), "system state hash equal")
	var good: Dictionary = _land.snapshot()
	var bad: Array[Dictionary] = []
	var c: Dictionary
	c = good.duplicate(true)
	_sub(c, "owners").erase(&"starter_street")
	bad.append(c)
	c = good.duplicate(true)
	_sub(c, "owners")[&"starter_plot"] = {"kind": &"actor", "id": 999}
	bad.append(c)
	c = good.duplicate(true)
	_sub(c, "owners")[&"starter_plot"] = {"kind": &"faction", "id": &"martians"}
	bad.append(c)
	c = good.duplicate(true)
	_sub(c, "owners")[&"starter_plot"] = {"kind": &"none", "id": 3}
	bad.append(c)
	c = good.duplicate(true)
	c["violations"] = -1
	bad.append(c)
	var i: int = 0
	for d: Dictionary in bad:
		var target: SimRoot = SimAssembly.build(SEED, _content())
		assert_eq(SimAssembly.actors_of(target).restore(_actors.snapshot()), OK, "actors first")
		assert_eq(SimAssembly.land_of(target).restore(d), ERR_INVALID_DATA, "hostile %d rejected" % i)
		assert_eq(SimAssembly.land_of(target).owner_of(&"starter_plot"), {"kind": &"none", "id": null}, "hostile %d left content owners" % i)
		i += 1


# ---------------------------------------------------------------- properties (claim 3)

## (a) rights_at() resolves for any position, including far outside every parcel.
func test_property_rights_at_is_total() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_TOTAL
	_build()
	var player: int = _actors.spawn(&"arcade", 0)
	_do(&"land.grant", {"actor": player, "parcel": "starter_plot"})
	var all: int = _bits(_land, _land.right_names())
	var failures: int = 0
	var hits: Dictionary = {}
	for case: int in range(PROPERTY_CASES):
		var p: Vector3i
		match rng.randi_range(0, 3):
			0:
				p = Vector3i(rng.randi_range(-8, 20), rng.randi_range(-8, 12), rng.randi_range(-10, 16))
			1:
				p = Vector3i(rng.randi_range(-100000, 100000), rng.randi_range(-1000, 1000), rng.randi_range(-100000, 100000))
			2:
				p = Vector3i(rng.randi(), rng.randi(), rng.randi())
			_:
				p = Vector3i(-rng.randi(), -rng.randi(), -rng.randi())
		var actor: int = player if rng.randf() < 0.5 else 77
		var rights: int = _land.rights_at(p, actor)
		if rights < 0 or rights > all:
			failures += 1
		hits[_land.parcel_at(p)] = true
	assert_eq(failures, 0, "every position resolved to a valid bit set")
	assert_true(hits.has(&"starter_plot") and hits.has(&"starter_street") and hits.has(LandAuthority.WILDERNESS), "all three parcels were reached")


## (b) A generated parcel set never contains two parcels sharing a voxel: every accepted
## pair is disjoint (brute force), and every rejected candidate really overlaps one.
func test_property_parcels_never_overlap() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_OVERLAP
	var failures: int = 0
	var accepted_total: int = 0
	var rejected_total: int = 0
	for case: int in range(PROPERTY_CASES / 50):
		var land: LandAuthority = _bare()
		var accepted: Array[Dictionary] = []
		for k: int in range(rng.randi_range(2, 6)):
			var poly: Array[Vector2i] = _random_polygon(rng)
			var floor_y: int = rng.randi_range(-6, 4)
			var ceiling_y: int = floor_y + rng.randi_range(1, 8)
			var err: Error = land.register_parcel(StringName("p%d" % k), &"starter_ghetto", &"city_private", poly, floor_y, ceiling_y, {"kind": &"none", "id": null})
			var candidate: Dictionary = {"polygon": poly, "floor": floor_y, "ceiling": ceiling_y}
			var overlaps_existing: bool = false
			for a: Dictionary in accepted:
				if _brute_overlap(land, a, candidate):
					overlaps_existing = true
					break
			if err == OK:
				accepted_total += 1
				if overlaps_existing:
					failures += 1
					if failures <= 3:
						fail("case %d: accepted a parcel that overlaps an accepted one" % case)
				accepted.append(candidate)
			else:
				rejected_total += 1
				if not overlaps_existing and land.parcel_ids().size() > 0 and _is_valid_shape(poly):
					failures += 1
					if failures <= 3:
						fail("case %d: rejected a non-overlapping valid parcel" % case)
	assert_eq(failures, 0, "no overlap ever accepted, no disjoint parcel wrongly rejected")
	assert_true(accepted_total > 200 and rejected_total > 50, "both outcomes exercised (%d accepted, %d rejected)" % [accepted_total, rejected_total])


## (c) A voxel inside the polygon and extent returns the parcel and its owner; the first
## voxel outside along +x, and one voxel above the ceiling, do not.
func test_property_inside_returns_owner_outside_does_not() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_INSIDE
	var failures: int = 0
	var checked: int = 0
	for case: int in range(PROPERTY_CASES / 5):
		var land: LandAuthority = _bare()
		var poly: Array[Vector2i] = _random_polygon(rng)
		var floor_y: int = rng.randi_range(-6, 4)
		var ceiling_y: int = floor_y + rng.randi_range(1, 8)
		var owner: Dictionary = {"kind": &"faction", "id": &"city_state"} if rng.randf() < 0.5 else {"kind": &"none", "id": null}
		if land.register_parcel(&"gen", &"starter_ghetto", &"city_private", poly, floor_y, ceiling_y, owner) != OK:
			continue
		var b: Dictionary = land.parcel_bounds(&"gen")
		var lo: Vector2i = b["min"]
		var hi: Vector2i = b["max"]
		for probe: int in range(10):
			var x: int = rng.randi_range(lo.x, hi.x - 1)
			var z: int = rng.randi_range(lo.y, hi.y - 1)
			var y: int = rng.randi_range(floor_y, ceiling_y - 1)
			if land.parcel_at(Vector3i(x, y, z)) != &"gen":
				continue
			checked += 1
			if land.owner_of(&"gen") != owner or land.rights_of(&"gen", 1) != land.rights_at(Vector3i(x, y, z), 1):
				failures += 1
			var ox: int = x
			while land.parcel_at(Vector3i(ox, y, z)) == &"gen":
				ox += 1
			if land.parcel_at(Vector3i(ox, y, z)) != LandAuthority.WILDERNESS:
				failures += 1
			if land.parcel_at(Vector3i(x, ceiling_y, z)) != LandAuthority.WILDERNESS or land.parcel_at(Vector3i(x, floor_y - 1, z)) != LandAuthority.WILDERNESS:
				failures += 1
	assert_eq(failures, 0, "inside returns the parcel and owner; the first voxel outside does not")
	assert_true(checked >= PROPERTY_CASES, "at least %d inside probes were checked (%d)" % [PROPERTY_CASES, checked])


# ---------------------------------------------------------------- helpers

## Rectangles, L-shapes and triangles with integer vertices in a small window placed
## well away from the authored parcels, so the only overlaps are between generated ones.
func _random_polygon(rng: RandomNumberGenerator) -> Array[Vector2i]:
	var x: int = rng.randi_range(190, 210)
	var z: int = rng.randi_range(-210, -190)
	var w: int = rng.randi_range(1, 8)
	var h: int = rng.randi_range(1, 8)
	match rng.randi_range(0, 2):
		0:
			return [Vector2i(x, z), Vector2i(x + w, z), Vector2i(x + w, z + h), Vector2i(x, z + h)]
		1:
			var w2: int = rng.randi_range(1, w)
			var h2: int = rng.randi_range(1, h)
			return [Vector2i(x, z), Vector2i(x + w, z), Vector2i(x + w, z + h2), Vector2i(x + w2, z + h2), Vector2i(x + w2, z + h), Vector2i(x, z + h)]
		_:
			return [Vector2i(x, z), Vector2i(x + w, z), Vector2i(x, z + h)]


func _is_valid_shape(poly: Array[Vector2i]) -> bool:
	# the generator only produces simple shapes with positive area; degenerate L-shapes
	# (w2 == w or h2 == h) fold onto a collinear neighbour and are rightly rejected
	if poly.size() == 6:
		return poly[2] != poly[3] and poly[3] != poly[4] and not (poly[1].x == poly[3].x) and not (poly[3].y == poly[4].y and poly[4].y == poly[5].y)
	return true


func _brute_overlap(land: LandAuthority, a: Dictionary, b: Dictionary) -> bool:
	var af: int = a["floor"]
	var ac: int = a["ceiling"]
	var bf: int = b["floor"]
	var bc: int = b["ceiling"]
	if ac <= bf or bc <= af:
		return false
	var poly_a: Array[Vector2i] = a["polygon"]
	var poly_b: Array[Vector2i] = b["polygon"]
	var pa: Dictionary = _record(poly_a)
	var pb: Dictionary = _record(poly_b)
	var amin: Vector2i = pa["min"]
	var amax: Vector2i = pa["max"]
	for z: int in range(amin.y, amax.y):
		for x: int in range(amin.x, amax.x):
			if LandAuthority._contains_xz(pa, x, z) and LandAuthority._contains_xz(pb, x, z):
				return true
	return false


static func _record(polygon: Array[Vector2i]) -> Dictionary:
	var lo: Vector2i = polygon[0]
	var hi: Vector2i = polygon[0]
	for v: Vector2i in polygon:
		lo = Vector2i(mini(lo.x, v.x), mini(lo.y, v.y))
		hi = Vector2i(maxi(hi.x, v.x), maxi(hi.y, v.y))
	return {"polygon": polygon, "min": lo, "max": hi}


static func _sub(dict: Dictionary, key: Variant) -> Dictionary:
	var out: Dictionary = dict[key]
	return out
