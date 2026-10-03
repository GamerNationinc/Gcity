extends GcityTest

## M7.5 spec claim 1: a body is as many cells tall as its profile says, and every
## step, climb and level change asks about all of them. The shipped profiles are two
## cells since claim 6; these tests compare a one-cell and a two-cell profile of their
## own, added before the sim is assembled, so they test the rule and not the content.

const SEED: int = 20261310
const M: int = 1000
const FAR: Vector3i = Vector3i(400 * M, 0, 400 * M)
const TALL: StringName = &"tall_test"
const SHORT: StringName = &"short_test"

var _sim: SimRoot
var _actors: ActorSystem
var _movement: MovementSystem
var _build: BuildSystem
var _short: int = 0
var _tall: int = 0


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var tall: Dictionary = db.get_entry(ActorSystem.KIND_PROFILE, &"arcade").duplicate(true)
	tall["body_cells"] = 2
	assert_eq(db.add(ActorSystem.KIND_PROFILE, TALL, tall), OK, "a two-cell profile")
	var short: Dictionary = db.get_entry(ActorSystem.KIND_PROFILE, &"arcade").duplicate(true)
	short["body_cells"] = 1
	assert_eq(db.add(ActorSystem.KIND_PROFILE, SHORT, short), OK, "a one-cell profile")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_movement = SimAssembly.movement_of(_sim)
	_build = SimAssembly.build_of(_sim)
	_short = _actors.spawn(SHORT, 0)
	_tall = _actors.spawn(TALL, 0)


func _at(cx: int, cy: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, cy * M, cz * M + 500)


## Walks `actor` toward one neighbouring cell at its own pace; true when it got there.
func _walk(actor: int, dx: int, dz: int) -> bool:
	var start: Vector3i = BuildSystem.cell_of(_actors.position_of(actor))
	var speed: int = _movement.speed_of(actor)
	for i: int in 20:
		if not _movement.move(actor, dx * speed, dz * speed):
			return false
		if BuildSystem.cell_of(_actors.position_of(actor)) != start:
			return BuildSystem.cell_of(_actors.position_of(actor)) == start + Vector3i(dx, 0, dz)
	return false


## A roof one metre up over two cells running north, (1, 0, 4) and (1, 0, 5), held by a
## foundation beside the first; open to the sky at (1, 0, 3), south of it. Since claim 6
## no shipped building has a one-metre roof, so the tests build their own.
func _low_roof() -> Vector3i:
	assert_true(_build.place(_short, &"foundation_block", _at(0, 0, 4), "") > 0, "a foundation")
	assert_true(_build.place(_short, &"floor_panel", _at(1, 0, 4), "py") > 0, "a roof a metre up")
	assert_true(_build.place(_short, &"floor_panel", _at(1, 0, 5), "py") > 0, "and the next one along")
	return BuildSystem.cell_of(_at(1, 0, 3))


## A wall at head height over an open cell at the feet: a foundation on the ground at
## z = -2, a wall beside it, one over that, and the lintel, a wall one row up between
## x = 0 and x = 1 at z = 0. The ground row under the lintel is open.
func _lintel() -> void:
	assert_true(_build.place(_short, &"foundation_block", _at(0, 0, -2), "") > 0, "foundation")
	assert_true(_build.place(_short, &"wall_panel", _at(0, 0, -1), "px") > 0, "a wall on the ground")
	assert_true(_build.place(_short, &"wall_panel", _at(0, 1, -1), "px") > 0, "a wall over it")
	assert_true(_build.place(_short, &"wall_panel", _at(0, 1, 0), "px") > 0, "the lintel")


func test_the_body_is_read_from_the_profile() -> void:
	_setup()
	assert_eq(_movement.body_cells(_short), 1, "a one-cell profile is one cell")
	assert_eq(_movement.body_cells(_actors.spawn(&"arcade", 0)), 2, "the shipped profiles are two cells (claim 6)")
	assert_eq(_movement.body_cells(_tall), 2, "a two-cell profile is two cells")
	assert_eq(_movement.body_cells(9999), 1, "an unknown actor is one cell")


func test_a_wall_at_head_height_stops_a_tall_body_and_not_a_short_one() -> void:
	_setup()
	_lintel()
	_actors.set_position(_short, _at(0, 0, 0))
	_actors.set_position(_tall, _at(0, 0, 0))
	assert_true(_walk(_short, 1, 0), "a one-cell body walks under the lintel")
	var blocked: int = _movement.blocked_count()
	assert_false(_walk(_tall, 1, 0), "a two-cell body does not")
	assert_true(_movement.blocked_count() > blocked, "and it is counted as blocked")
	assert_eq(BuildSystem.cell_of(_actors.position_of(_tall)), BuildSystem.cell_of(_at(0, 0, 0)), "it stayed where it was")
	assert_true(_walk(_tall, 0, 1), "a step that crosses no wall at either height is fine")


func test_a_solid_floor_between_the_body_cells_is_no_place_for_a_tall_body() -> void:
	_setup()
	# open to the sky at the mouth, roofed one metre up from the next cell in
	var outside: Vector3i = _low_roof()
	var lobby: Vector3i = outside + Vector3i(0, 0, 1)
	assert_true(_movement.body_fits(outside, 2), "the open mouth fits a two-cell body")
	assert_false(_movement.body_fits(lobby, 2), "the passage under its one-metre roof does not")
	assert_true(_movement.body_fits(lobby, 1), "it fits a one-cell body")
	var centre: Vector3i = Vector3i(outside.x * M + 500, outside.y * M, outside.z * M + 500)
	_actors.set_position(_short, centre)
	_actors.set_position(_tall, centre)
	assert_true(_walk(_short, 0, 1), "a one-cell body goes in under the roof")
	assert_false(_walk(_tall, 0, 1), "a two-cell body cannot")


