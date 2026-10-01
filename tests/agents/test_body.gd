extends GcityTest

## M7.5 spec claim 1: a body is as many cells tall as its profile says, and every
## step, climb and level change asks about all of them. The shipped profiles are one
## cell until the sites are rebuilt (claim 6); these tests use a two-cell profile of
## their own, added before the sim is assembled.

const SEED: int = 20261310
const M: int = 1000
const FAR: Vector3i = Vector3i(400 * M, 0, 400 * M)
const TALL: StringName = &"tall_test"

var _sim: SimRoot
var _actors: ActorSystem
var _movement: MovementSystem
var _build: BuildSystem
var _sites: SiteSystem
var _short: int = 0
var _tall: int = 0


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var tall: Dictionary = db.get_entry(ActorSystem.KIND_PROFILE, &"arcade").duplicate(true)
	tall["body_cells"] = 2
	assert_eq(db.add(ActorSystem.KIND_PROFILE, TALL, tall), OK, "a two-cell profile")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_movement = SimAssembly.movement_of(_sim)
	_build = SimAssembly.build_of(_sim)
	_sites = SimAssembly.sites_of(_sim)
	_short = _actors.spawn(&"arcade", 0)
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


## The M4 building, on the plots it stands on, the builder owning them as the client
## arranges it: without them every piece but the first is refused.
func _raise_m4() -> void:
	var at: int = _sim.get_tick() + 1
	_sim.submit(SimCommand.new(at, &"land.identify", {"actor": _short, "owner": "player"}))
	for parcel: String in ["starter_plot", "neighbour_north"]:
		_sim.submit(SimCommand.new(at, &"land.transfer", {"parcel": parcel, "owner": "player"}))
	_sim.step()
	assert_true(_sites.raise_site(_short, &"m4_test_building"), "raised")
	assert_eq(_sites.pieces_of(&"m4_test_building").size(), 93, "every piece of it")


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
	assert_eq(_movement.body_cells(_short), 1, "the shipped profiles are one cell until the sites are rebuilt")
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
	# the M4 building: the lobby is open to the sky, and the corridor running back from it
	# at x = 4 is roofed one metre up from z = 4
	_raise_m4()
	var outside: Vector3i = _sites.cell_of(&"m4_test_building", Vector3i(4, 0, 3))
	var lobby: Vector3i = outside + Vector3i(0, 0, 1)
	assert_true(_movement.body_fits(outside, 2), "the open lobby fits a two-cell body")
	assert_false(_movement.body_fits(lobby, 2), "the corridor under its one-metre roof does not")
	assert_true(_movement.body_fits(lobby, 1), "it fits a one-cell body")
	var centre: Vector3i = Vector3i(outside.x * M + 500, outside.y * M, outside.z * M + 500)
	_actors.set_position(_short, centre)
	_actors.set_position(_tall, centre)
	assert_true(_walk(_short, 0, 1), "a one-cell body goes into the corridor")
	assert_false(_walk(_tall, 0, 1), "a two-cell body cannot")


func test_a_body_put_where_it_does_not_fit_can_walk_out_but_not_further_in() -> void:
	_setup()
	_raise_m4()
	var corridor: Vector3i = _sites.cell_of(&"m4_test_building", Vector3i(4, 0, 4))
	_actors.set_position(_tall, Vector3i(corridor.x * M + 500, corridor.y * M, corridor.z * M + 500))
	assert_false(_walk(_tall, 0, 1), "further in, under the roof: refused")
	assert_true(_walk(_tall, 0, -1), "out to the open lobby: allowed")


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
