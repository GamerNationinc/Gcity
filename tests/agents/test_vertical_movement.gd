extends GcityTest

## M6 spec claim 1: floors are walking surfaces, a level change needs a climbable
## face, and an actor over nothing falls, taking damage for the levels beyond the
## first. Properties over 10 000 random structures: an actor never stands in a solid
## cell nor in the air once it has settled; a level change always had a climbable
## face; fall damage is the levels beyond the first times the profile's number.

const SEED: int = 20261170
const SEED_PROPERTY: int = 20261171
const PROPERTY_CASES: int = 10_000
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)
const FALL_PER_LEVEL: int = 12000

var _sim: SimRoot
var _actors: ActorSystem
var _build: BuildSystem
var _movement: MovementSystem
var _player: int = 0
var _fell: Array[Dictionary] = []


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	_actors = SimAssembly.actors_of(_sim)
	_build = SimAssembly.build_of(_sim)
	_movement = SimAssembly.movement_of(_sim)
	SimAssembly.combat_of(_sim).events().subscribe(MovementSystem.EVENT_FELL, _on_fell)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, _at(0, 0, 0))
	_fell = []


func _on_fell(payload: Dictionary) -> void:
	_fell.append(payload)


func _cell(cx: int, cy: int, cz: int) -> Vector3i:
	return BuildSystem.cell_of(FAR) + Vector3i(cx, cy, cz)


func _at(cx: int, cy: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, cy * M, cz * M + 500)


func _place(piece: StringName, cx: int, cy: int, cz: int, facing: String) -> int:
	return _build.place(_player, piece, _at(cx, cy, cz) + Vector3i(0, 500, 0), facing)


## A 3×3 of foundations, so level 1 is a standable floor; a ceiling of floor panels
## over level 1 with a hatch at the middle cell; a flight of stairs up the middle
## cell's west face, on both levels.
func _two_storey() -> void:
	for x: int in 3:
		for z: int in 3:
			assert_true(_place(&"foundation_block", x, 0, z, "") > 0, "foundation %d,%d" % [x, z])
	for x: int in 3:
		for z: int in 3:
			var piece: StringName = &"roof_hatch" if x == 1 and z == 1 else &"floor_panel"
			assert_true(_place(piece, x, 2, z, "ny") > 0, "ceiling %d,%d" % [x, z])
	assert_true(_place(&"stair_flight", 1, 1, 1, "nx") > 0, "stairs on the middle cell's west face")
	assert_true(_place(&"stair_flight", 1, 2, 1, "nx") > 0, "and the flight above it")


func test_a_cell_is_standable_on_a_floor_a_solid_below_or_the_ground() -> void:
	_setup()
	assert_true(_movement.is_standable(_cell(0, 0, 0)), "the ground is standable")
	assert_true(_movement.is_standable(_cell(50, -3, 50)), "and so is anything at or below it")
	assert_false(_movement.is_standable(_cell(0, 1, 0)), "the air above it is not")
	_two_storey()
	assert_true(_movement.is_standable(_cell(0, 1, 0)), "on top of a foundation: standable")
	assert_true(_movement.is_standable(_cell(0, 2, 0)), "on the floor panel at level 2: standable")
	assert_true(_movement.is_standable(_cell(1, 2, 1)), "and on the stairs themselves, under the hatch")
	assert_false(_movement.is_standable(_cell(0, 3, 0)), "three levels up over nothing: not")
	assert_false(_movement.is_standable(_cell(0, 0, 0)), "a cell a foundation fills is not standable")
	assert_true(_movement.has_climb(_cell(1, 1, 1), "nx"), "the stairs are climbable")
	assert_false(_movement.has_climb(_cell(1, 1, 1), "px"), "the other side is not")
	assert_true(_movement.has_any_climb(_cell(1, 1, 1)), "the cell has a climbable face")
	assert_false(_movement.has_any_climb(_cell(2, 1, 2)), "this one does not")


func test_a_level_change_needs_a_climbable_face() -> void:
	_setup()
	_two_storey()
	_actors.set_position(_player, _at(1, 1, 1))
	assert_true(_movement.is_standable(BuildSystem.cell_of(_actors.position_of(_player))), "standing on the foundation block")
	assert_true(_movement.move(_player, 0, 0, 1), "up the stairs")
	assert_eq(_actors.position_of(_player), _at(1, 2, 1), "a whole level up")
	assert_false(_movement.move(_player, 0, 0, 1), "the top of the flight: nothing above to stand on, refused")
	assert_true(_movement.move(_player, 0, 0, -1), "and back down the same flight")
	assert_eq(_actors.position_of(_player), _at(1, 1, 1), "home")
	_actors.set_position(_player, _at(2, 1, 2))
	assert_false(_movement.move(_player, 0, 0, 1), "a cell with no climbable face refuses the level change")
	assert_false(_movement.move(_player, 0, 0, 2), "and more than one level is always refused")
	_sim.step()
	assert_eq(_actors.position_of(_player), _at(2, 1, 2), "still standing where it was")


