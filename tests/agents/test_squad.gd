extends GcityTest

## M4 spec claim 11: a member's alert becomes a report to its squad after the radio
## latency, only if it has a radio; receivers learn the contact's cell and act on it;
## the planner hands members distinct entry edges of the contact's volume.
## Metamorphic: removing a radio never makes the squad alert sooner; adding a member
## never raises the alert latency of the others.

const SEED: int = 20261080
const SEED_PROPERTY: int = 20261081
const PROPERTY_CASES: int = 120
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)
const NEVER: int = 100_000

var _sim: SimRoot
var _actors: ActorSystem
var _perception: PerceptionSystem
var _squads: SquadSystem
var _build: BuildSystem
var _player: int = 0
var _reports: Array[Dictionary] = []


func _db(radio: bool = true, latency: int = 20) -> ContentDb:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	# a watcher that never fires or moves, so squads are tested without the stance layer acting
	db.add(&"agent_profile", &"watcher", {"schema_version": 1, "description": "test", "combat_profile": "guard", "perception_profile": "guard_sim",
		"aim_profile": "guard_sim", "stress_profile": "guard_sim", "stances": [{"stance": "surrender", "weight": 1000}], "radio": radio, "radio_latency_ticks": latency})
	db.add(&"agent_profile", &"mute", {"schema_version": 1, "description": "test", "combat_profile": "guard", "perception_profile": "guard_sim",
		"aim_profile": "guard_sim", "stress_profile": "guard_sim", "stances": [{"stance": "surrender", "weight": 1000}], "radio": false, "radio_latency_ticks": 0})
	return db


func _setup(db: ContentDb = null) -> void:
	if db == null:
		db = _db()
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_perception = SimAssembly.perception_of(_sim)
	_squads = SimAssembly.squads_of(_sim)
	_build = SimAssembly.build_of(_sim)
	SimAssembly.combat_of(_sim).events().subscribe(SquadSystem.EVENT_REPORT, _on_report)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, FAR + Vector3i(-100 * M, 0, -100 * M))


func _on_report(payload: Dictionary) -> void:
	_reports.append(payload)


func _cell(cx: int, cz: int) -> Vector3i:
	return BuildSystem.cell_of(FAR) + Vector3i(cx, 0, cz)


func _at(cx: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, 0, cz * M + 500)


func _ticks_until(predicate: Callable, limit: int) -> int:
	for i: int in limit:
		_sim.step()
		if predicate.call():
			return i + 1
	return NEVER


## A wall along z = 5 (x 0..5) with foundations at each end, so a guard south of it
## cannot see a player north of it.
func _screen() -> void:
	for x: int in [-1, 6]:
		_build.place(_player, &"foundation_block", _at(x, 5), "")
	for x: int in [0, 1, 2, 5, 4, 3]:  # from both foundations inward, so every wall is within span when placed
		assert_true(_build.place(_player, &"wall_panel", _at(x, 5), "nz") > 0, "screen wall at x = %d" % x)


