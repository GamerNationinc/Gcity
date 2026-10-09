extends GcityTest

## M6 spec claim 3 in the agents: a closed opening stops movement and pathing; a closed
## door, hatch or grate stops sight, a window never does (G4 debt 5), and an open
## opening stops neither.

const SEED: int = 20261016
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)

var _sim: SimRoot
var _build: BuildSystem
var _actors: ActorSystem
var _movement: MovementSystem
var _perception: PerceptionSystem
var _pathing: PathingSystem
var _player: int = 0


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_build = SimAssembly.build_of(_sim)
	_actors = SimAssembly.actors_of(_sim)
	_movement = SimAssembly.movement_of(_sim)
	_perception = SimAssembly.perception_of(_sim)
	_pathing = SimAssembly.pathing_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, _feet(6, 6))


func _feet(cx: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, 0, cz * M + 500)


func _at(cx: int, cy: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, cy * M + 500, cz * M + 500)


## A piece in the face between (0, 0, 0) and (1, 0, 0), held up by a foundation north.
func _between(piece: StringName) -> int:
	assert_true(_build.place(_player, &"foundation_block", _at(0, 0, 1), "") > 0, "foundation")
	var id: int = _build.place(_player, piece, _at(0, 0, 0), "px")
	assert_true(id > 0, piece)
	return id


func _walk_east(steps: int) -> void:
	for i: int in steps:
		_movement.move(_player, 150, 0)


func test_a_closed_door_stops_a_step_and_an_open_one_does_not() -> void:
	_setup()
	var door: int = _between(&"door_frame")
	_actors.set_position(_player, _feet(0, 0))
	assert_true(_build.set_open(_player, door, false), "closed")
	_walk_east(10)
	assert_eq(BuildSystem.cell_of(_actors.position_of(_player)), BuildSystem.cell_of(_feet(0, 0)), "stopped by the closed door")
	assert_false(_pathing.can_step(BuildSystem.cell_of(_feet(0, 0)), BuildSystem.cell_of(_feet(1, 0))), "pathing agrees")
	assert_true(_build.set_open(_player, door, true), "opened")
	_walk_east(10)
	assert_true(BuildSystem.cell_of(_actors.position_of(_player)).x >= BuildSystem.cell_of(_feet(1, 0)).x, "through the open door")
	assert_true(_pathing.can_step(BuildSystem.cell_of(_feet(0, 0)), BuildSystem.cell_of(_feet(1, 0))), "pathing agrees")


func test_a_closed_window_stops_bodies_but_not_sight() -> void:
	_setup()
	var window: int = _between(&"window_frame")
	assert_false(_build.is_open(window), "closed")
	_actors.set_position(_player, _feet(0, 0))
	_walk_east(10)
	assert_eq(BuildSystem.cell_of(_actors.position_of(_player)), BuildSystem.cell_of(_feet(0, 0)), "no climbing through a closed window")
	assert_true(_perception.line_of_sight(_feet(0, 0) + Vector3i(0, 500, 0), _feet(3, 0) + Vector3i(0, 500, 0)), "seen through it")


func test_a_closed_door_stops_sight_and_an_open_one_does_not() -> void:
	_setup()
	var door: int = _between(&"door_frame")
	var a: Vector3i = _feet(0, 0) + Vector3i(0, 500, 0)
	var b: Vector3i = _feet(3, 0) + Vector3i(0, 500, 0)
	assert_true(_perception.line_of_sight(a, b), "an open doorway is seen through")
	_actors.set_position(_player, _feet(0, 0))
	assert_true(_build.set_open(_player, door, false), "closed")
	assert_false(_perception.line_of_sight(a, b), "a closed door is not")
