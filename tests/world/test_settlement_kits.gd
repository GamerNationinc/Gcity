extends GcityTest

## M7 spec claim 6: a settlement is a prefab kit spliced onto the graph, not noise.
##
## The claim that matters most here is the one that is easiest to lose: splicing must
## not be able to break connectivity. A kit whose optional block hangs off another
## optional block would come apart whenever the first one was not built, and the world
## would quietly be in two pieces. That is checked at assembly rather than hoped for,
## and the negative cases below are what hold the check to it.

const SEED: int = 20261250
const SEED_PROPERTY: int = 20261251
const PROPERTY_CASES: int = 10_000
const VARIETY_SEEDS: int = 40

var _sim: SimRoot
var _db: ContentDb
var _routes: RouteGraph


func _setup() -> void:
	_db = ContentDb.new()
	assert_eq(ContentLoader.load_all(_db), OK, "content loads")
	_sim = SimAssembly.build(SEED, _db)
	_routes = SimAssembly.routes_of(_sim)


## A kit that is fine, with one thing about it changed. Written this way so each
## negative case below is one line different from something that works, and cannot pass
## for the wrong reason.
func _one_kit(changed: Dictionary) -> ContentDb:
	var entry: Dictionary = {
		"schema_version": 1,
		"title": "Test",
		"description": "a kit for a test",
		"district": "badlands_outskirts",
		"min_blocks": 0,
		"max_blocks": 1,
		"nodes": [
			{"rel": [50000, 0], "kind": "junction", "block": ""},
			{"rel": [100000, 0], "kind": "poi", "block": ""},
			{"rel": [100000, 60000], "kind": "poi", "block": "yard"},
		],
		"edges": [
			{"a": 0, "b": 1, "width": 6000},
			{"a": 1, "b": 2, "width": 5000},
		],
		"sockets": [{"node": 0, "width": 8000}],
	}
	for key: Variant in changed:
		var field: String = key
		entry[field] = changed[field]
	var db := ContentDb.new()
	assert_eq(db.add(SettlementKits.KIND, &"test_kit", entry), OK, "the kit is well formed")
	return db


func test_every_town_is_a_kit_spliced_onto_the_graph() -> void:
	_setup()
	var kits: Array[Dictionary] = SettlementKits.prepared(_db)
	assert_false(kits.is_empty(), "the game ships settlement kits")
	var settlements: int = 0
	for node: int in _routes.node_ids():
		if _routes.kind_of(node) == RouteGraph.KIND_SETTLEMENT:
			settlements += 1
			assert_true(_routes.has_town(node), "settlement %d has a town on it" % node)
	assert_eq(_routes.town_count(), settlements, "every settlement and nothing else")
	assert_true(settlements > 0, "and this world has some (%d)" % settlements)
	for anchor: int in _routes.town_ids():
		var kit: Dictionary = _kit_named(kits, _routes.town_kit(anchor))
		assert_false(kit.is_empty(), "town %d was built from a kit the world has" % anchor)
		var turn: int = _routes.town_turn(anchor)
		assert_true(turn >= 0 and turn <= 3, "and faces one of four ways (%d)" % turn)
		var built: Array = _routes.town_blocks(anchor)
		var min_blocks: int = kit["min_blocks"]
		var max_blocks: int = kit["max_blocks"]
		assert_true(built.size() >= min_blocks and built.size() <= max_blocks,
			"with between %d and %d of its blocks (%d)" % [min_blocks, max_blocks, built.size()])
		var names: Array = kit["blocks"]
		for v: Variant in built:
			var block: String = v
			assert_true(names.has(block), "and '%s' is one of the kit's blocks" % block)
		assert_eq(_routes.node_town(anchor), EntityIds.NONE, "the anchor is the world's, not the town's")
		var streets: int = 0
		var at: Vector2i = _routes.position_of(anchor)
		for node: int in _routes.node_ids():
			if _routes.node_town(node) != anchor:
				continue
			streets += 1
			var where: Vector2i = _routes.position_of(node)
			assert_true(RouteGraph._length_mm(at.x, at.y, where.x, where.y) <= SettlementKits.MAX_REACH_MM,
				"street %d is inside its own town" % node)
			assert_true(_routes.distance_between(anchor, node) >= 0, "and you can walk to it")
		assert_true(streets > 0, "town %d is somewhere rather than a label (%d streets)" % [anchor, streets])
	assert_true(_routes.everywhere_is_reachable(), "and the world with its towns in it is one piece")
	assert_true(_routes.narrowest_edge_mm() >= RouteGraph.MIN_WIDTH_MM, "every street included")


