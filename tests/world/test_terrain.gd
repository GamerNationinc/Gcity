extends GcityTest

## M7 spec claim 7: terrain is a consumer of the route graph.
##
## The claim the milestone actually rests on is the last one here — **every edge of the
## graph is traversable in the terrain it produced**. The generator is not allowed to
## carve a corridor and then block it, and the way that is made true is arithmetic
## rather than a search: roads follow only the shallow base field, so a road's grade is
## the base field's swing over the shortest an edge can be, and that is a constant.
##
## Everything above it is there to stop that property being true for a boring reason. A
## world of flat ground would pass it and mean nothing, so the land has to actually
## rise and fall; and if nothing ever needed a bridge, "the generator may not block a
## corridor it made" would never have been tested against a corridor worth blocking.

const SEED: int = 20261250
const SEED_PROPERTY: int = 20261251
const PROPERTY_CASES: int = 10_000
const VARIETY_SEEDS: int = 60

var _sim: SimRoot
var _db: ContentDb
var _routes: RouteGraph
var _terrain: Terrain


func _setup(world: int = SEED) -> void:
	_db = ContentDb.new()
	assert_eq(ContentLoader.load_all(_db), OK, "content loads")
	_sim = SimAssembly.build(world, _db)
	_routes = SimAssembly.routes_of(_sim)
	_terrain = SimAssembly.terrain_of(_sim)


func test_the_ground_is_a_function_of_the_seed_and_the_place() -> void:
	_setup()
	var elsewhere: Terrain = _bare(SEED)
	var other: Terrain = _bare(SEED + 1)
	var differs: bool = false
	for i: int in 24:
		var x: int = (i - 12) * 1_700_000
		var z: int = (i * 7 % 24 - 12) * 1_300_000
		assert_eq(_terrain.ground_mm(x, z), _terrain.ground_mm(x, z), "asking twice gives one answer")
		assert_eq(_terrain.base_mm(x, z), elsewhere.base_mm(x, z), "and the same seed makes the same land")
		if other.base_mm(x, z) != _terrain.base_mm(x, z):
			differs = true
	assert_true(differs, "and a different seed makes different land")


## A world with no sim around it: the graph and the land it produced, nothing else.
func _bare(world: int) -> Terrain:
	var routes: RouteGraph = RouteGraph.new()
	routes.set_kits(SettlementKits.prepared(_db))
	routes.generate(world)
	var terrain: Terrain = Terrain.new(routes)
	terrain.generate(world)
	return terrain


## A world of flat ground would satisfy every other claim here and mean nothing.
func test_the_land_rises_and_falls() -> void:
	_setup()
	var lowest: int = RouteGraph.WORLD_RADIUS_MM
	var highest: int = -RouteGraph.WORLD_RADIUS_MM
	var relief_seen: int = 0
	for i: int in 40:
		for j: int in 40:
			var x: int = (i - 20) * 700_000
			var z: int = (j - 20) * 700_000
			if _terrain.town_under(x, z) != EntityIds.NONE:
				continue
			var ground: int = _terrain.ground_mm(x, z)
			lowest = mini(lowest, ground)
			highest = maxi(highest, ground)
			relief_seen = maxi(relief_seen, absi(_terrain.relief_mm(x, z)))
			assert_true(absi(_terrain.base_mm(x, z)) <= Terrain.BASE_AMPLITUDE_MM,
				"the lie of the land stays shallow at %d,%d" % [x, z])
			assert_true(absi(_terrain.relief_mm(x, z)) <= Terrain.RELIEF_AMPLITUDE_MM,
				"and the relief stays inside its own bounds")
	assert_true(highest - lowest > Terrain.RELIEF_AMPLITUDE_MM,
		"the world is not a table top (%d mm between lowest and highest)" % (highest - lowest))
	assert_true(relief_seen > Terrain.RELIEF_AMPLITUDE_MM / 2, "and there is real relief in it")


