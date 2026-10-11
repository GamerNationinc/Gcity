extends GcityTest

## M6 spec claim 16 (ADR-007 C): a death leaves a corpse, a world container at the
## death position holding everything the actor carried except its device;
## item.take and item.drop move items between a container within reach and the
## inventory; taking from a corpse that is not your own needs `loot` where it lies,
## and a violation is recorded like any other (and the take still happens: a crime is
## recorded, not prevented, as trespass and breaching are).

const SEED: int = 20261150
const M: int = 1000
const FAR: Vector3i = Vector3i(600 * M, 0, 600 * M)

var _sim: SimRoot
var _actors: ActorSystem
var _items: ItemSystem
var _corpses: CorpseSystem
var _land: LandSystem
var _player: int = 0
var _created: Array[Dictionary] = []
var _moved: Array[Dictionary] = []


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_corpses = SimAssembly.corpses_of(_sim)
	_land = SimAssembly.land_of(_sim)
	var created: Array[Dictionary] = []
	var moved: Array[Dictionary] = []
	_created = created
	_moved = moved
	var bus: EventBus = SimAssembly.combat_of(_sim).events()
	bus.subscribe(CorpseSystem.EVENT_CREATED, func(p: Dictionary) -> void: created.append(p))
	bus.subscribe(CorpseSystem.EVENT_MOVED, func(p: Dictionary) -> void: moved.append(p))
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, _at(0, 0))


func _at(cx: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, 0, cz * M + 500)


func _id(kit: Dictionary, key: String) -> int:
	var id: int = kit[key]
	return id


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.rejected_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.rejected_count() == before


## A victim at (cx, cz) carrying a wielded pistol with a loaded magazine, a spare
## magazine, loose rounds and a device; killed by a shot's worth of damage.
func _kit(victim: int) -> Dictionary:
	var inv: StringName = ItemSystem.inventory_of(victim)
	var pistol: int = _items.spawn(&"weapon_frame", &"g19", inv, 1)
	var mag: int = _items.spawn(&"weapon_part", &"g19_mag_15", inv, 2)
	var spare: int = _items.spawn(&"weapon_part", &"g19_mag_15", inv, 3)
	var round: int = _items.spawn(&"ammo", &"9x19_fmj", inv, 4)
	var handset: int = _items.spawn(&"device_frame", &"handset", inv, 5)
	assert_true(_do(&"magazine.load", {"actor": victim, "magazine": mag, "round": round}), "load")
	assert_true(_do(&"weapon.reload_tactical", {"actor": victim, "weapon": pistol, "magazine": mag}), "seat the magazine")
	assert_true(_do(&"actor.wield", {"actor": victim, "weapon": pistol}), "wield")
	assert_true(_do(&"actor.equip_device", {"actor": victim, "device": handset}), "carry the device")
	return {"pistol": pistol, "mag": mag, "spare": spare, "round": round, "handset": handset}


func test_a_death_leaves_a_corpse_with_everything_but_the_device() -> void:
	_setup()
	var victim: int = _actors.spawn(&"arcade", 0)
	_actors.set_position(victim, _at(1, 0) + Vector3i(0, 1000, 0))
	var kit: Dictionary = _kit(victim)
	var inv: StringName = ItemSystem.inventory_of(victim)
	var order: Array[int] = []
	for id: int in _items.items_in(inv):
		if id != kit["handset"]:
			order.append(id)
	_actors.damage_node(victim, &"body", 100000)
	assert_eq(_created.size(), 1, "one corpse.created")
	var corpse: StringName = _corpses.corpse_of(victim)
	assert_eq(corpse, &"corpse.1", "the first corpse")
	assert_eq(_created[0], {"corpse": "corpse.1", "actor": victim, "x": _at(1, 0).x, "y": 1000, "z": _at(1, 0).z, "items": order.size()}, "where it fell, what it held")
	assert_eq(_items.items_in(corpse), order, "everything, in container order, including the wielded pistol")
	assert_eq(_items.container_of(_id(kit, "mag")), ItemSystem.socket_container(_id(kit, "pistol"), &"magazine"), "the seated magazine travels inside the pistol")
	assert_eq(_items.items_in(inv), [kit["handset"]] as Array[int], "the device stays with its owner")
	assert_eq(_corpses.position_of(corpse), _at(1, 0) + Vector3i(0, 1000, 0), "a world container with a position")
	assert_eq(_corpses.storey_of(corpse), 1, "and a storey")
	assert_eq(_corpses.owner_of(corpse), victim, "whose body it is")


