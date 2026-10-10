extends GcityTest

## M6 claim 6 in the agents: earth is solid. Nobody walks into unexcavated earth from a
## tunnel, and nobody sees through uncut ground; a cut in it lets sight through.

const SEED: int = 20261019
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)

var _sim: SimRoot
var _build: BuildSystem
var _actors: ActorSystem
var _movement: MovementSystem
var _perception: PerceptionSystem
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
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, _feet(6, 0, 6))


func _feet(cx: int, storey: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, storey * BuildSystem.STOREY_MM, cz * M + 500)


func _cell(cx: int, cy: int, cz: int) -> Vector3i:
	return BuildSystem.cell_of(FAR + Vector3i(cx * M + 500, cy * M + 500, cz * M + 500))


func test_a_tunnel_is_walked_but_its_earth_walls_are_not() -> void:
	_setup()
	assert_eq(_build.excavate([_cell(0, -1, 0), _cell(1, -1, 0), _cell(2, -1, 0)] as Array[Vector3i]), OK, "a tunnel east-west")
	_actors.set_position(_player, _feet(0, -1, 0))
	for i: int in 20:
		_movement.move(_player, 150, 0)
	assert_eq(BuildSystem.cell_of(_actors.position_of(_player)), _cell(2, -1, 0), "to the tunnel's end and no further")
	for i: int in 10:
		_movement.move(_player, 0, 150)
	assert_eq(BuildSystem.cell_of(_actors.position_of(_player)), _cell(2, -1, 0), "nor into its side")


func test_nobody_sees_through_the_ground_but_does_through_a_cut() -> void:
	_setup()
	assert_eq(_build.excavate([_cell(0, -1, 0)] as Array[Vector3i]), OK, "a shaft")
	var below: Vector3i = _feet(0, -1, 0) + Vector3i(0, 500, 0)
	var above: Vector3i = _feet(0, 1, 0) + Vector3i(0, 500, 0)
	assert_false(_perception.line_of_sight(below, above), "straight up through the ground: no")
	assert_true(_build.place(_player, &"foundation_block", FAR + Vector3i(1500, 500, 500), "") > 0, "foundation")
	var grate: int = _build.place(_player, &"street_grate", FAR + Vector3i(500, -500, 500), "py")
	assert_true(grate > 0, "a grate over the shaft")
	assert_false(_perception.line_of_sight(below, above), "nor through the closed grate")
	assert_false(_build.breach(grate).is_empty(), "cut")
	assert_true(_perception.line_of_sight(below, above), "through the hole: yes")
