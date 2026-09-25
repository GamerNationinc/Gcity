extends GcityTest

## M2 spec claims 1–7: rights_at() totality, parcel exclusivity and vertical extent,
## rights from district tables, violations as events, transfer and identify.

const SEED: int = 20260921
const PROPERTY_CASES: int = 10_000
const SEED_TOTALITY: int = 20260922
const SEED_SETS: int = 20260923
const M: int = 1000
const PLOT: StringName = &"starter_plot"
const EAST: StringName = &"neighbour_east"
const NORTH: StringName = &"neighbour_north"
const FIXER: StringName = &"fixers_office"
const LOT: StringName = &"cold_storage_lot"

var _sim: SimRoot
var _land: LandSystem
var _actors: ActorSystem
var _events_seen: Array[Dictionary] = []


func _build() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_land = SimAssembly.land_of(_sim)
	_actors = SimAssembly.actors_of(_sim)


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


func _player() -> int:
	var id: int = _actors.spawn(&"arcade", 0)
	assert_true(_do(LandSystem.COMMAND_IDENTIFY, {"actor": id, "owner": "player"}), "identify player")
	return id


func _rights(pos: Vector3i, actor: int) -> String:
	var r: Dictionary = _land.rights_at(pos, actor)
	var out: String = ""
	for right: StringName in LandSystem.RIGHTS:
		out += "1" if r[right] else "0"
	return out


# ---------------------------------------------------------------- content and lookup

func test_content_parcels_are_placed_at_assembly() -> void:
	_build()
	assert_eq(_land.parcel_ids(), [LOT, FIXER, EAST, NORTH, PLOT] as Array[StringName], "five content parcels, sorted")
	assert_eq(_land.owner_of(LOT), &"corp.coldchain", "the cold store's operator owns its lot")
	assert_eq(_land.owner_of(FIXER), &"npc.fixer", "and the fixer their office")
	assert_eq(_land.owner_of(PLOT), &"", "plot starts unowned")
	assert_eq(_land.owner_of(EAST), &"npc.landlord_east", "east landlord")
	assert_eq(_land.district_of(PLOT), &"starter_ghetto", "plot district")
	assert_eq(_land.wild_district(), &"badlands_outskirts", "the wild district covers unparcelled land")
	assert_eq(_land.district_of(&"nothing"), &"badlands_outskirts", "unknown parcel resolves to the wild district")


func test_parcel_at_geometry_and_shared_edges() -> void:
	_build()
	assert_eq(_land.parcel_at(Vector3i(6 * M, 0, 6 * M)), PLOT, "centre of the plot")
	assert_eq(_land.parcel_at(Vector3i(0, 0, 0)), PLOT, "south-west corner belongs to the plot")
	assert_eq(_land.parcel_at(Vector3i(12192, 0, 6 * M)), EAST, "the shared east edge belongs to the east parcel only")
	assert_eq(_land.parcel_at(Vector3i(6 * M, 0, 12192)), NORTH, "the shared north edge belongs to the north parcel only")
	assert_eq(_land.parcel_at(Vector3i(12192, 0, 12192)), NORTH, "three-way corner resolves to exactly one parcel")
	assert_eq(_land.parcel_at(Vector3i(18 * M, 0, 20 * M)), LandSystem.UNPARCELLED, "inside the L's notch is unparcelled")
	assert_eq(_land.parcel_at(Vector3i(6 * M, 0, 20 * M)), NORTH, "the L's northern arm")
	assert_eq(_land.parcel_at(Vector3i(-1, 0, 0)), LandSystem.UNPARCELLED, "one millimetre west is outside")
	assert_eq(_land.parcel_at(Vector3i(6 * M, 0, 100 * M)), LandSystem.UNPARCELLED, "far away is unparcelled")


func test_vertical_extent_is_half_open() -> void:
	_build()
	assert_eq(_land.parcel_at(Vector3i(6 * M, -3000, 6 * M)), PLOT, "floor is inside")
	assert_eq(_land.parcel_at(Vector3i(6 * M, -3001, 6 * M)), LandSystem.UNPARCELLED, "below the floor is not")
	assert_eq(_land.parcel_at(Vector3i(6 * M, 8999, 6 * M)), PLOT, "just under the ceiling is inside")
	assert_eq(_land.parcel_at(Vector3i(6 * M, 9000, 6 * M)), LandSystem.UNPARCELLED, "the ceiling is not")


# ---------------------------------------------------------------- rights

