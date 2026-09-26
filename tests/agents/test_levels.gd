extends GcityTest

## M6 spec claims 5–7: actors stand on floors, fall to the next floor when nothing
## holds them, change level only by a climb rule (a ladder, a climbable crate), path
## across levels through the same rules, and see between levels only through open
## faces.
##
## Test world, far out in unparcelled badlands (FAR_CELL = (500, 0, 500)):
##   platform  foundations at x 0..3, z 0: stand on them at y 1
##   crate     at x 4, z 0, beside the platform's end: climbable
##   shaft     foundation at (10, 0, 10); a hatch over (11, 0, 10); a ladder on the
##             +z face of (11, 0, 10)
##   sealed    the same at x 20 with a floor panel instead of the hatch

const SEED: int = 20261120
const SEED_METAMORPHIC: int = 20261121
const SEED_CRATES: int = 20261122
const PROPERTY_CASES: int = 10_000
const CRATE_CASES: int = 1_000
const M: int = 1000
const FAR_CELL: Vector3i = Vector3i(500, 0, 500)
const UP: Vector3i = Vector3i(0, 1, 0)

var _sim: SimRoot
var _actors: ActorSystem
var _build: BuildSystem
var _movement: MovementSystem
var _pathing: PathingSystem
var _perception: PerceptionSystem
var _player: int = 0


func _setup(db: ContentDb = null) -> void:
	if db == null:
		db = ContentDb.new()
		assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_build = SimAssembly.build_of(_sim)
	_movement = SimAssembly.movement_of(_sim)
	_pathing = SimAssembly.pathing_of(_sim)
	_perception = SimAssembly.perception_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_park(_player)


## Far beyond any guard's sight, so stances stay idle.
func _park(actor: int) -> void:
	_actors.set_position(actor, _floor_of(FAR_CELL + Vector3i(-100, 0, -100)))


func _c(x: int, y: int, z: int) -> Vector3i:
	return FAR_CELL + Vector3i(x, y, z)


## Where an actor stands in a cell: its centre, on its floor.
static func _floor_of(cell: Vector3i) -> Vector3i:
	return Vector3i(cell.x * M + M / 2, cell.y * M, cell.z * M + M / 2)


func _place(piece: StringName, cell: Vector3i, facing: String) -> int:
	var id: int = _build.place(_player, piece, BuildSystem.cell_centre(cell), facing)
	assert_true(id > 0, "%s at %s %s" % [piece, cell, facing])
	return id


func _world() -> void:
	for x: int in 4:
		_place(&"foundation_block", _c(x, 0, 0), "")
	_place(&"storage_crate", _c(4, 0, 0), "")
	_place(&"foundation_block", _c(10, 0, 10), "")
	_place(&"roof_hatch", _c(11, 0, 10), "py")
	_place(&"ladder", _c(11, 0, 10), "pz")
	_place(&"foundation_block", _c(20, 0, 10), "")
	_place(&"floor_panel", _c(21, 0, 10), "py")
	_place(&"ladder", _c(21, 0, 10), "pz")


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


func _cell_of(actor: int) -> Vector3i:
	return BuildSystem.cell_of(_actors.position_of(actor))


# ---------------------------------------------------------------- claim 5: floors

func test_what_holds_an_actor_up() -> void:
	_setup()
	_world()
	assert_true(_movement.is_supported(_c(7, 0, 7)), "the ground")
	assert_true(_movement.is_supported(_c(1, 1, 0)), "a foundation below")
	assert_true(_movement.is_supported(_c(4, 1, 0)), "a crate below")
	assert_true(_movement.is_supported(_c(11, 1, 10)), "a hatch below")
	assert_true(_movement.is_supported(_c(21, 1, 10)), "a floor below")
	assert_false(_movement.is_supported(_c(7, 1, 7)), "thin air")
	assert_false(_movement.is_supported(_c(11, 2, 10)), "a cell above a floor is not on it")
	assert_eq(_movement.landing_cell(_c(7, 3, 7)), _c(7, 0, 7), "a fall ends on the ground")
	assert_eq(_movement.landing_cell(_c(1, 4, 0)), _c(1, 1, 0), "or on the first thing below")
	assert_eq(_movement.landing_cell(_c(11, 3, 10)), _c(11, 1, 10), "a hatch holds you")


