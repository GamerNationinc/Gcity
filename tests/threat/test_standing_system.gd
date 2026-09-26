extends GcityTest

## M6 spec claim 11: heat and notoriety are per-actor scalars raised by content rules
## on bus events, as skill xp is, cooling by their content's decay each tick and never
## past their bounds. Property: over generated event streams the values equal an
## independent recount.

const SEED: int = 20261160
const SEED_PROPERTY: int = 20261161
const PROPERTY_CASES: int = 10_000

var _sim: SimRoot
var _standing: StandingSystem
var _events: EventBus
var _a: int = 0
var _b: int = 0


func _setup(db: ContentDb = null) -> void:
	if db == null:
		db = ContentDb.new()
		assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_standing = SimAssembly.standing_of(_sim)
	_events = SimAssembly.combat_of(_sim).events()
	_a = SimAssembly.actors_of(_sim).spawn(&"arcade", 0)
	_b = SimAssembly.actors_of(_sim).spawn(&"arcade", 0)


func _violation(actor: int) -> void:
	_events.emit(LandSystem.EVENT_VIOLATION, {"actor": actor, "parcel": &"starter_plot", "right": &"build", "x": 0, "y": 0, "z": 0})


func test_a_violation_warms_the_one_who_did_it_and_heat_cools() -> void:
	_setup()
	assert_eq(_standing.value_of(_a, &"heat"), 0, "cold at first")
	_violation(_a)
	assert_eq(_standing.value_of(_a, &"heat"), 1000, "a violation is 1000 heat")
	assert_eq(_standing.value_of(_b, &"heat"), 0, "the other actor stays cold")
	_sim.step_n(400)
	assert_eq(_standing.value_of(_a, &"heat"), 600, "cooling by 1 a tick")
	_sim.step_n(1000)
	assert_eq(_standing.value_of(_a, &"heat"), 0, "and never below nothing")
	var records: Dictionary = _standing.snapshot()["standing"]
	assert_true(records.is_empty(), "a cold actor leaves no record")


func test_heat_stops_at_its_max_and_notoriety_does_not_cool() -> void:
	_setup()
	for i: int in 30:
		_violation(_a)
	assert_eq(_standing.value_of(_a, &"heat"), 20000, "heat stops at its max")
	assert_eq(_standing.raise(_b, &"notoriety", 5000), true, "notoriety raised by hand, as a contract will")
	_sim.step_n(500)
	assert_eq(_standing.value_of(_b, &"notoriety"), 5000, "and it does not cool")
	assert_false(_standing.raise(_b, &"nothing", 5), "an unknown scalar is refused")
	assert_false(_standing.raise(999, &"heat", 5), "so is an unknown actor")


func test_events_crediting_nobody_known_change_nothing() -> void:
	_setup()
	var before: String = StateHash.of(_standing.snapshot())
	_violation(999)
	_events.emit(LandSystem.EVENT_VIOLATION, {"actor": "1"})
	_events.emit(LandSystem.EVENT_VIOLATION, {})
	assert_eq(StateHash.of(_standing.snapshot()), before, "no record for a stranger or a malformed payload")


func test_a_tag_filtered_rule_counts_only_tagged_events() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	assert_eq(db.add(&"standing_rule", &"zz_loud_shots", {"schema_version": 1, "description": "x", "event": "combat.fire",
		"credit": "shooter", "tags_any": ["weapon_class.handgun"], "scalar": "notoriety", "amount": 7}), OK, "a tagged rule")
	_setup(db)
	_events.emit(CombatSystem.EVENT_FIRE, {"shooter": _a, "weapon": 0, "target": 0, "round": 0, "tags": [&"weapon_class.rifle"] as Array[StringName]})
	assert_eq(_standing.value_of(_a, &"notoriety"), 0, "untagged: nothing")
	_events.emit(CombatSystem.EVENT_FIRE, {"shooter": _a, "weapon": 0, "target": 0, "round": 0, "tags": [&"weapon_class.handgun"] as Array[StringName]})
	assert_eq(_standing.value_of(_a, &"notoriety"), 7, "tagged: the amount")


func test_assembly_refuses_a_rule_naming_an_unknown_scalar() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	assert_eq(db.add(&"standing_rule", &"zz_bad", {"schema_version": 1, "description": "x", "event": "land.violation",
		"credit": "actor", "tags_any": [], "scalar": "wanted_level", "amount": 1}), OK, "added")
	assert_true(SimAssembly.build(SEED, db) == null, "refused")


## Standing equals a recount: every tick, each value cools by its decay, never below
## zero; every event adds its rule's amount to the credited actor, never past max.
func test_property_standing_equals_an_independent_recount() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	_setup()
	var db: ContentDb = _sim.get_system(&"content")
	var heat: Dictionary = db.get_entry(&"standing_scalar", &"heat")
	var decay: int = heat["decay_per_tick"]
	var cap: int = heat["max"]
	var who_ids: Array[int] = [_a, _b]
	var oracle: Array[int] = [0, 0]
	var failures: int = 0
	for case: int in PROPERTY_CASES:
		match rng.randi_range(0, 4):
			0, 1:
				var pick: int = rng.randi_range(0, 2)
				_violation(who_ids[pick] if pick < 2 else 999)
				if pick < 2:
					oracle[pick] = mini(cap, oracle[pick] + 1000)
			2:
				var pick: int = rng.randi_range(0, 1)
				_events.emit(&"sensor.tripped", {"sensor": 1, "actor": who_ids[pick]})
				oracle[pick] = mini(cap, oracle[pick] + 1500)
			_:
				var n: int = rng.randi_range(1, 60)
				_sim.step_n(n)
				for i: int in 2:
					oracle[i] = maxi(0, oracle[i] - decay * n)
		for i: int in 2:
			var got: int = _standing.value_of(who_ids[i], &"heat")
			if got != oracle[i]:
				failures += 1
				if failures <= 3:
					fail("case %d: actor %d heat %d, recount %d" % [case, who_ids[i], got, oracle[i]])
	assert_eq(failures, 0, "standing matched the recount over %d cases" % PROPERTY_CASES)


func test_snapshot_restore_round_trip_and_rejections() -> void:
	_setup()
	_violation(_a)
	_standing.raise(_b, &"notoriety", 3)
	var state: Dictionary = _standing.snapshot()
	var db: ContentDb = _sim.get_system(&"content")
	var fresh_sim: SimRoot = SimAssembly.build(SEED, db)
	SimAssembly.actors_of(fresh_sim).spawn(&"arcade", 0)
	SimAssembly.actors_of(fresh_sim).spawn(&"arcade", 0)
	var fresh: StandingSystem = SimAssembly.standing_of(fresh_sim)
	assert_eq(fresh.restore(state), OK, "restores")
	assert_eq(StateHash.of(fresh.snapshot()), StateHash.of(state), "round trip")
	for bad: Dictionary in [
		{}, {"standing": []}, {"standing": {}, "x": 1},
		{"standing": {999: {"heat": 1}}},
		{"standing": {_a: {"wanted": 1}}},
		{"standing": {_a: {"heat": -1}}},
		{"standing": {_a: {"heat": 20001}}},
		{"standing": {_a: {"heat": 0}}},
		{"standing": {"1": {"heat": 1}}},
	]:
		assert_eq(fresh.restore(bad), ERR_INVALID_DATA, "rejects %s" % [bad])
