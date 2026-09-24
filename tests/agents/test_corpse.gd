extends GcityTest

## M6 spec claims 10: a dead actor leaves a corpse holding everything it carried, and
## `corpse.loot` moves that kit to a living actor within reach. Death and looting are
## both transfers, never a spawn or a destroy, which is what extends M1 claim 10's
## conservation property over dying.

const SEED: int = 20261220
const SEED_PROPERTY: int = 20261221
const PROPERTY_CASES: int = 10_000
const M: int = 1000

var _sim: SimRoot
var _corpses: CorpseSystem
var _actors: ActorSystem
var _items: ItemSystem
var _events: EventBus
var _player: int = 0
var _left: Array[Dictionary] = []
var _looted: Array[Dictionary] = []


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	_corpses = SimAssembly.corpses_of(_sim)
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_events = SimAssembly.combat_of(_sim).events()
	_events.subscribe(CorpseSystem.EVENT_LEFT, _on_left)
	_events.subscribe(CorpseSystem.EVENT_LOOTED, _on_looted)
	_left = []
	_looted = []
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, Vector3i(10 * M, 0, 10 * M))


func _on_left(payload: Dictionary) -> void:
	_left.append(payload)


func _on_looted(payload: Dictionary) -> void:
	_looted.append(payload)


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


## A guard with a kit, standing where it is told, killed outright.
func _kill_a_guard_at(position: Vector3i, items: int) -> int:
	var guard: int = _actors.spawn(&"arcade", 0)
	_actors.set_position(guard, position)
	var inv: StringName = ItemSystem.inventory_of(guard)
	for i: int in items:
		assert_true(_items.spawn(&"currency", &"credit_note", inv, i + 1) > 0, "note %d" % i)
	_actors.damage_node(guard, &"body", 999999)
	assert_false(_actors.is_alive(guard), "down")
	return guard


func test_a_death_leaves_the_kit_on_the_body() -> void:
	_setup()
	var before: int = _items.item_count()
	var guard: int = _kill_a_guard_at(Vector3i(11 * M, 0, 10 * M), 3)
	assert_eq(_items.item_count(), before + 3, "three notes exist")
	var corpse: int = _corpses.corpse_of(guard)
	assert_true(corpse != EntityIds.NONE, "a body")
	assert_true(_corpses.has_corpse(corpse), "it is known")
	assert_eq(_corpses.actor_of(corpse), guard, "whose it is")
	assert_eq(_corpses.position_of(corpse), Vector3i(11 * M, 0, 10 * M), "where it fell")
	assert_eq(_corpses.items_on(corpse).size(), 3, "carrying what it carried")
	assert_eq(_items.items_in(ItemSystem.inventory_of(guard)).size(), 0, "and its pockets are empty")
	assert_false(_corpses.is_stripped(corpse), "nobody has been at it")
	assert_eq(_left.size(), 1, "one corpse.left")
	assert_eq(_left[0]["items"], 3, "naming what is on it")
	assert_eq(_items.item_count(), before + 3, "nothing was destroyed by dying")
	# an empty-handed death still leaves evidence
	var pauper: int = _kill_a_guard_at(Vector3i(12 * M, 0, 10 * M), 0)
	var bare: int = _corpses.corpse_of(pauper)
	assert_true(bare != EntityIds.NONE, "a body with nothing on it is still a body")
	assert_true(_corpses.is_stripped(bare), "nothing on it")
	assert_eq(_corpses.corpse_ids(), [corpse, bare] as Array[int], "in the order they fell")