func test_walking_off_an_edge_falls_to_the_next_floor_and_walking_on_does_not() -> void:
	_setup()
	_world()
	_actors.set_position(_player, _floor_of(_c(1, 1, 0)))
	for i: int in 7:
		assert_true(_do(&"actor.move", {"actor": _player, "dx": 150, "dz": 0}), "along the platform")
	assert_eq(_cell_of(_player), _c(2, 1, 0), "still on top")
	assert_eq(_actors.position_of(_player).y, M, "feet on the platform")
	for i: int in 8:
		_do(&"actor.move", {"actor": _player, "dx": 0, "dz": 150})
	assert_eq(_cell_of(_player), _c(2, 0, 1), "stepped off the side: down on the ground")
	assert_eq(_actors.position_of(_player).y, 0, "feet on the ground")


# ---------------------------------------------------------------- claim 6: climbing

func test_a_crate_is_climbed_and_a_platform_walked_from_it() -> void:
	_setup()
	_world()
	_actors.set_position(_player, _floor_of(_c(5, 0, 0)))
	assert_true(_do(&"actor.climb", {"actor": _player, "dir": "up", "facing": "nx"}), "up onto the crate ahead")
	assert_eq(_cell_of(_player), _c(4, 1, 0), "on top of it")
	assert_eq(_actors.position_of(_player), _floor_of(_c(4, 1, 0)), "at its centre, on its top")
	for i: int in 20:
		_do(&"actor.move", {"actor": _player, "dx": -60, "dz": 0})
	assert_eq(_cell_of(_player), _c(3, 1, 0), "and across onto the platform")
	assert_false(_do(&"actor.climb", {"actor": _player, "dir": "down", "facing": "nx"}), "no ladder: nothing to climb down")


func test_a_ladder_through_a_hatch_goes_both_ways_and_a_floor_panel_stops_it() -> void:
	_setup()
	_world()
	_actors.set_position(_player, _floor_of(_c(11, 0, 10)))
	assert_false(_do(&"actor.climb", {"actor": _player, "dir": "up", "facing": "px"}), "the ladder is on the +z face, not +x")
	assert_true(_do(&"actor.climb", {"actor": _player, "dir": "up", "facing": "pz"}), "up the ladder")
	assert_eq(_cell_of(_player), _c(11, 1, 10), "through the hatch")
	assert_eq(_actors.position_of(_player).y, M, "standing on it")
	_sim.step_n(3)
	assert_eq(_cell_of(_player), _c(11, 1, 10), "and it holds")
	assert_true(_do(&"actor.climb", {"actor": _player, "dir": "down", "facing": "pz"}), "back down")
	assert_eq(_cell_of(_player), _c(11, 0, 10), "at the ladder's foot")
	assert_false(_do(&"actor.climb", {"actor": _player, "dir": "down", "facing": "pz"}), "nothing below the ground")
	_actors.set_position(_player, _floor_of(_c(21, 0, 10)))
	assert_false(_do(&"actor.climb", {"actor": _player, "dir": "up", "facing": "pz"}), "a floor panel is no hatch")
	assert_eq(_cell_of(_player), _c(21, 0, 10), "still below it")


func test_a_ladder_holds_nobody_by_itself() -> void:
	_setup()
	_place(&"foundation_block", _c(30, 0, 30), "")
	_place(&"ladder", _c(31, 0, 30), "pz")
	_place(&"ladder", _c(31, 1, 30), "pz")
	assert_false(_movement.is_supported(_c(31, 1, 30)), "a cell beside a ladder, with nothing under it, holds nobody")
	_actors.set_position(_player, _floor_of(_c(31, 0, 30)))
	assert_false(_do(&"actor.climb", {"actor": _player, "dir": "up", "facing": "pz"}), "an open shaft: nothing to stand on at the top")
	assert_eq(_cell_of(_player), _c(31, 0, 30), "a refused climb moves nobody")


func test_climb_payloads_and_refusals() -> void:
	_setup()
	_world()
	_actors.set_position(_player, _floor_of(_c(5, 0, 0)))
	for payload: Dictionary in [
		{}, {"actor": _player}, {"actor": _player, "dir": "up"},
		{"actor": _player, "dir": "sideways", "facing": "nx"},
		{"actor": _player, "dir": "up", "facing": "py"},
		{"actor": _player, "dir": "up", "facing": 1},
		{"actor": "1", "dir": "up", "facing": "nx"},
		{"actor": 99, "dir": "up", "facing": "nx"},
		{"actor": _player, "dir": "up", "facing": "nx", "extra": 1},
	]:
		assert_false(_do(&"actor.climb", payload), "refused: %s" % [payload])
	assert_eq(_cell_of(_player), _c(5, 0, 0), "nobody moved")
	# something on top of the crate: no room to climb onto it
	_place(&"storage_crate", _c(4, 1, 0), "")
	assert_false(_do(&"actor.climb", {"actor": _player, "dir": "up", "facing": "nx"}), "the top is taken")
	SimAssembly.actors_of(_sim).damage_node(_player, &"body", 1_000_000)
	_build.remove(_player, _build.cell_piece_at(_c(4, 1, 0)))
	assert_false(_do(&"actor.climb", {"actor": _player, "dir": "up", "facing": "nx"}), "the dead do not climb")


