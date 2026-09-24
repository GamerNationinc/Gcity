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
	_sub(_sub(c, "actors"), a)["pos"] = [1, 2]
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


## M6 spec claim 10: dying is an event, emitted once, naming where the body fell.
func test_death_is_announced_once_with_the_position() -> void:
	_build()
	var died: Array[Dictionary] = []
	SimAssembly.combat_of(_sim).events().subscribe(ActorSystem.EVENT_DIED, func(payload: Dictionary) -> void:
		died.append(payload))
	var victim: int = _actors.spawn(&"arcade", 0)
	_actors.set_position(victim, Vector3i(1234, 0, 5678))
	var full: int = _actors.health_of(victim)[&"body"]
	assert_true(_actors.damage_node(victim, &"body", full - 1) > 0, "hurt, not killed")
	assert_true(_actors.is_alive(victim), "still up")
	assert_eq(died.size(), 0, "nothing announced")
	assert_true(_actors.damage_node(victim, &"body", 1) > 0, "the last point")
	assert_false(_actors.is_alive(victim), "down")
	assert_eq(died.size(), 1, "one actor.died")
	assert_eq(died[0]["actor"], victim, "the actor")
	assert_eq(died[0]["x"], 1234, "where it fell, x")
	assert_eq(died[0]["z"], 5678, "where it fell, z")
	# a corpse cannot die twice, however much it is shot
	assert_eq(_actors.damage_node(victim, &"body", 100), 0, "no health left to take")
	assert_eq(died.size(), 1, "still one")


## M7 spec claim 12: a living actor can be taken out of the sim entirely, which is what
## a squad going back to being a token is. Everything it carried goes to the stash;
## every system that kept a row for it drops the row, releasing the modifiers it held;
## and the sim runs on and saves as though the actor had never been there.
func test_a_living_agent_can_be_removed_and_leaves_nothing_behind() -> void:
	_build()
	var perception: PerceptionSystem = SimAssembly.perception_of(_sim)
	var aim: AimSystem = SimAssembly.aim_of(_sim)
	var stress: StressSystem = SimAssembly.stress_of(_sim)
	var events: EventBus = SimAssembly.combat_of(_sim).events()
	var player: int = _actors.spawn(&"arcade", 0)
	var gone: int = perception.spawn(&"guard_sim", Vector3i(6, 0, 0), 180, 1, "")
	var stays: int = perception.spawn(&"guard_sim", Vector3i(7, 0, 2), 180, 1, "")
	var pistol: int = _items.arm(gone, &"g19", &"g19_mag_15", &"9x19_fmj", 15, gone * 1000)
	assert_true(pistol != EntityIds.NONE and _actors.wield(gone, pistol), "the agent is armed")
	var removed: Array[int] = []
	events.subscribe(ActorSystem.EVENT_REMOVED, func(payload: Dictionary) -> void:
		var who: int = payload["actor"]
		removed.append(who))
	# a shot past it for stress, and time for both to see the player, aim and decide
	events.emit(CombatSystem.EVENT_FIRE, {"actor": player, "shooter": player, "weapon": 0, "target": gone, "x": 6000, "y": 0, "z": 0})
	_sim.step_n(60)
	var before: Dictionary = _sim.snapshot()
	assert_true(_mentions(before, gone), "the agent is all over the state before")
	assert_true(perception.awareness_of(gone, player) > 0, "it knows about the player")
	assert_true(perception.awareness_of(stays, gone) >= 0, "and its squadmate is next to it")
	var items_before: int = _items.item_count()
	var kit: Array[int] = _items.items_in(ItemSystem.inventory_of(gone))
	var stash: StringName = ItemSystem.token_container(1)
	assert_true(_actors.remove(gone, stash), "removed")
	assert_eq(removed, [gone] as Array[int], "announced once, naming it")
	assert_false(_actors.has_actor(gone), "no longer an actor")
	assert_false(perception.is_agent(gone), "nor an agent")
	assert_eq(_items.items_in(stash), kit, "its kit is in the stash, in order")
	assert_eq(_items.item_count(), items_before, "and not one item was made or lost")
	assert_eq(_stats.get_inherits(pistol), -1, "the pistol no longer inherits from anybody")
	assert_eq(aim.target_of(stays) == gone, false, "nobody is aiming at it")
	assert_eq(stress.stress_of(gone), 0, "it has no stress, because it is not there")
	assert_false(_mentions(_sim.snapshot(), gone), "and no system keeps a row for it")
	# the sim runs on, and the one that stayed is still an agent doing agent things
	_sim.step_n(100)
	assert_true(perception.is_agent(stays), "its squadmate is still there")
	assert_false(_mentions(_sim.snapshot(), gone), "and nothing brought it back")