func test_a_report_reaches_the_squad_after_the_latency_and_only_by_radio() -> void:
	_setup()
	_screen()
	var lookout: int = _perception.spawn(&"watcher", _cell(2, 8), 90, 1, "")   # north of the screen, facing +z
	var behind: int = _perception.spawn(&"watcher", _cell(2, 2), 90, 1, "")    # south of it, cannot see north
	var other_squad: int = _perception.spawn(&"watcher", _cell(4, 2), 90, 2, "")
	_sim.step()  # first tick: the teleported player must not read as movement
	_actors.set_position(_player, _at(2, 14))
	var alerted_at: int = _ticks_until(func() -> bool: return _perception.is_alerted(lookout, _player), 100)
	assert_true(alerted_at < NEVER, "the lookout is alerted")
	assert_eq(_squads.pending_count(), 1, "one report in flight")
	assert_false(_perception.is_alerted(behind, _player), "the one behind the wall knows nothing yet")
	var informed_at: int = _ticks_until(func() -> bool: return _perception.is_alerted(behind, _player), 100)
	assert_eq(informed_at, 20, "informed exactly the radio latency later")
	assert_eq(_reports.size(), 1, "one squad.report")
	assert_eq(_reports[0]["reporter"], lookout, "from the lookout")
	assert_eq(_reports[0]["informed"], [behind] as Array[int], "to the one who did not know")
	assert_eq(_perception.last_known(behind, _player), _at(2, 14), "who now knows where the contact is")
	assert_false(_perception.is_alerted(other_squad, _player), "another squad hears nothing")
	assert_eq(_squads.pending_count(), 1, "delivered, and the informed member's own alert is already on the air")
	# that echo is delivered, but nobody is newly informed
	_sim.step_n(25)
	assert_eq(_squads.delivered_count(), 2, "the echo delivered")
	assert_eq(_reports[1]["informed"], [] as Array[int], "to no one new")
	_sim.step_n(30)
	assert_eq(_squads.delivered_count(), 2, "and it stops there")
	# no radio, no report
	_reports.clear()
	_setup(_db(false))
	_screen()
	var mute_lookout: int = _perception.spawn(&"watcher", _cell(2, 8), 90, 1, "")
	var mute_behind: int = _perception.spawn(&"watcher", _cell(2, 2), 90, 1, "")
	_sim.step()
	_actors.set_position(_player, _at(2, 14))
	assert_true(_ticks_until(func() -> bool: return _perception.is_alerted(mute_lookout, _player), 100) < NEVER, "alerted")
	assert_eq(_squads.pending_count(), 0, "nothing in flight without a radio")
	_sim.step_n(60)
	assert_false(_perception.is_alerted(mute_behind, _player), "the squad never learns")
	assert_eq(_reports.size(), 0, "no report")


func test_property_no_radio_never_alerts_sooner_and_more_members_never_slow_the_others() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	var violations: int = 0
	var informed_cases: int = 0
	for case: int in PROPERTY_CASES:
		var latency: int = rng.randi_range(0, 60)
		var contact_z: int = rng.randi_range(7, 30)
		var extra: int = rng.randi_range(0, 3)
		var times: Array[int] = []
		# with radio; with radio and extra members; without radio
		for variant: int in 3:
			_setup(_db(variant != 2, latency))
			_screen()
			var lookout: int = _perception.spawn(&"watcher", _cell(2, 8), 90, 1, "")
			var behind: int = _perception.spawn(&"watcher", _cell(2, 2), 90, 1, "")
			if variant == 1:
				for i: int in extra:
					_perception.spawn(&"watcher", _cell(-3 - i, 2), 90, 1, "")
			_sim.step()
			_actors.set_position(_player, _at(2, contact_z))
			times.append(_ticks_until(func() -> bool: return _perception.is_alerted(behind, _player), 300))
			assert_true(lookout > 0, "spawned")
		if times[0] < NEVER:
			informed_cases += 1
		if times[2] < times[0] or times[1] > times[0]:
			violations += 1
			if violations <= 3:
				fail("case %d: radio %d, more members %d, no radio %d" % [case, times[0], times[1], times[2]])
	assert_eq(violations, 0, "no radio never alerts sooner; more members never slow the others")
	assert_true(informed_cases > 40, "enough squads were informed (%d)" % informed_cases)