# ---------------------------------------------------------------- claim 6: pathing

## The cost of the planned path from `from` to `to` (its transitions), -1 when there
## is none. Only the pathing system is ticked: the plan, not the walk or the guard's
## other layers, is what is measured, and the guard is held at the start.
func _plan(agent: int, from: Vector3i, to: Vector3i) -> int:
	_actors.set_position(agent, _floor_of(from))
	if not _pathing.request(agent, to):
		return -2
	var ticks: int = 0
	while _pathing.state_of(agent) == PathingSystem.STATE_PLANNING and ticks < 200:
		_pathing.tick(_sim)
		ticks += 1
		_actors.set_position(agent, _floor_of(from))
	var st: String = _pathing.state_of(agent)
	var cost: int = _pathing.path_of(agent).size() if st == PathingSystem.STATE_FOLLOWING else -1
	_pathing.cancel(agent)
	return cost


func test_a_guard_paths_up_a_ladder_and_walks_it() -> void:
	_setup()
	_world()
	var guard: int = _perception.spawn(&"guard_sim", _c(13, 0, 12), 0, 1, "")
	assert_true(_pathing.request(guard, _c(11, 1, 10)), "a goal on the level above")
	var ticks: int = 0
	while _pathing.state_of(guard) != PathingSystem.STATE_ARRIVED and ticks < 400:
		_sim.step()
		ticks += 1
	assert_eq(_pathing.state_of(guard), PathingSystem.STATE_ARRIVED, "arrived (%d ticks)" % ticks)
	assert_eq(_cell_of(guard), _c(11, 1, 10), "on the hatch, up the ladder")
	assert_eq(_movement.blocked_count(), 0, "never walked into anything")


## A roofless pen, walled all round with no door, and a crate outside its south wall:
## the only way in is up the crate, across the wall's top and down inside.
func test_a_guard_paths_over_a_wall_by_a_crate_and_drops_down_the_far_side() -> void:
	_setup()
	for corner: Vector3i in [_c(0, 0, 0), _c(4, 0, 0), _c(0, 0, 4), _c(4, 0, 4)]:
		_place(&"foundation_block", corner, "")
	for i: int in range(1, 4):
		_place(&"wall_panel", _c(1, 0, i), "nx")
		_place(&"wall_panel", _c(3, 0, i), "px")
		_place(&"wall_panel", _c(i, 0, 1), "nz")
		_place(&"wall_panel", _c(i, 0, 3), "pz")
	_place(&"storage_crate", _c(2, 0, 0), "")
	var guard: int = _perception.spawn(&"guard_sim", _c(2, 0, -3), 0, 1, "")
	var inside: Vector3i = _c(2, 0, 2)
	assert_eq(_plan(guard, _c(2, 0, -3), inside), 5, "two steps to the crate, up, over the wall and down, one more")
	_actors.set_position(guard, _floor_of(_c(2, 0, -3)))
	assert_true(_pathing.request(guard, inside), "walk it")
	var ticks: int = 0
	var went_over: bool = false
	while _pathing.state_of(guard) != PathingSystem.STATE_ARRIVED and ticks < 800:
		_sim.step()
		ticks += 1
		went_over = went_over or _cell_of(guard) == _c(2, 1, 0)
	assert_eq(_cell_of(guard), inside, "in the pen (%d ticks, %s)" % [ticks, _pathing.state_of(guard)])
	assert_true(went_over, "by way of the crate's top")


func test_requests_across_levels_are_accepted_and_the_search_radius_still_holds() -> void:
	_setup()
	var guard: int = _perception.spawn(&"guard_sim", _c(0, 0, 5), 0, 1, "")
	assert_true(_pathing.request(guard, _c(0, 1, 5)), "another level is a goal now")
	assert_false(_pathing.request(guard, _c(0, PathingSystem.SEARCH_RADIUS + 1, 5)), "beyond the radius vertically")