## Design doc §7.2: the town's rights tables already exist, so nobody has to invent one
## when the player walks in.
func test_a_town_brings_its_district_with_it() -> void:
	_setup()
	for anchor: int in _routes.town_ids():
		var district: StringName = _routes.town_district(anchor)
		assert_false(district.is_empty(), "town %d knows whose law it is under" % anchor)
		assert_true(_db.has(LandSystem.KIND_DISTRICT, district), "and %s is a district the game has" % district)
	assert_eq(_routes.town_district(99999), &"", "and somewhere that is not a town is under nobody's")


func test_a_world_with_no_kits_has_no_towns() -> void:
	var graph: RouteGraph = RouteGraph.new()
	graph.generate(SEED)
	assert_eq(graph.town_count(), 0, "no kits, no towns")
	assert_true(graph.everywhere_is_reachable(), "and the world is still one piece without them")
	for node: int in graph.node_ids():
		assert_eq(graph.node_town(node), EntityIds.NONE, "node %d belongs to no town" % node)
	assert_eq(graph.town_kit(1), &"", "nothing was built from anything")
	assert_eq(graph.town_turn(1), 0, "nothing faces anywhere")
	assert_eq(graph.town_blocks(1), [], "and nothing has blocks")


## Seeded variation is what stops two waystations on the same road being one place
## placed twice: which way it faces and which of its blocks got built.
func test_towns_vary_in_which_way_they_face_and_what_got_built() -> void:
	_setup()
	var graph: RouteGraph = RouteGraph.new()
	graph.set_kits(SettlementKits.prepared(_db))
	var turns: Dictionary = {}
	var densities: Dictionary = {}
	var blocks: Dictionary = {}
	for i: int in VARIETY_SEEDS:
		graph.generate(SEED + i)
		for anchor: int in graph.town_ids():
			turns[graph.town_turn(anchor)] = true
			var built: Array = graph.town_blocks(anchor)
			densities[built.size()] = true
			for v: Variant in built:
				var block: String = v
				blocks[block] = true
	assert_eq(turns.size(), 4, "towns face all four ways (%d)" % turns.size())
	assert_true(densities.size() >= 2, "and differ in how much got built (%d densities)" % densities.size())
	assert_true(blocks.size() >= 3, "and every block gets built somewhere (%d)" % blocks.size())


func test_the_same_seed_builds_the_same_towns() -> void:
	_setup()
	var kits: Array[Dictionary] = SettlementKits.prepared(_db)
	var first: RouteGraph = RouteGraph.new()
	var second: RouteGraph = RouteGraph.new()
	first.set_kits(kits)
	second.set_kits(kits)
	first.generate(SEED)
	second.generate(SEED)
	assert_eq(first.town_ids(), second.town_ids(), "the same towns")
	for anchor: int in first.town_ids():
		assert_eq(first.town_kit(anchor), second.town_kit(anchor), "town %d from the same kit" % anchor)
		assert_eq(first.town_turn(anchor), second.town_turn(anchor), "facing the same way")
		assert_eq(first.town_blocks(anchor), second.town_blocks(anchor), "with the same blocks")
	assert_eq(first.world_hash(), second.world_hash(), "and the same world around them")
	assert_true(first.world_hash() != RouteGraph.new().world_hash(), "which a world with nothing in it is not")


