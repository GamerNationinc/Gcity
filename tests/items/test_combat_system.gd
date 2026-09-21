extends GcityTest

const SEED: int = 20260920
const PROPERTY_CASES: int = 10_000
const SEED_PROPERTY: int = 20260927
const DUMMY_RANGE: int = 18

var _sim: SimRoot
var _actors: ActorSystem
var _items: ItemSystem
var _stats: StatResolver
var _combat: CombatSystem
var _player: int
var _dummy: int
var _pistol: int
var _mags: Array[int] = []
var _rounds: Array[int] = []


func _build(seed: int = SEED) -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	_sim = SimAssembly.build(seed, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_stats = SimAssembly.stats_of(_sim)
	_combat = SimAssembly.combat_of(_sim)


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


## Player with a loaded, wielded pistol; dummy at DUMMY_RANGE. Two magazines of 15, 30 rounds.
func _range(rounds_in_mag: int = 15) -> void:
	_player = _actors.spawn(&"arcade", 0)
	_dummy = _actors.spawn(&"arcade", DUMMY_RANGE)
	var inv: StringName = ItemSystem.inventory_of(_player)
	_pistol = _items.spawn(&"weapon_frame", &"g19", inv, 1)
	_mags = [_items.spawn(&"weapon_part", &"g19_mag_15", inv, 2), _items.spawn(&"weapon_part", &"g19_mag_15", inv, 3)]
	_rounds = []
	for i: int in range(30):
		_rounds.append(_items.spawn(&"ammo", &"9x19_fmj", inv, 100 + i))
	for i: int in range(rounds_in_mag):
		assert_true(_do(&"magazine.load", {"actor": _player, "magazine": _mags[0], "round": _rounds[i]}), "load")
	assert_true(_do(&"actor.wield", {"actor": _player, "weapon": _pistol}), "wield")
	assert_true(_do(&"weapon.reload_tactical", {"actor": _player, "weapon": _pistol, "magazine": _mags[0]}), "reload")
	_sim.step_n(80)


func _fire() -> bool:
	return _do(&"weapon.fire", {"actor": _player, "target": _dummy})


# ---------------------------------------------------------------- units

func test_fire_consumes_exactly_one_round_and_chambers_the_next() -> void:
	_build()
	_range()
	var count: int = _items.item_count()
	var chambered: int = _items.chambered(_pistol)
	var in_mag: int = _items.rounds_in(_mags[0]).size()
	assert_true(_fire(), "fire")
	assert_eq(_items.item_count(), count - 1, "exactly one item gone")
	assert_false(_items.has_item(chambered), "the fired round is gone")
	assert_eq(_stats.get_inherits(chambered), -1, "and the resolver forgot it")
	assert_eq(_items.rounds_in(_mags[0]).size(), in_mag - 1, "next round came out of the magazine")
	assert_ne(_items.chambered(_pistol), 0, "chamber refilled")
	assert_eq(_combat.shots(), 1, "counted")
	assert_true(_items.is_busy(_pistol, _sim.get_tick()), "cycling")
	assert_eq(_items.busy_until(_pistol), _sim.get_tick() + 6, "cycle_ticks 6000 milli-ticks = 6 ticks")
	assert_false(_fire(), "no second shot while cycling")
	_sim.step_n(6)
	assert_true(_fire(), "fires again after the cycle")


func test_hit_chance_uses_resolved_stat_and_profile_falloff() -> void:
	_build()
	_range()
	assert_eq(_stats.resolve(_pistol, &"hit_chance"), 650000, "frame base, no barrel")
	assert_eq(_combat.hit_chance_at(_player, _pistol, 0), 650000, "point blank")
	assert_eq(_combat.hit_chance_at(_player, _pistol, DUMMY_RANGE), 650000 - DUMMY_RANGE * 5000, "18 m of falloff at 5000/m")
	assert_eq(_combat.hit_chance_at(_player, _pistol, 1000), 0, "clamped at zero")
	var h: int = _stats.add_modifier(_pistol, {"stat": &"hit_chance", "class": &"add", "value": 400000, "source": &"test.laser"})
	assert_true(h >= 1, "mod")
	assert_eq(_combat.hit_chance_at(_player, _pistol, 0), 1000000, "clamped at one")


func test_hits_apply_resolved_damage_misses_do_not_and_kills_end_it() -> void:
	_build()
	_range()
	var hp: int = 100000
	var hits: int = 0
	var shots: int = 0
	while _actors.is_alive(_dummy) and shots < 60:
		if _items.chambered(_pistol) == 0:
			for i: int in range(15, 30):
				_do(&"magazine.load", {"actor": _player, "magazine": _mags[1], "round": _rounds[i]})
			assert_true(_do(&"weapon.reload_emergency", {"actor": _player, "weapon": _pistol, "magazine": _mags[1]}), "reload when empty")
			_sim.step_n(80)
		assert_true(_fire(), "shot %d" % shots)
		shots += 1
		var last: Dictionary = _combat.last_shot()
		var hit: bool = last["hit"]
		if hit:
			hits += 1
			var damage: int = last["damage"]
			assert_eq(damage, mini(34500, hp), "resolved round damage 34.5 (or what was left)")
			hp -= damage
			assert_eq(last["node"], &"body", "routed to the only node")
		else:
			assert_eq(last["damage"], 0, "a miss applies nothing")
		assert_eq(_actors.health_of(_dummy)[&"body"], hp, "health tracks the applied damage")
		_sim.step_n(6)
	assert_false(_actors.is_alive(_dummy), "dummy down within 60 shots")
	assert_eq(hits, 3, "100 hp at 34.5 per hit is three hits")
	assert_eq(_combat.kills(), 1, "one kill")
	assert_eq(_combat.hits(), hits, "hit counter")
	assert_eq(_combat.shots(), shots, "shot counter")
	assert_false(_fire(), "no shooting the dead")


func test_a_tagged_perk_changes_damage_by_exactly_its_factor() -> void:
	_build()
	_range()
	var perk: int = _stats.add_modifier(_player, {"stat": &"damage", "class": &"mul", "value": 1000, "source": &"perk.test",
		"tags": [&"weapon_class.handgun"]})
	assert_true(perk >= 1, "perk on the actor")
	var round: int = _items.chambered(_pistol)
	assert_eq(_stats.resolve(round, &"damage"), 37950, "actor -> weapon -> round: 34500 * 1.1")
	var damage_seen: int = 0
	for i: int in range(20):
		_fire()
		var last: Dictionary = _combat.last_shot()
		var hit: bool = last["hit"]
		if hit:
			damage_seen = last["damage"]
			break
		_sim.step_n(6)
	assert_eq(damage_seen, 37950, "the applied damage carries the perk's exact factor")
	assert_eq(_stats.remove_modifier(perk), OK, "remove")
	assert_eq(_stats.resolve(_items.chambered(_pistol), &"damage"), 34500, "back to base")


func test_rejections_and_events() -> void:
	_build()
	_range()
	var fires: Array[Dictionary] = []
	var hits: Array[Dictionary] = []
	assert_eq(_combat.events().subscribe(CombatSystem.EVENT_FIRE, func(p: Dictionary) -> void: fires.append(p)), OK, "sub fire")
	assert_eq(_combat.events().subscribe(CombatSystem.EVENT_HIT, func(p: Dictionary) -> void: hits.append(p)), OK, "sub hit")
	assert_false(_do(&"weapon.fire", {"actor": _player}), "missing target")
	assert_false(_do(&"weapon.fire", {"actor": _player, "target": _dummy, "x": 1}), "extra key")
	assert_false(_do(&"weapon.fire", {"actor": _player, "target": _player}), "not at yourself")
	assert_false(_do(&"weapon.fire", {"actor": _dummy, "target": _player}), "dummy wields nothing")
	assert_false(_do(&"weapon.fire", {"actor": 77, "target": _dummy}), "unknown shooter")
	assert_false(_do(&"weapon.fire", {"actor": _player, "target": 77}), "unknown target")
	assert_eq(fires.size(), 0, "no events for rejected commands")
	assert_true(_fire(), "fire")
	assert_eq(fires.size(), 1, "one fire event")
	assert_eq(fires[0]["tags"], ["weapon", "weapon_class.handgun"], "fire event carries the weapon's tags for the skill system")
	var last: Dictionary = _combat.last_shot()
	var hit: bool = last["hit"]
	assert_eq(hits.size(), 1 if hit else 0, "hit event iff hit")
	if hit:
		assert_eq(hits[0]["range_m"], DUMMY_RANGE, "hit event carries the range")
		assert_eq(hits[0]["damage"], 34500, "and the applied damage")
	assert_true(_do(&"actor.wield", {"actor": _player, "weapon": 0}), "unwield")
	_sim.step_n(6)
	assert_false(_fire(), "nothing wielded")


func test_empty_chamber_cannot_fire_and_reload_refills_it() -> void:
	_build()
	_range(1)
	assert_eq(_items.rounds_in(_mags[0]).size(), 0, "the only round is chambered")
	assert_true(_fire(), "fires the chambered round")
	assert_eq(_items.chambered(_pistol), 0, "nothing to chamber next")
	_sim.step_n(6)
	assert_false(_fire(), "click")
	for i: int in range(1, 4):
		_do(&"magazine.load", {"actor": _player, "magazine": _mags[1], "round": _rounds[i]})
	assert_true(_do(&"weapon.reload_tactical", {"actor": _player, "weapon": _pistol, "magazine": _mags[1]}), "reload")
	assert_eq(_items.chambered(_pistol), _rounds[3], "reload chambered the top round")
	assert_eq(_items.rounds_in(_mags[1]).size(), 2, "two left")


func test_same_seed_same_outcomes_different_seed_differs() -> void:
	var outcomes: Array[String] = []
	for seed: int in [SEED, SEED, SEED + 1]:
		_build(seed)
		_range()
		var record: PackedStringArray = PackedStringArray()
		for i: int in range(15):
			_fire()
			var last: Dictionary = _combat.last_shot()
			record.append("1" if last["hit"] else "0")
			_sim.step_n(6)
		outcomes.append("".join(record))
	assert_eq(outcomes[0], outcomes[1], "same seed, same 15 rolls")
	assert_ne(outcomes[0], outcomes[2], "different seed, different rolls")
	assert_eq(_sim.state_hash().length(), 64, "hashable throughout")


func test_extension_a_new_stage_is_a_registration_call_and_content_is_checked() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	var bad_profile: Dictionary = db.get_entry(&"combat_profile", &"arcade").duplicate(true)
	var stages: Array = bad_profile["stages"]
	stages.append("armour")
	assert_eq(db.add(&"combat_profile", &"zz_wants_armour", bad_profile), OK, "db takes the shape")
	assert_true(SimAssembly.build(SEED, db) == null, "a profile enabling an unimplemented stage stops assembly")
	_build()
	var calls: Array[int] = []
	assert_eq(_combat.register_stage(&"armour", func(ctx: Dictionary, _s: SimRoot) -> void: calls.append(ctx["shooter"])), OK, "register")
	assert_eq(_combat.register_stage(&"armour", func(_c: Dictionary, _s: SimRoot) -> void: pass), ERR_ALREADY_EXISTS, "duplicate")
	assert_eq(_combat.implemented_stages(), [&"armour", &"damage", &"hit_roll", &"routing"] as Array[StringName], "listed")
	assert_eq(_combat.validate_content(), OK, "still valid: the shipped profile does not enable it")


# ---------------------------------------------------------------- property: conservation with fire

func test_property_fire_is_the_only_way_a_round_leaves() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	_build()
	_range()
	var kinds: Array[StringName] = [&"weapon.fire", &"weapon.fire", &"magazine.load", &"magazine.unload",
		&"weapon.reload_tactical", &"weapon.reload_emergency", &"actor.wield"]
	var fired: int = 0
	var failures: int = 0
	for case: int in range(PROPERTY_CASES):
		var kind: StringName = kinds[rng.randi_range(0, kinds.size() - 1)]
		var payload: Dictionary = {}
		match kind:
			&"weapon.fire":
				payload = {"actor": _player, "target": _dummy}
			&"magazine.load":
				payload = {"actor": _player, "magazine": _mags[rng.randi_range(0, 1)], "round": _rounds[rng.randi_range(0, 29)]}
			&"magazine.unload":
				payload = {"actor": _player, "magazine": _mags[rng.randi_range(0, 1)]}
			&"actor.wield":
				payload = {"actor": _player, "weapon": _pistol if rng.randf() < 0.7 else 0}
			_:
				payload = {"actor": _player, "weapon": _pistol, "magazine": _mags[rng.randi_range(0, 1)]}
		var before: int = _items.item_count()
		var applied: bool = _do(kind, payload)
		var after: int = _items.item_count()
		if applied and kind == &"weapon.fire":
			fired += 1
			if after != before - 1:
				failures += 1
				if failures <= 3:
					fail("case %d: fire changed item count by %d" % [case, after - before])
		elif after != before:
			failures += 1
			if failures <= 3:
				fail("case %d: %s changed item count by %d" % [case, kind, after - before])
		if rng.randf() < 0.3:
			_sim.step_n(rng.randi_range(1, 90))
	assert_eq(failures, 0, "item count moved only by fire, by exactly one")
	assert_eq(_items.item_count(), 3 + 30 - fired, "every fired round is accounted for (%d fired)" % fired)
	assert_true(fired >= 30 - 1 or not _actors.is_alive(_dummy) or fired > 0, "shots happened")