func test_a_body_put_where_it_does_not_fit_can_walk_out_but_not_further_in() -> void:
	_setup()
	var corridor: Vector3i = _low_roof() + Vector3i(0, 0, 1)
	_actors.set_position(_tall, Vector3i(corridor.x * M + 500, corridor.y * M, corridor.z * M + 500))
	assert_false(_walk(_tall, 0, 1), "further in, under the roof: refused")
	assert_true(_walk(_tall, 0, -1), "out to the open sky: allowed")


func test_a_one_cell_body_moves_exactly_as_before_and_the_rule_is_the_same_for_both_heights() -> void:
	_setup()
	_lintel()
	for cell: Vector3i in [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, -2), Vector3i(5, 0, 5)]:
		var at: Vector3i = BuildSystem.cell_of(_at(cell.x, cell.y, cell.z))
		var one: bool = _build.cell_piece_at(at) == EntityIds.NONE
		assert_eq(_movement.body_fits(at, 1), one, "a one-cell body fits wherever its cell is free (%s)" % cell)
		assert_eq(_movement.body_fits(at, 2), one and _movement.body_fits(at + Vector3i(0, 1, 0), 1),
			"a two-cell body needs its upper cell free too (%s)" % cell)


func test_pathing_asks_the_same_body_question() -> void:
	_setup()
	_lintel()
	var pathing: PathingSystem = SimAssembly.pathing_of(_sim)
	var a: Vector3i = BuildSystem.cell_of(_at(0, 0, 0))
	var b: Vector3i = BuildSystem.cell_of(_at(1, 0, 0))
	assert_true(pathing.can_step(a, b, 1), "a one-cell agent may plan under the lintel")
	assert_false(pathing.can_step(a, b, 2), "a two-cell agent may not")
	assert_true(pathing.can_step(a, a + Vector3i(0, 0, 1), 2), "nor is it stopped where nothing is in the way")


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


## M7.5 spec claim 2: filling ground in never closes on a body, at any of its rows.
func test_filling_ground_never_closes_on_a_head() -> void:
	_setup()
	var regions: Regions = SimAssembly.regions_of(_sim)
	# the level apron outside the gate (M7's dig test): ground at y -1, air from y 0 up
	for pair: Array in [[_tall, 0], [_short, 3]]:
		var actor: int = pair[0]
		var x: int = pair[1]
		_actors.set_position(actor, Vector3i(x * M + 500, 0, -40_500))
		var under: Vector3i = Vector3i(x, -1, -41)
		assert_true(_do(Regions.COMMAND_DIG, {"actor": actor, "cell": [under.x, under.y, under.z]}), "dig under the feet")
		_sim.step_n(2)
		assert_eq(BuildSystem.cell_of(_actors.position_of(actor)).y, -1, "and drop a level")
	var tall_head: Vector3i = Vector3i(0, 0, -41)
	var short_above: Vector3i = Vector3i(3, 0, -41)
	assert_false(_do(Regions.COMMAND_FILL, {"actor": _tall, "cell": [tall_head.x, tall_head.y, tall_head.z]}), "the cell a tall body's head is in cannot be filled")
	assert_false(regions.is_solid(tall_head), "it is still air")
	assert_true(_do(Regions.COMMAND_FILL, {"actor": _short, "cell": [short_above.x, short_above.y, short_above.z]}), "the cell over a one-cell body can (by itself, within reach)")


## M7.5 spec claim 2: building never puts a piece in a body or a solid floor through it.
func test_building_never_closes_on_a_body() -> void:
	_setup()
	_actors.set_position(_tall, _at(2, 0, 2))
	_actors.set_position(_short, _at(5, 0, 2))
	assert_true(_build.place(_short, &"foundation_block", _at(2, 0, 1), "") > 0, "a foundation beside the tall body")
	assert_eq(_build.place(_short, &"foundation_block", _at(2, 0, 2), ""), EntityIds.NONE, "not on its feet")
	assert_true(_build.would_enclose_a_body(&"floor_panel", BuildSystem.cell_of(_at(2, 0, 2)), "py"), "a solid floor at one metre would cut through it")
	assert_eq(_build.place(_short, &"floor_panel", _at(2, 0, 2), "py"), EntityIds.NONE, "so it is refused")
	assert_false(_build.would_enclose_a_body(&"roof_hatch", BuildSystem.cell_of(_at(2, 0, 2)), "py"), "a hatch is passable and would not")
	assert_false(_build.would_enclose_a_body(&"floor_panel", BuildSystem.cell_of(_at(2, 1, 2)), "py"), "a floor at two metres is over its head")
	assert_false(_build.would_enclose_a_body(&"wall_panel", BuildSystem.cell_of(_at(2, 0, 2)), "px"), "a wall stands between cells")
	assert_true(_build.would_enclose_a_body(&"foundation_block", BuildSystem.cell_of(_at(5, 0, 2)), ""), "a one-cell body's own cell is refused too")
	assert_false(_build.would_enclose_a_body(&"foundation_block", BuildSystem.cell_of(_at(5, 1, 2)), ""), "but not the cell over it")