func test_rights_follow_owner_other_and_unowned_tables() -> void:
	_build()
	var player: int = _player()
	var stranger: int = _actors.spawn(&"arcade", 0)
	var plot_centre := Vector3i(6 * M, 0, 6 * M)
	assert_eq(_rights(plot_centre, player), "001110", "unowned plot in the ghetto: enter, carry, loot; not safe")
	assert_true(_do(LandSystem.COMMAND_TRANSFER, {"parcel": "starter_plot", "owner": "player"}), "transfer to player")
	assert_eq(_rights(plot_centre, player), "111111", "owner has every right, safe included")
	assert_eq(_rights(plot_centre, stranger), "001100", "another actor: enter and carry only")
	assert_eq(_rights(plot_centre, 999), "001100", "an actor that does not exist owns nothing")
	assert_eq(_rights(Vector3i(18 * M, 0, 6 * M), player), "001100", "the neighbour's parcel: other")
	assert_eq(_rights(Vector3i(500 * M, 0, 500 * M), player), "111110", "unparcelled badlands: free, but nowhere is safe")


func test_digging_under_the_neighbour_is_trespass() -> void:
	_build()
	var player: int = _player()
	_do(LandSystem.COMMAND_TRANSFER, {"parcel": "starter_plot", "owner": "player"})
	var under_own: Vector3i = Vector3i(11 * M, -2 * M, 6 * M)
	var under_east: Vector3i = Vector3i(13 * M, -2 * M, 6 * M)
	var deep_under_east: Vector3i = Vector3i(13 * M, -4 * M, 6 * M)
	assert_eq(_land.rights_at(under_own, player)[&"dig"], true, "may dig under own plot")
	assert_eq(_land.rights_at(under_east, player)[&"dig"], false, "may not dig under the neighbour")
	assert_eq(_land.rights_at(deep_under_east, player)[&"dig"], true, "below the neighbour's floor is unparcelled badlands")


func test_require_emits_one_violation_per_refusal_and_nothing_on_success() -> void:
	_build()
	var player: int = _player()
	var events: EventBus = _events_of()
	var count: Array[int] = [0]
	var seen: Array[Dictionary] = []
	var on_violation: Callable = func(payload: Dictionary) -> void:
		count[0] += 1
		seen.append(payload)
	assert_eq(events.subscribe(LandSystem.EVENT_VIOLATION, on_violation), OK, "subscribe")
	var east_centre := Vector3i(18 * M, 0, 6 * M)
	assert_true(_land.require(east_centre, player, &"enter"), "enter is allowed")
	assert_eq(count[0], 0, "no event on success")
	var before: String = _sim.state_hash()
	assert_false(_land.require(east_centre, player, &"build"), "build is refused")
	assert_eq(count[0], 1, "one event")
	assert_eq(seen[0]["actor"], player, "event names the actor")
	assert_eq(seen[0]["parcel"], EAST, "event names the parcel")
	assert_eq(seen[0]["right"], &"build", "event names the right")
	assert_eq(seen[0]["x"], 18 * M, "event carries the position")
	assert_eq(_land.violation_count(), 1, "counted")
	assert_ne(_sim.state_hash(), before, "the violation count is state")


func _events_of() -> EventBus:
	# The bus is not a system; reach it the way the assembly does, through combat.
	return SimAssembly.combat_of(_sim).events()


# ---------------------------------------------------------------- commands

func test_transfer_and_identify_validate_their_payloads() -> void:
	_build()
	var player: int = _actors.spawn(&"arcade", 0)
	assert_false(_do(LandSystem.COMMAND_TRANSFER, {"parcel": "nowhere", "owner": "player"}), "unknown parcel")
	assert_false(_do(LandSystem.COMMAND_TRANSFER, {"parcel": "starter_plot", "owner": "Bad Owner"}), "owner pattern")
	assert_false(_do(LandSystem.COMMAND_TRANSFER, {"parcel": "starter_plot"}), "missing owner")
	assert_false(_do(LandSystem.COMMAND_TRANSFER, {"parcel": "starter_plot", "owner": "player", "x": 1}), "extra key")
	assert_false(_do(LandSystem.COMMAND_TRANSFER, {"parcel": 1, "owner": "player"}), "parcel type")
	assert_true(_do(LandSystem.COMMAND_TRANSFER, {"parcel": "neighbour_east", "owner": ""}), "transfer to nobody")
	assert_eq(_land.owner_of(EAST), &"", "east is now unowned")
	assert_false(_do(LandSystem.COMMAND_IDENTIFY, {"actor": 42, "owner": "player"}), "actor must exist")
	assert_false(_do(LandSystem.COMMAND_IDENTIFY, {"actor": "1", "owner": "player"}), "actor type")
	assert_false(_do(LandSystem.COMMAND_IDENTIFY, {"actor": player, "owner": "x y"}), "owner pattern")
	assert_true(_do(LandSystem.COMMAND_IDENTIFY, {"actor": player, "owner": "faction.scrapline"}), "identify")
	assert_eq(_land.owner_tag_of_actor(player), &"faction.scrapline", "mapped")
	assert_true(_do(LandSystem.COMMAND_IDENTIFY, {"actor": player, "owner": ""}), "clear")
	assert_eq(_land.owner_tag_of_actor(player), &"", "cleared")