func test_the_planner_hands_out_distinct_entry_edges_cheapest_first() -> void:
	# the M3 demo room (a door on the south side, walls and a roof) with the player
	# inside; three squad members outside are told where it is
	_setup()
	var base: Vector3i = _cell(10, 10)
	for command: Dictionary in WorldView.room_commands(base, _player):
		var piece_s: String = command["piece"]
		var facing: String = command["facing"]
		var x: int = command["x"]
		var y: int = command["y"]
		var z: int = command["z"]
		var placed: int = _build.place(_player, StringName(piece_s), Vector3i(x, y, z), facing)
		assert_true(placed > 0, "room piece %s" % piece_s)
	var portals: PortalGraph = SimAssembly.portals_of(_sim)
	assert_eq(portals.volume_count(), 1, "one enclosed volume")
	_actors.set_position(_player, BuildSystem.cell_centre(base + Vector3i(1, 0, 1)))
	var a: int = _perception.spawn(&"watcher", base + Vector3i(1, 0, -4), 90, 1, "")
	var b: int = _perception.spawn(&"watcher", base + Vector3i(-3, 0, 1), 0, 1, "")
	var c: int = _perception.spawn(&"watcher", base + Vector3i(5, 0, 1), 180, 1, "")
	_sim.step()
	assert_true(_perception.receive_report(a, _player, _actors.position_of(_player), _sim.get_tick()), "a is told")
	assert_true(_perception.receive_report(b, _player, _actors.position_of(_player), _sim.get_tick()), "b is told")
	assert_true(_perception.receive_report(c, _player, _actors.position_of(_player), _sim.get_tick()), "c is told")
	_sim.step_n(30)  # their own alerts become reports; delivery triggers the planner
	assert_true(_squads.has_assignment(a) and _squads.has_assignment(b) and _squads.has_assignment(c), "every member outside has an entry")
	var cells: Array[Vector3i] = [_squads.assignment_of(a), _squads.assignment_of(b), _squads.assignment_of(c)]
	assert_true(cells[0] != cells[1] and cells[1] != cells[2] and cells[0] != cells[2], "three distinct entries")
	assert_eq(cells[0], base + Vector3i(1, 0, -1), "the first member takes the cheapest edge: outside the door")
	for cell: Vector3i in cells:
		assert_eq(portals.node_at(cell), PortalGraph.EXTERIOR, "every entry cell is outside")
	# a member already inside carries no assignment
	_actors.set_position(c, BuildSystem.cell_centre(base + Vector3i(0, 0, 0)))
	_build.breach(_build.piece_ids()[0])  # any change re-plans
	_sim.step()
	assert_false(_squads.has_assignment(c), "inside: nothing to enter")
	assert_true(_squads.has_assignment(a) and _squads.has_assignment(b), "the others still have theirs")


func test_restore_round_trip_and_rejections() -> void:
	_setup()
	_screen()
	var lookout: int = _perception.spawn(&"watcher", _cell(2, 8), 90, 1, "")
	var behind: int = _perception.spawn(&"watcher", _cell(2, 2), 90, 1, "")
	_sim.step()
	_actors.set_position(_player, _at(2, 14))
	assert_true(_ticks_until(func() -> bool: return _squads.pending_count() > 0, 100) < NEVER, "a report in flight")
	var snap: Dictionary = _sim.snapshot()
	var other: SimRoot = SimAssembly.build(SEED, _db())
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "restored mid-flight")
	assert_eq(other.restore_root(snap), OK, "root restored")
	_sim.step_n(30)
	other.step_n(30)
	assert_true(_squads.delivered_count() >= 1 and _perception.has_last_known(behind, _player), "delivered here: the member remembers where the contact was")
	assert_true(SimAssembly.squads_of(other).delivered_count() >= 1 and SimAssembly.perception_of(other).has_last_known(behind, _player), "and there")
	assert_eq(other.state_hash(), _sim.state_hash(), "hashes agree")
	assert_true(lookout > 0, "spawned")
	var squads: SquadSystem = SimAssembly.squads_of(other)
	var state: Dictionary = _squads.snapshot()
	assert_eq(squads.restore({}), ERR_INVALID_DATA, "empty")
	var bad: Dictionary = state.duplicate(true)
	bad["reports"] = [{"due": 1, "squad": 1, "reporter": _player, "contact": behind, "cell": [0, 0, 0]}]
	assert_eq(squads.restore(bad), ERR_INVALID_DATA, "a report from a non-agent")
	bad = state.duplicate(true)
	var assignments: Dictionary = bad["assignments"]
	assignments[_player] = [0, 0, 0]
	assert_eq(squads.restore(bad), ERR_INVALID_DATA, "an assignment for a non-agent")
	assert_eq(squads.snapshot(), state, "rejections leave the state untouched")
