extends GcityTest

## M6 claim 6 in pathing: a guard plans across storeys through stairs and ladders when
## its profile has the `climb` move, climbs them on the way, and never plans a step onto
## a cell nobody can stand in. Metamorphic relation (the spec's, corrected): removing a
## wall never lengthens the shortest path between two cells that were already joined.

const SEED: int = 20261021
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)
const RELATION_CASES: int = 200
const SEED_RELATION: int = 20261022

var _sim: SimRoot
var _build: BuildSystem
var _actors: ActorSystem
var _perception: PerceptionSystem
var _pathing: PathingSystem
var _player: int = 0


func _setup(db: ContentDb = null) -> void:
	if db == null:
		db = ContentDb.new()
		assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_build = SimAssembly.build_of(_sim)
	_actors = SimAssembly.actors_of(_sim)
	_perception = SimAssembly.perception_of(_sim)
	_pathing = SimAssembly.pathing_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, FAR + Vector3i(-20 * M, 0, -20 * M))


func _cell(cx: int, cy: int, cz: int) -> Vector3i:
	return BuildSystem.cell_of(FAR + Vector3i(cx * M + 500, cy * M + 500, cz * M + 500))


func _at(cx: int, cy: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, cy * M + 500, cz * M + 500)


## A stair at x 1 (foot at x 0) up to a storey-1 deck over x 2..3.
func _stair_and_deck() -> void:
	assert_true(_build.place(_player, &"foundation_block", _at(4, 0, 0), "") > 0, "foundation")
	assert_true(_build.place(_player, &"floor_panel", _at(3, 0, 0), "py") > 0, "deck east")
	assert_true(_build.place(_player, &"floor_panel", _at(2, 0, 0), "py") > 0, "deck west")
	assert_true(_build.place(_player, &"stair_steel", _at(1, 0, 0), "nx") > 0, "stair")


func _walk_until(agent: int, state: String, limit: int) -> int:
	for i: int in limit:
		_sim.step()
		if _pathing.state_of(agent) == state:
			return i
	return -1


func test_a_guard_climbs_a_stair_to_a_goal_on_the_deck() -> void:
	_setup()
	_stair_and_deck()
	var guard: int = _perception.spawn(&"guard_mute", _cell(-3, 0, 0), 0, 1, "")
	assert_true(guard > 0, "a guard on the ground")
	assert_true(_pathing.request(guard, _cell(3, 1, 0)), "sent to the deck")
	assert_true(_walk_until(guard, PathingSystem.STATE_ARRIVED, 600) >= 0, "arrived")
	assert_eq(BuildSystem.cell_of(_actors.position_of(guard)), _cell(3, 1, 0), "on the deck")
	assert_true(_pathing.request(guard, _cell(-3, 0, 0)), "and back down")
	assert_true(_walk_until(guard, PathingSystem.STATE_ARRIVED, 600) >= 0, "arrived")
	assert_eq(BuildSystem.cell_of(_actors.position_of(guard)), _cell(-3, 0, 0), "on the ground")


func test_a_guard_without_the_climb_move_never_plans_a_climb() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	var body: Dictionary = db.get_entry(&"combat_profile", &"guard").duplicate(true)
	body["moves"] = ["walk"]
	assert_eq(db.add(&"combat_profile", &"zz_flat_guard", body), OK, "a walk-only body")
	var agent: Dictionary = db.get_entry(&"agent_profile", &"guard_mute").duplicate(true)
	agent["combat_profile"] = "zz_flat_guard"
	assert_eq(db.add(&"agent_profile", &"zz_flat", agent), OK, "a walk-only guard")
	_setup(db)
	_stair_and_deck()
	var guard: int = _perception.spawn(&"zz_flat", _cell(-3, 0, 0), 0, 1, "")
	assert_true(_pathing.request(guard, _cell(3, 1, 0)), "sent to the deck")
	assert_true(_walk_until(guard, PathingSystem.STATE_FAILED, 200) >= 0, "no route without climbing")


func test_no_step_is_planned_off_an_edge() -> void:
	_setup()
	_stair_and_deck()
	assert_false(_pathing.can_step(_cell(3, 1, 0), _cell(4, 1, 0) + Vector3i(1, 0, 0)), "off the deck's end into air")
	assert_true(_pathing.can_step(_cell(2, 1, 0), _cell(3, 1, 0)), "along the deck")


func test_metamorphic_removing_a_wall_never_lengthens_the_shortest_path() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_RELATION
	var violations: int = 0
	var compared: int = 0
	for case: int in RELATION_CASES:
		_setup()
		# a row of foundations to hold walls, and random walls on the ground storey
		for x: int in range(-4, 5):
			_build.place(_player, &"foundation_block", _at(x, 0, 5), "")
		var walls: Array[int] = []
		for i: int in 14:
			var c: Vector3i = Vector3i(rng.randi_range(-4, 4), 0, rng.randi_range(0, 4))
			var facing: String = ["px", "nx", "pz", "nz"][rng.randi_range(0, 3)]
			var id: int = _build.place(_player, &"wall_panel", _at(c.x, 0, c.z), facing)
			if id > 0:
				walls.append(id)
		if walls.is_empty():
			continue
		var a: Vector3i = _cell(rng.randi_range(-4, 4), 0, rng.randi_range(0, 4))
		var b: Vector3i = _cell(rng.randi_range(-4, 4), 0, rng.randi_range(0, 4))
		var before: int = _shortest(a, b)
		if before < 0:
			continue
		_build.remove(_player, walls[rng.randi_range(0, walls.size() - 1)])
		var after: int = _shortest(a, b)
		compared += 1
		if after < 0 or after > before:
			violations += 1
	assert_eq(violations, 0, "never longer after a wall comes out (%d compared)" % compared)
	assert_true(compared > RELATION_CASES / 4, "enough joined pairs compared (%d)" % compared)


## The planned length from a to b for a guard placed at a, or -1 when unreachable.
func _shortest(a: Vector3i, b: Vector3i) -> int:
	var guard: int = _perception.spawn(&"guard_mute", a, 0, 1, "")
	if guard <= 0 or not _pathing.request(guard, b):
		return -1
	for i: int in 200:
		_sim.step()
		var st: String = _pathing.state_of(guard)
		if st == PathingSystem.STATE_FOLLOWING or st == PathingSystem.STATE_ARRIVED:
			var length: int = _pathing.path_of(guard).size()
			_actors.damage_node(guard, &"body", 1_000_000_000)
			_sim.step()
			return length
		if st == PathingSystem.STATE_FAILED:
			_actors.damage_node(guard, &"body", 1_000_000_000)
			_sim.step()
			return -1
	return -1
