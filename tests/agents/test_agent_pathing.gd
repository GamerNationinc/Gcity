extends GcityTest

## M4 spec claim 9: agents path on the 1 m cell grid through open faces and doors,
## never through a wall or into a solid cell; planning is budgeted and resumes across
## ticks; a path exists whenever the cells are joined through open faces; the walk
## uses the movement rules and re-plans when the world changes under it.

const SEED: int = 20261050
const SEED_PROPERTY: int = 20261051
const PROPERTY_CASES: int = 10_000
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)

var _sim: SimRoot
var _actors: ActorSystem
var _build: BuildSystem
var _perception: PerceptionSystem
var _pathing: PathingSystem
var _movement: MovementSystem
var _player: int = 0


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_build = SimAssembly.build_of(_sim)
	_perception = SimAssembly.perception_of(_sim)
	_pathing = SimAssembly.pathing_of(_sim)
	_movement = SimAssembly.movement_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, FAR + Vector3i(-20 * M, 0, -20 * M))


func _cell(cx: int, cz: int) -> Vector3i:
	return BuildSystem.cell_of(FAR) + Vector3i(cx, 0, cz)


func _at(cx: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, 0, cz * M + 500)


## A wall across the whole z = 3 / z = 4 line from x = 0 to x = 5, with a door at x = 2.
func _wall_with_door() -> Dictionary:
	var pieces: Dictionary = {}
	for x: int in 6:
		_build.place(_player, &"foundation_block", _at(x, 5), "")
		var t: StringName = &"door_frame" if x == 2 else &"wall_panel"
		var placed: int = _build.place(_player, t, _at(x, 4), "nz")
		assert_true(placed > 0, "piece at x = %d" % x)
		pieces[x] = placed
	return pieces


func _walk_until(agent: int, state: String, limit: int) -> int:
	for i: int in limit:
		_sim.step()
		if _pathing.state_of(agent) == state:
			return i + 1
	return -1


func test_a_guard_walks_through_the_door_never_through_the_wall_and_re_plans_when_it_closes() -> void:
	_setup()
	var pieces: Dictionary = _wall_with_door()
	var guard: int = _perception.spawn(&"guard_sim", _cell(4, 1), 0, 1, "")
	assert_true(_pathing.request(guard, _cell(2, 4)), "request accepted: the cell just inside the door")
	assert_eq(_pathing.state_of(guard), PathingSystem.STATE_PLANNING, "planning")
	_sim.step()
	assert_eq(_pathing.state_of(guard), PathingSystem.STATE_FOLLOWING, "planned within one tick's budget")
	var path: Array[Vector3i] = _pathing.path_of(guard)
	assert_true(path.has(_cell(2, 3)) and path.has(_cell(2, 4)), "the path goes through the door cell pair")
	assert_eq(path.size(), 2 + 2 + 1, "x 4->2, z 1->3, through the door: shorter than around the end of the wall")
	var previous: Vector3i = _cell(4, 1)
	for c: Vector3i in path:
		assert_true(_pathing.can_step(previous, c), "every step is legal: %s -> %s" % [previous, c])
		previous = c
	var ticks: int = _walk_until(guard, PathingSystem.STATE_ARRIVED, 400)
	assert_true(ticks > 0, "arrived")
	assert_eq(BuildSystem.cell_of(_actors.position_of(guard)), _cell(2, 4), "standing on the goal")
	assert_eq(_movement.blocked_count(), 0, "no step was ever refused")
	assert_eq(_perception.facing_of(guard), 90, "faced the last step, +z through the door")
	# send it back, but brick the door up before it can leave
	assert_true(_pathing.request(guard, _cell(4, 1)), "back again")
	var door: int = pieces[2]
	_build.breach(door)
	assert_true(_build.place(_player, &"wall_panel", _at(2, 4), "nz") > 0, "the doorway is now a wall")
	_sim.step()
	assert_eq(_pathing.state_of(guard), PathingSystem.STATE_FOLLOWING, "re-planned around the end of the wall")
	assert_false(_pathing.path_of(guard).has(_cell(2, 3)), "not through the bricked doorway")
	assert_true(_pathing.path_of(guard).has(_cell(6, 4)), "around the end at x = 6")
	var end_wall: int = pieces[5]
	_build.breach(end_wall)
	assert_true(_build.place(_player, &"door_frame", _at(5, 4), "nz") > 0, "a new door at x = 5")
	_sim.step()
	assert_eq(_pathing.state_of(guard), PathingSystem.STATE_FOLLOWING, "the build change re-planned it")
	assert_true(_pathing.path_of(guard).has(_cell(5, 3)), "through the new door")
	assert_true(_walk_until(guard, PathingSystem.STATE_ARRIVED, 400) > 0, "arrived back")
	assert_eq(BuildSystem.cell_of(_actors.position_of(guard)), _cell(4, 1), "home")
	assert_eq(_movement.blocked_count(), 0, "still no refused step")