func test_looting_needs_reach_and_takes_all_of_it() -> void:
	_setup()
	var guard: int = _kill_a_guard_at(Vector3i(11 * M, 0, 10 * M), 4)
	var corpse: int = _corpses.corpse_of(guard)
	var inv: StringName = ItemSystem.inventory_of(_player)
	var before: int = _items.item_count()
	_actors.set_position(_player, Vector3i(13 * M, 0, 10 * M))
	assert_false(_do(&"corpse.loot", {"actor": _player, "corpse": corpse}), "two metres away is out of reach")
	assert_eq(_items.credits_in(inv), 0, "and nothing moved")
	_actors.set_position(_player, Vector3i(10 * M, 0, 10 * M))
	assert_true(_do(&"corpse.loot", {"actor": _player, "corpse": corpse}), "standing over it, within arm's length")
	assert_eq(_items.credits_in(inv), 400, "all four notes at once")
	assert_true(_corpses.is_stripped(corpse), "stripped")
	assert_true(_corpses.has_corpse(corpse), "but the body is still lying there")
	assert_eq(_items.item_count(), before, "looting made nothing and lost nothing")
	assert_eq(_looted.size(), 1, "one corpse.looted")
	assert_false(_do(&"corpse.loot", {"actor": _player, "corpse": corpse}), "and there is nothing left to take")


func test_the_loot_payload_is_exact() -> void:
	_setup()
	var guard: int = _kill_a_guard_at(Vector3i(10 * M, 0, 10 * M), 1)
	var corpse: int = _corpses.corpse_of(guard)
	assert_false(_do(&"corpse.loot", {}), "empty")
	assert_false(_do(&"corpse.loot", {"actor": _player}), "no corpse")
	assert_false(_do(&"corpse.loot", {"actor": _player, "corpse": corpse, "extra": 1}), "an unknown key")
	assert_false(_do(&"corpse.loot", {"actor": _player, "corpse": "1"}), "a corpse that is not an id")
	assert_false(_do(&"corpse.loot", {"actor": _player, "corpse": 99999}), "a corpse that is not one")
	assert_false(_do(&"corpse.loot", {"actor": 99999, "corpse": corpse}), "a looter that is not an actor")
	assert_false(_do(&"corpse.loot", {"actor": guard, "corpse": corpse}), "and a corpse cannot loot itself")
	assert_eq(_corpses.items_on(corpse).size(), 1, "every refusal left the body alone")


func test_property_no_item_is_made_or_lost_by_dying_looting_or_the_police() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	_setup()
	var spawned: int = 0
	var deaths: int = 0
	var loots: int = 0
	var returns: int = 0
	var violations: int = 0
	var alive: Array[int] = []
	for case: int in PROPERTY_CASES:
		var before: int = _items.item_count()
		if not _actors.is_alive(_player):
			# dead: the only thing to do is come back, in town or out of it
			if _do(&"actor.respawn", {"actor": _player}):
				returns += 1
		else:
			match rng.randi_range(0, 4):
				0:
					# a new actor with a random kit of rounds and notes
					var who: int = _actors.spawn(&"arcade", 0)
					_actors.set_position(who, Vector3i(rng.randi_range(0, 20) * M, 0, rng.randi_range(0, 20) * M))
					var inv: StringName = ItemSystem.inventory_of(who)
					var n: int = rng.randi_range(0, 3)
					for i: int in n:
						var kind: StringName = &"currency" if rng.randi_range(0, 1) == 0 else &"ammo"
						var template: StringName = &"credit_note" if kind == &"currency" else &"9x19_fmj"
						assert_true(_items.spawn(kind, template, inv, case * 8 + i) > 0, "kit item")
					spawned += n
					alive.append(who)
				1:
					if not alive.is_empty():
						var index: int = rng.randi_range(0, alive.size() - 1)
						var victim: int = alive[index]
						alive.remove_at(index)
						_actors.damage_node(victim, &"body", 999999)
						deaths += 1
				2:
					var ids: Array[int] = _corpses.corpse_ids()
					if not ids.is_empty():
						var corpse: int = ids[rng.randi_range(0, ids.size() - 1)]
						_actors.set_position(_player, _corpses.position_of(corpse))
						if _do(&"corpse.loot", {"actor": _player, "corpse": corpse}):
							loots += 1
				3:
					var ids2: Array[int] = _corpses.corpse_ids()
					if not ids2.is_empty():
						var corpse2: int = ids2[rng.randi_range(0, ids2.size() - 1)]
						_actors.set_position(_player, Vector3i(rng.randi_range(0, 20) * M, 0, rng.randi_range(0, 20) * M))
						if _do(&"corpse.loot", {"actor": _player, "corpse": corpse2}):
							loots += 1
				_:
					# the player dies too, sometimes where the law holds the scene
					_actors.set_position(_player, IN_TOWN if rng.randi_range(0, 1) == 0 else IN_THE_BADLANDS)
					_actors.damage_node(_player, &"body", 999999)
					deaths += 1
		# nothing but a deliberate spawn ever changes how many items exist
		if _items.item_count() != spawned:
			violations += 1
			if violations <= 3:
				fail("case %d: %d items exist but %d were spawned (was %d before this case)" % [case, _items.item_count(), spawned, before])
	assert_eq(violations, 0, "no death, loot or police return ever made or lost an item (%d spawned, %d deaths, %d loots, %d returns)" % [spawned, deaths, loots, returns])
	assert_eq(_items.item_count(), spawned, "and the final count is exactly what was spawned")
	assert_true(deaths > 500 and loots > 200 and returns > 200, "the stream exercised all three (%d deaths, %d loots, %d returns)" % [deaths, loots, returns])