func test_take_and_drop_within_reach() -> void:
	_setup()
	var victim: int = _actors.spawn(&"arcade", 0)
	_actors.set_position(victim, _at(1, 0))
	var kit: Dictionary = _kit(victim)
	_actors.damage_node(victim, &"body", 100000)
	var corpse: StringName = _corpses.corpse_of(victim)
	var spare: int = kit["spare"]
	var mine: StringName = ItemSystem.inventory_of(_player)
	_actors.set_position(_player, _at(5, 0))
	assert_false(_do(CorpseSystem.COMMAND_TAKE, {"actor": _player, "from": String(corpse), "item": spare}), "out of reach at 4 m")
	_actors.set_position(_player, _at(0, 0))
	assert_true(_do(CorpseSystem.COMMAND_TAKE, {"actor": _player, "from": String(corpse), "item": spare}), "taken at 1 m")
	assert_eq(_items.container_of(spare), mine, "now in the inventory")
	assert_eq(_moved.back(), {"actor": _player, "item": spare, "from": "corpse.1", "to": String(mine)}, "item.moved")
	assert_false(_do(CorpseSystem.COMMAND_TAKE, {"actor": _player, "from": String(corpse), "item": spare}), "not there any more")
	assert_false(_do(CorpseSystem.COMMAND_TAKE, {"actor": _player, "from": String(corpse), "item": kit["handset"]}), "not from an inventory")
	assert_false(_do(CorpseSystem.COMMAND_TAKE, {"actor": victim, "from": String(corpse), "item": kit["pistol"]}), "the dead take nothing")
	assert_false(_do(CorpseSystem.COMMAND_TAKE, {"actor": _player, "from": "corpse.9", "item": kit["pistol"]}), "no such corpse")
	# drop: onto a pile at your feet; a second drop in the same cell joins it
	assert_true(_do(CorpseSystem.COMMAND_DROP, {"actor": _player, "item": spare}), "dropped")
	var pile: StringName = _items.container_of(spare)
	assert_eq(pile, &"pile.2", "a pile, numbered after the corpse")
	assert_eq(_corpses.position_of(pile), _at(0, 0), "at the dropper's feet")
	var pistol: int = kit["pistol"]
	assert_true(_do(CorpseSystem.COMMAND_TAKE, {"actor": _player, "from": String(corpse), "item": pistol}), "take the pistol")
	assert_true(_do(&"actor.wield", {"actor": _player, "weapon": pistol}), "and wield it")
	assert_false(_do(CorpseSystem.COMMAND_DROP, {"actor": _player, "item": pistol}), "not what you wield")
	assert_true(_do(&"actor.wield", {"actor": _player, "weapon": 0}), "put it away")
	assert_true(_do(CorpseSystem.COMMAND_DROP, {"actor": _player, "item": pistol}), "then it drops")
	assert_eq(_items.container_of(pistol), pile, "onto the same pile")
	assert_eq(_corpses.place_ids(), [&"pile.2"] as Array[StringName], "the corpse went when its last loose item (the pistol) was taken")
	for id: int in _items.items_in(pile):
		assert_true(_do(CorpseSystem.COMMAND_TAKE, {"actor": _player, "from": String(pile), "item": id}), "pick up %d" % id)
	assert_eq(_corpses.place_ids(), [] as Array[StringName], "and the pile when it was emptied")