# ---------------------------------------------------------------- add_parcel

func test_add_parcel_rejects_bad_polygons_and_overlaps() -> void:
	_build()
	var sq: Array = _rect(100 * M, 100 * M, 10 * M, 10 * M)
	assert_eq(_land.add_parcel(&"starter_plot", &"starter_ghetto", &"", sq, 0, M), ERR_ALREADY_EXISTS, "duplicate id")
	assert_eq(_land.add_parcel(&"a", &"nowhere", &"", sq, 0, M), ERR_INVALID_PARAMETER, "unknown district")
	assert_eq(_land.add_parcel(&"a", &"starter_ghetto", &"Bad", sq, 0, M), ERR_INVALID_PARAMETER, "owner pattern")
	assert_eq(_land.add_parcel(&"a", &"starter_ghetto", &"", sq, M, 0), ERR_INVALID_PARAMETER, "empty vertical extent")
	assert_eq(_land.add_parcel(&"a", &"starter_ghetto", &"", [[0, 0], [M, 0]], 0, M), ERR_INVALID_PARAMETER, "two vertices")
	assert_eq(_land.add_parcel(&"a", &"starter_ghetto", &"", [[0, 0], [M, 0], [M, 0], [0, M]], 0, M), ERR_INVALID_PARAMETER, "repeated vertex")
	assert_eq(_land.add_parcel(&"a", &"starter_ghetto", &"", [[0, 0], [500, 0], [500, 500], [0, 500]], 0, M), ERR_INVALID_PARAMETER, "under one square metre")
	assert_eq(_land.add_parcel(&"a", &"starter_ghetto", &"", [[0, 0], [10 * M, 10 * M], [10 * M, 0], [0, 10 * M]], 0, M), ERR_INVALID_PARAMETER, "self-intersecting bow tie")
	assert_eq(_land.add_parcel(&"a", &"starter_ghetto", &"", [[0, 0], [10 * M, 0], [5 * M, 0], [5 * M, 5 * M]], 0, M), ERR_INVALID_PARAMETER, "folded-back edge")
	assert_eq(_land.add_parcel(&"a", &"starter_ghetto", &"", sq, 0, M), OK, "a valid square")
	assert_eq(_land.add_parcel(&"b", &"starter_ghetto", &"", sq, 0, M), ERR_ALREADY_EXISTS, "identical footprint overlaps")
	assert_eq(_land.add_parcel(&"b", &"starter_ghetto", &"", _rect(105 * M, 105 * M, 10 * M, 10 * M), 0, M), ERR_ALREADY_EXISTS, "partial overlap")
	assert_eq(_land.add_parcel(&"b", &"starter_ghetto", &"", _rect(102 * M, 102 * M, 2 * M, 2 * M), 0, M), ERR_ALREADY_EXISTS, "contained")
	assert_eq(_land.add_parcel(&"b", &"starter_ghetto", &"", _rect(90 * M, 90 * M, 40 * M, 40 * M), 0, M), ERR_ALREADY_EXISTS, "containing")
	assert_eq(_land.add_parcel(&"b", &"starter_ghetto", &"", sq, M, 2 * M), OK, "same footprint stacked above is fine")
	assert_eq(_land.add_parcel(&"c", &"starter_ghetto", &"", _rect(110 * M, 100 * M, 10 * M, 10 * M), 0, M), OK, "sharing an edge is fine")
	assert_eq(_land.add_parcel(&"d", &"starter_ghetto", &"", _rect(110 * M, 110 * M, 10 * M, 10 * M), 0, M), OK, "sharing a corner is fine")
	assert_eq(_land.add_parcel(&"e", &"starter_ghetto", &"", [[0, 0], [10 * M, 0], [0, 10 * M]], 0, M), ERR_ALREADY_EXISTS, "overlaps the starter plot")
	assert_eq(_land.parcel_ids().size(), 9, "the five from content and the four added here")


