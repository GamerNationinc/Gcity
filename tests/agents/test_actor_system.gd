extends GcityTest

const SEED: int = 20260920

var _sim: SimRoot
var _actors: ActorSystem
var _items: ItemSystem
var _stats: StatResolver


func _build() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_stats = SimAssembly.stats_of(_sim)


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


func test_spawn_from_profile_and_health_graph() -> void:
	_build()
	assert_true(_do(&"actor.spawn", {"profile": "arcade", "range_m": 18}), "spawn via command")
	var ids: Array[int] = _actors.actor_ids()
	assert_eq(ids.size(), 1, "one actor")
	var a: int = ids[0]
	assert_eq(_actors.profile_of(a), &"arcade", "profile")
	assert_eq(_actors.health_of(a), {&"body": 100000}, "health from the profile's nodes")
	assert_eq(_actors.max_health(a, &"body"), 100000, "max")
	assert_eq(_actors.range_of(a), 18, "range")
	assert_true(_actors.is_alive(a), "alive")
	assert_eq(_actors.damage_node(a, &"body", 40000), 40000, "damage applied")
	assert_eq(_actors.health_of(a), {&"body": 60000}, "hp reduced")
	assert_eq(_actors.damage_node(a, &"arm", 1), 0, "unknown node applies nothing")
	assert_eq(_actors.damage_node(a, &"body", 0), 0, "zero applies nothing")
	assert_eq(_actors.damage_node(a, &"body", 999999), 60000, "clamped at zero")
	assert_false(_actors.is_alive(a), "fatal node at zero kills")
	assert_false(_do(&"actor.spawn", {"profile": "sim", "range_m": 1}), "unknown profile")
	assert_false(_do(&"actor.spawn", {"profile": "arcade", "range_m": -1}), "negative range")
	assert_false(_do(&"actor.spawn", {"profile": "arcade", "range_m": 1, "x": 1}), "extra key")
	assert_false(_do(&"actor.spawn", {"profile": "arcade"}), "missing key")
	assert_eq(_actors.actor_ids().size(), 1, "nothing else spawned")


func test_wield_requires_a_held_frame_and_links_inheritance() -> void:
	_build()
	_do(&"actor.spawn", {"profile": "arcade", "range_m": 0})
	var a: int = _actors.actor_ids()[0]
	var pistol: int = _items.spawn(&"weapon_frame", &"g19", ItemSystem.inventory_of(a), 1)
	var barrel: int = _items.spawn(&"weapon_part", &"g19_barrel", ItemSystem.inventory_of(a), 2)
	var elsewhere: int = _items.spawn(&"weapon_frame", &"g19", &"world", 3)
	assert_false(_do(&"actor.wield", {"actor": a, "weapon": barrel}), "parts are not wielded")
	assert_false(_do(&"actor.wield", {"actor": a, "weapon": elsewhere}), "not held")
	assert_false(_do(&"actor.wield", {"actor": a, "weapon": 0}), "nothing to unwield yet")
	assert_true(_do(&"actor.wield", {"actor": a, "weapon": pistol}), "wield")
	assert_eq(_actors.wielded(a), pistol, "wielded")
	assert_eq(_stats.get_inherits(pistol), a, "weapon inherits from the actor")
	var perk: int = _stats.add_modifier(a, {"stat": &"recoil", "class": &"add", "value": -500, "source": &"test.perk", "tags": [&"weapon_class.handgun"]})
	assert_true(perk >= 1, "perk on the actor")
	assert_eq(_stats.resolve(pistol, &"recoil"), 2500, "reaches the wielded handgun")
	assert_false(_do(&"actor.wield", {"actor": a, "weapon": pistol}), "already wielded")
	assert_true(_do(&"actor.wield", {"actor": a, "weapon": 0}), "unwield")
	assert_eq(_actors.wielded(a), 0, "nothing wielded")
	assert_eq(_stats.get_inherits(pistol), -1, "link removed")
	assert_eq(_stats.resolve(pistol, &"recoil"), 3000, "perk no longer applies")
	assert_false(_do(&"actor.wield", {"actor": 99, "weapon": pistol}), "unknown actor")


func test_restore_round_trip_and_rejections() -> void:
	_build()
	_do(&"actor.spawn", {"profile": "arcade", "range_m": 12})
	var a: int = _actors.actor_ids()[0]
	var pistol: int = _items.spawn(&"weapon_frame", &"g19", ItemSystem.inventory_of(a), 1)
	_do(&"actor.wield", {"actor": a, "weapon": pistol})
	_actors.damage_node(a, &"body", 12345)
	var full: Dictionary = _sim.snapshot()
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	var fresh: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(fresh, full), OK, "restore all systems")
	var fa: ActorSystem = SimAssembly.actors_of(fresh)
	assert_eq(fa.health_of(a), {&"body": 100000 - 12345}, "health restored")
	assert_eq(fa.wielded(a), pistol, "wield restored")
	assert_eq(fa.range_of(a), 12, "range restored")
	var systems_a: Dictionary = _sim.snapshot()["systems"]
	var systems_b: Dictionary = fresh.snapshot()["systems"]
	assert_eq(StateHash.of(systems_b), StateHash.of(systems_a), "system state hash equal")
	var good: Dictionary = _actors.snapshot()
	var bad: Array[Dictionary] = []
	var c: Dictionary
	c = good.duplicate(true)
	_sub(_sub(c, "actors"), a)["alive"] = 1
	bad.append(c)
	c = good.duplicate(true)
	_sub(_sub(c, "actors"), a)["profile"] = "sim"
	bad.append(c)
	c = good.duplicate(true)
	_sub(_sub(c, "actors"), a)["health"] = {&"body": 999999}
	bad.append(c)
	c = good.duplicate(true)
	_sub(_sub(c, "actors"), a)["wielded"] = 12345
	bad.append(c)
	c = good.duplicate(true)
	_sub(_sub(c, "actors"), a)["range_m"] = -3
	bad.append(c)
	c = good.duplicate(true)
	c["extra"] = 1
	bad.append(c)
	var i: int = 0
	for b: Dictionary in bad:
		var target: SimRoot = SimAssembly.build(SEED, db)
		assert_eq(SimAssembly.items_of(target).restore(_items.snapshot()), OK, "items first so wield checks can see them")
		assert_eq(SimAssembly.actors_of(target).restore(b), ERR_INVALID_DATA, "hostile %d rejected" % i)
		assert_eq(SimAssembly.actors_of(target).actor_ids(), [] as Array[int], "hostile %d left no actors" % i)
		i += 1


static func _sub(dict: Dictionary, key: Variant) -> Dictionary:
	var out: Dictionary = dict[key]
	return out