func test_looting_another_body_is_recorded_where_loot_is_not_a_right() -> void:
	_setup()
	var x0: int = FAR.x
	var z0: int = FAR.z
	_land.add_parcel(&"zz_yard", &"starter_ghetto", &"corp", [[x0, z0], [x0 + 10000, z0], [x0 + 10000, z0 + 10000], [x0, z0 + 10000]], -1000, 3000)
	var victim: int = _actors.spawn(&"arcade", 0)
	_actors.set_position(victim, _at(1, 1))
	_actors.set_position(_player, _at(1, 2))
	var kit: Dictionary = _kit(victim)
	_actors.damage_node(victim, &"body", 100000)
	var corpse: StringName = _corpses.corpse_of(victim)
	var before: int = _land.violation_count()
	assert_true(_do(CorpseSystem.COMMAND_TAKE, {"actor": _player, "from": String(corpse), "item": kit["spare"]}), "the take happens")
	assert_eq(_land.violation_count(), before + 1, "and a loot violation is recorded")
	assert_eq(_items.container_of(_id(kit, "spare")), ItemSystem.inventory_of(_player), "the spare is yours")
	# your own body: no right needed
	_actors.damage_node(_player, &"body", 100000)
	var own: StringName = _corpses.corpse_of(_player)
	var me_again: int = _actors.spawn(&"arcade", 0)
	assert_true(me_again != _player, "a stand-in (respawn is claim 17)")
	assert_eq(_corpses.owner_of(own), _player, "the player's body")
	assert_false(_items.items_in(own).is_empty(), "with the spare in it")


func test_a_guards_corpse_is_real_loot() -> void:
	_setup()
	var guard: int = SimAssembly.perception_of(_sim).spawn(&"guard_sim", BuildSystem.cell_of(_at(2, 0)), 0, 1, "")
	var kit: Dictionary = _kit(guard)
	_actors.damage_node(guard, &"body", 1_000_000)
	var corpse: StringName = _corpses.corpse_of(guard)
	assert_true(_items.items_in(corpse).has(kit["pistol"]), "the guard's pistol lies in its corpse")
	_actors.set_position(_player, _at(1, 0))
	assert_true(_do(CorpseSystem.COMMAND_TAKE, {"actor": _player, "from": String(corpse), "item": kit["pistol"]}), "and can be taken")


func test_places_survive_the_restore_and_bad_ones_are_refused() -> void:
	_setup()
	var victim: int = _actors.spawn(&"arcade", 0)
	_actors.set_position(victim, _at(1, 0))
	var kit: Dictionary = _kit(victim)
	_actors.damage_node(victim, &"body", 100000)
	assert_true(_do(CorpseSystem.COMMAND_TAKE, {"actor": _player, "from": "corpse.1", "item": kit["spare"]}), "take")
	assert_true(_do(CorpseSystem.COMMAND_DROP, {"actor": _player, "item": kit["spare"]}), "drop")
	var snap: Dictionary = _sim.snapshot()
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "restored")
	assert_eq(other.restore_root(snap), OK, "root restored")
	assert_eq(SimAssembly.corpses_of(other).snapshot(), _corpses.snapshot(), "equal places")
	_sim.step()
	other.step()
	assert_eq(other.state_hash(), _sim.state_hash(), "step on together")
	var state: Dictionary = _corpses.snapshot()
	var bads: Array[Dictionary] = [{}]
	var b1: Dictionary = state.duplicate(true)
	var p1: Dictionary = b1["places"]
	var c1: Dictionary = p1["corpse.1"]
	c1["owner"] = 999
	bads.append(b1)
	var b2: Dictionary = state.duplicate(true)
	var p2: Dictionary = b2["places"]
	p2["crate.7"] = p2["corpse.1"]
	bads.append(b2)
	var b3: Dictionary = state.duplicate(true)
	b3["next"] = 1
	bads.append(b3)
	var b4: Dictionary = state.duplicate(true)
	var p4: Dictionary = b4["places"]
	var c4: Dictionary = p4["pile.2"]
	c4["kind"] = "corpse"
	bads.append(b4)
	for bad: Dictionary in bads:
		assert_eq(_corpses.restore(bad), ERR_INVALID_DATA, "refused: %s" % str(bad))
	assert_eq(_corpses.snapshot(), state, "and nothing changed")