## A bar of foundation blocks from x = 0 to x = 20 along z = 5: solid cells on the ground.
func _crate_bar() -> void:
	for x: int in 21:
		assert_true(_build.place(_player, &"foundation_block", _at(x, 5), "") > 0, "block at x = %d" % x)


func test_requests_are_validated_and_budget_is_shared_in_agent_order() -> void:
	_setup()
	_crate_bar()
	for c: Vector3i in [_cell(9, 10), _cell(11, 10), _cell(10, 9), _cell(10, 11)]:
		assert_true(_build.place(_player, &"foundation_block", BuildSystem.cell_centre(c), "") > 0, "a ring of blocks")
	var a: int = _perception.spawn(&"guard_sim", _cell(10, 0), 0, 1, "")
	var b: int = _perception.spawn(&"guard_sim", _cell(0, 1), 0, 1, "")
	assert_false(_pathing.request(_player, _cell(1, 1)), "not an agent")
	assert_false(_pathing.request(a, _cell(50, 0)), "beyond the search radius")
	assert_false(_pathing.request(a, _cell(1, 0) + Vector3i(0, 1, 0)), "another level")
	assert_true(_pathing.request(a, _cell(10, 10)), "a goal walled in by blocks")
	assert_true(_pathing.request(b, _cell(0, 3)), "a short open route")
	var before: int = _pathing.expanded_count()
	_sim.step()
	assert_eq(_pathing.expanded_count() - before, PathingSystem.PATH_NODES_PER_TICK, "one tick spends exactly the budget")
	assert_eq(_pathing.state_of(a), PathingSystem.STATE_PLANNING, "the first agent's search is not done")
	assert_eq(_pathing.state_of(b), PathingSystem.STATE_PLANNING, "the second got no budget")
	var ticks: int = 1
	while _pathing.state_of(a) == PathingSystem.STATE_PLANNING and ticks < 40:
		_sim.step()
		ticks += 1
	assert_eq(_pathing.state_of(a), PathingSystem.STATE_FAILED, "every reachable cell searched: no way in")
	assert_true(ticks > 4, "over several ticks (%d)" % ticks)
	assert_eq(_pathing.state_of(b), PathingSystem.STATE_FOLLOWING, "the second agent planned once budget was free")
	assert_eq(_pathing.path_of(b).size(), 2, "two cells north")
	_pathing.cancel(b)
	assert_eq(_pathing.state_of(b), "", "cancelled")


func test_property_paths_are_legal_and_exist_exactly_when_the_cells_are_joined() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	_setup()
	var lattice: Dictionary = {}
	for x: int in [0, 2, 4, 6]:
		for z: int in [0, 2, 4, 6]:
			lattice[_build.place(_player, &"foundation_block", _at(x, z), "")] = true
	var guard: int = _perception.spawn(&"guard_sim", _cell(-2, -2), 0, 1, "")
	var templates: Array[StringName] = [&"wall_panel", &"door_frame", &"window_frame", &"concrete_wall", &"storage_crate"]
	var facings: Array[String] = ["px", "nx", "pz", "nz"]
	var failures: int = 0
	var found: int = 0
	var unreachable: int = 0
	for case: int in PROPERTY_CASES:
		if rng.randi_range(0, 3) > 0 or _build.piece_ids().size() <= lattice.size():
			var t: StringName = templates[rng.randi_range(0, templates.size() - 1)]
			var facing: String = "" if t == &"storage_crate" else facings[rng.randi_range(0, 3)]
			_build.place(_player, t, _at(rng.randi_range(0, 6), rng.randi_range(0, 6)), facing)
		else:
			var ids: Array[int] = _build.piece_ids()
			var victim: int = ids[rng.randi_range(0, ids.size() - 1)]
			if not lattice.has(victim):
				_build.remove(_player, victim)
		var from: Vector3i = _cell(rng.randi_range(-1, 7), rng.randi_range(-1, 7))
		var to: Vector3i = _cell(rng.randi_range(-1, 7), rng.randi_range(-1, 7))
		if _build.cell_piece_at(from) != EntityIds.NONE or _build.cell_piece_at(to) != EntityIds.NONE or from == to:
			continue
		_actors.set_position(guard, BuildSystem.cell_centre(from) - Vector3i(0, 500, 0))
		assert_true(_pathing.request(guard, to), "request")
		var problem: String = ""
		var ticks: int = 0
		while _pathing.state_of(guard) == PathingSystem.STATE_PLANNING and ticks < 200:
			_sim.step()
			ticks += 1
			# hold the guard still: the property is about the plan, not the walk
			_actors.set_position(guard, BuildSystem.cell_centre(from) - Vector3i(0, 500, 0))
		var st: String = _pathing.state_of(guard)
		var joined: bool = _joined(from, to)
		if st == PathingSystem.STATE_FOLLOWING:
			found += 1
			if not joined:
				problem = "a path where the oracle finds none"
			var previous: Vector3i = from
			for c: Vector3i in _pathing.path_of(guard):
				if not _pathing.can_step(previous, c):
					problem = "an illegal step %s -> %s" % [previous, c]
				previous = c
			if previous != to:
				problem = "the path ends at %s, not %s" % [previous, to]
		elif st == PathingSystem.STATE_FAILED:
			unreachable += 1
			if joined:
				problem = "no path though the oracle joins them"
		else:
			problem = "still %s after %d ticks" % [st, ticks]
		_pathing.cancel(guard)
		if not problem.is_empty():
			failures += 1
			if failures <= 3:
				fail("case %d: %s (%s -> %s)" % [case, problem, from, to])
	assert_eq(failures, 0, "pathing invariants held (%d found, %d unreachable)" % [found, unreachable])
	assert_true(found > 500 and unreachable > 200, "both outcomes were exercised (%d found, %d unreachable)" % [found, unreachable])


