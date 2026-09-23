extends GcityTest

## M4 spec claim 8: per-agent stress rises when fired at, hit or bereaved, decays per
## tick, degrades aim through the resolver and marks the agent broken or routed.
## Metamorphic: more stress never improves aim.
##
## M4 spec claim 6: an agent's error cone converges while its target stays visible,
## resets on broken contact, swings on a target that appears, and reaches combat as
## a hit_chance modifier through the stat resolver. Metamorphic (standards §3.4):
## longer exposure never lowers the agent's hit chance; a broken contact never raises
## it; a wider settled cone never raises it.

const SEED: int = 20261030
const SEED_PROPERTY: int = 20261031
const PROPERTY_CASES: int = 10_000
const SIM_CASES: int = 60
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)

var _sim: SimRoot
var _actors: ActorSystem
var _perception: PerceptionSystem
var _aim: AimSystem
var _stress: StressSystem
var _combat: CombatSystem
var _items: ItemSystem
var _player: int = 0


func _setup(db: ContentDb = null) -> void:
	if db == null:
		db = ContentDb.new()
		assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_perception = SimAssembly.perception_of(_sim)
	_aim = SimAssembly.aim_of(_sim)
	_stress = SimAssembly.stress_of(_sim)
	_combat = SimAssembly.combat_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, _at(10, 0))


func _cell(cx: int, cz: int) -> Vector3i:
	return BuildSystem.cell_of(FAR) + Vector3i(cx, 0, cz)


func _at(cx: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, 0, cz * M + 500)


## A guard at the origin facing +x, wielding a G19 through the wield command.
func _armed_guard(profile: StringName = &"guard_sim") -> Array[int]:
	var guard: int = _perception.spawn(profile, _cell(0, 0), 0, 1, "")
	assert_true(guard > 0, "guard spawned")
	var pistol: int = _items.spawn(&"weapon_frame", &"g19", ItemSystem.inventory_of(guard), 1)
	assert_true(pistol > 0, "pistol spawned")
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, ActorSystem.COMMAND_WIELD, {"actor": guard, "weapon": pistol})), OK, "submit wield")
	return [guard, pistol]


func _chance(guard: int, pistol: int) -> int:
	return _combat.hit_chance_at(guard, pistol, 10)


func test_cone_arithmetic() -> void:
	var p: Dictionary = {"cone_start_mdeg": 8000, "cone_settled_mdeg": 1000, "settle_ticks": 48, "swing_penalty_mdeg": 4000, "swing_ticks": 12, "penalty_per_mdeg": 50}
	assert_eq(AimSystem.cone_mdeg(p, 0, 0), 8000, "unsettled: the start cone")
	assert_eq(AimSystem.cone_mdeg(p, 48, 0), 1000, "settled")
	assert_eq(AimSystem.cone_mdeg(p, 24, 0), 4500, "halfway")
	assert_eq(AimSystem.cone_mdeg(p, 0, 5), 12000, "swinging: start plus the penalty")
	assert_eq(AimSystem.cone_mdeg(p, 100, 0), 1000, "clamped to the settle count")