## GDScript divides toward zero, which would make the lattice cell left of the origin
## the same as the one right of it and crease the whole world along two lines.
func test_there_is_no_seam_through_the_origin() -> void:
	_setup()
	var step: int = Terrain.BASE_LATTICE_MM / 64
	var worst: int = 0
	for i: int in 32:
		var x: int = (i - 16) * step
		worst = maxi(worst, absi(_terrain.base_mm(x + step, 0) - _terrain.base_mm(x, 0)))
	var smooth: int = Terrain.BASE_AMPLITUDE_MM / 4
	assert_true(worst < smooth, "the land does not jump anywhere near the origin (%d mm)" % worst)
	assert_eq(Terrain._floor_div(-1, 8), -1, "the cell left of the origin is not the cell right of it")
	assert_eq(Terrain._floor_div(-8, 8), -1, "and a cell boundary belongs to the cell above it")
	assert_eq(Terrain._floor_div(-9, 8), -2, "and the one before that is the one before that")
	assert_eq(Terrain._floor_div(7, 8), 0, "positives are unchanged")


## A settlement stands on ground someone levelled. That is both how towns are and what
## keeps a town's sixty-metre streets from being the steepest roads in the world.
func test_a_town_stands_on_level_ground() -> void:
	_setup()
	assert_true(_routes.town_count() > 0, "this world has towns")
	for anchor: int in _routes.town_ids():
		var at: Vector2i = _routes.position_of(anchor)
		var level: int = _terrain.ground_mm(at.x, at.y)
		for node: int in _routes.node_ids():
			if _routes.node_town(node) != anchor:
				continue
			var where: Vector2i = _routes.position_of(node)
			assert_eq(_terrain.ground_mm(where.x, where.y), level, "street %d is on the town's own level" % node)
			assert_eq(_terrain.node_height_mm(node), level, "and the road through it is too")
		assert_eq(_terrain.town_under(at.x, at.y), anchor, "the town covers its own ground")
	var far: int = RouteGraph.WORLD_RADIUS_MM
	assert_eq(_terrain.town_under(far, far), EntityIds.NONE, "and nothing covers the far corner")


func test_no_road_in_the_world_is_too_steep_to_walk() -> void:
	_setup()
	assert_eq(Terrain.MAX_GRADE_PERMILLE, 2 * Terrain.BASE_AMPLITUDE_MM * 1000 / RouteGraph.MIN_SPACING_MM,
		"the limit is derived from the land and the spacing, not chosen")
	var steepest: int = 0
	var flat: int = 0
	for edge: int in _routes.edge_ids():
		var grade: int = _terrain.grade_permille(edge)
		steepest = maxi(steepest, grade)
		if grade == 0:
			flat += 1
		assert_true(grade <= Terrain.MAX_GRADE_PERMILLE, "road %d climbs %d per thousand" % [edge, grade])
	assert_true(steepest > 0, "some roads climb (%d per thousand at worst)" % steepest)
	assert_true(flat > 0, "and a town's streets are level (%d of them)" % flat)
	assert_eq(_terrain.grade_permille(99999), 0, "and a road that is not one climbs nothing")


## Where the road and the land disagree, something gets built. All three kinds turn up
## in a world, or the claim would be about a case that never happens.
func test_where_the_road_and_the_land_disagree_something_gets_built() -> void:
	_setup()
	var kinds: Dictionary = {}
	var routes: RouteGraph = RouteGraph.new()
	routes.set_kits(SettlementKits.prepared(_db))
	var terrain: Terrain = Terrain.new(routes)
	for i: int in VARIETY_SEEDS:
		routes.generate(SEED + i)
		terrain.generate(SEED + i)
		for edge: int in routes.edge_ids():
			for carve: Dictionary in terrain.carves_on(edge):
				var kind: StringName = carve["kind"]
				kinds[kind] = true
				var from: int = carve["from"]
				var to: int = carve["to"]
				var depth: int = carve["depth"]
				assert_true(to > from, "a %s spans some of the road" % kind)
				assert_true(depth > Terrain.ON_GROUND_MM, "and is there because the land is %d mm off" % depth)
	assert_true(kinds.has(Terrain.CARVE_BRIDGE), "roads cross ravines on bridges")
	assert_true(kinds.has(Terrain.CARVE_CUT), "and go through rises in cuttings")
	assert_true(kinds.has(Terrain.CARVE_TUNNEL), "and through the deep ones in tunnels")
	assert_eq(_terrain.carves_on(99999), [] as Array[Dictionary], "and a road that is not one needs nothing built")


