extends GcityTest

const SEED: int = 20260920
const DUMMY_RANGE: int = 18

var _sim: SimRoot
var _actors: ActorSystem
var _items: ItemSystem
var _stats: StatResolver
var _combat: CombatSystem
var _prog: ProgressionSystem
var _player: int
var _dummy: int
var _pistol: int
var _mags: Array[int] = []
var _rounds: Array[int] = []


func _build(seed: int = SEED, db: ContentDb = null) -> void:
	if db == null:
		db = ContentDb.new()
		assert_eq(ContentLoader.load_all(db), OK, "content")
	_sim = SimAssembly.build(seed, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_stats = SimAssembly.stats_of(_sim)
	_combat = SimAssembly.combat_of(_sim)
	_prog = SimAssembly.progression_of(_sim)


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


func _range() -> void:
	_player = _actors.spawn(&"arcade", 0)
	_dummy = _actors.spawn(&"range_dummy", DUMMY_RANGE)
	var inv: StringName = ItemSystem.inventory_of(_player)
	_pistol = _items.spawn(&"weapon_frame", &"g19", inv, 1)
	_mags = [_items.spawn(&"weapon_part", &"g19_mag_15", inv, 2), _items.spawn(&"weapon_part", &"g19_mag_15", inv, 3)]
	_rounds = []
	for i: int in range(30):
		_rounds.append(_items.spawn(&"ammo", &"9x19_fmj", inv, 100 + i))
	for i: int in range(15):
		_do(&"magazine.load", {"actor": _player, "magazine": _mags[0], "round": _rounds[i]})
	for i: int in range(15, 30):
		_do(&"magazine.load", {"actor": _player, "magazine": _mags[1], "round": _rounds[i]})
	assert_true(_do(&"actor.wield", {"actor": _player, "weapon": _pistol}), "wield")
	assert_true(_do(&"weapon.reload_tactical", {"actor": _player, "weapon": _pistol, "magazine": _mags[0]}), "reload")
	_sim.step_n(80)


## Fires until `hits` hits have landed (reloading the second magazine when empty).
## Returns the applied damage of each hit, in order.
func _shoot_until_hits(hits: int) -> Array[int]:
	var seen: Array[int] = []
	var shots: int = 0
	while seen.size() < hits and shots < 40:
		if _items.chambered(_pistol) == 0:
			assert_true(_do(&"weapon.reload_emergency", {"actor": _player, "weapon": _pistol, "magazine": _mags[1]}), "second magazine")
			_sim.step_n(80)
		assert_true(_do(&"weapon.fire", {"actor": _player, "target": _dummy}), "fire")
		shots += 1
		var last: Dictionary = _combat.last_shot()
		var hit: bool = last["hit"]
		if hit:
			var damage: int = last["damage"]
			seen.append(damage)
		_sim.step_n(6)
	return seen


func test_hits_credit_the_skill_and_levels_grant_points() -> void:
	_build()
	_range()
	assert_eq(_prog.skill_ids(), [&"handguns"] as Array[StringName], "one skill")
	assert_eq(_prog.perk_ids(), [&"handgun_control", &"handgun_focus"] as Array[StringName], "two perks")
	assert_eq(_prog.xp_of(_player, &"handguns"), 0, "no xp yet")
	assert_eq(_prog.next_level_xp(_player, &"handguns"), 300, "first threshold")
	var hits: Array[int] = _shoot_until_hits(3)
	assert_eq(hits.size(), 3, "three hits landed")
	assert_eq(_prog.xp_of(_player, &"handguns"), 300, "100 xp per handgun hit; misses credit nothing")
	assert_eq(_prog.level_of(_player, &"handguns"), 1, "level 1 at 300")
	assert_eq(_prog.points_of(_player, _prog.skill_ids()[0]), 1, "one point per level")
	assert_eq(_prog.xp_of(_dummy, &"handguns"), 0, "the target earns nothing")
	_shoot_until_hits(5)
	assert_eq(_prog.xp_of(_player, &"handguns"), 800, "eight hits")
	assert_eq(_prog.level_of(_player, &"handguns"), 2, "level 2 at 800")
	assert_eq(_prog.points_of(_player, &"handguns"), 2, "two points")
	assert_eq(_prog.xp_of(_player, &"nope"), 0, "unknown skill reads as zero")


func test_unlock_is_gated_by_level_points_prerequisites_and_pays_out_modifiers() -> void:
	_build()
	_range()
	assert_eq(_prog.unlock_blocker(_player, &"handgun_focus"), "needs handguns level 1", "blocked at level 0")
	assert_false(_do(&"perk.unlock", {"actor": _player, "perk": "handgun_focus"}), "rejected at level 0")
	_shoot_until_hits(3)
	assert_eq(_prog.unlock_blocker(_player, &"handgun_focus"), "", "available at level 1 with a point")
	assert_eq(_prog.unlock_blocker(_player, &"handgun_control"), "needs handguns level 2", "second perk needs level 2")
	var damage_before: int = _stats.resolve(_items.chambered(_pistol), &"damage")
	assert_eq(damage_before, 34500, "base damage")
	assert_false(_do(&"perk.unlock", {"actor": _player, "perk": "handgun_focus", "x": 1}), "extra key")
	assert_false(_do(&"perk.unlock", {"actor": _player, "perk": 7}), "perk must be a name")
	assert_false(_do(&"perk.unlock", {"actor": _player, "perk": "nope"}), "unknown perk")
	assert_false(_do(&"perk.unlock", {"actor": _dummy, "perk": "handgun_focus"}), "dummy has no level")
	assert_true(_do(&"perk.unlock", {"actor": _player, "perk": "handgun_focus"}), "unlock")
	assert_true(_prog.has_perk(_player, &"handgun_focus"), "unlocked")
	assert_eq(_prog.perks_of(_player), [&"handgun_focus"] as Array[StringName], "listed")
	assert_eq(_prog.points_of(_player, &"handguns"), 0, "point spent")
	assert_eq(_stats.resolve(_items.chambered(_pistol), &"damage"), 37950, "the chambered round now resolves with +10 %")
	assert_eq(_stats.resolve(_pistol, &"damage"), 0, "the weapon has no damage of its own; the perk lives on the actor")
	assert_false(_do(&"perk.unlock", {"actor": _player, "perk": "handgun_focus"}), "no double unlock")
	assert_eq(_prog.unlock_blocker(_player, &"handgun_control"), "needs handguns level 2", "still gated by level")
	_shoot_until_hits(5)
	assert_eq(_prog.level_of(_player, &"handguns"), 2, "level 2")
	assert_eq(_prog.unlock_blocker(_player, &"handgun_control"), "", "prerequisite perk owned, level met, point available")
	var recoil_before: int = _stats.resolve(_pistol, &"recoil")
	assert_true(_do(&"perk.unlock", {"actor": _player, "perk": "handgun_control"}), "unlock the second perk")
	assert_eq(_stats.resolve(_pistol, &"recoil"), recoil_before * 9000 / 10000, "-10 % recoil reaches the wielded handgun")
	assert_eq(_prog.points_of(_player, &"handguns"), 0, "spent")


## Claim 14: same seed and command stream with and without the perk differ in applied
## damage by exactly the factor in the file. The unlock consumes no randomness, so the
## hit pattern is identical in both runs.
func test_perk_changes_applied_damage_by_exactly_the_files_factor() -> void:
	var damages: Array[Array] = []
	for with_perk: bool in [false, true]:
		_build()
		_range()
		_shoot_until_hits(3)
		if with_perk:
			assert_true(_do(&"perk.unlock", {"actor": _player, "perk": "handgun_focus"}), "unlock")
		else:
			_sim.step()  # keep the tick streams aligned
		damages.append(_shoot_until_hits(4))
	assert_eq(damages[0].size(), 4, "four hits without")
	assert_eq(damages[1].size(), 4, "four hits with")
	for i: int in range(4):
		var without: int = damages[0][i]
		var with_p: int = damages[1][i]
		assert_eq(without, 34500, "without the perk: base damage")
		assert_eq(with_p, 37950, "with the perk: 34500 * (10000 + 1000) / 10000")
		assert_eq(with_p * 10000 / 11000, without, "exactly the factor from content/perk/handgun_focus.json")


func test_snapshot_restore_round_trip_and_hostile_input() -> void:
	_build()
	_range()
	_shoot_until_hits(3)
	assert_true(_do(&"perk.unlock", {"actor": _player, "perk": "handgun_focus"}), "unlock")
	var full: Dictionary = _sim.snapshot()
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	var fresh: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(fresh, full), OK, "restore")
	var fp: ProgressionSystem = SimAssembly.progression_of(fresh)
	assert_eq(fp.xp_of(_player, &"handguns"), 300, "xp restored")
	assert_true(fp.has_perk(_player, &"handgun_focus"), "perk restored")
	var a: Dictionary = _sim.snapshot()["systems"]
	var b: Dictionary = fresh.snapshot()["systems"]
	assert_eq(StateHash.of(b), StateHash.of(a), "system state hash equal")
	assert_eq(SimAssembly.stats_of(fresh).resolve(_items.chambered(_pistol), &"damage"), 37950, "the restored perk still applies")
	var good: Dictionary = _prog.snapshot()
	var bad: Array[Dictionary] = []
	var c: Dictionary
	c = good.duplicate(true)
	c.erase("perks")
	bad.append(c)
	c = good.duplicate(true)
	_sub(_sub(c, "skills"), _player)[&"handguns"] = {"xp": 300, "level": 3, "points": 1}  # level inconsistent with xp
	bad.append(c)
	c = good.duplicate(true)
	_sub(_sub(c, "skills"), _player)[&"archery"] = {"xp": 0, "level": 0, "points": 0}
	bad.append(c)
	c = good.duplicate(true)
	_sub(_sub(c, "perks"), _player)[&"handgun_focus"] = [999999]  # not a live modifier
	bad.append(c)
	c = good.duplicate(true)
	_sub(_sub(c, "perks"), _player)[&"nope"] = []
	bad.append(c)
	var i: int = 0
	for d: Dictionary in bad:
		var target: SimRoot = SimAssembly.build(SEED, db)
		assert_eq(SimAssembly.stats_of(target).restore(_stats.snapshot()), OK, "resolver first")
		assert_eq(SimAssembly.progression_of(target).restore(d), ERR_INVALID_DATA, "hostile %d rejected" % i)
		assert_eq(SimAssembly.progression_of(target).xp_of(_player, &"handguns"), 0, "hostile %d left it empty" % i)
		i += 1