func test_the_cone_settles_on_a_visible_target_resets_on_break_and_swings_on_return() -> void:
	_setup()
	var armed: Array[int] = _armed_guard()
	var guard: int = armed[0]
	var pistol: int = armed[1]
	assert_eq(_aim.cone_of(guard), 8000, "no record yet: the start cone")
	_sim.step()  # the wield lands; the guard sees the player at 10 m and swings onto it
	assert_eq(_aim.target_of(guard), _player, "aiming at the player")
	assert_eq(_aim.cone_of(guard), 12000, "swinging through onto a new target")
	assert_eq(_aim.penalty_of(guard), 600000, "60 % off")
	assert_eq(_chance(guard, pistol), 0, "650 000 - 600 000 - 50 000 falloff at 10 m: nothing")
	var previous: int = _chance(guard, pistol)
	for i: int in 60:
		_sim.step()
		var now: int = _chance(guard, pistol)
		assert_true(now >= previous, "tick %d: exposure never lowers the hit chance (%d -> %d)" % [i, previous, now])
		previous = now
	assert_eq(_aim.settle_of(guard), 48, "fully settled")
	assert_eq(_aim.cone_of(guard), 1000, "the settled cone")
	assert_eq(_chance(guard, pistol), 550000, "650 000 - 50 000 aim - 50 000 falloff")
	var settled: int = _chance(guard, pistol)
	_actors.set_position(_player, _at(-10, 0))
	_sim.step()
	assert_eq(_aim.target_of(guard), 0, "contact broken: no target")
	assert_eq(_aim.cone_of(guard), 8000, "back to the start cone")
	assert_true(_chance(guard, pistol) < settled, "a broken contact never raises the hit chance")
	_actors.set_position(_player, _at(10, 0))
	_sim.step()
	assert_eq(_aim.cone_of(guard), 12000, "the target reappears: swing again")
	_sim.step_n(12)
	assert_eq(_aim.cone_of(guard), 8000 - 7000 * 12 / 48, "the swing has passed after 12 ticks; 12 ticks of settling")
	var own: int = _items.spawn(&"weapon_frame", &"g19", ItemSystem.inventory_of(_player), 1)
	assert_eq(_combat.hit_chance_at(_player, own, 10), 600000, "the player, without an aim profile, carries no aim modifier")


func test_a_swing_outlives_a_broken_contact() -> void:
	_setup()
	var armed: Array[int] = _armed_guard()
	var guard: int = armed[0]
	var pistol: int = armed[1]
	_sim.step_n(4)  # swinging onto the player: 8 swing ticks left, 3 ticks settled
	assert_eq(_aim.cone_of(guard), 4000 + 1000 + 7000 * 45 / 48, "swinging and settling")
	var before: int = _chance(guard, pistol)
	_actors.set_position(_player, _at(-10, 0))
	_sim.step()
	assert_eq(_aim.cone_of(guard), 4000 + 8000, "the swing stays; the settle is gone")
	assert_true(_chance(guard, pistol) <= before, "so the break never raises the hit chance")


func test_switching_targets_resets_the_settle() -> void:
	_setup()
	var armed: Array[int] = _armed_guard()
	var guard: int = armed[0]
	var other: int = _actors.spawn(&"arcade", 0)
	_actors.set_position(other, _at(12, 0))
	_sim.step_n(20)
	assert_eq(_aim.target_of(guard), _player, "the nearer contact is seen more: the player")
	assert_true(_aim.settle_of(guard) > 10, "settling on it")
	_actors.set_position(_player, _at(-10, 0))
	_sim.step()
	assert_eq(_aim.target_of(guard), other, "the other contact takes over")
	assert_eq(_aim.settle_of(guard), 0, "with the settle reset")
	assert_eq(_aim.cone_of(guard), 12000, "and a swing")


func test_property_cone_relations_over_random_profiles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	var violations: int = 0
	for case: int in PROPERTY_CASES:
		var settled: int = rng.randi_range(0, 90000)
		var start: int = rng.randi_range(settled, 180000)
		var ticks: int = rng.randi_range(1, 200)
		var p: Dictionary = {"cone_start_mdeg": start, "cone_settled_mdeg": settled, "settle_ticks": ticks,
			"swing_penalty_mdeg": rng.randi_range(0, 20000), "swing_ticks": rng.randi_range(0, 40), "penalty_per_mdeg": rng.randi_range(0, 100)}
		var wider: Dictionary = p.duplicate()
		wider["cone_settled_mdeg"] = rng.randi_range(settled, start)
		var s: int = rng.randi_range(0, ticks)
		var swing: int = rng.randi_range(0, 3)
		var now: int = AimSystem.cone_mdeg(p, s, swing)
		var later: int = AimSystem.cone_mdeg(p, s + 1, maxi(swing - 1, 0))
		var reset: int = AimSystem.cone_mdeg(p, 0, swing)
		var wide: int = AimSystem.cone_mdeg(wider, s, swing)
		if later > now or reset < now or wide < now or now < settled:
			violations += 1
			if violations <= 3:
				fail("case %d: now %d later %d reset %d wide %d" % [case, now, later, reset, wide])
	assert_eq(violations, 0, "exposure never widens the cone; a reset never narrows it; a wider settled cone is never narrower")