func test_an_actor_over_nothing_falls_and_takes_damage_beyond_the_first_level() -> void:
	_setup()
	_two_storey()
	var full: int = _actors.health_of(_player)[&"body"]
	# one level: a step off the block, no damage
	_actors.set_position(_player, _at(4, 1, 4))
	_sim.step()
	assert_eq(_actors.position_of(_player), _at(4, 0, 4), "fell to the ground")
	assert_eq(_actors.health_of(_player)[&"body"], full, "one level costs nothing")
	assert_eq(_fell.size(), 0, "and is not worth an event")
	assert_false(_movement.is_falling(_player), "the fall is resolved on the tick it lands")
	# three levels: two beyond the first
	_actors.set_position(_player, _at(4, 3, 4))
	_sim.step_n(4)
	assert_eq(_actors.position_of(_player), _at(4, 0, 4), "fell all the way")
	assert_eq(_actors.health_of(_player)[&"body"], full - 2 * FALL_PER_LEVEL, "two levels beyond the first")
	assert_eq(_fell.size(), 1, "one actor.fell")
	assert_eq(_fell[0]["levels"], 3, "three levels")
	assert_eq(_fell[0]["damage"], 2 * FALL_PER_LEVEL, "and its damage")
	assert_eq(_movement.fall_count(), 4, "four descending ticks across both falls")
	assert_false(_movement.is_falling(_player), "landed")


func test_a_long_fall_can_kill_and_the_move_command_carries_dy() -> void:
	_setup()
	_two_storey()
	assert_false(_do({"actor": _player, "dx": 0, "dz": 0, "dy": 1}), "a level change from the ground with no stairs is refused")
	_actors.set_position(_player, _at(1, 1, 1))
	assert_true(_do({"actor": _player, "dx": 0, "dz": 0, "dy": 1}), "up the stairs through the command")
	assert_eq(_actors.position_of(_player), _at(1, 2, 1), "up a level")
	assert_false(_do({"actor": _player, "dx": 0, "dz": 0, "dy": 2}), "two levels at once")
	assert_false(_do({"actor": _player, "dx": 0, "dz": 0, "dy": 1, "dw": 1}), "an unknown key")
	assert_false(_do({"actor": _player, "dx": 0, "dz": 0, "dy": 1.5}), "a fractional level")
	assert_false(_do({"actor": _player, "dx": 0, "dz": 0}), "the three-key form still parses; a zero move is refused as ever")
	# a lethal fall
	var other: int = _actors.spawn(&"arcade", 0)
	_actors.set_position(other, _at(9, 12, 9))
	_sim.step_n(14)
	assert_false(_actors.is_alive(other), "a twelve-level fall kills an arcade profile")


func _do(payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, &"actor.move", payload)), OK, "submit")
	_sim.step()
	return _sim.dispatched_count() == before + 1


func test_property_an_actor_never_settles_in_a_solid_cell_or_the_air() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	_setup()
	var templates: Array[StringName] = [&"foundation_block", &"floor_panel", &"stair_flight", &"wall_panel", &"storage_crate"]
	var facings: Array[String] = ["px", "nx", "pz", "nz", "py", "ny"]
	var violations: int = 0
	var settled_high: int = 0
	var fell_cases: int = 0
	for case: int in PROPERTY_CASES:
		# the structure changes every fifth case: each change rebuilds the portal graph,
		# which the G4 bench measured at 11-15 ms on the Deck, and the property is about
		# where an actor settles, not how often the world moves
		if case % 5 == 0 or _build.piece_ids().is_empty():
			var t: StringName = templates[rng.randi_range(0, templates.size() - 1)]
			var facing: String = "" if t == &"foundation_block" or t == &"storage_crate" else facings[rng.randi_range(0, 5)]
			_build.place(_player, t, _at(rng.randi_range(0, 3), rng.randi_range(0, 2), rng.randi_range(0, 3)) + Vector3i(0, 500, 0), facing)
		elif case % 5 == 1:
			var ids: Array[int] = _build.piece_ids()
			_build.remove(_player, ids[rng.randi_range(0, ids.size() - 1)])
		# drop the actor somewhere in the region and let gravity settle it
		var start: Vector3i = _at(rng.randi_range(0, 3), rng.randi_range(0, 4), rng.randi_range(0, 3))
		if _build.cell_piece_at(BuildSystem.cell_of(start)) != EntityIds.NONE:
			continue
		_actors.set_position(_player, start)
		var before: Vector3i = _actors.position_of(_player)
		_sim.step_n(6)  # the region is four levels deep: six ticks always settles
		var cell: Vector3i = BuildSystem.cell_of(_actors.position_of(_player))
		if _actors.position_of(_player).y < before.y:
			fell_cases += 1
		if cell.y > BuildSystem.GROUND_CELL_Y:
			settled_high += 1
		if _build.cell_piece_at(cell) != EntityIds.NONE:
			violations += 1
			if violations <= 3:
				fail("case %d: settled inside a solid cell %s" % [case, cell])
		elif not _movement.is_standable(cell):
			violations += 1
			if violations <= 3:
				fail("case %d: settled in the air at %s" % [case, cell])
		if not _actors.is_alive(_player):
			_setup()  # a lethal fall: start over, the structure with it
	assert_eq(violations, 0, "every settled actor stands on something (%d fell, %d settled above the ground)" % [fell_cases, settled_high])
	assert_true(fell_cases > 500 and settled_high > 50, "both outcomes were exercised (%d fell, %d settled above the ground)" % [fell_cases, settled_high])