func test_restore_round_trip_and_rejections() -> void:
	_setup()
	var guard: int = _kill_a_guard_at(Vector3i(11 * M, 0, 10 * M), 2)
	var corpse: int = _corpses.corpse_of(guard)
	var snap: Dictionary = _sim.snapshot()
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "restored")
	assert_eq(other.restore_root(snap), OK, "root restored")
	var restored: CorpseSystem = SimAssembly.corpses_of(other)
	assert_true(restored.has_corpse(corpse), "the body carried over")
	assert_eq(restored.items_on(corpse).size(), 2, "with what was on it")
	_sim.step()
	other.step()
	assert_eq(other.state_hash(), _sim.state_hash(), "hashes agree")
	var state: Dictionary = _corpses.snapshot()
	assert_eq(restored.restore({}), ERR_INVALID_DATA, "empty")
	var bad: Dictionary = state.duplicate(true)
	var all: Dictionary = bad["corpses"]
	all[corpse] = {"actor": 99999, "pos": [0, 0, 0]}
	assert_eq(restored.restore(bad), ERR_INVALID_DATA, "a corpse of nobody")
	bad = state.duplicate(true)
	all = bad["corpses"]
	var rec: Dictionary = all[corpse]
	rec["pos"] = [0, 0]
	assert_eq(restored.restore(bad), ERR_INVALID_DATA, "a position with two numbers")
	assert_eq(restored.snapshot(), state, "rejections leave the state untouched")


## A body outlives a respawn (M6 spec claims 10-11: it persists with the gear on it),
## so a save taken after one has a corpse whose actor is standing again. The first
## version of restore refused exactly that, and a save made after any respawn would
## not load; the round-trip property never reached it because its stream almost never
## kills the player and brings them back.
func test_a_save_taken_after_a_respawn_loads() -> void:
	_setup()
	_actors.set_position(_player, IN_THE_BADLANDS)
	_actors.damage_node(_player, &"body", 999999)
	var corpse: int = _corpses.corpse_of(_player)
	assert_true(_do(&"actor.respawn", {"actor": _player}), "come back")
	assert_true(_corpses.has_corpse(corpse), "the body is still out there")
	var snap: Dictionary = _sim.snapshot()
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "the save loads")
	assert_eq(other.restore_root(snap), OK, "root restored")
	assert_eq(other.state_hash(), _sim.state_hash(), "as the world it was")


