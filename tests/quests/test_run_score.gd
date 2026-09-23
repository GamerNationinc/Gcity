extends GcityTest

## M6 spec claim 7 (design doc §15.4): four counters, each raised by an event the sim
## already emits; all four at zero is the bonus; partial credit is a multiplier from
## the curve. Property over 10 000 generated event streams: every counter is monotone
## while a run is on, the multiplier is monotone in each counter, and a run with no
## events scores the bonus.

const SEED: int = 20261200
const SEED_PROPERTY: int = 20261201
const PROPERTY_CASES: int = 10_000
const CURVE: StringName = &"fixer_standard"
const M: int = 1000

var _sim: SimRoot
var _score: RunScoreSystem
var _actors: ActorSystem
var _perception: PerceptionSystem
var _build: BuildSystem
var _events: EventBus
var _player: int = 0
var _scored: Array[Dictionary] = []


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	_score = SimAssembly.score_of(_sim)
	_actors = SimAssembly.actors_of(_sim)
	_perception = SimAssembly.perception_of(_sim)
	_build = SimAssembly.build_of(_sim)
	_events = SimAssembly.combat_of(_sim).events()
	_events.subscribe(RunScoreSystem.EVENT_SCORED, _on_scored)
	_scored = []
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, Vector3i(500 * M, 0, 500 * M))


func _on_scored(payload: Dictionary) -> void:
	_scored.append(payload)


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


func _alert(observer: int, contact: int) -> void:
	_events.emit(PerceptionSystem.EVENT_ALERTED, {"observer": observer, "contact": contact, "tick": _sim.get_tick()})


func _report(reporter: int, contact: int) -> void:
	_events.emit(SquadSystem.EVENT_REPORT, {"squad": 1, "reporter": reporter, "contact": contact, "cell": [0, 0, 0], "informed": [] as Array[int]})


func _kill(shooter: int, target: int) -> void:
	_events.emit(CombatSystem.EVENT_HIT, {"shooter": shooter, "weapon": 0, "target": target, "node": &"body", "damage": 1, "range_m": 5, "tags": [], "killed": true})


func test_a_clean_run_scores_the_bonus_and_the_counters_only_count_while_it_is_on() -> void:
	_setup()
	var guard: int = _perception.spawn(&"guard_sim", BuildSystem.cell_of(Vector3i(400 * M, 0, 400 * M)), 0, 1, "")
	# nothing counts before the run begins
	_alert(guard, _player)
	assert_eq(_score.counters(_player), [0, 0, 0, 0] as Array[int], "no run: nothing counted")
	assert_false(_score.is_running(_player), "not running")
	assert_false(_score.has_run(_player), "and no run on record at all")
	assert_true(_do(&"run.begin", {"actor": _player}), "the contract starts a run")
	assert_true(_score.is_running(_player), "running")
	assert_true(_score.is_clean(_player), "clean so far")
	assert_eq(_score.multiplier(_player, CURVE), 2000, "and clean is double")
	assert_true(_do(&"run.end", {"actor": _player}), "turned in")
	assert_true(_score.has_run(_player), "a run on record")
	assert_false(_score.is_running(_player), "but not running any more")
	assert_eq(_scored.size(), 1, "one run.scored")
	var clean: bool = _scored[0]["clean"]
	assert_true(clean, "a full stealth run")
	assert_eq(_scored[0]["detected"], 0, "nobody saw you")
	assert_false(_do(&"run.end", {"actor": _player}), "and it ends once")
	# after the run, events stop counting
	_alert(guard, _player)
	assert_eq(_score.times_detected(_player), 0, "the run is over: nothing counts")


func test_each_counter_is_raised_by_its_own_event() -> void:
	_setup()
	var guard: int = _perception.spawn(&"guard_sim", BuildSystem.cell_of(Vector3i(400 * M, 0, 400 * M)), 0, 1, "")
	var other: int = _actors.spawn(&"arcade", 0)
	assert_true(_do(&"run.begin", {"actor": _player}), "begin")
	_alert(guard, _player)
	_alert(guard, _player)
	assert_eq(_score.times_detected(_player), 2, "seen twice")
	_alert(guard, other)
	assert_eq(_score.times_detected(_player), 2, "someone else being seen is not your run")
	# an alarm needs the reporter to have seen you
	_report(guard, _player)
	assert_eq(_score.alarms_raised(_player), 0, "a radio call from a guard that never saw you is not an alarm")
	assert_true(_perception.receive_report(guard, _player, _actors.position_of(_player), _sim.get_tick()), "another guard places you for it")
	assert_true(_perception.is_alerted(guard, _player), "now it knows where you are")
	assert_eq(_score.times_detected(_player), 3, "and being placed is a detection like any other")
	_report(guard, _player)
	assert_eq(_score.alarms_raised(_player), 1, "so this report is an alarm")
	_kill(_player, other)
	assert_eq(_score.bodies(_player), 1, "a body is a body")
	_kill(guard, other)
	assert_eq(_score.bodies(_player), 1, "somebody else's kill is not yours")
	assert_false(_score.is_clean(_player), "not clean now")


