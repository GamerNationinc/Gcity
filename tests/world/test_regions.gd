extends GcityTest

## M7 spec claim 13 and the approved regions design note: one rule for both region
## types. The city is the authored north, with the ground it always had; the wilds are
## everywhere else, their ground 1 m voxel cells from the terrain with every road cut in.

const SEED: int = 20261290
const SEED_PROPERTY: int = 20261291
const PROPERTY_CASES: int = 10_000
## How much of one road each world's property case walks, a metre at a time.
const STRETCH_M: int = 32
const M: int = 1000

var _db: ContentDb
var _sim: SimRoot
var _routes: RouteGraph
var _terrain: Terrain
var _regions: Regions


func _setup(world: int = SEED) -> void:
	_db = ContentDb.new()
	assert_eq(ContentLoader.load_all(_db), OK, "content loads")
	_sim = SimAssembly.build(world, _db)
	assert_true(_sim != null, "assembly")
	_routes = SimAssembly.routes_of(_sim)
	_terrain = SimAssembly.terrain_of(_sim)
	_regions = SimAssembly.regions_of(_sim)


func test_the_city_is_the_north_and_the_wilds_are_everywhere_else() -> void:
	_setup()
	assert_eq(_regions.region_ids(), [&"city", &"wilds"] as Array[StringName], "one authored region and the wild")
	assert_eq(_regions.region_at(0, 1).id(), &"city", "just inside the gate is the city")
	assert_eq(_regions.region_at(0, -1).id(), &"wilds", "just outside it the wilds")
	assert_eq(_regions.region_at(500 * M, 500 * M).id(), &"city", "the outskirts every earlier milestone played in are the city")
	for node: int in _routes.node_ids():
		if node == 1:
			continue
		var at: Vector2i = _routes.position_of(node)
		assert_eq(_regions.region_at(at.x, at.y).id(), &"wilds", "node %d is out in the wilds" % node)
	var gates: Array[Dictionary] = _regions.gates_of(&"city")
	assert_eq(gates.size(), 1, "the city has one gate")
	assert_eq(gates[0]["node"], 1, "and it is the graph's gate")
	assert_true(_regions.crosses_edge(Vector3i(5 * M, 0, 500), Vector3i(5 * M, 0, -500)), "stepping south out of the city crosses its edge")
	assert_false(_regions.crosses_edge(Vector3i(5 * M, 0, 500), Vector3i(6 * M, 0, 700)), "walking about inside it does not")


## The city's ground is exactly the ground the sim had before regions: standing at or
## below the ground level, and nothing solid that was not built.
func test_the_city_keeps_the_ground_it_always_had() -> void:
	_setup()
	for cell: Vector3i in [Vector3i(3, 0, 8), Vector3i(40, -1, 40), Vector3i(500, 0, 500), Vector3i(-7, 3, 2)]:
		assert_eq(_regions.stands_on_ground(cell), cell.y <= BuildSystem.GROUND_CELL_Y, "cell %s" % cell)
		assert_false(_regions.is_solid(cell), "nothing under the city is rock: %s" % cell)
	assert_eq(_regions.step_levels(Vector3i(3, 0, 8)), 0, "and nobody walks up a slope in a city of flat streets")
	assert_eq(_regions.standing_cell_y(3 * M, 8 * M), BuildSystem.GROUND_CELL_Y, "everyone stands on the ground level")


func test_outside_the_gate_the_ground_is_the_citys_level() -> void:
	_setup()
	for x: int in [-40, 0, 40]:
		var cell: Vector3i = Vector3i(x, 0, -40)
		assert_eq(_regions.region_of_cell(cell).id(), &"wilds", "the apron is the wilds")
		assert_true(_regions.stands_on_ground(cell), "and it carries you at the city's level (%d, -40)" % x)
		assert_true(_regions.is_solid(cell - Vector3i(0, 1, 0)), "on solid ground")
		assert_false(_regions.stands_on_ground(cell + Vector3i(0, 1, 0)), "not a level above it")
	assert_eq(_regions.step_levels(Vector3i(0, 0, -40)), 1, "and out here a step can climb")


## The ground follows the land: solid below the terrain's height, air above it.
func test_the_wild_ground_is_the_terrain() -> void:
	_setup()
	var checked: int = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	while checked < 200:
		var x: int = rng.randi_range(-20_000, 20_000) * M
		var z: int = rng.randi_range(-20_000, -1_000) * M
		var cx: int = Terrain._floor_div(x, M)
		var cz: int = Terrain._floor_div(z, M)
		var centre_x: int = cx * M + M / 2
		var centre_z: int = cz * M + M / 2
		if _regions.standing_cell_y(x, z) != Terrain._floor_div(_terrain.ground_mm(centre_x, centre_z) + M / 2, M):
			continue  # a road runs here; roads have their own test
		var surface: int = _regions.standing_cell_y(x, z)
		assert_true(_regions.is_solid(Vector3i(cx, surface - 1, cz)), "solid just below the surface at %d,%d" % [cx, cz])
		assert_false(_regions.is_solid(Vector3i(cx, surface, cz)), "and air at it")
		assert_true(_regions.stands_on_ground(Vector3i(cx, surface, cz)), "so it carries you there")
		checked += 1


