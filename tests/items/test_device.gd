extends GcityTest

## M5 spec claims 1–2: the device is a socketed item of its own family; modules fit
## its bays through the resolver and provide the tags apps require; an actor carries
## one device, inheriting its modifiers like a wielded weapon. Attach and detach
## restore the exact prior value (M1 claim 3 on the device), over 10 000 sequences.

const SEED: int = 20261110
const SEED_PROPERTY: int = 20261111
const PROPERTY_CASES: int = 10_000

var _sim: SimRoot
var _actors: ActorSystem
var _items: ItemSystem
var _stats: StatResolver
var _player: int = 0
var _device: int = 0
var _radio: int = 0


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_stats = SimAssembly.stats_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	var inv: StringName = ItemSystem.inventory_of(_player)
	_device = _items.spawn(&"device_frame", &"handset", inv, 1)
	_radio = _items.spawn(&"device_module", &"radio_module", inv, 2)
	assert_true(_device > 0 and _radio > 0, "device and module spawned")


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


func test_a_device_is_an_item_with_bays_and_stats() -> void:
	_setup()
	assert_eq(_items.item_kind(_device), &"device_frame", "kind")
	assert_eq(_stats.resolve(_device, &"memory_capacity"), 1000, "one daemon's worth of memory")
	assert_eq(_stats.resolve(_device, &"antenna_gain"), 0, "no antenna on its own")
	assert_eq(_stats.get_tags(_device), [&"device"] as Array[StringName], "tagged a device")
	assert_eq(_items.provides_of(_device), [] as Array[StringName], "provides nothing bare")
	assert_eq(_items.provides_of(_radio), [] as Array[StringName], "a module is not a device")
	assert_eq(_items.socket_part(_device, &"radio"), 0, "the radio bay is empty")
	assert_true(_items.is_frame(_device), "a frame")
	assert_false(_items.is_frame(_radio), "a module is not")


func test_modules_fit_bays_through_item_attach_and_provide_tags() -> void:
	_setup()
	assert_true(_do(&"item.attach", {"actor": _player, "weapon": _device, "part": _radio}), "the radio module fits the radio bay")
	assert_eq(_items.socket_part(_device, &"radio"), _radio, "in the bay")
	assert_eq(_items.container_of(_radio), ItemSystem.socket_container(_device, &"radio"), "its container is the bay")
	assert_eq(_stats.resolve(_device, &"antenna_gain"), 400000, "400 m of antenna through the resolver")
	assert_eq(_items.provides_of(_device), [&"radio"] as Array[StringName], "provides radio")
	assert_false(_do(&"item.attach", {"actor": _player, "weapon": _device, "part": _radio}), "not twice")
	var second: int = _items.spawn(&"device_module", &"radio_module", ItemSystem.inventory_of(_player), 3)
	assert_false(_do(&"item.attach", {"actor": _player, "weapon": _device, "part": second}), "the bay is taken")
	var pistol: int = _items.spawn(&"weapon_frame", &"g19", ItemSystem.inventory_of(_player), 4)
	assert_false(_do(&"item.attach", {"actor": _player, "weapon": pistol, "part": second}), "a device module does not fit a weapon")
	var barrel: int = _items.spawn(&"weapon_part", &"g19_barrel", ItemSystem.inventory_of(_player), 5)
	assert_false(_do(&"item.attach", {"actor": _player, "weapon": _device, "part": barrel}), "a weapon part does not fit a device")
	assert_true(_do(&"item.attach", {"actor": _player, "weapon": pistol, "part": barrel}), "item.attach is weapon.attach for weapons too")
	assert_true(_do(&"item.detach", {"actor": _player, "weapon": _device, "socket": "radio"}), "detach by bay")
	assert_eq(_stats.resolve(_device, &"antenna_gain"), 0, "the exact prior value")
	assert_eq(_items.provides_of(_device), [] as Array[StringName], "provides nothing again")
	assert_eq(_items.container_of(_radio), ItemSystem.inventory_of(_player), "back in the inventory")
	assert_false(_do(&"item.detach", {"actor": _player, "weapon": _device, "socket": "coprocessor"}), "an empty bay")
	assert_false(_do(&"item.detach", {"actor": _player, "weapon": _device, "socket": "barrel"}), "a weapon socket is not a device bay")
	assert_eq(_items.item_count(), 5, "conservation: nothing created or lost")