## Each counter is priced once, in isolation, on an actor the sim is not otherwise
## touching: the sim's own guards raise these same counters, so a run being played
## cannot tell one price from another.
func test_the_curve_prices_each_counter_and_floors_the_total() -> void:
	_setup()
	var guard: int = _perception.spawn(&"guard_sim", BuildSystem.cell_of(Vector3i(400 * M, 0, 400 * M)), 0, 1, "")
	var solo: int = _actors.spawn(&"arcade", 0)
	var victim: int = _actors.spawn(&"arcade", 0)
	assert_true(_do(&"run.begin", {"actor": solo}), "begin")
	assert_eq(_score.multiplier(solo, CURVE), 2000, "nothing done: the clean bonus")
	_kill(solo, victim)
	assert_true(_actors.is_alive(victim), "shot but still standing")
	assert_eq(_score.multiplier(solo, CURVE), 1000 - 400, "a body costs per_body, and the bonus is gone")
	_actors.damage_node(victim, &"body", 999999)
	assert_false(_actors.is_alive(victim), "down")
	assert_eq(_score.traces_left(solo), 1, "left where it fell")
	assert_eq(_score.multiplier(solo, CURVE), 1000 - 400 - 150, "and the body it leaves costs per_trace")
	assert_true(_perception.receive_report(guard, solo, _actors.position_of(solo), _sim.get_tick()), "a guard is told where you are")
	assert_eq(_score.multiplier(solo, CURVE), 1000 - 400 - 150 - 100, "a detection costs per_detection")
	_report(guard, solo)
	assert_eq(_score.alarms_raised(solo), 1, "the alarm goes out")
	assert_eq(_score.multiplier(solo, CURVE), 250, "and the total stops at the curve's floor")
	assert_eq(_score.multiplier(solo, &"no_such_curve"), 1000, "an unknown curve pays flat")


func test_traces_are_what_is_left_behind_and_a_wipe_takes_one_away() -> void:
	_setup()
	var terminals: TerminalSystem = SimAssembly.terminals_of(_sim)
	var sites: SiteSystem = SimAssembly.sites_of(_sim)
	_raise_cold_storage()
	assert_true(sites.raise_site(_player, &"cold_storage"), "the site stands")
	var terminal: int = sites.terminals_of(&"cold_storage")[0]
	assert_true(_do(&"run.begin", {"actor": _player}), "begin")
	assert_eq(_score.traces_left(_player), 0, "nothing left behind yet")
	# a piece the player removes is a trace
	var grate: int = _build.face_piece_at(BuildSystem.face_key(sites.cell_of(&"cold_storage", Vector3i(4, 1, -2)), "ny"))
	assert_true(grate > 0, "the street grate")
	var grate_cell: Vector3i = sites.cell_of(&"cold_storage", Vector3i(4, 1, -2))
	var slot: String = _build.key_of_piece(grate)
	assert_eq(slot, BuildSystem.face_key(grate_cell, "ny"), "the grate's slot")
	assert_false(_build.remove(_player, grate).is_empty(), "cut it")
	assert_eq(_score.traces_left(_player), 1, "a cut grate is a trace")
	# a gap somebody closed again is not a gap: this is the same reading the terminals
	# and the bodies get, not a tally that can never be undone
	assert_true(_build.place(_player, &"floor_panel", BuildSystem.cell_centre(grate_cell), "ny") > 0, "put it back")
	assert_true(_score.traces_left(_player) == 0, "and the street looks untouched")
	var replaced: int = _build.face_piece_at(slot)
	assert_true(replaced > 0, "the new panel stands in the old slot")
	assert_false(_build.remove(_player, replaced).is_empty(), "cut it again")
	assert_eq(_score.traces_left(_player), 1, "open once more")
	# a terminal left open is a trace, and wiping it takes that away
	var inv: StringName = ItemSystem.inventory_of(_player)
	var items: ItemSystem = SimAssembly.items_of(_sim)
	var handset: int = items.spawn(&"device_frame", &"handset", inv, 1)
	var module: int = items.spawn(&"device_module", &"daemon_coprocessor", inv, 2)
	assert_true(_do(&"actor.equip_device", {"actor": _player, "device": handset}), "carried")
	assert_true(_do(&"item.attach", {"actor": _player, "weapon": handset, "part": module}), "fitted")
	_actors.set_position(_player, terminals.position_of(terminal))
	assert_true(_do(&"terminal.hack_start", {"actor": _player, "terminal": terminal}), "hacking")
	_sim.step_n(terminals.hack_ticks_of(terminal))
	assert_eq(_score.traces_left(_player), 2, "the open terminal is the second")
	assert_true(_do(&"terminal.wipe", {"actor": _player, "terminal": terminal}), "wipe the log")
	assert_eq(_score.traces_left(_player), 1, "and that trace is gone")
	# a body left where it fell is a trace
	var victim: int = _actors.spawn(&"arcade", 0)
	_kill(_player, victim)
	_actors.damage_node(victim, &"body", 999999)
	assert_false(_actors.is_alive(victim), "down")
	assert_eq(_score.traces_left(_player), 2, "a body left in the open is a trace")
	assert_true(_do(&"run.end", {"actor": _player}), "turned in")
	assert_eq(_scored[0]["traces"], 2, "the score records what was left")
	var clean: bool = _scored[0]["clean"]
	assert_false(clean, "not a stealth run")
	# the reading is frozen at the end: opening the terminal again afterwards belongs to
	# no run, and tidying up later cannot un-leave what was left
	assert_true(_do(&"terminal.hack_start", {"actor": _player, "terminal": terminal}), "hacking again")
	_sim.step_n(terminals.hack_ticks_of(terminal))
	assert_eq(terminals.traces(), 1, "the terminal is open once more")
	assert_eq(_score.traces_left(_player), 2, "but the finished run still reads two")


