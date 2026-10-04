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
## The player of these tests: the M6 rules at one-cell scale (the header says why).
const M6_SCALE: StringName = &"m6_scale_test"

var _sim: SimRoot
var _actors: ActorSystem
var _build: BuildSystem
var _movement: MovementSystem
var _player: int = 0
var _fell: Array[Dictionary] = []


func _setup(given: ContentDb = null) -> void:
	var db: ContentDb = given
	if db == null:
		db = ContentDb.new()
		assert_eq(ContentLoader.load_all(db), OK, "content loads")
	# the M6 rules on one-cell levels: the shipped bodies have been two cells with a storey
	# of drop free since M7.5 claim 6, so the player here is a profile of the old scale
	var m6: Dictionary = db.get_entry(ActorSystem.KIND_PROFILE, &"arcade").duplicate(true)
	m6.merge({"body_cells": 1, "eye_mm": 0, "centre_mm": 0, "fall_free_levels": 1, "fall_damage_per_level": FALL_PER_LEVEL}, true)
	assert_eq(db.add(ActorSystem.KIND_PROFILE, M6_SCALE, m6), OK, "the M6-scale player")
	_sim = SimAssembly.build(SEED, db)
	_actors = SimAssembly.actors_of(_sim)
	_build = SimAssembly.build_of(_sim)
	_movement = SimAssembly.movement_of(_sim)
	SimAssembly.combat_of(_sim).events().subscribe(MovementSystem.EVENT_FELL, _on_fell)
	_player = _actors.spawn(M6_SCALE, 0)
	# off the build area: since M7.5 claim 2 nothing is built where a body stands
	_actors.set_position(_player, _at(-4, 0, -4))
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
	# M7 claim 10: below the ground level is the ground itself, as it is in the wilds, so
	# a foundation and a room both end at it by one rule; nothing ever stood down there
	assert_false(_movement.is_standable(_cell(50, -3, 50)), "below it is the ground, not somewhere to stand")
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


## M7.5 claim 7 (decision 5): falls are measured in metres. A cell is a metre, so a level
## is a metre, and a profile's `fall_free_levels` is the drop that costs nothing. Every
## shipped profile holds 1 (the M6 rule) until claim 6 sets a storey, 3, with 4 000 a
## metre beyond; this pins that tuning on a test profile: a storey is free, and a
## two-storey drop does exactly what a two-level drop did at M6.
func test_falls_in_metres_a_storey_is_free_and_two_storeys_cost_what_two_levels_did() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var storey: Dictionary = db.get_entry(ActorSystem.KIND_PROFILE, &"arcade").duplicate(true)
	storey["fall_free_levels"] = 3
	storey["fall_damage_per_level"] = 4000
	assert_eq(db.add(ActorSystem.KIND_PROFILE, &"storey_faller", storey), OK, "a profile with a storey free")
	_setup(db)
	# M6's rule, the old scale's profile: a two-level drop, the first level free
	var m6_before: int = _actors.health_of(_player)[&"body"]
	_actors.set_position(_player, _at(6, 2, 6))
	_sim.step_n(3)
	var m6_two_levels: int = m6_before - _actors.health_of(_player)[&"body"]
	assert_eq(m6_two_levels, FALL_PER_LEVEL, "two levels under the M6 rule")
	var faller: int = _actors.spawn(&"storey_faller", 0)
	for drop: Array in [[1, 0], [3, 0], [4, 4000], [6, m6_two_levels]]:
		var height: int = drop[0]
		var expected: int = drop[1]
		_fell = []
		var before: int = _actors.health_of(faller)[&"body"]
		_actors.set_position(faller, _at(4, height, 4))
		_sim.step_n(height + 1)
		assert_eq(_actors.position_of(faller), _at(4, 0, 4), "a %d m drop lands on the ground" % height)
		assert_eq(before - _actors.health_of(faller)[&"body"], expected, "a %d m drop costs %d" % [height, expected])
		assert_eq(_fell.size(), 1 if expected > 0 else 0, "an event only when it hurts (%d m)" % height)