func test_the_snapshot_is_the_seed_and_the_ground_it_made() -> void:
	_setup()
	var saved: Dictionary = _terrain.snapshot()
	assert_eq(saved["seed"], SEED, "the ground is its seed")
	assert_eq(saved["ground"], _terrain.terrain_hash(), "and the land that seed made")
	assert_eq(_terrain.restore(saved), OK, "restored")
	assert_eq(_terrain.restore({}), ERR_INVALID_DATA, "empty")
	assert_eq(_terrain.restore({"seed": SEED, "ground": "not the ground that seed makes"}), ERR_INVALID_DATA,
		"a save from a different generator is refused rather than loaded")
	assert_eq(_terrain.snapshot()["seed"], SEED, "and the refusal left the world alone")


## The property the G7 bar names: the generator may not make a corridor it then blocks.
func test_property_every_edge_is_traversable_in_the_terrain_it_produced() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var routes: RouteGraph = RouteGraph.new()
	routes.set_kits(SettlementKits.prepared(db))
	var terrain: Terrain = Terrain.new(routes)
	var blocked: int = 0
	var steep: int = 0
	var carved: int = 0
	var edges: int = 0
	for i: int in PROPERTY_CASES:
		var world: int = SEED_PROPERTY + i
		routes.generate(world)
		terrain.generate(world)
		# one road per world rather than all of them: a world has ninety and the claim
		# is about the generator, so ten thousand worlds beat ninety thousand roads in
		# three hundred
		var ids: Array[int] = routes.edge_ids()
		var edge: int = ids[world % ids.size()]
		edges += 1
		if terrain.grade_permille(edge) > Terrain.MAX_GRADE_PERMILLE:
			steep += 1
			if steep <= 3:
				fail("seed %d made road %d too steep to walk" % [world, edge])
		if not terrain.is_traversable(edge):
			blocked += 1
			if blocked <= 3:
				fail("seed %d made a road it then blocked" % world)
		if not terrain.carves_on(edge).is_empty():
			carved += 1
	assert_eq(steep, 0, "no world built a road too steep to walk (%d roads)" % edges)
	assert_eq(blocked, 0, "and none built one it then blocked")
	assert_true(carved > 0, "and some of them needed building (%d)" % carved)


## A bound site's track (M7 spec claim 9) is the one road in the world shorter than
## [RouteGraph.MIN_SPACING_MM], which is the premise [Terrain.MAX_GRADE_PERMILLE] is
## derived from. It holds anyway, because the base field is too long and shallow to
## swing far over sixty metres — and this is the property that says so rather than the
## argument. One slot per world, for the same reason as the property above.
func test_property_a_bound_sites_track_is_traversable_too() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var routes: RouteGraph = RouteGraph.new()
	routes.set_kits(SettlementKits.prepared(db))
	var terrain: Terrain = Terrain.new(routes)
	var blocked: int = 0
	var steepest: int = 0
	for i: int in PROPERTY_CASES:
		var world: int = SEED_PROPERTY + i
		routes.generate(world)
		terrain.generate(world)
		var slots: Array[int] = routes.slot_ids()
		var slot: int = slots[world % slots.size()]
		var site: int = routes.stitch_slot(slot)
		var track: int = routes.edge_between(site, routes.slot_node(slot))
		steepest = maxi(steepest, terrain.grade_permille(track))
		if not terrain.is_traversable(track):
			blocked += 1
			if blocked <= 3:
				fail("seed %d: the track to slot %d cannot be walked" % [world, slot])
	assert_eq(blocked, 0, "every bound site can be reached on foot (%d tracks)" % PROPERTY_CASES)
	assert_true(steepest <= Terrain.MAX_GRADE_PERMILLE / 2, "and the steepest is nowhere near the limit (%d ‰ of %d)" % [
		steepest, Terrain.MAX_GRADE_PERMILLE])