func test_metamorphic_hit_chance_over_random_profiles_in_the_sim() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	var violations: int = 0
	for case: int in SIM_CASES:
		var settled: int = rng.randi_range(0, 6000)
		var aim: Dictionary = {"schema_version": 1, "description": "generated", "cone_start_mdeg": rng.randi_range(settled, 12000), "cone_settled_mdeg": settled,
			"settle_ticks": rng.randi_range(1, 60), "swing_penalty_mdeg": rng.randi_range(0, 5000), "swing_ticks": rng.randi_range(0, 20), "penalty_per_mdeg": rng.randi_range(0, 60)}
		var db := ContentDb.new()
		assert_eq(ContentLoader.load_all(db), OK, "content loads")
		db.add(&"aim_profile", &"t_aim", aim)
		db.add(&"agent_profile", &"t_agent", {"schema_version": 1, "description": "generated", "combat_profile": "arcade", "perception_profile": "guard_sim", "aim_profile": "t_aim", "stress_profile": "guard_sim", "stances": [{"stance": "hold", "weight": 1000}], "radio": false, "radio_latency_ticks": 0})
		_setup(db)
		var armed: Array[int] = _armed_guard(&"t_agent")
		var guard: int = armed[0]
		var pistol: int = armed[1]
		_sim.step()
		var previous: int = _chance(guard, pistol)
		var ticks: int = rng.randi_range(1, 80)
		for i: int in ticks:
			_sim.step()
			var now: int = _chance(guard, pistol)
			if now < previous:
				violations += 1
				if violations <= 3:
					fail("case %d tick %d: exposure lowered the hit chance %d -> %d" % [case, i, previous, now])
			previous = now
		_actors.set_position(_player, _at(-10, 0))
		_sim.step()
		if _chance(guard, pistol) > previous:
			violations += 1
			if violations <= 3:
				fail("case %d: a broken contact raised the hit chance %d -> %d" % [case, previous, _chance(guard, pistol)])
	assert_eq(violations, 0, "relations held over %d generated profiles" % SIM_CASES)


func test_restore_round_trip_and_rejections() -> void:
	_setup()
	var armed: Array[int] = _armed_guard()
	var guard: int = armed[0]
	_sim.step_n(7)
	var snap: Dictionary = _sim.snapshot()
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "restored")
	assert_eq(other.restore_root(snap), OK, "root restored")
	var aim: AimSystem = SimAssembly.aim_of(other)
	assert_eq(aim.snapshot(), _aim.snapshot(), "equal state")
	assert_eq(aim.settle_of(guard), 6, "settle carried over")
	_sim.step()
	other.step()
	assert_eq(other.state_hash(), _sim.state_hash(), "steps on together")
	var state: Dictionary = _aim.snapshot()
	assert_eq(aim.restore({}), ERR_INVALID_DATA, "empty")
	var bad: Dictionary = state.duplicate(true)
	var records: Dictionary = bad["aim"]
	records[_player] = records[guard]
	assert_eq(aim.restore(bad), ERR_INVALID_DATA, "a record for a non-agent")
	bad = state.duplicate(true)
	records = bad["aim"]
	var rec: Dictionary = records[guard]
	rec["value"] = 5
	assert_eq(aim.restore(bad), ERR_INVALID_DATA, "a positive aim modifier")
	assert_eq(aim.snapshot(), state, "rejections leave the state untouched")


