extends GcityTest

## M7 spec claim 5: what a generated slot is for comes from `content/site_tag/`.
##
## The choice under test is that a tag is a *reading* over a slot rather than a field
## written into it. That is what keeps the Q4 extension exercise honest: a fifth tag is
## one new file, it applies to every slot it fits, and no world hash moves — so no save
## made before the file existed disagrees with the generator afterwards.

const SEED: int = 20261250

var _sim: SimRoot
var _db: ContentDb
var _routes: RouteGraph


func _setup() -> void:
	_db = ContentDb.new()
	assert_eq(ContentLoader.load_all(_db), OK, "content loads")
	_sim = SimAssembly.build(SEED, _db)
	_routes = SimAssembly.routes_of(_sim)


func test_every_slot_is_good_for_something() -> void:
	_setup()
	assert_true(_routes.slot_count() > 0, "the world offers places to build")
	for slot: int in _routes.slot_ids():
		var tags: Array[StringName] = SiteTags.of_slot(_db, _routes, slot)
		assert_false(tags.is_empty(), "slot %d is good for something" % slot)
		assert_true(tags.has(&"ruin"), "and can always have been something before")


## A tag appears exactly where it says it does. Read from the file rather than written
## out here, so a tag whose declaration changes is checked against the new declaration.
func test_a_tag_appears_where_it_says_it_does() -> void:
	_setup()
	var used: Dictionary = {}
	for slot: int in _routes.slot_ids():
		var biome: StringName = _routes.slot_biome(slot)
		var kind: StringName = _routes.kind_of(_routes.slot_node(slot))
		for tag: StringName in SiteTags.of_slot(_db, _routes, slot):
			used[tag] = true
			var entry: Dictionary = _db.get_entry(SiteTags.KIND, tag)
			var biomes: Array = entry["biomes"]
			var kinds: Array = entry["node_kinds"]
			if not biomes.is_empty():
				assert_true(biomes.has(String(biome)), "%s belongs on %s" % [tag, biome])
			if not kinds.is_empty():
				assert_true(kinds.has(String(kind)), "%s belongs at a %s" % [tag, kind])
	assert_false(used.is_empty(), "and this world is good for something")


## Across a handful of worlds every tag the game ships gets used. One world is not
## enough to claim it — a tag could be fine and simply not have come up — so this asks
## twenty, which is also what would catch a tag whose declaration no slot can ever meet.
func test_every_tag_the_game_ships_is_reachable() -> void:
	_setup()
	var used: Dictionary = {}
	var graph: RouteGraph = RouteGraph.new()
	for i: int in 20:
		graph.generate(SEED + i)
		for slot: int in graph.slot_ids():
			for tag: StringName in SiteTags.of_slot(_db, graph, slot):
				used[tag] = true
	assert_eq(used.size(), _db.ids(SiteTags.KIND).size(), "every tag is somewhere a contract could send you")


func test_a_tag_that_names_nothing_belongs_everywhere() -> void:
	_setup()
	for biome: StringName in RouteGraph.BIOMES:
		for kind: StringName in RouteGraph.KINDS:
			assert_true(SiteTags.matching(_db, biome, kind).has(&"ruin"), "ruin fits %s at a %s" % [biome, kind])
	assert_true(SiteTags.matching(_db, &"nowhere", &"nothing").has(&"ruin"), "and fits ground the world does not have")
	assert_false(SiteTags.matching(_db, &"nowhere", &"nothing").has(&"industrial"), "which a tag that names ground does not")
	assert_eq(SiteTags.of_slot(_db, _routes, 99999), [] as Array[StringName], "nothing is good for nothing")


## A tag naming a biome or a node kind that does not exist would be content that can
## never apply: a contract asking for it would find nowhere, and nothing would say why.
## It fails assembly instead.
func test_a_tag_that_names_ground_the_world_does_not_have_fails_assembly() -> void:
	_setup()
	assert_eq(SiteTags.validate(_db), OK, "the tags the game ships with are all reachable")
	var bad_biome: ContentDb = ContentDb.new()
	assert_eq(bad_biome.add(SiteTags.KIND, &"swamped", {
		"schema_version": 1, "title": "Swamped", "description": "on ground that is not",
		"biomes": ["lava"], "node_kinds": [],
	}), OK, "the entry is well formed")
	assert_eq(SiteTags.validate(bad_biome), ERR_INVALID_DATA, "but names ground the world does not have")
	var bad_kind: ContentDb = ContentDb.new()
	assert_eq(bad_kind.add(SiteTags.KIND, &"docked", {
		"schema_version": 1, "title": "Docked", "description": "at a place that is not",
		"biomes": [], "node_kinds": ["harbour"],
	}), OK, "the entry is well formed")
	assert_eq(SiteTags.validate(bad_kind), ERR_INVALID_DATA, "and this one names a place the graph has not")