## Metamorphic relation: adding a ladder never raises the cost of a path that existed,
## and never removes one (cases with no path before say nothing and are skipped). A ladder is a passable face: it blocks nothing, it only adds
## climbs. Two floors over a lattice of foundations; random walls, floors, hatches,
## crates and ladders; a ladder added on a free vertical face. A ring of foundation
## blocks two cells out bounds every search: nothing climbs it, and no upper floor
## reaches its top, so a goal with no path fails inside the ring, not across the
## whole search radius.
func test_property_adding_a_ladder_never_raises_a_path_cost() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_METAMORPHIC
	_setup()
	for x: int in [0, 3, 6]:
		for z: int in [0, 3, 6]:
			_place(&"foundation_block", _c(x, 0, z), "")
	for i: int in range(-3, 10):
		for ring: Vector3i in [_c(i, 0, -3), _c(i, 0, 9), _c(-3, 0, i), _c(9, 0, i)]:
			if _build.cell_piece_at(ring) == EntityIds.NONE:
				_place(&"foundation_block", ring, "")
	var fixed: int = _build.piece_ids().size()
	var guard: int = _perception.spawn(&"guard_sim", _c(-2, 0, -2), 0, 1, "")
	var templates: Array[StringName] = [&"wall_panel", &"floor_panel", &"roof_hatch", &"storage_crate", &"ladder", &"door_frame"]
	var vertical: Array[String] = ["px", "nx", "pz", "nz"]
	var failures: int = 0
	var compared: int = 0
	var improved: int = 0
	for case: int in PROPERTY_CASES:
		var t: StringName = templates[rng.randi_range(0, templates.size() - 1)]
		var cell: Vector3i = _c(rng.randi_range(0, 6), rng.randi_range(0, 1), rng.randi_range(0, 6))
		var facing: String = ""
		if t == &"floor_panel" or t == &"roof_hatch":
			facing = "py"
		elif t != &"storage_crate":
			facing = vertical[rng.randi_range(0, 3)]
		_build.place(_player, t, BuildSystem.cell_centre(cell), facing)
		if _build.piece_ids().size() > fixed + 51:
			var ids: Array[int] = _build.piece_ids()
			_build.remove(_player, ids[rng.randi_range(fixed, ids.size() - 1)])
		# half the ladders go under a hatch, and then half the goals are on top of it:
		# that is where a ladder can open a way at all
		var ladder_cell: Vector3i = _c(rng.randi_range(0, 6), rng.randi_range(0, 1), rng.randi_range(0, 6))
		var hatches: Array[int] = []
		for id: int in _build.piece_ids():
			if _build.template_of(id) == &"roof_hatch":
				hatches.append(id)
		var under_hatch: bool = not hatches.is_empty() and rng.randi_range(0, 1) == 0
		if under_hatch:
			ladder_cell = _build.cell_of_piece(hatches[rng.randi_range(0, hatches.size() - 1)])
		var from: Vector3i = _c(rng.randi_range(-1, 7), 0, rng.randi_range(-1, 7))
		var to: Vector3i = _c(rng.randi_range(-1, 7), rng.randi_range(0, 1), rng.randi_range(0, 6))
		if under_hatch and rng.randi_range(0, 1) == 0:
			to = ladder_cell + UP
		to = _movement.landing_cell(to)
		if _build.cell_piece_at(from) != EntityIds.NONE or _build.cell_piece_at(to) != EntityIds.NONE or from == to:
			continue
		var before: int = _plan(guard, from, to)
		if before < 0:
			# no path to keep: the relation says nothing, and a failed search is the
			# costly kind, so the ladder is not tried here
			continue
		var ladder: int = _build.place(_player, &"ladder", BuildSystem.cell_centre(ladder_cell), vertical[rng.randi_range(0, 3)])
		if ladder == EntityIds.NONE:
			continue
		var after: int = _plan(guard, from, to)
		_build.remove(_player, ladder)
		compared += 1
		var problem: String = ""
		if after < 0:
			problem = "a ladder cut a path (%d -> none)" % before
		elif after > before:
			problem = "a ladder raised a path's cost %d -> %d" % [before, after]
		elif after < before:
			improved += 1
		if not problem.is_empty():
			failures += 1
			if failures <= 3:
				fail("case %d: %s (%s -> %s)" % [case, problem, from, to])
	assert_eq(failures, 0, "no ladder ever raised a cost (%d compared)" % compared)
	assert_true(compared > 3000, "enough comparisons (%d)" % compared)
	assert_true(improved > 30, "and ladders did open shorter ways (%d)" % improved)