## M7.5 claim 6: every shipped profile frees a storey (3 m), and every one that takes
## fall damage takes 4 000 a metre beyond it: the tuning the storey test above pins.
func test_every_shipped_profile_frees_a_storey() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	for id: StringName in db.ids(ActorSystem.KIND_PROFILE):
		var profile: Dictionary = db.get_entry(ActorSystem.KIND_PROFILE, id)
		assert_eq(profile["fall_free_levels"], 3, "%s: a storey of drop is free" % id)
		var per: int = profile["fall_damage_per_level"]
		assert_true(per == 0 or per == 4000, "%s: nothing, or 4 000 a metre beyond it (%d)" % [id, per])


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
	# a lethal fall, at the shipped tuning: a storey free, then 4 000 a metre (M7.5 claim 6),
	# so 27 m beyond the free drop is more than an arcade profile's 100 000
	var other: int = _actors.spawn(&"arcade", 0)
	_actors.set_position(other, _at(9, 30, 9))
	_sim.step_n(32)
	assert_false(_actors.is_alive(other), "a thirty-metre fall kills an arcade profile")


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


## Mutation testing (M6 claim 12): a refused level change bumped the blocked counter
## and nothing read it, so the bump could be deleted unnoticed. The counter is how the
## client and the benches tell "nobody tried to move" from "the world said no".
func test_a_refused_level_change_is_counted_as_blocked() -> void:
	_setup()
	_two_storey()
	var blocked: int = _movement.blocked_count()
	_actors.set_position(_player, _at(2, 1, 2))
	assert_false(_movement.move(_player, 0, 0, 1), "nothing to climb here")
	assert_eq(_movement.blocked_count(), blocked + 1, "and the refusal was counted")
	# an impossible request is not a blocked move: asking for two levels at once is
	# refused before the world is consulted, and the counter is about the world
	assert_false(_movement.move(_player, 0, 0, 2), "two levels at once")
	assert_eq(_movement.blocked_count(), blocked + 1, "not counted: nothing blocked it")
	assert_false(_movement.move(_player, 0, 0, 0), "a zero move is refused")
	assert_eq(_movement.blocked_count(), blocked + 1, "nor that")
	# and a climb that works is not counted either
	_actors.set_position(_player, _at(1, 1, 1))
	assert_true(_movement.move(_player, 0, 0, 1), "up the stairs")
	assert_eq(_movement.blocked_count(), blocked + 1, "still one")


## The other way a level change is refused: something solid is already there.
func test_climbing_into_a_solid_cell_is_refused_and_counted() -> void:
	_setup()
	_two_storey()
	assert_true(_place(&"stair_flight", 0, 1, 2, "nx") > 0, "a flight in the north-west")
	assert_true(_place(&"storage_crate", 0, 2, 2, "") > 0, "and a crate filling the cell above it")
	_actors.set_position(_player, _at(0, 1, 2))
	var blocked: int = _movement.blocked_count()
	assert_false(_movement.move(_player, 0, 0, 1), "there is no room up there")
	assert_eq(_movement.blocked_count(), blocked + 1, "counted once, not twice")
	assert_eq(_actors.position_of(_player), _at(0, 1, 2), "and the actor stayed put")


## Found by the G7 mutation run: the third way a level change is refused, a solid
## floor between the two levels, was refused but never shown to be counted.
func test_climbing_through_a_solid_floor_is_refused_and_counted() -> void:
	_setup()
	_two_storey()
	assert_true(_place(&"stair_flight", 0, 1, 0, "nx") > 0, "a flight under the solid ceiling")
	_actors.set_position(_player, _at(0, 1, 0))
	var blocked: int = _movement.blocked_count()
	assert_false(_movement.move(_player, 0, 0, 1), "the floor above is not a hatch")
	assert_eq(_movement.blocked_count(), blocked + 1, "and the refusal was counted")
	assert_eq(_actors.position_of(_player), _at(0, 1, 0), "the actor stayed put")


