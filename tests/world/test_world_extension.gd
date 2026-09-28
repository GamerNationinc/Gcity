extends GcityTest

## The M7 extension exercise (spec, "Extension exercise for Q4"; standards §11): a second
## settlement kit and a fifth site tag added as content files alone, and a contract
## bound to the new tag. If any of this needed a line under `sim/`, kits and tags were
## never content. docs/extending-world.md is the procedure.

const SEED: int = 20261310
const KIT: StringName = &"mining_camp"
const TAG: StringName = &"extraction"
const QUEST: StringName = &"claim_jumpers"
## Worlds searched for one with a mining camp in it. A settlement node takes one of the
## kits at random, so a world without one is possible but a run of this many is not.
const WORLDS: int = 50

var _db: ContentDb


func _content() -> ContentDb:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	return db


## The first world from SEED on with a town built from the new kit, and that town.
func _world_with_a_camp(routes: RouteGraph) -> int:
	for i: int in WORLDS:
		routes.generate(SEED + i)
		for anchor: int in routes.town_ids():
			if routes.town_kit(anchor) == KIT:
				return anchor
	return EntityIds.NONE


func test_the_new_kit_builds_towns_joined_to_the_roads() -> void:
	_db = _content()
	var routes := RouteGraph.new()
	routes.set_kits(SettlementKits.prepared(_db))
	var anchor: int = _world_with_a_camp(routes)
	assert_true(anchor != EntityIds.NONE, "a mining camp stands in one of %d worlds" % WORLDS)
	assert_true(routes.everywhere_is_reachable(), "and the world holds together with it")
	var streets: int = 0
	for node: int in routes.node_ids():
		if routes.node_town(node) == anchor and node != anchor:
			streets += 1
			assert_true(routes.path_between(1, node).size() >= 2, "the gate's road reaches the camp's place %d" % node)
	assert_true(streets >= 3, "the camp's own places are on the graph (%d)" % streets)
	assert_true(routes.edges_at(anchor).size() >= 2, "stitched in: the road comes in and the camp's streets go on")


func test_the_fifth_tag_is_carried_by_the_slots_it_describes() -> void:
	_db = _content()
	var routes := RouteGraph.new()
	routes.set_kits(SettlementKits.prepared(_db))
	routes.generate(SEED)
	var carried: int = 0
	for slot: int in routes.slot_ids():
		var tags: Array[StringName] = SiteTags.of_slot(_db, routes, slot)
		var fits: bool = [&"rock", &"scrub"].has(routes.slot_biome(slot)) and [RouteGraph.KIND_POI, RouteGraph.KIND_JUNCTION].has(routes.kind_of(routes.slot_node(slot)))
		assert_eq(tags.has(TAG), fits, "slot %d carries the tag exactly where it says it belongs" % slot)
		if fits:
			carried += 1
	assert_true(carried > 0, "and some slot in the world does (%d)" % carried)


func test_a_contract_binds_to_the_fifth_tag() -> void:
	_db = _content()
	var sim: SimRoot = SimAssembly.build(SEED, _db)
	assert_true(sim != null, "assembly")
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var player: int = actors.spawn(&"arcade", 0)
	assert_eq(sim.submit(SimCommand.new(1, &"quest.accept", {"actor": player, "quest": String(QUEST)})), OK, "submitted")
	sim.step()
	var binder: SiteBinder = SimAssembly.binder_of(sim)
	var routes: RouteGraph = SimAssembly.routes_of(sim)
	var slot: int = binder.slot_of(QUEST)
	assert_true(slot != EntityIds.NONE, "the contract bound a slot")
	assert_true(SiteTags.of_slot(_db, routes, slot).has(TAG), "one that carries the new tag")
	assert_true(routes.slot_metres_from_gate(slot) <= 10_000, "within the ten kilometres it asked for")
	assert_eq(SimAssembly.quests_of(sim).status_of(player, QUEST), QuestSystem.STATUS_ACTIVE, "and the contract is on the books")