## Every death leaves a body (M6 spec claim 10). The first version made a corpse only
## if the actor had none yet, so dying a second time after a respawn left no body and
## the kit stayed in a dead actor's pockets, out of reach of anyone.
func test_dying_twice_leaves_two_bodies() -> void:
	_setup()
	var inv: StringName = ItemSystem.inventory_of(_player)
	_actors.set_position(_player, IN_THE_BADLANDS)
	_actors.damage_node(_player, &"body", 999999)
	var first: int = _corpses.corpse_of(_player)
	assert_true(_do(&"actor.respawn", {"actor": _player}), "come back")
	for i: int in 3:
		assert_true(_items.spawn(&"currency", &"credit_note", inv, i + 1) > 0, "note %d" % i)
	_actors.set_position(_player, IN_THE_BADLANDS + Vector3i(10 * M, 0, 0))
	_actors.damage_node(_player, &"body", 999999)
	var second: int = _corpses.corpse_of(_player)
	assert_true(second != EntityIds.NONE and second != first, "a second body (%d, then %d)" % [first, second])
	assert_true(_corpses.has_corpse(first), "and the first is still where it fell")
	assert_eq(_corpses.items_on(second).size(), 3, "with what was carried the second time on it")
	assert_eq(_items.items_in(inv).size(), 0, "and nothing left in a dead actor's pockets")
	assert_true(_do(&"actor.respawn", {"actor": _player}), "and coming back works a second time")
	var snap: Dictionary = _sim.snapshot()
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "and a save with two bodies for one actor loads")


## M6 spec claim 11: where you died decides what you come back with. Above the rule's
## law threshold the police held the scene and sell a fraction of the kit back; below
## it nobody touched anything, and the walk back is the price.

## content/parcel/cold_storage_lot.json, in starter_ghetto (law_index 250 > 200)
const IN_TOWN: Vector3i = Vector3i(40 * M, 0, 40 * M)
## outside every parcel, so badlands_outskirts answers (law_index 50)
const IN_THE_BADLANDS: Vector3i = Vector3i(500 * M, 0, 500 * M)
## content/recovery_rule/police.json
const RETURNED_PERMILLE: int = 400
const FEE_PER_ITEM: int = 50


func test_dying_in_the_badlands_leaves_everything_where_it_fell() -> void:
	_setup()
	var back: Array[Dictionary] = []
	_events.subscribe(CorpseSystem.EVENT_RESPAWNED, func(payload: Dictionary) -> void:
		back.append(payload))
	var inv: StringName = ItemSystem.inventory_of(_player)
	for i: int in 10:
		assert_true(_items.spawn(&"currency", &"credit_note", inv, i + 1) > 0, "note %d" % i)
	_actors.set_position(_player, IN_THE_BADLANDS)
	var before: int = _items.item_count()
	_actors.damage_node(_player, &"body", 999999)
	var corpse: int = _corpses.corpse_of(_player)
	assert_eq(_corpses.items_on(corpse).size(), 10, "the whole kit is on the body")
	assert_true(_do(&"actor.respawn", {"actor": _player}), "come back")
	assert_true(_actors.is_alive(_player), "standing")
	assert_eq(_actors.health_of(_player)[&"body"], _actors.max_health(_player, &"body"), "and whole")
	assert_eq(_items.credits_in(inv), 0, "nobody out there returns anything")
	assert_eq(_corpses.items_on(corpse).size(), 10, "it is all still lying there")
	assert_eq(_items.item_count(), before, "and nothing was made or lost")
	assert_eq(back.size(), 1, "one actor.respawned")
	assert_eq(back[0]["returned"], 0, "nothing returned")
	assert_eq(back[0]["fee"], 0, "nothing charged")
	assert_eq(_actors.position_of(_player), _corpses.respawn_position_of(_player), "back at the plot")
	assert_false(_do(&"actor.respawn", {"actor": _player}), "and a standing actor does not respawn")