func test_removal_refuses_the_dead_the_embodied_and_nowhere() -> void:
	_build()
	var perception: PerceptionSystem = SimAssembly.perception_of(_sim)
	var corpses: CorpseSystem = SimAssembly.corpses_of(_sim)
	var agent: int = perception.spawn(&"guard_sim", Vector3i(6, 0, 0), 180, 1, "")
	var pistol: int = _items.arm(agent, &"g19", &"g19_mag_15", &"9x19_fmj", 15, agent * 1000)
	assert_true(_actors.wield(agent, pistol), "armed")
	var before: String = StateHash.of(_sim.snapshot())
	assert_false(_actors.remove(99999, ItemSystem.token_container(1)), "nobody")
	assert_false(_actors.remove(agent, &"mag.3"), "a stash that is not somewhere to put a kit")
	assert_eq(StateHash.of(_sim.snapshot()), before, "and a refusal changes nothing")
	assert_eq(_actors.wielded(agent), pistol, "not even the pistol in its hand")
	var dead: int = perception.spawn(&"guard_sim", Vector3i(9, 0, 0), 180, 1, "")
	_actors.damage_node(dead, &"body", 999999)
	assert_false(_actors.remove(dead, ItemSystem.token_container(1)), "a body is a trace, and stays")
	# a living actor that left a body once is named by it
	var player: int = _actors.spawn(&"arcade", 0)
	_actors.set_position(player, Vector3i(500_000, 0, 500_000))
	_actors.damage_node(player, &"body", 999999)
	assert_true(_do(&"actor.respawn", {"actor": player}), "back")
	assert_true(corpses.has_body(player), "with a body out there")
	assert_false(_actors.remove(player, ItemSystem.token_container(1)), "which keeps them in the world")
	# an actor with empty pockets needs no stash at all
	var bare: int = _actors.spawn(&"arcade", 0)
	assert_true(_actors.remove(bare, &""), "nothing to carry, nowhere needed")
	assert_eq(_items.items_in(ItemSystem.inventory_of(bare)), [] as Array[int], "and no pocket left behind")
	assert_false(_actors.remove(bare, &""), "and it cannot go twice")


## The systems that drop every row for a removed actor. Grows one module at a time as
## each learns to (M7 claim 12), until it is every system that keeps rows by actor.
const REMOVAL_CLEAN: Array[StringName] = [&"actors", &"movement", &"perception", &"aim", &"stress", &"pathing", &"squads", &"stances", &"corpses"]


## True when an actor's id appears in any of those systems anywhere a per-actor row
## could hold it: as a key or a value of any dictionary or array in its state. Coarse on
## purpose: a stale row anywhere is the bug being looked for.
func _mentions(snapshot: Dictionary, actor: int) -> bool:
	var systems: Dictionary = snapshot["systems"]
	for key: Variant in systems:
		var id: StringName = key
		if not REMOVAL_CLEAN.has(id):
			continue
		if _holds(systems[key], actor, 0):
			return true
	return false


func _holds(value: Variant, actor: int, depth: int) -> bool:
	match typeof(value):
		TYPE_DICTIONARY:
			var d: Dictionary = value
			for k: Variant in d:
				if typeof(k) == TYPE_INT and k == actor and depth <= 1:
					return true
				if _holds(d[k], actor, depth + 1):
					return true
		TYPE_ARRAY:
			var a: Array = value
			if depth <= 3:
				for v: Variant in a:
					if typeof(v) == TYPE_INT and v == actor:
						return true
	return false
