extends GcityTest

## M6 spec claim 1 in movement: actors move in x/z on their storey and never onto a
## cell nobody can stand in; agents spawn only where they can stand. Property: over
## 10 000 generated build and move operations, every living actor stands on a
## standable cell after every one.

const SEED: int = 20261009
const PROPERTY_CASES: int = 10_000
const SEED_STREAM: int = 20261010
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)

var _sim: SimRoot
var _actors: ActorSystem
var _movement: MovementSystem
var _build: BuildSystem
var _player: int = 0


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_movement = SimAssembly.movement_of(_sim)
	_build = SimAssembly.build_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, _feet(0, 0, 0))


## The centre of a cell at floor level: where an actor on that storey stands.
func _feet(cx: int, storey: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, storey * BuildSystem.STOREY_MM, cz * M + 500)


func _at(cx: int, cy: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, cy * M + 500, cz * M + 500)


## A 3×1 deck on storey 1 over x 1..3, z 0: foundations at its ends, floors between.
func _deck() -> void:
	assert_true(_build.place(_player, &"foundation_block", _at(1, 0, 0), "") > 0, "west foundation")
	assert_true(_build.place(_player, &"foundation_block", _at(3, 0, 0), "") > 0, "east foundation")
	assert_true(_build.place(_player, &"floor_panel", _at(2, 0, 0), "py") > 0, "floor between")


func test_an_actor_on_a_deck_cannot_step_off_its_edge() -> void:
	_setup()
	_deck()
	assert_eq(_actors.set_position(_player, _feet(2, 1, 0)), OK, "on the deck")
	assert_true(_movement.move(_player, 150, 0), "along the deck, same cell")
	for i: int in 6:
		_movement.move(_player, 150, 0)
	assert_eq(BuildSystem.cell_of(_actors.position_of(_player)), BuildSystem.cell_of(_feet(3, 1, 0)), "onto the east foundation's top")
	for i: int in 10:
		_movement.move(_player, 150, 0)
	assert_eq(BuildSystem.cell_of(_actors.position_of(_player)), BuildSystem.cell_of(_feet(3, 1, 0)), "never into the air past it")
	assert_false(_movement.move(_player, 0, -150 * 4 + 1), "nor off the side")


func test_on_the_ground_movement_is_unchanged() -> void:
	_setup()
	for i: int in 10:
		assert_true(_movement.move(_player, 150, 0), "ground step %d" % i)
	assert_eq(_actors.position_of(_player), _feet(0, 0, 0) + Vector3i(1500, 0, 0), "1.5 m along the ground")


func test_agents_spawn_only_where_they_can_stand() -> void:
	_setup()
	_deck()
	var perception: PerceptionSystem = SimAssembly.perception_of(_sim)
	var on_deck: int = perception.spawn(&"guard_sim", BuildSystem.cell_of(_feet(2, 1, 0)), 0, 1, "")
	assert_true(on_deck > 0, "a guard on the deck")
	assert_eq(BuildSystem.storey_of(_actors.position_of(on_deck)), 1, "at storey 1")
	assert_eq(perception.spawn(&"guard_sim", BuildSystem.cell_of(_feet(5, 1, 0)), 0, 1, ""), EntityIds.NONE, "not in the air")
	assert_eq(perception.spawn(&"guard_sim", BuildSystem.cell_of(_feet(1, 0, 0)), 0, 1, ""), EntityIds.NONE, "not inside a foundation")


func test_property_every_living_actor_always_stands_on_a_standable_cell() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_STREAM
	_setup()
	_deck()
	var guard: int = SimAssembly.perception_of(_sim).spawn(&"guard_sim", BuildSystem.cell_of(_feet(2, 1, 0)), 0, 1, "")
	assert_true(guard > 0, "a guard on the deck")
	var movers: Array[int] = [_player, guard]
	var templates: Array[StringName] = [&"foundation_block", &"storage_crate", &"floor_panel", &"wall_panel"]
	var failures: int = 0
	var accepted_moves: int = 0
	for case: int in PROPERTY_CASES:
		var op: int = rng.randi_range(0, 9)
		if op < 6:
			var who: int = movers[rng.randi_range(0, 1)]
			var cap: int = _movement.speed_of(who)
			if _movement.move(who, rng.randi_range(-cap, cap), rng.randi_range(-cap, cap)):
				accepted_moves += 1
		elif op < 9:
			var template: StringName = templates[rng.randi_range(0, templates.size() - 1)]
			var cell: Vector3i = Vector3i(rng.randi_range(-2, 6), rng.randi_range(0, 2), rng.randi_range(-3, 3))
			var facing: String = ""
			if template == &"floor_panel":
				facing = "py"
			elif template == &"wall_panel":
				facing = ["px", "nx", "pz", "nz"][rng.randi_range(0, 3)]
			_build.place(_player, template, _at(cell.x, cell.y, cell.z), facing)
		else:
			var ids: Array[int] = _build.piece_ids()
			if not ids.is_empty():
				_build.remove(_player, ids[rng.randi_range(0, ids.size() - 1)])
		for a: int in movers:
			if _actors.is_alive(a) and not _build.is_standable(BuildSystem.cell_of(_actors.position_of(a))):
				failures += 1
	assert_eq(failures, 0, "every living actor on a standable cell after every operation")
	assert_true(accepted_moves > PROPERTY_CASES / 10, "the stream moved actors (%d moves)" % accepted_moves)
