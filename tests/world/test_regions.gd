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
		assert_eq(_regions.is_solid(cell), cell.y < BuildSystem.GROUND_CELL_Y, "under the ground level is ground, above it is not: %s" % cell)
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


# ---------------------------------------------------------------- claim 14: the seam

func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


## M7 spec claim 14: the gate is a designed seam with a load window. Standing in its
## opening, `region.enter` takes you through; for the window you are in the gate and go
## nowhere, while the world keeps running; then you are set down on the far side, on
## the ground. And back the same way.
func test_the_gate_takes_you_through_after_a_load_window() -> void:
	_setup()
	var actors: ActorSystem = SimAssembly.actors_of(_sim)
	var tokens: MacroTokenSystem = SimAssembly.tokens_of(_sim)
	var player: int = actors.spawn(&"arcade", 0)
	actors.set_position(player, Vector3i(1500, 0, 400))
	assert_eq(_regions.gate_at(actors.position_of(player)), 1, "standing in the gate's opening")
	# something off in the wilds, so the world visibly keeps running during the window
	var far: Array[int] = []
	for node: int in _routes.node_ids():
		if node != 1 and _routes.neighbours(node).size() > 0:
			far = [node, _routes.neighbours(node)[0]]
			break
	var token: int = tokens.spawn("faction.scrapline", far[0], far[1], 40, {})
	assert_true(_do(Regions.COMMAND_ENTER, {"actor": player, "region": "wilds"}), "through the gate")
	assert_true(_regions.in_transit(player), "and in it")
	var tick_in: int = _sim.get_tick()
	var progress_in: int = tokens.progress_of(token)
	assert_false(_do(&"actor.move", {"actor": player, "dx": 100, "dz": 0}), "going nowhere while in the gate")
	assert_false(_do(Regions.COMMAND_ENTER, {"actor": player, "region": "wilds"}), "and not taking it twice")
	while _regions.in_transit(player):
		_sim.step()
	assert_eq(_sim.get_tick() - tick_in, Regions.LOAD_WINDOW_TICKS, "for exactly the load window")
	assert_true(tokens.progress_of(token) > progress_in, "while the world outside kept going")
	var out: Vector3i = actors.position_of(player)
	assert_eq(out, Vector3i(1500, _regions.standing_cell_y(1500, -500) * BuildSystem.CELL, -500), "set down straight through it, on the ground")
	assert_eq(_regions.region_at(out.x, out.z).id(), &"wilds", "in the wilds")
	assert_true(_do(&"actor.move", {"actor": player, "dx": 100, "dz": -100}), "and free to walk")
	# and back
	actors.set_position(player, Vector3i(-2000, 0, -300))
	assert_true(_do(Regions.COMMAND_ENTER, {"actor": player, "region": "city"}), "back through it")
	_sim.step_n(Regions.LOAD_WINDOW_TICKS)
	assert_eq(actors.position_of(player), Vector3i(-2000, 0, 500), "into the city")


func test_the_gate_is_only_taken_from_its_opening_and_only_through() -> void:
	_setup()
	var actors: ActorSystem = SimAssembly.actors_of(_sim)
	var player: int = actors.spawn(&"arcade", 0)
	actors.set_position(player, Vector3i(9000, 0, 400))
	assert_false(_do(Regions.COMMAND_ENTER, {"actor": player, "region": "wilds"}), "beside the gate, not in it")
	actors.set_position(player, Vector3i(500, 0, 2500))
	assert_false(_do(Regions.COMMAND_ENTER, {"actor": player, "region": "wilds"}), "too far back from it")
	actors.set_position(player, Vector3i(500, 0, 400))
	assert_false(_do(Regions.COMMAND_ENTER, {"actor": player, "region": "city"}), "not into the region you are already in")
	assert_false(_do(Regions.COMMAND_ENTER, {"actor": player, "region": "moon"}), "nor one that is not")
	assert_false(_do(Regions.COMMAND_ENTER, {"actor": 99999, "region": "wilds"}), "nobody")
	assert_false(_do(Regions.COMMAND_ENTER, {"actor": player}), "a short payload")
	assert_false(_do(Regions.COMMAND_ENTER, {"actor": player, "region": "wilds", "fast": true}), "an extra key")
	actors.damage_node(player, &"body", 999999)
	assert_false(_do(Regions.COMMAND_ENTER, {"actor": player, "region": "wilds"}), "and not the dead")
	assert_eq(_regions.transit_ids(), [] as Array[int], "and none of that put anyone in the gate")