## Claim 7 in the sim's own geometry, over ten thousand worlds: walking any road a
## metre at a time, the surface never rises or falls more than the one level a step can
## climb, every surface cell carries you, and there is headroom above it. One stretch of
## one road per world: building every chunk of every road would take hours, and the
## claim is about the generator, not about any one road.
func test_property_every_road_can_be_walked_in_the_wild_ground() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var routes := RouteGraph.new()
	routes.set_kits(SettlementKits.prepared(db))
	var terrain := Terrain.new(routes)
	var regions := Regions.new(routes, terrain)
	var steep: int = 0
	var unstandable: int = 0
	var low: int = 0
	var walked: int = 0
	var climbed: int = 0
	for i: int in PROPERTY_CASES:
		var world: int = SEED_PROPERTY + i
		routes.generate(world)
		terrain.generate(world)
		assert_eq(regions.build(db), OK, "regions for seed %d" % world) if i == 0 else regions.build(db)
		var ids: Array[int] = routes.edge_ids()
		var edge: int = ids[world % ids.size()]
		var rec: Dictionary = routes.edge(edge)
		var length: int = rec["length"]
		var start: int = (length - STRETCH_M * M) * (world % 97) / 97 if length > STRETCH_M * M else 0
		var previous: int = -1_000_000
		for step: int in STRETCH_M:
			var along: int = mini(start + step * M, length)
			var at: Vector2i = terrain.road_at(edge, along)
			if regions.region_at(at.x, at.y).id() != &"wilds":
				continue
			var y: int = regions.standing_cell_y(at.x, at.y)
			var cell: Vector3i = Vector3i(Terrain._floor_div(at.x, M), y, Terrain._floor_div(at.y, M))
			walked += 1
			if not regions.stands_on_ground(cell):
				unstandable += 1
				if unstandable <= 3:
					fail("seed %d edge %d at %d mm: the road surface does not carry you" % [world, edge, along])
			for up: int in range(1, 3):
				if regions.is_solid(cell + Vector3i(0, up, 0)):
					low += 1
					if low <= 3:
						fail("seed %d edge %d at %d mm: no headroom" % [world, edge, along])
					break
			if previous != -1_000_000 and absi(y - previous) > 1:
				steep += 1
				if steep <= 3:
					fail("seed %d edge %d at %d mm: the surface jumps %d levels in a metre" % [world, edge, along, y - previous])
			if previous != -1_000_000 and y != previous:
				climbed += 1
			previous = y
	assert_eq(unstandable, 0, "every metre of road carries you (%d metres over %d worlds)" % [walked, PROPERTY_CASES])
	assert_eq(low, 0, "with headroom above it")
	assert_eq(steep, 0, "and no step is more than a level")
	assert_true(climbed > 0, "and the roads do go up and down (%d level changes)" % climbed)


## The ground is derived, not stored: binding a site cuts its track into the ground the
## moment it exists, because the cache is thrown away when the graph changes.
func test_a_bound_sites_track_is_cut_in_as_soon_as_it_exists() -> void:
	_setup()
	# a slot off a point of interest: a town's own streets would cover some of its track
	var slot: int = EntityIds.NONE
	for candidate: int in _routes.slot_ids():
		if _routes.kind_of(_routes.slot_node(candidate)) == RouteGraph.KIND_POI:
			slot = candidate
			break
	assert_true(slot != EntityIds.NONE, "the world has a point of interest with a slot")
	var node: int = _routes.slot_node(slot)
	# near the site end, where only the track will run: near its node every road that
	# leaves the node overlaps the others
	var site: int = _routes.stitch_slot(slot)
	var track: int = _routes.edge_between(node, site)
	var rec: Dictionary = _routes.edge(track)
	var length: int = rec["length"]
	var along: int = length - 5 * M if rec["b"] == site else 5 * M
	var at: Vector2i = _terrain.road_at(track, along)
	_routes.unstitch_all()
	var ground: int = Terrain._floor_div(_terrain.ground_mm(Terrain._floor_div(at.x, M) * M + M / 2, Terrain._floor_div(at.y, M) * M + M / 2) + M / 2, M)
	assert_eq(_regions.standing_cell_y(at.x, at.y), ground, "before the binding it is just ground there")
	_routes.stitch_slot(slot)
	var road: int = Terrain._floor_div(_terrain.road_mm(track, along) + M / 2, M)
	assert_eq(_regions.standing_cell_y(at.x, at.y), road, "and once the site is bound the track is cut in there")


func test_regions_that_make_no_sense_fail_assembly() -> void:
	_setup()
	var cases: Array = [
		["a second wild", &"moor", {"schema_version": 1, "title": "x", "description": "x", "kind": "wild", "bounds": [], "gates": []}],
		["a gate that is not the graph's", &"annex", {"schema_version": 1, "title": "x", "description": "x", "kind": "authored",
			"bounds": [100, 100, 200, 200], "gates": [{"node": 1, "x": 150, "z": 100, "half_width_mm": 3000}]}],
		["an empty box", &"annex", {"schema_version": 1, "title": "x", "description": "x", "kind": "authored",
			"bounds": [100, 100, 100, 200], "gates": []}],
	]
	for c: Array in cases:
		var db := ContentDb.new()
		assert_eq(ContentLoader.load_all(db), OK, "content loads")
		var name: String = c[0]
		var id: StringName = c[1]
		var entry: Dictionary = c[2]
		assert_eq(db.add(Regions.KIND, id, entry), OK, "%s is well formed" % name)
		var regions := Regions.new(_routes, _terrain)
		assert_eq(regions.build(db), ERR_INVALID_DATA, "but %s is refused" % name)