func test_content_rules_are_enforced_at_assembly() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	assert_eq(db.add(&"perk", &"zz_loop_a", {"schema_version": 1, "description": "x", "skill": "handguns",
		"prerequisites": {"level": 0, "perks": ["zz_loop_b"]}, "cost": 0, "tags": [], "modifiers": [{"stat": "sway", "class": "add", "value": 1}]}), OK, "a")
	assert_eq(db.add(&"perk", &"zz_loop_b", {"schema_version": 1, "description": "x", "skill": "handguns",
		"prerequisites": {"level": 0, "perks": ["zz_loop_a"]}, "cost": 0, "tags": [], "modifiers": [{"stat": "sway", "class": "add", "value": 1}]}), OK, "b")
	assert_true(SimAssembly.build(SEED, db) == null, "a prerequisite cycle stops assembly")
	var db2 := ContentDb.new()
	assert_eq(ContentLoader.load_all(db2), OK, "content")
	assert_eq(db2.add(&"skill", &"zz_bad", {"schema_version": 1, "description": "x", "xp": [{"event": "combat.hit", "credit": "shooter", "tags_any": [], "amount": 1}],
		"levels": [0, 100, 50], "points_per_level": 1}), OK, "skill shape")
	assert_true(SimAssembly.build(SEED, db2) == null, "non-increasing thresholds stop assembly")
	var db3 := ContentDb.new()
	assert_eq(ContentLoader.load_all(db3), OK, "content")
	assert_eq(db3.add(&"perk", &"zz_pow", {"schema_version": 1, "description": "x", "skill": "handguns",
		"prerequisites": {"level": 0, "perks": []}, "cost": 0, "tags": [], "modifiers": [{"stat": "sway", "class": "pow", "value": 1}]}), OK, "perk shape")
	assert_true(SimAssembly.build(SEED, db3) == null, "an unregistered modifier class stops assembly")


func test_extension_a_zero_cost_untagged_perk_is_data_only() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	assert_eq(db.add(&"perk", &"zz_steady", {"schema_version": 1, "description": "Steady hands.", "skill": "handguns",
		"prerequisites": {"level": 0, "perks": []}, "cost": 0, "tags": [], "modifiers": [{"stat": "sway", "class": "add", "value": -500}]}), OK, "new perk file")
	_build(SEED, db)
	_range()
	assert_true(_do(&"perk.unlock", {"actor": _player, "perk": "zz_steady"}), "free perk at level 0")
	assert_eq(_stats.resolve(_player, &"sway"), -500, "untagged: applies to the actor")
	assert_eq(_stats.resolve(_pistol, &"sway"), 2000, "and not to the wielded weapon")


static func _sub(dict: Dictionary, key: Variant) -> Dictionary:
	var out: Dictionary = dict[key]
	return out