## Each of these builds a town the graph could not keep its promises about, so each
## fails assembly rather than producing a world that is wrong.
func test_a_kit_that_would_break_the_world_fails_assembly() -> void:
	_setup()
	assert_eq(SettlementKits.validate(_db), OK, "the kits the game ships are all sound")
	assert_eq(SettlementKits.validate(_one_kit({})), OK, "and so is the one these cases start from")
	assert_eq(SettlementKits.validate(_one_kit({"min_blocks": 2})), ERR_INVALID_DATA,
		"a kit cannot want more blocks than it will build")
	assert_eq(SettlementKits.validate(_one_kit({"max_blocks": 4})), ERR_INVALID_DATA,
		"nor more than it has")
	assert_eq(SettlementKits.validate(_one_kit({"edges": [{"a": 0, "b": 9, "width": 6000}]})), ERR_INVALID_DATA,
		"a road cannot go to a place that is not in the kit")
	assert_eq(SettlementKits.validate(_one_kit({"edges": [{"a": 0, "b": 0, "width": 6000}]})), ERR_INVALID_DATA,
		"nor from a place to itself")
	assert_eq(SettlementKits.validate(_one_kit({"sockets": [{"node": 2, "width": 8000}]})), ERR_INVALID_DATA,
		"the road cannot arrive at something that might not be built")
	assert_eq(SettlementKits.validate(_one_kit({
		"nodes": [
			{"rel": [50000, 0], "kind": "junction", "block": ""},
			{"rel": [100000, 0], "kind": "settlement", "block": ""},
			{"rel": [100000, 60000], "kind": "poi", "block": "yard"},
		]})), ERR_INVALID_DATA, "a town inside a town would raise a town inside that one")
	assert_eq(SettlementKits.validate(_one_kit({
		"nodes": [
			{"rel": [50000, 0], "kind": "junction", "block": ""},
			{"rel": [199000, 0], "kind": "poi", "block": ""},
			{"rel": [199000, 199000], "kind": "poi", "block": "yard"},
		]})), ERR_INVALID_DATA, "and a kit cannot reach so far that two towns interleave")
	# the always-built part in two pieces, joined only through a block that may not exist
	assert_eq(SettlementKits.validate(_one_kit({
		"nodes": [
			{"rel": [50000, 0], "kind": "junction", "block": ""},
			{"rel": [100000, 0], "kind": "poi", "block": ""},
			{"rel": [100000, 60000], "kind": "poi", "block": "yard"},
		],
		"edges": [
			{"a": 0, "b": 2, "width": 6000},
			{"a": 2, "b": 1, "width": 5000},
		]})), ERR_INVALID_DATA, "a kit must hold together without its blocks")
	# a block joined to nothing at all
	assert_eq(SettlementKits.validate(_one_kit({
		"edges": [{"a": 0, "b": 1, "width": 6000}],
	})), ERR_INVALID_DATA, "and a block with no way in is a place nobody can reach")


## The property the splice rests on: over ten thousand worlds, adding towns never puts
## a street outside its own town, never leaves one unreachable, and never makes a road
## too narrow to walk.
func test_property_splicing_towns_never_breaks_a_world() -> void:
	_setup()
	var graph: RouteGraph = RouteGraph.new()
	graph.set_kits(SettlementKits.prepared(_db))
	var broken: int = 0
	var stray: int = 0
	var townless: int = 0
	for i: int in PROPERTY_CASES:
		var world: int = SEED_PROPERTY + i
		graph.generate(world)
		if graph.town_count() == 0:
			townless += 1
		if not graph.everywhere_is_reachable() or graph.narrowest_edge_mm() < RouteGraph.MIN_WIDTH_MM:
			broken += 1
			if broken <= 3:
				fail("seed %d built a world its towns broke" % world)
		for node: int in graph.node_ids():
			var anchor: int = graph.node_town(node)
			if anchor == EntityIds.NONE:
				continue
			var at: Vector2i = graph.position_of(anchor)
			var where: Vector2i = graph.position_of(node)
			if RouteGraph._length_mm(at.x, at.y, where.x, where.y) > SettlementKits.MAX_REACH_MM:
				stray += 1
				if stray <= 3:
					fail("seed %d put street %d outside its own town" % [world, node])
				break
	# A world with no settlement in it is rare but legitimate: a quarter of the places a
	# world rolls are settlements and a world holds at least eighteen, so about one seed
	# in seven hundred has none. Nothing depends on a town existing — slots come from
	# points of interest too — so this measures the rate rather than forbidding it, and
	# would catch a change that made towns vanish or become certain.
	assert_true(townless * 100 < PROPERTY_CASES, "a world with nowhere to stop is rare (%d in %d)" % [
		townless, PROPERTY_CASES])
	assert_true(townless > 0, "but not impossible, which is worth knowing at the gate")
	assert_eq(broken, 0, "and every world is still one piece with every road walkable")
	assert_eq(stray, 0, "and every street is inside the town that built it")


func _kit_named(kits: Array[Dictionary], wanted: StringName) -> Dictionary:
	for kit: Dictionary in kits:
		var id: StringName = kit["id"]
		if id == wanted:
			return kit
	return {}