func test_a_save_taken_in_the_gate_loads_and_comes_out_the_same() -> void:
	_setup()
	var actors: ActorSystem = SimAssembly.actors_of(_sim)
	var player: int = actors.spawn(&"arcade", 0)
	actors.set_position(player, Vector3i(500, 0, 400))
	assert_true(_do(Regions.COMMAND_ENTER, {"actor": player, "region": "wilds"}), "through the gate")
	_sim.step_n(30)
	var snap: Dictionary = _sim.snapshot()
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "restored mid-window")
	assert_eq(other.restore_root(snap), OK, "root")
	_sim.step_n(60)
	other.step_n(60)
	assert_eq(other.state_hash(), _sim.state_hash(), "and comes out the other side the same")
	var good: Dictionary = _regions.snapshot()
	for bad: Dictionary in [
		{}, {"transits": [], },
		{"transits": {99999: {"region": "wilds", "gate": 1, "due": 5}}},
		{"transits": {player: {"region": "moon", "gate": 1, "due": 5}}},
		{"transits": {player: {"region": "wilds", "gate": 2, "due": 5}}},
		{"transits": {player: {"region": "wilds", "gate": 1, "due": -1}}},
		{"transits": {player: {"region": "wilds", "gate": 1}}},
	]:
		assert_eq(_regions.restore(bad), ERR_INVALID_DATA, "refused: %s" % [bad])
		assert_eq(_regions.snapshot(), good, "and nothing changed")


# ---------------------------------------------------------------- claim 15: editing the ground

## M7 spec claim 15: the wild ground can be dug out and filled in, and what has been
## changed is the part of the ground a save carries — deltas per chunk, and nothing
## once a cell is put back the way the seed made it.
func test_the_wild_ground_can_be_dug_and_filled_and_the_save_holds_only_the_changes() -> void:
	_setup()
	var actors: ActorSystem = SimAssembly.actors_of(_sim)
	var player: int = actors.spawn(&"arcade", 0)
	# on the level apron outside the gate: standing in cell y 0, ground below
	actors.set_position(player, Vector3i(500, 0, -40_500))
	var ahead: Vector3i = Vector3i(1, -1, -41)
	assert_true(_regions.is_solid(ahead), "the ground beside and below is ground")
	assert_true(_do(Regions.COMMAND_DIG, {"actor": player, "cell": [ahead.x, ahead.y, ahead.z]}), "dig it out")
	assert_false(_regions.is_solid(ahead), "and it is a hole")
	var edits: Dictionary = _regions.snapshot()["edits"]
	assert_eq(edits.size(), 1, "one chunk changed")
	assert_false(_do(Regions.COMMAND_DIG, {"actor": player, "cell": [ahead.x, ahead.y, ahead.z]}), "a hole cannot be dug again")
	assert_true(_do(Regions.COMMAND_FILL, {"actor": player, "cell": [ahead.x, ahead.y, ahead.z]}), "fill it back in")
	assert_true(_regions.is_solid(ahead), "and it is ground")
	assert_eq(_regions.snapshot()["edits"], {}, "put back the way the seed made it, it is no change at all")
	# dig out from under yourself and you fall into it
	var under: Vector3i = Vector3i(0, -1, -41)
	assert_true(_do(Regions.COMMAND_DIG, {"actor": player, "cell": [under.x, under.y, under.z]}), "dig under your own feet")
	_sim.step_n(2)
	assert_eq(actors.position_of(player).y, -BuildSystem.CELL, "and drop into the hole")
	assert_true(actors.is_alive(player), "unhurt")
	assert_false(_do(Regions.COMMAND_FILL, {"actor": player, "cell": [under.x, under.y, under.z]}), "and you cannot fill the cell you stand in")
	# the save carries the hole
	var snap: Dictionary = _sim.snapshot()
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "a save with a hole in it loads")
	assert_false(SimAssembly.regions_of(other).is_solid(under), "with the hole")
	var good: Dictionary = _regions.snapshot()
	for bad: Dictionary in [
		{"transits": {}},
		{"transits": {}, "edits": {"a,b,c": {0: 0}}},
		{"transits": {}, "edits": {"0,0,0": {}}},
		{"transits": {}, "edits": {"0,0,0": {5000: 0}}},
		{"transits": {}, "edits": {"0,0,0": {5: 2}}},
		{"transits": {}, "edits": {"0,0,0": {"5": 0}}},
	]:
		assert_eq(_regions.restore(bad), ERR_INVALID_DATA, "refused: %s" % [bad])
		assert_eq(_regions.snapshot(), good, "and nothing changed")