## Found by the G7 mutation run: a save with a negative counter was never offered.
func test_a_save_with_a_negative_counter_is_refused() -> void:
	_setup()
	var good: Dictionary = _movement.snapshot()
	for key: String in ["moves", "blocked", "falls"]:
		var bad: Dictionary = good.duplicate(true)
		bad[key] = -1
		assert_eq(_movement.restore(bad), ERR_INVALID_DATA, "refused: %s below zero" % key)
	assert_eq(_movement.restore(good), OK, "the real one restores")



## Found by the G7 mutation run: only actors that are hurt by falling were dropped. The
## range dummy's profile takes no fall damage, so its fall is not worth an event.
func test_a_fall_that_does_no_damage_is_not_an_event() -> void:
	_setup()
	var dummy: int = _actors.spawn(&"range_dummy", 0)
	var full: int = _actors.health_of(dummy)[&"body"]
	_actors.set_position(dummy, _at(4, 3, 4))
	_sim.step_n(4)
	assert_eq(_actors.position_of(dummy), _at(4, 0, 4), "fell all the way")
	assert_eq(_actors.health_of(dummy)[&"body"], full, "unhurt")
	assert_eq(_fell.size(), 0, "and no actor.fell")


## M7.5 mutation, the deeper movement sample: standing still is not a fall. A body with
## no drop free (a content value the schema allows) standing on the ground for a while
## takes no fall damage and reports no fall.
func test_standing_still_is_never_a_fall_even_with_no_drop_free() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var brittle: Dictionary = db.get_entry(ActorSystem.KIND_PROFILE, &"arcade").duplicate(true)
	brittle.merge({"fall_free_levels": 0, "fall_damage_per_level": 5000}, true)
	assert_eq(db.add(ActorSystem.KIND_PROFILE, &"brittle_test", brittle), OK, "a body with no drop free")
	_setup(db)
	var body: int = _actors.spawn(&"brittle_test", 0)
	_actors.set_position(body, _at(-8, 0, -8))
	var before: Dictionary = _actors.health_of(body)
	_sim.step_n(20)
	assert_eq(_actors.health_of(body), before, "unhurt after twenty ticks on the ground")
	assert_eq(_fell.size(), 0, "and no fall reported")


## M7.5 mutation, the deeper movement sample: the blocked counter survives a save, and
## a body removed while it falls leaves no falling row behind (a save holding one would
## not load: the restore refuses a falling row for an actor that is not there).
func test_a_save_keeps_the_blocked_count_and_no_row_for_a_removed_faller() -> void:
	_setup()
	assert_false(_movement.move(_player, 0, 0, 1), "a climb with nothing to climb")
	assert_true(_movement.blocked_count() > 0, "counted as blocked")
	var faller: int = _actors.spawn(M6_SCALE, 0)
	_actors.set_position(faller, _at(-12, 6, -12))
	_sim.step()
	assert_true(_movement.is_falling(faller), "falling")
	assert_true(_actors.remove(faller, ItemSystem.token_container(1)), "removed mid-fall")
	var falling: Dictionary = _movement.snapshot()["falling"]
	assert_false(falling.has(faller), "and its falling row went with it")
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var m6: Dictionary = db.get_entry(ActorSystem.KIND_PROFILE, &"arcade").duplicate(true)
	m6.merge({"body_cells": 1, "eye_mm": 0, "centre_mm": 0, "fall_free_levels": 1, "fall_damage_per_level": FALL_PER_LEVEL}, true)
	assert_eq(db.add(ActorSystem.KIND_PROFILE, M6_SCALE, m6), OK, "the same profiles")
	var other: SimRoot = SimAssembly.build(SEED, db)
	var snap: Dictionary = _sim.snapshot()
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "the save loads")
	assert_eq(SimAssembly.movement_of(other).blocked_count(), _movement.blocked_count(), "with the blocked count")