func test_an_actor_carries_one_device_and_inherits_its_modifiers() -> void:
	_setup()
	assert_eq(_actors.device_of(_player), 0, "nothing carried")
	assert_true(_do(&"actor.equip_device", {"actor": _player, "device": _device}), "equip")
	assert_eq(_actors.device_of(_player), _device, "carried")
	assert_false(_do(&"actor.equip_device", {"actor": _player, "device": _device}), "not twice")
	var pistol: int = _items.spawn(&"weapon_frame", &"g19", ItemSystem.inventory_of(_player), 4)
	assert_false(_do(&"actor.equip_device", {"actor": _player, "device": pistol}), "a weapon is not a device")
	assert_false(_do(&"actor.equip_device", {"actor": _player, "device": _radio}), "a module is not a device")
	var other: int = _actors.spawn(&"arcade", 0)
	assert_false(_do(&"actor.equip_device", {"actor": other, "device": _device}), "not another actor's device")
	assert_false(_do(&"actor.equip_device", {"actor": _player}), "missing key")
	# a modifier on the actor tagged for devices reaches the carried device
	_stats.add_modifier(_player, {"stat": &"antenna_gain", "class": StatResolver.CLASS_ADD, "value": 50000, "source": &"perk.long_reach", "tags": [&"device"] as Array[StringName]})
	assert_eq(_stats.resolve(_device, &"antenna_gain"), 50000, "the carrier's tagged modifier reaches the device")
	assert_true(_do(&"actor.equip_device", {"actor": _player, "device": 0}), "put away")
	assert_eq(_stats.resolve(_device, &"antenna_gain"), 0, "and the inheritance ends")
	assert_eq(_actors.device_of(_player), 0, "nothing carried")
	assert_false(_do(&"actor.equip_device", {"actor": _player, "device": 0}), "nothing to put away")


func test_property_attach_and_detach_restore_the_exact_prior_value() -> void:
	_setup()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	var inv: StringName = ItemSystem.inventory_of(_player)
	var modules: Array[int] = [_radio]
	for i: int in 3:
		modules.append(_items.spawn(&"device_module", &"radio_module", inv, 10 + i))
	var base: Dictionary = {}
	for stat: StringName in [&"antenna_gain", &"memory_capacity", &"battery_reserve"]:
		base[stat] = _stats.resolve(_device, stat)
	var violations: int = 0
	var attached: int = 0
	for case: int in PROPERTY_CASES:
		var module: int = modules[rng.randi_range(0, modules.size() - 1)]
		if rng.randi_range(0, 1) == 0:
			if _items.container_of(module) == inv and _items.socket_part(_device, &"radio") == 0:
				_do(&"item.attach", {"actor": _player, "weapon": _device, "part": module})
				attached += 1
		elif _items.socket_part(_device, &"radio") != 0:
			_do(&"item.detach", {"actor": _player, "weapon": _device, "socket": "radio"})
		var fitted: bool = _items.socket_part(_device, &"radio") != 0
		var gain: int = _stats.resolve(_device, &"antenna_gain")
		var expected: int = base[&"antenna_gain"] + (400000 if fitted else 0)
		if gain != expected or _stats.resolve(_device, &"memory_capacity") != base[&"memory_capacity"]:
			violations += 1
			if violations <= 3:
				fail("case %d: antenna %d expected %d" % [case, gain, expected])
		if _items.item_count() != 5:
			violations += 1
	assert_eq(violations, 0, "every attach and detach restores the exact prior value and conserves items")
	assert_true(attached > 1000, "enough attaches (%d)" % attached)


func test_restore_round_trip_and_rejections() -> void:
	_setup()
	assert_true(_do(&"item.attach", {"actor": _player, "weapon": _device, "part": _radio}), "fitted")
	assert_true(_do(&"actor.equip_device", {"actor": _player, "device": _device}), "carried")
	var snap: Dictionary = _sim.snapshot()
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "restored")
	assert_eq(other.restore_root(snap), OK, "root restored")
	var items: ItemSystem = SimAssembly.items_of(other)
	var actors: ActorSystem = SimAssembly.actors_of(other)
	assert_eq(items.socket_part(_device, &"radio"), _radio, "the bay came across")
	assert_eq(items.provides_of(_device), [&"radio"] as Array[StringName], "and provides")
	assert_eq(actors.device_of(_player), _device, "carried across")
	assert_eq(SimAssembly.stats_of(other).resolve(_device, &"antenna_gain"), 400000, "resolved the same")
	_sim.step()
	other.step()
	assert_eq(other.state_hash(), _sim.state_hash(), "hashes agree")
	var state: Dictionary = _actors.snapshot()
	var bad: Dictionary = state.duplicate(true)
	var recs: Dictionary = bad["actors"]
	var rec: Dictionary = recs[_player]
	rec["device"] = _radio
	assert_eq(actors.restore(bad), ERR_INVALID_DATA, "a module is not a device to carry")
	bad = state.duplicate(true)
	recs = bad["actors"]
	rec = recs[_player]
	rec.erase("device")
	assert_eq(actors.restore(bad), ERR_INVALID_DATA, "the device slot is required")
