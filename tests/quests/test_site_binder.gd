extends GcityTest

## M7 spec claim 9: binding is deterministic and permanent.
##
## Accepting a contract with a handle picks one of the slots that fit it, from the seed,
## and writes that down; the same save always has the same place, and a place once bound
## is never offered to another contract. The bound site becomes a node on the graph.
##
## None of the contracts the game ships carries a handle yet — Cold Storage gets one in
## claim 10 — so these tests add their own on top of the shipped content.

const SEED: int = 20261260
const SEED_PROPERTY: int = 20261261
const PROPERTY_BINDINGS: int = 10_000

var _db: ContentDb
var _sim: SimRoot
var _actors: ActorSystem
var _quests: QuestSystem
var _binder: SiteBinder
var _routes: RouteGraph
var _player: int = 0


## A contract with a handle, as content writes one. It has an objective so that an
## accepted one is active rather than already done, which is what restore insists on.
static func _job(tags: Array, min_km: int, max_km: int) -> Dictionary:
	return {
		"schema_version": 1, "title": "A job", "description": "x", "text": "x",
		"objectives": [{"description": "x", "event": "terminal.hacked", "credit": "actor", "tags_any": [], "count": 1}],
		"reward": [],
		"site": {"tags_any": tags, "min_km": min_km, "max_km": max_km, "undiscovered": false},
	}


func _content(jobs: Dictionary) -> ContentDb:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	for key: Variant in jobs:
		var id: String = key
		var entry: Dictionary = jobs[key]
		assert_eq(db.add(QuestSystem.KIND_QUEST, StringName(id), entry), OK, "quest/%s added" % id)
	return db


func _default_jobs() -> Dictionary:
	return {
		"old_works": _job(["industrial", "ruin"], 0, 100),
		"same_again": _job(["industrial", "ruin"], 0, 100),
		"far_out": _job(["ruin"], 90, 100),
	}