func test_diagonal_split_assigns_the_diagonal_to_one_triangle() -> void:
	_build()
	var lower: Array = [[100 * M, 100 * M], [110 * M, 100 * M], [110 * M, 110 * M]]
	var upper: Array = [[100 * M, 100 * M], [110 * M, 110 * M], [100 * M, 110 * M]]
	assert_eq(_land.add_parcel(&"lower", &"starter_ghetto", &"", lower, 0, M), OK, "lower triangle")
	assert_eq(_land.add_parcel(&"upper", &"starter_ghetto", &"", upper, 0, M), OK, "upper triangle shares the diagonal")
	var on_diagonal: StringName = _land.parcel_at(Vector3i(105 * M, 0, 105 * M))
	assert_true(on_diagonal == &"lower" or on_diagonal == &"upper", "a point on the diagonal belongs to one of them")
	assert_eq(_land.parcel_at(Vector3i(107 * M, 0, 102 * M)), &"lower", "below the diagonal")
	assert_eq(_land.parcel_at(Vector3i(102 * M, 0, 107 * M)), &"upper", "above the diagonal")


# ---------------------------------------------------------------- properties

func test_property_rights_at_is_total() -> void:
	_build()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_TOTALITY
	var player: int = _player()
	_do(LandSystem.COMMAND_TRANSFER, {"parcel": "starter_plot", "owner": "player"})
	var incomplete: int = 0
	for _i: int in PROPERTY_CASES:
		var pos := Vector3i(rng.randi_range(-40 * M, 40 * M), rng.randi_range(-10 * M, 20 * M), rng.randi_range(-40 * M, 40 * M))
		var actor: int = [player, 0, -1, 7, 1 << 40][rng.randi_range(0, 4)]
		var r: Dictionary = _land.rights_at(pos, actor)
		if r.size() != LandSystem.RIGHTS.size():
			incomplete += 1
			continue
		for right: StringName in LandSystem.RIGHTS:
			if typeof(r.get(right)) != TYPE_BOOL:
				incomplete += 1
	assert_eq(incomplete, 0, "every position and actor resolves to five booleans")


## Generated rectangle sets checked against a brute-force oracle: add_parcel accepts a
## rectangle exactly when its volume misses every accepted one, and every point resolves
## to exactly the rectangle the oracle says (or to none).
func test_property_parcels_never_overlap_and_points_resolve_uniquely() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_SETS
	var add_mismatches: int = 0
	var lookup_mismatches: int = 0
	var adds: int = 0
	var queries: int = 0
	var sets: int = 0
	while adds < PROPERTY_CASES or queries < PROPERTY_CASES:
		sets += 1
		_build()
		var accepted: Array = []  # [x0, z0, x1, z1, floor, ceiling, id]
		for i: int in 60:
			var x0: int = rng.randi_range(-20, 20) * 5 * M
			var z0: int = rng.randi_range(-20, 20) * 5 * M
			var w: int = rng.randi_range(1, 4) * 5 * M
			var h: int = rng.randi_range(1, 4) * 5 * M
			var floor_y: int = rng.randi_range(-2, 2) * 5 * M
			var ceiling_y: int = floor_y + rng.randi_range(1, 3) * 5 * M
			var rect: Array = [x0, z0, x0 + w, z0 + h, floor_y, ceiling_y, StringName("gen_%d" % i)]
			var oracle_free: bool = true
			for other: Array in accepted:
				if _rects_overlap(rect, other):
					oracle_free = false
					break
			# content parcels reach [0, 49 000] by [0, 55 000] once the fixer's office and
			# the Cold Storage lot are in: keep generated ones clear of all of them
			if x0 < 60 * M and x0 + w > -5 * M and z0 < 60 * M and z0 + h > -5 * M:
				continue
			var footprint: Array = _rect(x0, z0, w, h)
			var gen_id: StringName = rect[6]
			var err: Error = _land.add_parcel(gen_id, &"badlands_outskirts", &"", footprint, floor_y, ceiling_y)
			adds += 1
			if (err == OK) != oracle_free:
				add_mismatches += 1
			if err == OK:
				accepted.append(rect)
		for _q: int in 100:
			var p := Vector3i(rng.randi_range(-110 * M, 110 * M), rng.randi_range(-12 * M, 17 * M), rng.randi_range(-110 * M, 110 * M))
			if p.x < 60 * M and p.x > -5 * M and p.z < 60 * M and p.z > -5 * M:
				continue
			queries += 1
			var expected: StringName = LandSystem.UNPARCELLED
			var hits: int = 0
			for r: Array in accepted:
				if p.x >= r[0] and p.x < r[2] and p.z >= r[1] and p.z < r[3] and p.y >= r[4] and p.y < r[5]:
					hits += 1
					expected = r[6]
			if hits > 1 or _land.parcel_at(p) != expected:
				lookup_mismatches += 1
	assert_eq(add_mismatches, 0, "add_parcel agrees with the oracle over %d attempts in %d sets" % [adds, sets])
	assert_eq(lookup_mismatches, 0, "parcel_at agrees with the oracle over %d queries" % queries)