# ---------------------------------------------------------------- claim 8: stress

func _fire_event(shooter: int, target: int) -> void:
	SimAssembly.combat_of(_sim).events().emit(CombatSystem.EVENT_FIRE, {"shooter": shooter, "weapon": 0, "target": target, "round": 0, "tags": []})


func _hit_event(shooter: int, target: int, killed: bool) -> void:
	SimAssembly.combat_of(_sim).events().emit(CombatSystem.EVENT_HIT, {"shooter": shooter, "weapon": 0, "target": target, "node": &"body", "damage": 1, "range_m": 5, "tags": [], "killed": killed})


func test_stress_rises_when_fired_at_hit_or_bereaved_and_decays() -> void:
	_setup()
	var a: int = _perception.spawn(&"guard_sim", _cell(0, 0), 0, 1, "")
	var b: int = _perception.spawn(&"guard_sim", _cell(0, 1), 0, 1, "")  # 1 m beside the player's line to a
	var c: int = _perception.spawn(&"guard_sim", _cell(0, 4), 0, 1, "")  # 4 m off it
	var d: int = _perception.spawn(&"guard_sim", _cell(5, 5), 0, 2, "")  # another squad
	_actors.set_position(_player, _at(10, 0))
	_fire_event(_player, a)
	assert_eq(_stress.stress_of(a), 150000, "fired at")
	assert_eq(_stress.stress_of(b), 150000, "a near miss within 1.5 m of the line")
	assert_eq(_stress.stress_of(c), 0, "4 m off the line: nothing")
	assert_eq(_stress.stress_of(d), 0, "nowhere near")
	_hit_event(_player, a, false)
	assert_eq(_stress.stress_of(a), 450000, "hit")
	assert_false(_stress.is_broken(a), "not yet broken at 45 %")
	_hit_event(_player, a, true)
	assert_eq(_stress.stress_of(a), 750000, "hit again")
	assert_true(_stress.is_broken(a), "broken at 75 %")
	assert_false(_stress.is_routed(a), "not routed")
	assert_eq(_stress.stress_of(b), 400000, "b: a squadmate went down")
	assert_eq(_stress.stress_of(c), 250000, "c too")
	assert_eq(_stress.stress_of(d), 0, "another squad is unmoved")
	_fire_event(a, _player)
	assert_eq(_stress.stress_of(b), 400000, "a squadmate's own fire past you is not a near miss")
	_sim.step()
	assert_eq(_stress.stress_of(a), 747500, "decays per tick")
	_hit_event(_player, a, false)
	_hit_event(_player, a, false)
	assert_eq(_stress.stress_of(a), StressSystem.STRESS_MAX, "clamped")
	assert_true(_stress.is_routed(a), "routed at full stress")
	_sim.step_n(400)
	assert_eq(_stress.stress_of(a), 0, "recovered in 10 s")
	assert_eq(StressSystem.distance_to_segment_mm(Vector3i(0, 0, 1500), Vector3i(-5000, 0, 0), Vector3i(5000, 0, 0)), 1500, "distance to a segment")
	assert_eq(StressSystem.distance_to_segment_mm(Vector3i(8000, 0, 0), Vector3i(0, 0, 0), Vector3i(5000, 0, 0)), 3000, "past its end")


