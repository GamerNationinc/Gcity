extends GcityTest

## M6 spec claim 11: heat and notoriety are per-actor integer scalars (content kind
## `standing`), raised by bus events through content rules {standing, event, credit,
## tags_any, violating, amount} the way skill xp rules are. A rule with `violating`
## applies only while the credited actor stands where it lacks that right: an alert on
## a contact standing in violation of `enter` is a witnessed trespass. Each standing
## falls by its content rate every 1000 ticks and never goes below zero; notoriety's
## rate is 0. Property: over 10 000 generated event streams the standings equal a
## straightforward recount, and none is ever negative.

const SEED: int = 20261030
const SEED_PROPERTY: int = 20261031
const PROPERTY_CASES: int = 10_000
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)

var _sim: SimRoot
var _actors: ActorSystem
var _standing: StandingSystem
var _events: EventBus
var _player: int = 0


func _content() -> ContentDb:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var district: Dictionary = db.get_entry(&"district", &"starter_ghetto").duplicate(true)
	var rights: Dictionary = district["rights"]
	var other: Dictionary = rights["other"]
	other["enter"] = false
	assert_eq(db.add(&"district", &"zz_private", district), OK, "a district where non-owners may not enter")
	return db


func _setup(db: ContentDb = null) -> void:
	if db == null:
		db = _content()
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_standing = SimAssembly.standing_of(_sim)
	_events = SimAssembly.combat_of(_sim).events()
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, _feet(-20, -20))
	var land: LandSystem = SimAssembly.land_of(_sim)
	var x0: int = FAR.x
	var z0: int = FAR.z
	assert_eq(land.add_parcel(&"zz_yard", &"zz_private", &"corp", [[x0, z0], [x0 + 10 * M, z0], [x0 + 10 * M, z0 + 10 * M], [x0, z0 + 10 * M]], -M, 3 * M), OK, "a private yard")


func _feet(cx: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, 0, cz * M + 500)


func _at(cx: int, cy: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, cy * M + 500, cz * M + 500)


func _alarm(actor: int) -> void:
	_events.emit(SensorSystem.EVENT_ALARM, {"sensor": &"power_monitor", "piece": 1, "squad": 1, "actor": actor})


func test_an_alarm_against_an_actor_raises_its_heat() -> void:
	_setup()
	assert_eq(_standing.standing_of(_player, &"heat"), 0, "cold to start")
	_alarm(_player)
	assert_eq(_standing.standing_of(_player, &"heat"), 200, "an alarm is 200 heat")
	_alarm(_player)
	assert_eq(_standing.standing_of(_player, &"heat"), 400, "and adds up")
	assert_eq(_standing.standing_of(_player, &"notoriety"), 0, "notoriety is untouched")
	_alarm(999)
	assert_eq(_standing.standing_of(999, &"heat"), 0, "an unknown actor is never credited")
	assert_eq(_standing.standing_of(_player, &"zz_nothing"), 0, "an unknown standing reads 0")


func test_a_real_alarm_from_a_sensor_raises_heat() -> void:
	_setup()
	var build: BuildSystem = SimAssembly.build_of(_sim)
	_actors.set_position(_player, _feet(-20, -20))
	for c: Vector3i in [Vector3i(-31, 0, -30), Vector3i(-30, 0, -29), Vector3i(-30, 0, -31)]:
		assert_true(build.place(_player, &"foundation_block", _at(c.x, c.y, c.z), "") > 0, "foundation")
	assert_true(build.place(_player, &"floor_panel", _at(-30, 0, -30), "py") > 0, "roof")
	var window: int = build.place(_player, &"window_frame", _at(-30, 0, -30), "px")
	assert_true(window > 0, "window")
	assert_true(SimAssembly.sensors_of(_sim).install(&"power_monitor", window, 1), "a monitor")
	_actors.set_position(_player, _feet(-30, -30))
	_sim.submit(SimCommand.new(_sim.get_tick() + 1, &"opening.open", {"actor": _player, "piece": window}))
	_sim.step()
	assert_eq(SimAssembly.sensors_of(_sim).alarm_count(), 1, "the monitor tripped")
	assert_eq(_standing.standing_of(_player, &"heat"), 200, "and the player's heat rose")


func test_an_alert_is_a_witnessed_trespass_only_inside_where_entry_is_barred() -> void:
	_setup()
	var perception: PerceptionSystem = SimAssembly.perception_of(_sim)
	_actors.set_position(_player, _feet(14, 5))  # outside the yard, in the open street
	var guard: int = perception.spawn(&"guard_sim", BuildSystem.cell_of(_feet(12, 5)), 0, 1, "")
	assert_true(guard > 0, "a guard facing the player")
	var outside: int = _run_until_alerted(guard)
	assert_true(outside > 0, "alerted to the player outside the yard")
	assert_eq(_standing.standing_of(_player, &"heat"), 0, "no trespass outside: no heat")
	_setup()
	perception = SimAssembly.perception_of(_sim)
	_actors.set_position(_player, _feet(5, 5))  # inside the private yard
	guard = perception.spawn(&"guard_sim", BuildSystem.cell_of(_feet(3, 5)), 0, 1, "")
	assert_true(_run_until_alerted(guard) > 0, "alerted to the player inside the yard")
	assert_eq(_standing.standing_of(_player, &"heat"), 100, "a witnessed trespass is 100 heat")
	_actors.set_position(_player, _feet(5, 5))


