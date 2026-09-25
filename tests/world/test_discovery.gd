extends GcityTest

## M7 spec claim 15, discovery: the places the player has found are part of the save's
## overlay, and a contract that wants somewhere new (claim 8's `undiscovered`) is asked
## against them.

const SEED: int = 20261300
const M: int = 1000

var _sim: SimRoot
var _routes: RouteGraph
var _actors: ActorSystem
var _discovery: Discovery
var _player: int = 0


func _setup(db: ContentDb = null) -> void:
	if db == null:
		db = _db({})
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_routes = SimAssembly.routes_of(_sim)
	_actors = SimAssembly.actors_of(_sim)
	_discovery = SimAssembly.discovery_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, Vector3i(5_000 * M, 0, 5_000 * M))


func _db(extra: Dictionary) -> ContentDb:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	for key: Variant in extra:
		var id: String = key
		var entry: Dictionary = extra[key]
		assert_eq(db.add(QuestSystem.KIND_QUEST, StringName(id), entry), OK, "quest/%s" % id)
	return db


func _look() -> void:
	_sim.step()
	while _sim.get_tick() % Discovery.LOOK_EVERY != 0:
		_sim.step()


## Stands the player near a place, on the ground there: out in the wilds a player put
## down at the wrong height falls, and a long fall kills.
func _visit(node: int) -> void:
	var at: Vector2i = _routes.position_of(node)
	var x: int = at.x + 50 * M
	var y: int = SimAssembly.regions_of(_sim).standing_cell_y(x, at.y) * BuildSystem.CELL
	_actors.set_position(_player, Vector3i(x, y, at.y))
	_look()
	assert_true(_actors.is_alive(_player), "still standing after visiting node %d" % node)


func test_the_gate_is_known_and_places_are_found_by_going_there() -> void:
	_setup()
	assert_eq(_discovery.found_nodes(), [1] as Array[int], "only the gate to begin with")
	var place: int = _routes.slot_node(_routes.slot_ids()[0])
	assert_false(_discovery.is_found(place), "a place nobody has been")
	_visit(place)
	assert_true(_discovery.is_found(place), "is found by going there")
	assert_true(_discovery.found_slots().has(_routes.slot_ids()[0]), "and so is the slot it offers")
	_actors.set_position(_player, Vector3i(5_000 * M, 0, 5_000 * M))
	_sim.step_n(3 * Discovery.LOOK_EVERY)
	assert_true(_discovery.is_found(place), "and stays found when you leave")
	var far: int = _routes.node_ids()[_routes.node_count() - 1]
	var at: Vector2i = _routes.position_of(far)
	_actors.set_position(_player, Vector3i(at.x + Discovery.DISCOVER_MM + 10 * M, 0, at.y))
	_look()
	assert_false(_discovery.is_found(far), "passing just out of range finds nothing")


func test_only_a_living_player_finds_anything() -> void:
	_setup()
	var perception: PerceptionSystem = SimAssembly.perception_of(_sim)
	var place: int = _routes.slot_node(_routes.slot_ids()[1])
	var at: Vector2i = _routes.position_of(place)
	var cell: Vector3i = BuildSystem.cell_of(Vector3i(at.x, 0, at.y))
	perception.spawn(&"guard_sim", cell, 0, 1, "")
	_look()
	assert_false(_discovery.is_found(place), "a guard standing there has found nothing for you")
	_actors.set_position(_player, Vector3i(at.x, 0, at.y))
	_actors.damage_node(_player, &"body", 999999)
	_look()
	assert_false(_discovery.is_found(place), "nor has a player lying dead there")


## Claim 8's `undiscovered`, now that something discovers: a contract wanting somewhere
## new is never bound to a place the player has found.
func test_a_contract_wanting_somewhere_new_skips_what_you_have_found() -> void:
	var job: Dictionary = {
		"schema_version": 1, "title": "x", "description": "x", "text": "x",
		"objectives": [{"description": "x", "event": "terminal.hacked", "credit": "actor", "tags_any": [], "count": 1}],
		"reward": [],
		"site": {"tags_any": ["ruin"], "min_km": 0, "max_km": 100, "undiscovered": true},
	}
	_setup(_db({"somewhere_new": job}))
	var binder: SiteBinder = SimAssembly.binder_of(_sim)
	# keep one place of the world's own aside, find every slot well away from it, then
	# take the job. A town's streets are close together, so finding one finds its
	# neighbours; the place kept aside is a world node, which nothing else is near.
	var slots: Array[int] = _routes.slot_ids()
	var keep: int = EntityIds.NONE
	for slot: int in slots:
		if _routes.node_town(_routes.slot_node(slot)) == EntityIds.NONE:
			keep = slot
	var kept_at: Vector2i = _routes.slot_position(keep)
	for slot: int in slots:
		var at: Vector2i = _routes.position_of(_routes.slot_node(slot))
		if RouteGraph._length_mm(at.x, at.y, kept_at.x, kept_at.y) > Discovery.DISCOVER_MM * 2 + 100 * M:
			_visit(_routes.slot_node(slot))
	var left: Array[int] = []
	for slot: int in slots:
		if not _discovery.found_slots().has(slot):
			left.append(slot)
	assert_true(left.size() >= 1, "somewhere is still unfound (%s)" % [left])
	_actors.set_position(_player, Vector3i(5_000 * M, 0, 5_000 * M))
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, QuestSystem.COMMAND_ACCEPT, {"actor": _player, "quest": "somewhere_new"})), OK, "submit")
	_sim.step()
	assert_eq(_sim.dispatched_count(), before + 1, "the job is taken")
	assert_true(left.has(binder.slot_of(&"somewhere_new")), "and it is somewhere you have not been (%d)" % binder.slot_of(&"somewhere_new"))


func test_what_you_found_is_saved_and_a_bad_record_is_refused() -> void:
	_setup()
	_visit(_routes.slot_node(_routes.slot_ids()[0]))
	var snap: Dictionary = _sim.snapshot()
	var other: SimRoot = SimAssembly.build(SEED, _db({}))
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "restored")
	assert_eq(SimAssembly.discovery_of(other).found_nodes(), _discovery.found_nodes(), "with the same places found")
	var good: Dictionary = _discovery.snapshot()
	for bad: Dictionary in [{}, {"found": {}}, {"found": {1: 0, 99999: 4}}, {"found": {1: -1}}, {"found": {1: "0"}}, {"found": [1]}]:
		assert_eq(_discovery.restore(bad), ERR_INVALID_DATA, "refused: %s" % [bad])
		assert_eq(_discovery.snapshot(), good, "and nothing changed")