func test_property_counters_are_monotone_and_the_multiplier_follows_them() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	_setup()
	var guard: int = _perception.spawn(&"guard_sim", BuildSystem.cell_of(Vector3i(400 * M, 0, 400 * M)), 0, 1, "")
	var victim: int = _actors.spawn(&"range_dummy", 0)
	assert_true(_do(&"run.begin", {"actor": _player}), "begin")
	var violations: int = 0
	var previous: Array[int] = _score.counters(_player)
	var previous_multiplier: int = _score.multiplier(_player, CURVE)
	assert_eq(previous_multiplier, 2000, "a run with no events scores the bonus")
	for case: int in PROPERTY_CASES:
		match rng.randi_range(0, 2):
			0:
				_alert(guard, _player)
			1:
				_report(guard, _player)
			_:
				_kill(_player, victim)
		var now: Array[int] = _score.counters(_player)
		var multiplier: int = _score.multiplier(_player, CURVE)
		for i: int in 4:
			if now[i] < previous[i]:
				violations += 1
				if violations <= 3:
					fail("case %d: counter %d went backwards, %d to %d" % [case, i, previous[i], now[i]])
		if multiplier > previous_multiplier:
			violations += 1
			if violations <= 3:
				fail("case %d: the multiplier rose, %d to %d" % [case, previous_multiplier, multiplier])
		if multiplier < 250:
			violations += 1
			if violations <= 3:
				fail("case %d: the multiplier fell through the floor: %d" % [case, multiplier])
		previous = now
		previous_multiplier = multiplier
	assert_eq(violations, 0, "counters never fall, the multiplier never rises, and it stops at the floor")
	assert_eq(_score.multiplier(_player, CURVE), 250, "a long loud run bottoms out at the floor")
	assert_true(_score.times_detected(_player) > 2000, "the stream was substantial (%d detections)" % _score.times_detected(_player))


func test_restore_round_trip_and_rejections() -> void:
	_setup()
	var guard: int = _perception.spawn(&"guard_sim", BuildSystem.cell_of(Vector3i(400 * M, 0, 400 * M)), 0, 1, "")
	assert_true(_do(&"run.begin", {"actor": _player}), "begin")
	_alert(guard, _player)
	var snap: Dictionary = _sim.snapshot()
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "restored")
	assert_eq(other.restore_root(snap), OK, "root restored")
	var score: RunScoreSystem = SimAssembly.score_of(other)
	assert_eq(score.times_detected(_player), 1, "the run carried over")
	assert_true(score.is_running(_player), "still on")
	_sim.step()
	other.step()
	assert_eq(other.state_hash(), _sim.state_hash(), "hashes agree")
	var state: Dictionary = _score.snapshot()
	assert_eq(score.restore({}), ERR_INVALID_DATA, "empty")
	var bad: Dictionary = state.duplicate(true)
	var runs: Dictionary = bad["runs"]
	var rec: Dictionary = runs[_player]
	rec["detected"] = -1
	assert_eq(score.restore(bad), ERR_INVALID_DATA, "a negative counter")
	bad = state.duplicate(true)
	runs = bad["runs"]
	rec = runs[_player]
	rec["corpses"] = [9999]
	assert_eq(score.restore(bad), ERR_INVALID_DATA, "a body that is not an actor")
	bad = state.duplicate(true)
	runs = bad["runs"]
	rec = runs[_player]
	rec["traces"] = 5
	assert_eq(score.restore(bad), ERR_INVALID_DATA, "a live run with a frozen trace reading")
	assert_eq(score.snapshot(), state, "rejections leave the state untouched")


## Cold Storage stands on `cold_storage_lot`, which the operator owns; a builder can
## only raise it on land that is theirs, so the test takes the lot first exactly as
## the client does before raising a site on owned ground.
func _raise_cold_storage() -> void:
	var at: int = _sim.get_tick() + 1
	assert_eq(_sim.submit(SimCommand.new(at, &"land.identify", {"actor": _player, "owner": "player"})), OK, "identify")
	assert_eq(_sim.submit(SimCommand.new(at, &"land.transfer", {"parcel": "cold_storage_lot", "owner": "player"})), OK, "transfer")
	_sim.step()
