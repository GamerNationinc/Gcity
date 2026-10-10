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


func test_no_cell_piece_is_placed_where_a_living_actor_stands() -> void:
	_setup()
	var actors: ActorSystem = SimAssembly.actors_of(_sim)
	assert_eq(actors.set_position(_player, _at(2, 0, 0) - Vector3i(0, 500, 0)), OK, "player on the ground")
	assert_eq(_build.place(_player, &"foundation_block", _at(2, 0, 0), ""), EntityIds.NONE, "not on the player")
	assert_true(_build.place(_player, &"foundation_block", _at(3, 0, 0), "") > 0, "beside the player")


func test_the_piece_a_living_actor_stands_on_can_be_removed() -> void:
	# ADR-011 C: a removal under an actor is not refused; the actor falls (sim/agents)
	_setup()
	var actors: ActorSystem = SimAssembly.actors_of(_sim)
	var f: int = _build.place(_player, &"foundation_block", _at(0, 0, 0), "")
	var floor_id: int = _build.place(_player, &"floor_panel", _at(1, 0, 0), "py")
	assert_true(f > 0 and floor_id > 0, "foundation and floor")
	assert_eq(actors.set_position(_player, _at(1, 1, 0) - Vector3i(0, 500, 0)), OK, "player on the floor")
	assert_eq(_build.remove(_player, floor_id), [floor_id] as Array[int], "the floor comes out from under the player")
	assert_false(_build.is_standable(_cell(1, 1, 0)), "leaving nothing to stand on")


func test_storey_minus_one_is_earth_until_excavated() -> void:
	# M6 claim 6 (as built): no terrain and no dig before M7; a site excavates its tunnels
	_setup()
	assert_true(_build.is_solid(_cell(0, -1, 0)), "earth under the street")
	assert_false(_build.is_standable(_cell(0, -1, 0)), "nobody stands inside it")
	assert_eq(_build.place(_player, &"storage_crate", _at(0, -1, 0), ""), EntityIds.NONE, "nor builds into it")
	assert_eq(_build.excavate([_cell(0, -1, 0), _cell(1, -1, 0)] as Array[Vector3i]), OK, "a tunnel dug")
	assert_false(_build.is_solid(_cell(0, -1, 0)), "air now")
	assert_true(_build.is_standable(_cell(0, -1, 0)), "on bedrock")
	assert_false(_build.is_solid(_cell(0, 0, 0)), "the ground storey is air")
	assert_eq(_build.excavate([_cell(0, 0, 0)] as Array[Vector3i]), ERR_INVALID_PARAMETER, "only the basement storey is dug")
	assert_false(_build.is_standable(_cell(0, -2, 0)), "nothing below the storey range")


func test_excavation_survives_a_restore_and_bad_cells_are_rejected() -> void:
	_setup()
	assert_eq(_build.excavate([_cell(3, -1, 3)] as Array[Vector3i]), OK, "dug")
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var other: BuildSystem = SimAssembly.build_of(SimAssembly.build(SEED, db))
	assert_eq(other.restore(_build.snapshot()), OK, "restores")
	assert_false(other.is_solid(_cell(3, -1, 3)), "still dug")
	var bad: Dictionary = _build.snapshot().duplicate(true)
	bad["excavated"] = ["0,0,0"]
	assert_eq(other.restore(bad), ERR_INVALID_DATA, "a ground-storey cell is not excavation")


func test_a_stair_is_a_cell_piece_placed_with_the_facing_of_its_foot() -> void:
	_setup()
	assert_true(_build.place(_player, &"foundation_block", _at(-1, 0, 0), "") > 0, "a foundation to hold it")
	assert_eq(_build.place(_player, &"stair_steel", _at(0, 0, 0), ""), EntityIds.NONE, "a stair needs a facing")
	assert_eq(_build.place(_player, &"stair_steel", _at(0, 0, 0), "py"), EntityIds.NONE, "and a level one")
	var stair: int = _build.place(_player, &"stair_steel", _at(0, 0, 0), "px")
	assert_true(stair > 0, "placed, foot to the east")
	assert_eq(_build.facing_of(stair), "px", "the facing is kept")
	assert_eq(_build.climb_ticks_of(stair), 20, "climbable, at the kind's ticks")
	assert_true(_build.is_standable(_cell(0, 1, 0)), "its top is standable")
	assert_eq(_build.place(_player, &"foundation_block", _at(2, 0, 0), "px"), EntityIds.NONE, "a foundation takes no facing")


func test_a_ladder_is_a_climbable_horizontal_opening_and_crates_can_be_mantled() -> void:
	_setup()
	assert_true(_build.place(_player, &"foundation_block", _at(0, 0, 0), "") > 0, "foundation")
	var ladder: int = _build.place(_player, &"ladder_hatch", _at(1, 0, 0), "py")
	assert_true(ladder > 0, "a ladder through the floor of storey 1")
	assert_eq(_build.climb_ticks_of(ladder), 30, "climbable")
	assert_true(_build.is_standable(_cell(1, 1, 0)), "standing on the ladder's top")
	assert_true(_build.place(_player, &"foundation_block", _at(4, 0, 0), "") > 0, "a foundation for the crate")
	var crate: int = _build.place(_player, &"storage_crate", _at(3, 0, 0), "")
	assert_true(_build.is_mantleable(crate), "a crate can be mantled")
	assert_false(_build.is_mantleable(_build.cell_piece_at(_cell(0, 0, 0))), "a foundation cannot")
	assert_eq(_build.climb_ticks_of(crate), 0, "and a crate is not climbed")


func test_a_restored_stair_keeps_its_facing() -> void:
	_setup()
	assert_true(_build.place(_player, &"foundation_block", _at(-1, 0, 0), "") > 0, "a foundation to hold it")
	var stair: int = _build.place(_player, &"stair_steel", _at(0, 0, 0), "nz")
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.build_of(other).restore(_build.snapshot()), OK, "restores")
	assert_eq(SimAssembly.build_of(other).facing_of(stair), "nz", "facing survives")
	var bad: Dictionary = _build.snapshot().duplicate(true)
	var pieces: Dictionary = bad["pieces"]
	var rec: Dictionary = pieces[stair]
	rec["facing"] = "py"
	assert_eq(SimAssembly.build_of(other).restore(bad), ERR_INVALID_DATA, "a level stair is rejected")


func test_the_uncut_ground_face_blocks_sight_and_passage_and_a_hole_does_not() -> void:
	_setup()
	assert_eq(_build.excavate([_cell(0, -1, 0), _cell(1, -1, 0)] as Array[Vector3i]), OK, "a tunnel")
	var ground: String = BuildSystem.face_key(_cell(0, 0, 0), "ny")
	assert_true(_build.blocks_sight(ground) and _build.blocks_passage(ground), "solid ground over the tunnel")
	assert_true(_build.place(_player, &"foundation_block", _at(2, 0, 0), "") > 0, "foundation")
	var grate: int = _build.place(_player, &"street_grate", _at(1, -1, 0), "py")
	assert_true(grate > 0, "a grate over the tunnel")
	var grate_face: String = BuildSystem.face_key(_cell(1, 0, 0), "ny")
	assert_true(_build.blocks_sight(grate_face), "a closed grate is opaque")
	assert_false(_build.breach(grate).is_empty(), "cut")
	assert_false(_build.blocks_sight(grate_face) or _build.blocks_passage(grate_face), "the hole lets both through")
	var side: String = BuildSystem.face_key(_cell(0, 0, 0), "px")
	assert_false(_build.blocks_sight(side), "a bare face above ground blocks nothing")