func _run_until_alerted(guard: int) -> int:
	var perception: PerceptionSystem = SimAssembly.perception_of(_sim)
	for i: int in 400:
		_sim.step()
		if perception.is_alerted(guard, _player):
			return _sim.get_tick()
	return -1


func test_heat_decays_every_1000_ticks_and_never_below_zero_and_notoriety_stays() -> void:
	_setup()
	_alarm(_player)
	_events.emit(&"contract.delivered", {"actor": _player, "quest": &"cold_storage"})
	assert_eq(_standing.standing_of(_player, &"notoriety"), 100, "a contract is 100 notoriety")
	_sim.step_n(999 - _sim.get_tick())
	assert_eq(_standing.standing_of(_player, &"heat"), 200, "no decay before tick 1000")
	_sim.step()
	assert_eq(_standing.standing_of(_player, &"heat"), 150, "50 off at tick 1000")
	_sim.step_n(3000)
	assert_eq(_standing.standing_of(_player, &"heat"), 0, "0 by tick 4000")
	_sim.step_n(2000)
	assert_eq(_standing.standing_of(_player, &"heat"), 0, "and never below")
	assert_eq(_standing.standing_of(_player, &"notoriety"), 100, "notoriety does not decay")


func test_rules_are_validated_at_assembly() -> void:
	var bad_rules: Array[Dictionary] = [
		{"standing": "zz_nothing", "violating": ""},
		{"standing": "heat", "violating": "fly"},
	]
	for patch: Dictionary in bad_rules:
		var db: ContentDb = _content()
		var rule: Dictionary = db.get_entry(&"standing_rule", &"heat_alarm").duplicate(true)
		rule.merge(patch, true)
		assert_eq(db.add(&"standing_rule", &"zz_bad", rule), OK, "a bad rule")
		assert_eq(SimAssembly.build(SEED, db), null, "rejected: %s" % str(patch))


func test_the_snapshot_restores_and_rejects_hostile_state() -> void:
	_setup()
	_alarm(_player)
	_events.emit(&"contract.delivered", {"actor": _player, "quest": &"x"})
	var snap: Dictionary = _standing.snapshot()
	assert_eq(_standing.restore(snap.duplicate(true)), OK, "restores")
	assert_eq(StateHash.of(_standing.snapshot()), StateHash.of(snap), "exactly")
	var hostile: Array[Dictionary] = []
	var bad: Dictionary = snap.duplicate(true)
	var per: Dictionary = bad["standing"]
	var rec: Dictionary = per[_player]
	rec[&"heat"] = -1
	hostile.append(bad)
	bad = snap.duplicate(true)
	per = bad["standing"]
	rec = per[_player]
	rec[&"zz_nothing"] = 5
	hostile.append(bad)
	bad = snap.duplicate(true)
	per = bad["standing"]
	per[999] = {&"heat": 5}
	hostile.append(bad)
	bad = snap.duplicate(true)
	per = bad["standing"]
	rec = per[_player]
	rec[&"heat"] = 0  # zeros are not stored: a stored zero is not a state the sim makes
	hostile.append(bad)
	bad = snap.duplicate(true)
	bad["extra"] = 1
	hostile.append(bad)
	for h: Dictionary in hostile:
		assert_eq(_standing.restore(h), ERR_INVALID_DATA, "a hostile snapshot is rejected")
	assert_eq(StateHash.of(_standing.snapshot()), StateHash.of(snap), "and changes nothing")


func test_property_standings_equal_a_recount_and_are_never_negative() -> void:
	_setup()
	var others: Array[int] = [_player, _actors.spawn(&"arcade", 1), _actors.spawn(&"arcade", 2)]
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	var heat: Dictionary[int, int] = {}
	var notoriety: Dictionary[int, int] = {}
	for a: int in others:
		heat[a] = 0
		notoriety[a] = 0
	var mismatches: int = 0
	var negatives: int = 0
	for case: int in PROPERTY_CASES:
		var actor: int = others[rng.randi_range(0, others.size() - 1)]
		var credited: int = actor if rng.randi_range(0, 9) > 0 else 777
		match rng.randi_range(0, 3):
			0:
				_alarm(credited)
				if credited == actor:
					heat[actor] = heat[actor] + 200
			1:
				var inside: bool = rng.randi_range(0, 1) == 0
				_actors.set_position(actor, _feet(5, 5) if inside else _feet(14, 5))
				_events.emit(PerceptionSystem.EVENT_ALERTED, {"observer": 1, "contact": credited, "tick": _sim.get_tick()})
				if credited == actor and inside:
					heat[actor] = heat[actor] + 100
			2:
				_events.emit(&"contract.delivered", {"actor": credited, "quest": &"q"})
				if credited == actor:
					notoriety[actor] = notoriety[actor] + 100
			3:
				var n: int = rng.randi_range(1, 400)
				for k: int in n:
					_sim.step()
					if _sim.get_tick() % 1000 == 0:
						for a: int in others:
							heat[a] = maxi(0, heat[a] - 50)
		for a: int in others:
			var h: int = _standing.standing_of(a, &"heat")
			var n2: int = _standing.standing_of(a, &"notoriety")
			if h < 0 or n2 < 0:
				negatives += 1
			if h != heat[a] or n2 != notoriety[a]:
				mismatches += 1
	assert_eq(negatives, 0, "never negative")
	assert_eq(mismatches, 0, "always equal to the recount")
	assert_true(_sim.get_tick() > 100_000, "over a long stream (%d ticks)" % _sim.get_tick())