func test_dying_in_town_with_nothing_to_pay_with_keeps_the_kit_at_the_station() -> void:
	_setup()
	var back: Array[Dictionary] = []
	_events.subscribe(CorpseSystem.EVENT_RESPAWNED, func(payload: Dictionary) -> void:
		back.append(payload))
	var inv: StringName = ItemSystem.inventory_of(_player)
	for i: int in 10:
		assert_true(_items.spawn(&"ammo", &"9x19_fmj", inv, i + 1) > 0, "round %d" % i)
	_actors.set_position(_player, IN_TOWN)
	var before: int = _items.item_count()
	_actors.damage_node(_player, &"body", 999999)
	var corpse: int = _corpses.corpse_of(_player)
	assert_eq(_corpses.items_on(corpse).size(), 10, "everything went onto the body")
	assert_eq(_items.credits_in(ItemSystem.corpse_container(corpse)), 0, "and not a credit among it")
	assert_true(_do(&"actor.respawn", {"actor": _player}), "come back anyway")
	assert_eq(back[0]["returned"], 0, "nothing to pay the fee with, so nothing comes back")
	assert_eq(back[0]["fee"], 0, "and nothing is charged")
	assert_eq(_corpses.items_on(corpse).size(), 10, "the kit stays at the station")
	assert_eq(_items.item_count(), before, "conserved")
	assert_true(_actors.is_alive(_player), "but I am standing again")


func test_the_fee_comes_out_of_the_money_on_the_body() -> void:
	_setup()
	var back: Array[Dictionary] = []
	_events.subscribe(CorpseSystem.EVENT_RESPAWNED, func(payload: Dictionary) -> void:
		back.append(payload))
	var inv: StringName = ItemSystem.inventory_of(_player)
	for i: int in 6:
		assert_true(_items.spawn(&"ammo", &"9x19_fmj", inv, i + 1) > 0, "round %d" % i)
	for i: int in 4:
		assert_true(_items.spawn(&"currency", &"credit_note", inv, 100 + i) > 0, "note %d" % i)
	_actors.set_position(_player, IN_TOWN)
	var before: int = _items.item_count()
	_actors.damage_node(_player, &"body", 999999)
	var corpse: int = _corpses.corpse_of(_player)
	assert_eq(_corpses.items_on(corpse).size(), 10, "ten things went down with me")
	assert_eq(_items.credits_in(ItemSystem.corpse_container(corpse)), 400, "four hundred credits of it")
	assert_true(_do(&"actor.respawn", {"actor": _player}), "come back")
	# two fifths of ten is four, at fifty credits each: two hundred, which is two notes
	assert_eq(back[0]["returned"], 10 * RETURNED_PERMILLE / 1000, "two fifths of the kit")
	assert_eq(back[0]["fee"], 4 * FEE_PER_ITEM, "at fifty credits an item")
	assert_eq(_items.items_in(inv).size(), 4, "four things handed back")
	assert_eq(_corpses.items_on(corpse).size(), 10 - 4 - 2, "the two notes that paid for it are gone with the rest still held")
	assert_eq(_items.item_count(), before, "and not one item was made or lost by the exchange")
	assert_true(_actors.is_alive(_player), "standing, poorer")


func test_respawn_payload_is_exact_and_needs_a_body() -> void:
	_setup()
	assert_false(_do(&"actor.respawn", {}), "empty")
	assert_false(_do(&"actor.respawn", {"actor": "1"}), "not an id")
	assert_false(_do(&"actor.respawn", {"actor": _player, "extra": 1}), "an unknown key")
	assert_false(_do(&"actor.respawn", {"actor": 99999}), "an actor that is not one")
	assert_false(_do(&"actor.respawn", {"actor": _player}), "a living actor")
	_actors.damage_node(_player, &"body", 999999)
	assert_true(_do(&"actor.respawn", {"actor": _player}), "dead, with a body: fine")