func test_the_ground_is_only_edited_by_someone_there_where_it_can_be() -> void:
	_setup()
	var actors: ActorSystem = SimAssembly.actors_of(_sim)
	var player: int = actors.spawn(&"arcade", 0)
	actors.set_position(player, Vector3i(500, 0, -40_500))
	var near: Array = [1, -1, -41]
	assert_false(_do(Regions.COMMAND_DIG, {"actor": player, "cell": [9, -1, -41]}), "out of reach")
	assert_false(_do(Regions.COMMAND_DIG, {"actor": player, "cell": [1, 3, -41]}), "air is not dug")
	assert_false(_do(Regions.COMMAND_FILL, {"actor": player, "cell": near}), "ground is not filled")
	assert_false(_do(Regions.COMMAND_DIG, {"actor": 99999, "cell": near}), "nobody")
	assert_false(_do(Regions.COMMAND_DIG, {"actor": player, "cell": [1, -1]}), "a short cell")
	assert_false(_do(Regions.COMMAND_DIG, {"actor": player, "cell": [1.0, -1, -41]}), "a fractional cell")
	assert_false(_do(Regions.COMMAND_DIG, {"actor": player, "cell": near, "deep": true}), "an extra key")
	# the city's ground is built on, not dug
	actors.set_position(player, Vector3i(5_500, 0, 5_500))
	assert_false(_do(Regions.COMMAND_DIG, {"actor": player, "cell": [5, -1, 6]}), "not in the city")
	assert_eq(_regions.snapshot()["edits"], {}, "and none of that changed the ground")


## M7 spec claim 16: the client draws the ground from a block of cells at a time, and the
## block must be the ground the sim walks on, cell for cell — roads cut in, edits laid
## over, and across the city's edge.
func test_a_block_of_cells_is_the_ground_cell_for_cell() -> void:
	_setup()
	var actors: ActorSystem = SimAssembly.actors_of(_sim)
	var player: int = actors.spawn(&"arcade", 0)
	actors.set_position(player, Vector3i(500, 0, -40_500))
	assert_true(_do(Regions.COMMAND_DIG, {"actor": player, "cell": [1, -1, -41]}), "a hole dug")
	assert_true(_do(Regions.COMMAND_FILL, {"actor": player, "cell": [0, 0, -42]}), "and a cell filled in")
	# a road: the first stretch of whatever leaves the gate
	var edge: int = _routes.edges_at(1)[0]
	var on_road: Vector2i = _terrain.road_at(edge, 400 * M)
	var road_cell: Vector3i = Vector3i(Terrain._floor_div(on_road.x, M), _regions.standing_cell_y(on_road.x, on_road.y), Terrain._floor_div(on_road.y, M))
	var origins: Array[Vector3i] = [
		Vector3i(-8, -12, -52),                       # the apron, the hole and the fill
		road_cell - Vector3i(8, 7, 5),                # a road cut in
		Vector3i(-4, -6, -5),                         # across the city's edge
		Vector3i(3000, _regions.standing_cell_y(3_000 * M, -5_000 * M) - 7, -5000),  # plain wild ground
	]
	# a box that is not a cube, so a mix-up of the axes cannot pass
	var size: Vector3i = Vector3i(18, 14, 11)
	var cells: int = size.x * size.y * size.z
	for origin: Vector3i in origins:
		var block: PackedByteArray = _regions.solids(origin, size)
		assert_eq(block.size(), cells, "a whole box")
		var wrong: int = 0
		var solid: int = 0
		for z: int in size.z:
			for y: int in size.y:
				for x: int in size.x:
					var cell: Vector3i = origin + Vector3i(x, y, z)
					var want: int = 1 if _regions.is_solid(cell) else 0
					var got: int = block[(z * size.y + y) * size.x + x]
					solid += got
					if got != want:
						wrong += 1
						if wrong <= 3:
							fail("block at %s: cell %s is %d, the ground says %d" % [origin, cell, got, want])
		assert_eq(wrong, 0, "the box at %s is the ground (%d solid of %d)" % [origin, solid, cells])
		assert_true(solid > 0 and solid < cells, "and has both ground and air in it")
