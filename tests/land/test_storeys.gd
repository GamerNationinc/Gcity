extends GcityTest

## M6 spec claim 1: a storey is one build cell; an actor stands on the ground at
## storey 0, on a horizontal face piece under its cell, or on a cell piece below it.

const SEED: int = 20261008
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)

var _sim: SimRoot
var _build: BuildSystem
var _player: int = 0


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_build = SimAssembly.build_of(_sim)
	_player = SimAssembly.actors_of(_sim).spawn(&"arcade", 0)


func _at(cx: int, cy: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, cy * M + 500, cz * M + 500)


func _cell(cx: int, cy: int, cz: int) -> Vector3i:
	return BuildSystem.cell_of(_at(cx, cy, cz))


func test_a_storey_is_one_build_cell() -> void:
	assert_eq(BuildSystem.STOREY_MM, BuildSystem.CELL, "storey height")
	assert_eq(BuildSystem.storey_of(Vector3i(0, 0, 0)), 0, "ground")
	assert_eq(BuildSystem.storey_of(Vector3i(0, 999, 0)), 0, "within the ground storey")
	assert_eq(BuildSystem.storey_of(Vector3i(0, 1000, 0)), 1, "first floor")
	assert_eq(BuildSystem.storey_of(Vector3i(0, -1, 0)), -1, "basement")
	assert_true(BuildSystem.is_storey_in_range(-1) and BuildSystem.is_storey_in_range(2), "range ends")
	assert_false(BuildSystem.is_storey_in_range(-2) or BuildSystem.is_storey_in_range(3), "outside the range")


func test_the_ground_storey_stands_on_the_ground() -> void:
	_setup()
	assert_true(_build.is_standable(_cell(0, 0, 0)), "bare ground")
	assert_false(_build.is_standable(_cell(0, 1, 0)), "air above bare ground")
	assert_false(_build.is_standable(_cell(0, -1, 0)), "nothing under a basement cell")


func test_a_floor_face_under_the_cell_is_standable() -> void:
	_setup()
	assert_true(_build.place(_player, &"foundation_block", _at(0, 0, 0), "") > 0, "foundation")
	assert_true(_build.place(_player, &"floor_panel", _at(1, 0, 0), "py") > 0, "floor over the neighbour")
	assert_true(_build.is_standable(_cell(1, 1, 0)), "on the floor panel")
	assert_true(_build.place(_player, &"roof_hatch", _at(0, 0, 1), "py") > 0, "hatch")
	assert_true(_build.is_standable(_cell(0, 1, 1)), "on a closed hatch")


func test_a_cell_piece_below_is_standable_and_an_occupied_cell_is_not() -> void:
	_setup()
	assert_true(_build.place(_player, &"foundation_block", _at(0, 0, 0), "") > 0, "foundation")
	assert_true(_build.is_standable(_cell(0, 1, 0)), "on top of the foundation")
	assert_false(_build.is_standable(_cell(0, 0, 0)), "inside the foundation")
	assert_true(_build.place(_player, &"storage_crate", _at(0, 1, 0), "") > 0, "crate on the foundation")
	assert_true(_build.is_standable(_cell(0, 2, 0)), "on top of the crate")
	assert_false(_build.is_standable(_cell(0, 3, 0)), "above the top storey")


func test_a_wall_face_does_not_hold_anyone_up() -> void:
	_setup()
	assert_true(_build.place(_player, &"foundation_block", _at(0, 0, 0), "") > 0, "foundation")
	assert_true(_build.place(_player, &"wall_panel", _at(0, 1, 0), "px") > 0, "wall")
	assert_false(_build.is_standable(_cell(1, 1, 0)), "beside the wall, in the air")