func _setup(jobs: Dictionary = {}) -> void:
	if jobs.is_empty():
		jobs = _default_jobs()
	_db = _content(jobs)
	_sim = SimAssembly.build(SEED, _db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_quests = SimAssembly.quests_of(_sim)
	_binder = SimAssembly.binder_of(_sim)
	_routes = SimAssembly.routes_of(_sim)
	_player = _actors.spawn(&"arcade", 0)


func _do(kind: StringName, payload: Dictionary, sim: SimRoot = null) -> bool:
	if sim == null:
		sim = _sim
	var before: int = sim.dispatched_count()
	assert_eq(sim.submit(SimCommand.new(sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	sim.step()
	return sim.dispatched_count() == before + 1


func _accept(quest: String, actor: int = -1, sim: SimRoot = null) -> bool:
	return _do(QuestSystem.COMMAND_ACCEPT, {"actor": _player if actor < 0 else actor, "quest": quest}, sim)


func test_accepting_a_contract_binds_a_place_that_fits_it() -> void:
	_setup()
	var nodes: int = _routes.node_count()
	var world: String = _routes.world_hash()
	assert_eq(_binder.slot_of(&"old_works"), EntityIds.NONE, "nothing is bound before anyone takes the job")
	assert_true(_accept("old_works"), "the contract is taken")
	var slot: int = _binder.slot_of(&"old_works")
	assert_true(_routes.has_slot(slot), "and has a place (%d)" % slot)
	assert_true(SiteConstraint.matches(_quests.site_of(&"old_works"), _db, _routes, slot, {}), "one that fits what it asked for")
	assert_true(_binder.is_bound(slot), "which is now taken")
	assert_eq(_binder.bound_quests(), [&"old_works"] as Array[StringName], "by this contract")
	# the place is on the graph: a site node where the slot is, one track off the node
	# that offers it
	var site: int = _binder.node_of(&"old_works")
	assert_eq(_routes.node_count(), nodes + 1, "the world gained exactly one place")
	assert_eq(_routes.kind_of(site), RouteGraph.KIND_SITE, "a bound site")
	assert_eq(_routes.position_of(site), _routes.slot_position(slot), "standing where the slot is")
	assert_eq(_routes.site_node_of(slot), site, "which the graph knows by its slot")
	assert_eq(_routes.neighbours(site), [_routes.slot_node(slot)] as Array[int], "joined to the place that offered it")
	var track: Dictionary = _routes.edge(_routes.edge_between(site, _routes.slot_node(slot)))
	assert_eq(track["width"], RouteGraph.MIN_WIDTH_MM, "by a track as narrow as the world allows and no narrower")
	assert_eq(_routes.distance_between(1, site), _routes.slot_metres_from_gate(slot),
		"and it is exactly as far out as the contract was told it was")
	assert_true(_routes.everywhere_is_reachable(), "the world is still one piece")
	assert_eq(_routes.world_hash(), world, "and still the world the seed built: a binding is the save's, not the seed's")


func test_a_place_once_bound_is_the_same_place_for_good() -> void:
	_setup()
	assert_true(_accept("old_works"), "taken")
	var slot: int = _binder.slot_of(&"old_works")
	var nodes: int = _routes.node_count()
	assert_true(_do(QuestSystem.COMMAND_ABANDON, {"actor": _player, "quest": "old_works"}), "dropped")
	assert_eq(_binder.slot_of(&"old_works"), slot, "dropping the job does not release the place")
	assert_true(_accept("old_works"), "taken again")
	assert_eq(_binder.slot_of(&"old_works"), slot, "and it is the same place")
	assert_eq(_routes.node_count(), nodes, "not a second copy of it")
	var other: int = _actors.spawn(&"arcade", 0)
	assert_true(_accept("old_works", other), "someone else takes the same contract")
	assert_eq(_binder.slot_of(&"old_works"), slot, "and it happens in the same place")
	assert_eq(_binder.bound_quests().size(), 1, "one contract, one place")


func test_a_bound_slot_is_never_offered_to_a_second_contract() -> void:
	_setup()
	assert_true(_accept("old_works"), "the first job")
	assert_true(_accept("same_again"), "a second asking for exactly the same kind of place")
	assert_true(_binder.slot_of(&"old_works") != _binder.slot_of(&"same_again"), "gets somewhere else (%d, %d)" % [
		_binder.slot_of(&"old_works"), _binder.slot_of(&"same_again")])
	# and when every place is taken the next contract has nowhere to go
	var bare := RouteGraph.new()
	var probe: ContentDb = _content({})
	bare.set_kits(SettlementKits.prepared(probe))
	bare.generate(SEED)
	var slots: int = bare.slot_count()
	var jobs: Dictionary = {}
	for i: int in slots + 1:
		jobs["anywhere_%02d" % i] = _job(["ruin"], 0, 100)
	_setup(jobs)
	var taken: Dictionary = {}
	for i: int in slots:
		assert_true(_accept("anywhere_%02d" % i), "job %d of %d finds a place" % [i + 1, slots])
		taken[_binder.slot_of(StringName("anywhere_%02d" % i))] = true
	assert_eq(taken.size(), slots, "every one somewhere different")
	for slot: int in _routes.slot_ids():
		assert_true(taken.has(slot), "until the whole world is spoken for (slot %d)" % slot)
	var last: String = "anywhere_%02d" % slots
	assert_false(_accept(last), "the next job is refused")
	assert_eq(_quests.status_of(_player, StringName(last)), "", "and not taken")
	assert_eq(_binder.slot_of(StringName(last)), EntityIds.NONE, "and binds nothing")


func test_a_contract_with_nowhere_to_go_is_refused_and_leaves_nothing_behind() -> void:
	_setup()
	var nodes: int = _routes.node_count()
	assert_false(_accept("far_out"), "nothing is ninety kilometres out in a sixty kilometre world")
	assert_eq(_quests.status_of(_player, &"far_out"), "", "so the contract is not taken")
	assert_eq(_binder.bound_quests(), [] as Array[StringName], "nothing is bound")
	assert_eq(_routes.node_count(), nodes, "and the map is as it was")
	# a refused accept for any other reason binds nothing either: the binding is last
	assert_false(_accept("old_works", 99), "an actor who is not one")
	assert_eq(_binder.slot_of(&"old_works"), EntityIds.NONE, "leaves no place behind")
	# a contract with a handle and nothing to turn it into a place cannot be taken
	_quests.set_site_binder(Callable())
	assert_false(_accept("old_works"), "no binder, no job")
	assert_true(_accept("first_blood"), "but a contract without a handle does not need one")
	assert_eq(_binder.bound_quests(), [] as Array[StringName], "and binds nothing")


## The choice is a function of the seed, the quest and what is already taken. Not the
## sim's shared generator, or adding a system that draws from it would move every
## contract; and not the tick, or taking the job a minute later would be somewhere else.
func test_the_choice_is_the_seeds_and_not_the_sims() -> void:
	_setup()
	assert_true(_accept("old_works"), "taken at once")
	var slot: int = _binder.slot_of(&"old_works")
	var later: SimRoot = SimAssembly.build(SEED, _content(_default_jobs()))
	var player: int = SimAssembly.actors_of(later).spawn(&"arcade", 0)
	for i: int in 50:
		later.rng().randi()
	for i: int in 30:
		later.step()
	assert_true(_accept("old_works", player, later), "taken later, after the dice were rolled")
	assert_eq(SimAssembly.binder_of(later).slot_of(&"old_works"), slot, "in the same place")


func test_a_bound_site_disturbs_nothing_that_was_already_there() -> void:
	_setup()
	var before: Dictionary = {}
	for node: int in _routes.node_ids():
		before[node] = _routes.distance_mm_between(1, node)
	assert_true(_accept("old_works"), "taken")
	assert_true(_accept("same_again"), "and another")
	for node: int in before:
		assert_eq(_routes.distance_mm_between(1, node), before[node], "node %d is as far out as it was" % node)
	var terrain: Terrain = SimAssembly.terrain_of(_sim)
	for quest: StringName in _binder.bound_quests():
		var site: int = _binder.node_of(quest)
		for edge_id: int in _routes.edges_at(site):
			assert_true(terrain.is_traversable(edge_id), "the track to %s can be walked in the ground it crosses" % quest)


func test_the_same_save_has_the_same_place() -> void:
	_setup()
	assert_true(_accept("old_works"), "taken")
	assert_true(_accept("same_again"), "and another")
	var snap: Dictionary = _sim.snapshot()
	assert_eq(snap["systems"][SiteBinder.SYSTEM_ID], {"bound": [["old_works", _binder.slot_of(&"old_works")], ["same_again", _binder.slot_of(&"same_again")]]},
		"the save holds which contract bound which slot, in order, and nothing else")
	var other: SimRoot = SimAssembly.build(SEED, _content(_default_jobs()))
	# a sim that has already bound something of its own is overwritten, not added to
	var player: int = SimAssembly.actors_of(other).spawn(&"arcade", 0)
	assert_true(_accept("same_again", player, other), "the other sim bound a different job first")
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "restored")
	assert_eq(other.restore_root(snap), OK, "root restored")
	var binder: SiteBinder = SimAssembly.binder_of(other)
	var routes: RouteGraph = SimAssembly.routes_of(other)
	for quest: StringName in [&"old_works", &"same_again"]:
		assert_eq(binder.slot_of(quest), _binder.slot_of(quest), "%s is where it was" % quest)
		assert_eq(binder.node_of(quest), _binder.node_of(quest), "under the same node")
	assert_eq(routes.node_count(), _routes.node_count(), "no more places and no fewer")
	assert_eq(routes.edge_count(), _routes.edge_count(), "nor roads")
	assert_eq(StateHash.of(other.snapshot()), StateHash.of(snap), "the whole state agrees")


func test_a_save_that_binds_badly_is_refused() -> void:
	_setup()
	assert_true(_accept("old_works"), "taken")
	var slot: int = _binder.slot_of(&"old_works")
	var good: Dictionary = _binder.snapshot()
	var elsewhere: int = _routes.slot_ids()[0] if _routes.slot_ids()[0] != slot else _routes.slot_ids()[1]
	var nodes: int = _routes.node_count()
	var bad: Array[Dictionary] = [
		{},
		{"bound": [], "extra": 1},
		{"bound": "old_works"},
		{"bound": [["old_works"]]},
		{"bound": [["old_works", "7"]]},
		{"bound": [["nothing", slot]]},
		{"bound": [["first_blood", slot]]},
		{"bound": [["old_works", 99999]]},
		{"bound": [["old_works", slot], ["old_works", elsewhere]]},
		{"bound": [["old_works", slot], ["same_again", slot]]},
		{"bound": [["far_out", slot]]},
	]
	for state: Dictionary in bad:
		assert_eq(_binder.restore(state), ERR_INVALID_DATA, "refused: %s" % [state])
		assert_eq(_binder.snapshot(), good, "and the bindings are as they were")
		assert_eq(_routes.node_count(), nodes, "and so is the map")
	assert_eq(_binder.restore(good), OK, "the real thing restores")
	assert_eq(_binder.node_of(&"old_works"), _routes.site_node_of(slot), "onto the same site")


## The property the G7 bar names. Ten thousand bindings over as many worlds as that
## takes, each world built twice from its seed: the same seed and constraints give the
## same slot, every slot fits what was asked, and no slot is bound twice in a world.
func test_property_the_same_seed_and_constraints_give_the_same_slot_and_no_slot_twice() -> void:
	var db: ContentDb = _content({})
	var tags: Array[StringName] = db.ids(SiteTags.KIND)
	var first := RouteGraph.new()
	var second := RouteGraph.new()
	first.set_kits(SettlementKits.prepared(db))
	second.set_kits(SettlementKits.prepared(db))
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	var bindings: int = 0
	var bound: int = 0
	var worlds: int = 0
	var disagreed: int = 0
	var twice: int = 0
	var misfit: int = 0
	while bindings < PROPERTY_BINDINGS:
		var world: int = SEED_PROPERTY + worlds
		worlds += 1
		first.generate(world)
		second.generate(world)
		var taken_first: Dictionary = {}
		var taken_second: Dictionary = {}
		for k: int in rng.randi_range(4, 12):
			var wanted: Array = []
			for tag: StringName in tags:
				if rng.randi_range(0, 1) == 1:
					wanted.append(String(tag))
			if wanted.is_empty():
				wanted.append(String(tags[rng.randi_range(0, tags.size() - 1)]))
			var min_km: int = rng.randi_range(0, 20)
			var constraint: Dictionary = {"tags_any": wanted, "min_km": min_km, "max_km": min_km + rng.randi_range(0, 40), "undiscovered": false}
			var quest: StringName = StringName("job_%d" % k)
			var a: int = SiteBinder.pick(constraint, db, first, taken_first, quest)
			var b: int = SiteBinder.pick(constraint, db, second, taken_second, quest)
			bindings += 1
			if a != b:
				disagreed += 1
				if disagreed <= 3:
					fail("seed %d, %s: one build picked %d and the other %d" % [world, quest, a, b])
			if a == EntityIds.NONE:
				continue
			bound += 1
			if taken_first.has(a):
				twice += 1
				if twice <= 3:
					fail("seed %d: slot %d bound twice" % [world, a])
			if not SiteConstraint.matches(constraint, db, first, a, {}):
				misfit += 1
				if misfit <= 3:
					fail("seed %d: slot %d does not fit %s" % [world, a, constraint])
			taken_first[a] = true
			taken_second[b] = true
	assert_eq(disagreed, 0, "the same seed and constraints gave the same slot, %d bindings over %d worlds" % [bindings, worlds])
	assert_eq(twice, 0, "no slot was ever bound twice")
	assert_eq(misfit, 0, "and every slot fit what was asked")
	assert_true(bound > bindings / 2, "and most contracts found somewhere (%d of %d)" % [bound, bindings])