## Breadth-first reachability over the same cells within the search radius, using
## only the piece data: an independent answer to "are these cells joined?".
func _joined(from: Vector3i, to: Vector3i) -> bool:
	var seen: Dictionary = {BuildSystem.cell_key(from): true}
	var queue: Array[Vector3i] = [from]
	while not queue.is_empty():
		var c: Vector3i = queue.pop_front()
		if c == to:
			return true
		for step: Vector3i in PathingSystem.STEPS:
			var n: Vector3i = c + step
			var key: String = BuildSystem.cell_key(n)
			if seen.has(key) or PathingSystem._manhattan(from, n) > PathingSystem.SEARCH_RADIUS:
				continue
			if _build.cell_piece_at(n) != EntityIds.NONE:
				continue
			var facing: String = ("p" if step.x > 0 else "n") + "x" if step.x != 0 else ("p" if step.z > 0 else "n") + "z"
			var piece: int = _build.face_piece_at(BuildSystem.face_key(c, facing))
			if piece != EntityIds.NONE:
				var kind: Dictionary = _build.kind_data(piece)
				var passable: bool = kind["passable"]
				if not passable:
					continue
			seen[key] = true
			queue.append(n)
	return false


func test_sliced_planning_survives_the_save_round_trip_mid_search_and_mid_walk() -> void:
	_setup()
	_crate_bar()
	var a: int = _perception.spawn(&"guard_sim", _cell(10, 0), 0, 1, "")
	assert_true(_pathing.request(a, _cell(10, 10)), "around the bar")
	_sim.step()
	assert_eq(_pathing.state_of(a), PathingSystem.STATE_PLANNING, "the pocket under the bar takes more than one tick's budget")
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var snap: Dictionary = _sim.snapshot()
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "restored mid-search")
	assert_eq(other.restore_root(snap), OK, "root restored")
	var ticks: int = 0
	while _pathing.state_of(a) == PathingSystem.STATE_PLANNING and ticks < 40:
		_sim.step()
		other.step()
		ticks += 1
	assert_eq(_pathing.state_of(a), PathingSystem.STATE_FOLLOWING, "planned")
	assert_eq(SimAssembly.pathing_of(other).path_of(a), _pathing.path_of(a), "the resumed search ends the same way")
	assert_eq(other.state_hash(), _sim.state_hash(), "and the hashes agree")
	assert_true(_pathing.path_of(a).has(_cell(21, 5)) or _pathing.path_of(a).has(_cell(-1, 5)), "around one end of the bar")
	_sim.step_n(30)
	other.step_n(30)
	snap = _sim.snapshot()
	var third: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(third, snap), OK, "restored mid-walk")
	assert_eq(third.restore_root(snap), OK, "root restored")
	assert_eq(SimAssembly.pathing_of(third).path_of(a), _pathing.path_of(a), "the route survives the round trip")
	_sim.step()
	third.step()
	assert_eq(third.state_hash(), _sim.state_hash(), "steps on together")
	var state: Dictionary = _pathing.snapshot()
	var pathing: PathingSystem = SimAssembly.pathing_of(third)
	assert_eq(pathing.restore({}), ERR_INVALID_DATA, "empty")
	var bad: Dictionary = state.duplicate(true)
	var routes: Dictionary = bad["routes"]
	var rec: Dictionary = routes[a]
	rec["state"] = "flying"
	assert_eq(pathing.restore(bad), ERR_INVALID_DATA, "an unknown state")
	bad = state.duplicate(true)
	routes = bad["routes"]
	rec = routes[a]
	rec["index"] = 99
	assert_eq(pathing.restore(bad), ERR_INVALID_DATA, "an index past the path")
	assert_eq(pathing.snapshot(), state, "rejections leave the state untouched")