## The same relation for the climb flag itself: over the same layout, content where
## crates are climbable never gives a costlier path than content where they are not.
func test_property_a_climbable_crate_never_costs_more_than_a_plain_one() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_CRATES
	var plain := ContentDb.new()
	assert_eq(ContentLoader.load_all(plain, ContentLoader.CONTENT_ROOT), OK, "content loads")
	var crate_kind: Dictionary = plain.get_entry(&"piece_kind", &"crate").duplicate(true)
	crate_kind["climb"] = false
	var flat := ContentDb.new()
	for kind: StringName in plain.kinds():
		for id: StringName in plain.ids(kind):
			var data: Dictionary = plain.get_entry(kind, id).duplicate(true)
			if kind == &"piece_kind" and id == &"crate":
				data = crate_kind
			assert_eq(flat.add(kind, id, data), OK, "copy %s/%s" % [kind, id])
	var failures: int = 0
	var compared: int = 0
	var cheaper: int = 0
	for case: int in CRATE_CASES:
		var layout: Array[Array] = []
		for x: int in [0, 3, 6]:
			layout.append([&"foundation_block", _c(x, 0, 0), ""])
		for i: int in rng.randi_range(4, 16):
			var t: StringName = [&"wall_panel", &"storage_crate", &"storage_crate"][rng.randi_range(0, 2)]
			var facing: String = "" if t == &"storage_crate" else ["px", "nx", "pz", "nz"][rng.randi_range(0, 3)]
			layout.append([t, _c(rng.randi_range(0, 6), 0, rng.randi_range(-1, 1)), facing])
		var from: Vector3i = _c(rng.randi_range(0, 6), 0, -3)
		var to: Vector3i = _c(rng.randi_range(0, 6), 0, 3)
		var costs: Array[int] = []
		for db: ContentDb in [flat, plain]:
			_setup(db)
			for entry: Array in layout:
				var template: StringName = entry[0]
				var cell: Vector3i = entry[1]
				var facing: String = entry[2]
				_build.place(_player, template, BuildSystem.cell_centre(cell), facing)
			var guard: int = _perception.spawn(&"guard_sim", _c(-2, 0, -5), 0, 1, "")
			if _build.cell_piece_at(from) != EntityIds.NONE or _build.cell_piece_at(to) != EntityIds.NONE:
				costs.append(-3)
			else:
				costs.append(_plan(guard, from, to))
		if costs[0] == -3:
			continue
		compared += 1
		if costs[0] >= 0 and (costs[1] < 0 or costs[1] > costs[0]):
			failures += 1
			if failures <= 3:
				fail("case %d: plain crates %d, climbable %d" % [case, costs[0], costs[1]])
		elif costs[1] >= 0 and (costs[0] < 0 or costs[1] < costs[0]):
			cheaper += 1
	assert_eq(failures, 0, "climbable crates never cost more (%d compared)" % compared)
	assert_true(cheaper > 20, "and sometimes a crate is the way over (%d)" % cheaper)


# ---------------------------------------------------------------- claim 7: sight

func test_a_floor_blocks_sight_between_levels_and_a_hatch_does_not() -> void:
	_setup()
	_world()
	# the guard on the hatch looks down through it; on the floor panel it cannot
	assert_true(_perception.line_of_sight(_floor_of(_c(11, 1, 10)), _floor_of(_c(13, 0, 10))), "through the hatch it stands on")
	assert_false(_perception.line_of_sight(_floor_of(_c(21, 1, 10)), _floor_of(_c(23, 0, 10))), "not through a floor panel")
	assert_true(_perception.line_of_sight(_floor_of(_c(1, 1, 0)), _floor_of(_c(1, 1, 3))), "along one level in the open")
	assert_false(_perception.line_of_sight(_floor_of(_c(1, 1, 0)), _floor_of(_c(1, 0, -1))), "not down through the foundation it stands on")
	var guard: int = _perception.spawn(&"guard_sim", _c(21, 1, 10), 0, 1, "")
	_actors.set_position(_player, _floor_of(_c(23, 0, 10)))
	assert_false(_perception.can_see(guard, _player), "the guard upstairs does not see the player below the floor")
	_actors.set_position(_player, _floor_of(_c(23, 1, 10)))
	assert_true(_perception.can_see(guard, _player), "but sees one on its own level")