func test_stress_degrades_aim_through_the_resolver_and_never_improves_it() -> void:
	_setup()
	var armed: Array[int] = _armed_guard()
	var guard: int = armed[0]
	var pistol: int = armed[1]
	_sim.step_n(70)
	assert_eq(_chance(guard, pistol), 550000, "settled, calm")
	_hit_event(_player, guard, false)
	_sim.step()
	assert_eq(_stress.stress_of(guard), 297500, "hit, one tick of decay")
	assert_eq(_stress.penalty_of(guard), 89250, "30 % of the penalty at 29.75 % stress")
	assert_eq(_chance(guard, pistol), 550000 - 89250, "the hit chance carries the stress penalty")
	var previous: int = _chance(guard, pistol)
	for i: int in 30:
		_hit_event(_player, guard, false)
		_sim.step()
		var now: int = _chance(guard, pistol)
		assert_true(now <= previous or _stress.stress_of(guard) < 300000, "more stress never improves aim (tick %d: %d -> %d)" % [i, previous, now])
		previous = now
	assert_eq(_stress.stress_of(guard), 997500, "full stress less one tick of decay")
	assert_eq(_chance(guard, pistol), 550000 - 299250, "29.925 % off")
	var own: int = _items.spawn(&"weapon_frame", &"g19", ItemSystem.inventory_of(_player), 1)
	assert_eq(_combat.hit_chance_at(_player, own, 10), 600000, "the player, without a profile, is untouched")


func test_property_stress_penalty_is_monotone() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	var violations: int = 0
	for case: int in PROPERTY_CASES:
		var p: Dictionary = {"hit_penalty_at_max": rng.randi_range(0, 1000000)}
		var low: int = rng.randi_range(0, StressSystem.STRESS_MAX)
		var high: int = rng.randi_range(low, StressSystem.STRESS_MAX)
		var at_max: int = p["hit_penalty_at_max"]
		if StressSystem.penalty(p, high) < StressSystem.penalty(p, low) or StressSystem.penalty(p, StressSystem.STRESS_MAX) != at_max or StressSystem.penalty(p, 0) != 0:
			violations += 1
			if violations <= 3:
				fail("case %d: %d at %d, %d at %d" % [case, StressSystem.penalty(p, low), low, StressSystem.penalty(p, high), high])
	assert_eq(violations, 0, "more stress never lowers the penalty")


func test_stress_restore_round_trip_and_rejections() -> void:
	_setup()
	var guard: int = _perception.spawn(&"guard_sim", _cell(0, 0), 0, 1, "")
	_hit_event(_player, guard, false)
	_sim.step_n(3)
	var snap: Dictionary = _sim.snapshot()
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "restored")
	assert_eq(other.restore_root(snap), OK, "root restored")
	var stress: StressSystem = SimAssembly.stress_of(other)
	assert_eq(stress.stress_of(guard), 292500, "stress carried over")
	_sim.step()
	other.step()
	assert_eq(other.state_hash(), _sim.state_hash(), "steps on together")
	var state: Dictionary = _stress.snapshot()
	assert_eq(stress.restore({}), ERR_INVALID_DATA, "empty")
	var bad: Dictionary = state.duplicate(true)
	var records: Dictionary = bad["stress"]
	var rec: Dictionary = records[guard]
	rec["stress"] = StressSystem.STRESS_MAX + 1
	assert_eq(stress.restore(bad), ERR_INVALID_DATA, "over the maximum")
	bad = state.duplicate(true)
	records = bad["stress"]
	records[_player] = records[guard]
	assert_eq(stress.restore(bad), ERR_INVALID_DATA, "a record for a non-agent")
	assert_eq(stress.snapshot(), state, "rejections leave the state untouched")


## Mutation testing (M6 claim 12): the cone of something that is not an agent read as
## zero and nothing said so, so `return 0` could become `return 1` unnoticed. An
## actor with no aim profile has no cone, which is different from having a cone of one.
func test_something_that_is_not_an_agent_has_no_cone_at_all() -> void:
	_setup()
	var bystander: int = _actors.spawn(&"arcade", 3)
	assert_true(_aim.aim_profile_of(bystander).is_empty(), "no aim profile")
	assert_eq(_aim.cone_of(bystander), 0, "and so no cone")
	assert_eq(_aim.cone_of(99999), 0, "nor has an actor that does not exist")
	assert_eq(_aim.target_of(bystander), 0, "and it is aiming at nobody")