static func _rects_overlap(a: Array, b: Array) -> bool:
	return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3] and a[4] < b[5] and b[4] < a[5]


static func _rect(x: int, z: int, w: int, h: int) -> Array:
	return [[x, z], [x + w, z], [x + w, z + h], [x, z + h]]


# ---------------------------------------------------------------- round trip

func test_snapshot_restore_round_trip_including_generated_parcels() -> void:
	_build()
	var player: int = _player()
	_do(LandSystem.COMMAND_TRANSFER, {"parcel": "starter_plot", "owner": "player"})
	assert_eq(_land.add_parcel(&"tri", &"badlands_outskirts", &"faction.dustrunners", [[100 * M, 100 * M], [110 * M, 100 * M], [100 * M, 110 * M]], -M, 5 * M), OK, "generated parcel")
	_land.require(Vector3i(18 * M, 0, 6 * M), player, &"build")
	var snap: Dictionary = _land.snapshot()
	var db := ContentDb.new()
	ContentLoader.load_all(db)
	var other: SimRoot = SimAssembly.build(SEED, db)
	var restored: LandSystem = SimAssembly.land_of(other)
	assert_eq(restored.restore(snap), OK, "restore")
	assert_eq(StateHash.of(restored.snapshot()), StateHash.of(snap), "identical state")
	assert_eq(restored.parcel_at(Vector3i(102 * M, 0, 102 * M)), &"tri", "index rebuilt")
	assert_eq(restored.owner_tag_of_actor(player), &"player", "actor mapping")
	var bad: Dictionary = snap.duplicate(true)
	var parcels: Dictionary = bad["parcels"]
	var tri: Dictionary = parcels[&"tri"]
	tri["footprint"] = [[0, 0], [1, 0]]
	var fresh: LandSystem = SimAssembly.land_of(SimAssembly.build(SEED, db))
	var before: String = StateHash.of(fresh.snapshot())
	assert_eq(fresh.restore(bad), ERR_INVALID_DATA, "bad footprint rejected")
	assert_eq(StateHash.of(fresh.snapshot()), before, "a rejected restore changes nothing")


## M7 spec claim 10: a lot moves with the building raised on it. Footprint and height band
## move together, the old place is nobody's any more, the new one is the lot's, and a
## move onto another parcel, off the world or of a lot that is not there changes nothing.
func test_a_parcel_moves_whole_and_never_onto_another() -> void:
	_build()
	var before: Dictionary = _land.parcel(&"cold_storage_lot")
	var inside: Vector3i = Vector3i(42 * M, 0, 45 * M)
	assert_eq(_land.parcel_at(inside), &"cold_storage_lot", "the lot is where content put it")
	var offset: Vector3i = Vector3i(2_000 * M, -13 * M, -3_000 * M)
	assert_eq(_land.move_parcel(&"cold_storage_lot", offset), OK, "moved")
	assert_eq(_land.parcel_at(inside), &"", "the old place is nobody's now")
	assert_eq(_land.parcel_at(inside + offset), &"cold_storage_lot", "and the new one is the lot")
	var after: Dictionary = _land.parcel(&"cold_storage_lot")
	assert_eq(after["floor_y"], before["floor_y"] + offset.y, "the floor moved with it")
	assert_eq(after["ceiling_y"], before["ceiling_y"] + offset.y, "and the ceiling")
	var snap: Dictionary = _land.snapshot()
	assert_eq(_land.move_parcel(&"cold_storage_lot", Vector3i(-2_000 * M + 6 * M - 42 * M, 13 * M, 3_000 * M + 30 * M - 45 * M)), ERR_ALREADY_EXISTS,
		"not onto the fixer's office")
	assert_eq(_land.move_parcel(&"cold_storage_lot", Vector3i(LandSystem.MAX_COORD, 0, 0)), ERR_INVALID_PARAMETER, "not off the world")
	assert_eq(_land.move_parcel(&"nowhere", offset), ERR_DOES_NOT_EXIST, "not a lot that is not there")
	assert_eq(_land.snapshot(), snap, "and none of that moved anything")
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.land_of(other).restore(snap), OK, "a save with the lot moved loads")
	assert_eq(SimAssembly.land_of(other).parcel_at(inside + offset), &"cold_storage_lot", "with the lot where it was moved to")
