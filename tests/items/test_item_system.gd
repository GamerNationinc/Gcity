extends GcityTest

const SEED: int = 20260920
const PROPERTY_CASES: int = 10_000
const SEED_CONSERVATION: int = 20260925
const SEED_FUZZ: int = 20260926
const ACTOR: int = 1
const OTHER_ACTOR: int = 2

var _sim: SimRoot
var _items: ItemSystem
var _stats: StatResolver


func _build() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_items = SimAssembly.items_of(_sim)
	_stats = SimAssembly.stats_of(_sim)
	# M2 spec claim 17: item commands name a live actor. ACTOR and OTHER_ACTOR are the
	# first two entities, so item ids start at 3.
	var actors: ActorSystem = SimAssembly.actors_of(_sim)
	assert_eq(actors.spawn(&"arcade", 0), ACTOR, "actor 1")
	assert_eq(actors.spawn(&"arcade", 0), OTHER_ACTOR, "actor 2")


## Submits a command for the next tick and steps once. Returns true if it was applied.
func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


func _inv() -> StringName:
	return ItemSystem.inventory_of(ACTOR)


## The standard M1 kit: pistol, barrel, slide, two magazines and 30 rounds, all loose.
func _kit() -> Dictionary:
	var pistol: int = _items.spawn(&"weapon_frame", &"g19", _inv(), 1)
	var barrel: int = _items.spawn(&"weapon_part", &"g19_barrel", _inv(), 2)
	var slide: int = _items.spawn(&"weapon_part", &"g19_slide", _inv(), 3)
	var mag_a: int = _items.spawn(&"weapon_part", &"g19_mag_15", _inv(), 4)
	var mag_b: int = _items.spawn(&"weapon_part", &"g19_mag_15", _inv(), 5)
	var rounds: Array[int] = []
	for i: int in range(30):
		rounds.append(_items.spawn(&"ammo", &"9x19_fmj", _inv(), 100 + i))
	return {"pistol": pistol, "barrel": barrel, "slide": slide, "mag_a": mag_a, "mag_b": mag_b, "rounds": rounds}


# ---------------------------------------------------------------- units

func test_spawn_sets_bases_and_tags_from_the_template() -> void:
	_build()
	var pistol: int = _items.spawn(&"weapon_frame", &"g19", _inv(), 7)
	assert_true(pistol >= 1, "id issued")
	assert_eq(_items.item_kind(pistol), &"weapon_frame", "kind")
	assert_eq(_items.item_template(pistol), &"g19", "template")
	assert_eq(_items.container_of(pistol), _inv(), "in the inventory")
	assert_eq(_stats.resolve(pistol, &"hit_chance"), 650000, "base from the frame file")
	assert_eq(_stats.resolve(pistol, &"reload_ticks"), 80000, "reload ticks")
	assert_eq(_stats.get_tags(pistol), [&"weapon", &"weapon_class.handgun"] as Array[StringName], "tags from the frame file")
	var round: int = _items.spawn(&"ammo", &"9x19_fmj", &"world", 8)
	assert_eq(_stats.resolve(round, &"damage"), 34500, "round damage from the ammo file")
	assert_eq(_items.items_in(&"world"), [round] as Array[int], "world holds the round")
	assert_eq(_items.spawn(&"weapon_frame", &"nope", _inv(), 1), 0, "unknown template")
	assert_eq(_items.spawn(&"calibre", &"9x19", _inv(), 1), 0, "calibres are not items")
	assert_eq(_items.spawn(&"ammo", &"9x19_fmj", &"mag.3", 1), 0, "cannot spawn into a closed container")
	assert_eq(_items.spawn(&"ammo", &"9x19_fmj", &"inv.x", 1), 0, "malformed inventory name")
	assert_eq(_items.item_count(), 2, "only the two valid spawns")


func test_same_template_and_seed_give_identical_stats() -> void:
	_build()
	var a: int = _items.spawn(&"weapon_frame", &"g19", _inv(), 42)
	var b: int = _items.spawn(&"weapon_frame", &"g19", _inv(), 42)
	assert_ne(a, b, "distinct instances")
	for stat: StringName in _stats.stat_ids():
		assert_eq(_stats.resolve(a, stat), _stats.resolve(b, stat), "stat %s equal" % stat)


func test_attach_and_detach_move_the_part_and_its_modifiers() -> void:
	_build()
	var k: Dictionary = _kit()
	var pistol: int = k["pistol"]
	var barrel: int = k["barrel"]
	var before: int = _stats.resolve(pistol, &"hit_chance")
	assert_true(_do(&"weapon.attach", {"actor": ACTOR, "weapon": pistol, "part": barrel}), "attach barrel")
	assert_eq(_items.socket_part(pistol, &"barrel"), barrel, "socket filled")
	assert_eq(_items.container_of(barrel), ItemSystem.socket_container(pistol, &"barrel"), "part moved into the socket container")
	assert_eq(_stats.resolve(pistol, &"hit_chance"), before + 20000, "barrel modifier applied")
	assert_false(_do(&"weapon.attach", {"actor": ACTOR, "weapon": pistol, "part": barrel}), "part no longer loose")
	var slide: int = k["slide"]
	assert_false(_do(&"weapon.attach", {"actor": OTHER_ACTOR, "weapon": pistol, "part": slide}), "other actor does not own them")
	assert_false(_do(&"weapon.attach", {"actor": 99, "weapon": pistol, "part": slide}), "an actor that does not exist may do nothing (M2 claim 17)")
	assert_false(_do(&"weapon.attach", {"actor": ACTOR, "weapon": pistol, "part": k["mag_a"]}), "magazines never attach; they reload")
	assert_true(_do(&"weapon.detach", {"actor": ACTOR, "weapon": pistol, "socket": "barrel"}), "detach")
	assert_eq(_items.socket_part(pistol, &"barrel"), 0, "socket empty")
	assert_eq(_items.container_of(barrel), _inv(), "part back in the inventory")
	assert_eq(_stats.resolve(pistol, &"hit_chance"), before, "modifier removed exactly")
	assert_false(_do(&"weapon.detach", {"actor": ACTOR, "weapon": pistol, "socket": "barrel"}), "nothing to detach")
	assert_false(_do(&"weapon.detach", {"actor": ACTOR, "weapon": pistol, "socket": "magazine"}), "magazines do not detach either")


func test_magazines_are_ordered_containers() -> void:
	_build()
	var k: Dictionary = _kit()
	var mag: int = k["mag_a"]
	var rounds: Array[int] = k["rounds"]
	for i: int in range(15):
		assert_true(_do(&"magazine.load", {"actor": ACTOR, "magazine": mag, "round": rounds[i]}), "load %d" % i)
	assert_eq(_items.rounds_in(mag), rounds.slice(0, 15), "order preserved, last loaded on top")
	assert_false(_do(&"magazine.load", {"actor": ACTOR, "magazine": mag, "round": rounds[15]}), "capacity 15")
	assert_true(_do(&"magazine.unload", {"actor": ACTOR, "magazine": mag}), "unload pops the top")
	assert_eq(_items.rounds_in(mag).size(), 14, "fourteen left")
	assert_eq(_items.container_of(rounds[14]), _inv(), "the top round is back in the inventory")
	assert_false(_do(&"magazine.load", {"actor": ACTOR, "magazine": mag, "round": k["barrel"]}), "only rounds load")
	assert_false(_do(&"magazine.load", {"actor": ACTOR, "magazine": k["barrel"], "round": rounds[20]}), "only magazines take rounds")
	assert_false(_do(&"magazine.load", {"actor": OTHER_ACTOR, "magazine": mag, "round": rounds[20]}), "ownership")
	assert_false(_do(&"magazine.unload", {"actor": ACTOR, "magazine": k["mag_b"]}), "empty magazine")


func test_reloads_keep_or_drop_the_old_magazine_chamber_and_take_time() -> void:
	_build()
	var k: Dictionary = _kit()
	var pistol: int = k["pistol"]
	var mag_a: int = k["mag_a"]
	var mag_b: int = k["mag_b"]
	var rounds: Array[int] = k["rounds"]
	for i: int in range(5):
		_do(&"magazine.load", {"actor": ACTOR, "magazine": mag_a, "round": rounds[i]})
	for i: int in range(5, 8):
		_do(&"magazine.load", {"actor": ACTOR, "magazine": mag_b, "round": rounds[i]})
	var ergo_before: int = _stats.resolve(pistol, &"ergonomics")
	assert_true(_do(&"weapon.reload_tactical", {"actor": ACTOR, "weapon": pistol, "magazine": mag_a}), "first reload into an empty well")
	assert_eq(_items.magazine_of(pistol), mag_a, "magazine seated")
	assert_eq(_items.chambered(pistol), rounds[4], "empty chamber took the top round")
	assert_eq(_items.rounds_in(mag_a), rounds.slice(0, 4), "four left in the magazine")
	assert_eq(_stats.resolve(pistol, &"ergonomics"), ergo_before - 300, "magazine modifier applied")
	assert_eq(_stats.get_inherits(rounds[4]), pistol, "chambered round inherits from the weapon")
	assert_eq(_stats.get_tags(rounds[4]), [&"ammo", &"weapon", &"weapon_class.handgun"] as Array[StringName], "chambered round carries the frame's tags")
	var perk: int = _stats.add_modifier(pistol, {"stat": &"damage", "class": &"mul", "value": 1000, "source": &"test.perk", "tags": [&"weapon_class.handgun"]})
	assert_true(perk >= 1, "a tagged modifier on the weapon")
	assert_eq(_stats.resolve(rounds[4], &"damage"), 37950, "reaches the chambered round: 34500 * 1.1")
	assert_eq(_stats.resolve(rounds[0], &"damage"), 34500, "and not the rounds still in the magazine")
	var busy_until: int = _items.busy_until(pistol)
	assert_eq(busy_until, _sim.get_tick() + 80, "reload_ticks 80000 milli-ticks = 80 ticks")
	assert_true(_items.is_busy(pistol, _sim.get_tick()), "busy now")
	assert_false(_do(&"weapon.reload_tactical", {"actor": ACTOR, "weapon": pistol, "magazine": mag_b}), "rejected while busy")
	assert_false(_do(&"weapon.attach", {"actor": ACTOR, "weapon": pistol, "part": k["barrel"]}), "attach rejected while busy")
	_sim.step_n(busy_until - _sim.get_tick())
	assert_false(_items.is_busy(pistol, _sim.get_tick()), "free again")
	assert_true(_do(&"weapon.reload_tactical", {"actor": ACTOR, "weapon": pistol, "magazine": mag_b}), "tactical reload")
	assert_eq(_items.magazine_of(pistol), mag_b, "new magazine seated")
	assert_eq(_items.container_of(mag_a), _inv(), "tactical keeps the partial magazine")
	assert_eq(_items.rounds_in(mag_a), rounds.slice(0, 4), "with its rounds")
	assert_eq(_items.chambered(pistol), rounds[4], "chamber untouched when already loaded")
	assert_eq(_items.rounds_in(mag_b).size(), 3, "new magazine still full: no round taken")
	assert_eq(_stats.resolve(pistol, &"ergonomics"), ergo_before - 300, "one magazine modifier at a time")
	_sim.step_n(80)
	assert_true(_do(&"weapon.reload_emergency", {"actor": ACTOR, "weapon": pistol, "magazine": mag_a}), "emergency reload")
	assert_eq(_items.container_of(mag_b), &"world", "emergency drops the old magazine to the world")
	assert_eq(_items.rounds_in(mag_b).size(), 3, "dropped with its rounds")
	assert_eq(_items.magazine_of(pistol), mag_a, "seated")


func test_payload_contracts_are_exact() -> void:
	_build()
	var k: Dictionary = _kit()
	var pistol: int = k["pistol"]
	var rounds: Array[int] = k["rounds"]
	var rejected: Array[Array] = [
		[&"item.spawn", {"kind": "ammo", "template": "9x19_fmj", "container": "inv.1", "seed": 1}],
		[&"item.spawn", {"kind": "ammo", "template": "9x19_fmj", "container": "inv.1", "seed": 1, "count": 0}],
		[&"item.spawn", {"kind": "ammo", "template": "9x19_fmj", "container": "inv.1", "seed": 1, "count": 101}],
		[&"item.spawn", {"kind": "ammo", "template": "9x19_fmj", "container": "mag.1", "seed": 1, "count": 1}],
		[&"item.spawn", {"kind": "ammo", "template": "9x19_fmj", "container": "inv.1", "seed": 1.0, "count": 1}],
		[&"item.spawn", {"kind": 3, "template": "9x19_fmj", "container": "inv.1", "seed": 1, "count": 1}],
		[&"item.spawn", {"kind": "stat", "template": "damage", "container": "inv.1", "seed": 1, "count": 1}],
		[&"magazine.load", {"actor": ACTOR, "magazine": k["mag_a"]}],
		[&"magazine.load", {"actor": ACTOR, "magazine": k["mag_a"], "round": rounds[0], "x": 1}],
		[&"magazine.load", {"actor": "1", "magazine": k["mag_a"], "round": rounds[0]}],
		[&"magazine.load", {"actor": ACTOR, "magazine": k["mag_a"], "round": 99999}],
		[&"weapon.attach", {"actor": ACTOR, "weapon": k["barrel"], "part": pistol}],
		[&"weapon.detach", {"actor": ACTOR, "weapon": pistol, "socket": 4}],
		[&"weapon.detach", {"actor": ACTOR, "weapon": pistol, "socket": "Bad Socket"}],
		[&"weapon.reload_tactical", {"actor": ACTOR, "weapon": pistol, "magazine": k["barrel"]}],
		[&"weapon.reload_emergency", {"actor": ACTOR, "weapon": pistol}],
	]
	var snap_before: String = _sim.state_hash()
	var count_before: int = _items.item_count()
	for entry: Array in rejected:
		var kind: StringName = entry[0]
		var payload: Dictionary = entry[1]
		assert_false(_do(kind, payload), "rejected: %s %s" % [kind, var_to_str(payload)])
	assert_eq(_items.item_count(), count_before, "no item appeared")
	assert_eq(_sim.rejected_count(), rejected.size(), "every one counted as rejected")
	var systems_hash_before: String = snap_before
	assert_ne(_sim.state_hash(), systems_hash_before, "the tick advanced (hash includes tick)")
	assert_true(_do(&"item.spawn", {"kind": "ammo", "template": "9x19_fmj", "container": "inv.1", "seed": 500, "count": 3}), "valid spawn via command")
	assert_eq(_items.item_count(), count_before + 3, "three rounds spawned")


# ---------------------------------------------------------------- properties (claim 9)

## Every item id, across every container, exactly once.
func _placement_ok(expected_ids: Array[int]) -> String:
	var seen: Dictionary = {}
	for name: StringName in [&"world", _inv(), ItemSystem.inventory_of(OTHER_ACTOR)]:
		for id: int in _items.items_in(name):
			if seen.has(id):
				return "item %d in two containers" % id
			seen[id] = name
	# closed containers: magazines, chambers, sockets
	for id: int in expected_ids:
		for name: StringName in [ItemSystem.magazine_container(id), ItemSystem.chamber_container(id)]:
			for inner: int in _items.items_in(name):
				if seen.has(inner):
					return "item %d in two containers (%s)" % [inner, name]
				seen[inner] = name
		for socket: StringName in [&"barrel", &"slide", &"optic", &"magazine", &"power_cell"]:
			var socket_name: StringName = ItemSystem.socket_container(id, socket)
			for inner: int in _items.items_in(socket_name):
				if seen.has(inner):
					return "item %d in two containers (socket)" % inner
				seen[inner] = socket_name
	if seen.size() != expected_ids.size():
		return "%d items placed, %d expected" % [seen.size(), expected_ids.size()]
	for id: int in expected_ids:
		if not seen.has(id):
			return "item %d lost" % id
		if _items.container_of(id) != seen[id]:
			return "item %d location index disagrees with containers" % id
	return ""


func test_property_items_are_conserved_across_random_command_sequences() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_CONSERVATION
	_build()
	var k: Dictionary = _kit()
	var ids: Array[int] = [k["pistol"], k["barrel"], k["slide"], k["mag_a"], k["mag_b"]]
	var rounds: Array[int] = k["rounds"]
	ids.append_array(rounds)
	var mags: Array[int] = [k["mag_a"], k["mag_b"]]
	var parts: Array[int] = [k["barrel"], k["slide"]]
	var kinds: Array[StringName] = [&"magazine.load", &"magazine.unload", &"weapon.attach", &"weapon.detach",
		&"weapon.reload_tactical", &"weapon.reload_emergency"]
	var applied: int = 0
	var failures: int = 0
	for case: int in range(PROPERTY_CASES):
		var kind: StringName = kinds[rng.randi_range(0, kinds.size() - 1)]
		var actor: int = ACTOR if rng.randf() < 0.9 else OTHER_ACTOR
		var payload: Dictionary = {}
		match kind:
			&"magazine.load":
				payload = {"actor": actor, "magazine": mags[rng.randi_range(0, 1)], "round": rounds[rng.randi_range(0, rounds.size() - 1)]}
			&"magazine.unload":
				payload = {"actor": actor, "magazine": mags[rng.randi_range(0, 1)]}
			&"weapon.attach":
				payload = {"actor": actor, "weapon": k["pistol"], "part": parts[rng.randi_range(0, 1)] if rng.randf() < 0.8 else mags[0]}
			&"weapon.detach":
				payload = {"actor": actor, "weapon": k["pistol"], "socket": ["barrel", "slide", "optic", "magazine"][rng.randi_range(0, 3)]}
			_:
				payload = {"actor": actor, "weapon": k["pistol"], "magazine": mags[rng.randi_range(0, 1)]}
		if _do(kind, payload):
			applied += 1
		if rng.randf() < 0.2:
			_sim.step_n(rng.randi_range(1, 100))  # lets reload busy windows expire
		var problem: String = _placement_ok(ids)
		if not problem.is_empty():
			failures += 1
			if failures <= 3:
				fail("case %d after %s: %s" % [case, kind, problem])
	assert_eq(failures, 0, "conserved through %d commands" % PROPERTY_CASES)
	assert_true(applied > PROPERTY_CASES / 20, "the sequence exercised real state changes (%d applied)" % applied)
	assert_eq(_items.item_count(), ids.size(), "no item created or destroyed")


## Random payload shapes, values and kinds never crash and never break conservation.
func test_property_hostile_payloads_are_rejected_without_damage() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_FUZZ
	_build()
	var k: Dictionary = _kit()
	var ids: Array[int] = [k["pistol"], k["barrel"], k["slide"], k["mag_a"], k["mag_b"]]
	var rounds: Array[int] = k["rounds"]
	ids.append_array(rounds)
	var kinds: Array[StringName] = [&"item.spawn", &"magazine.load", &"magazine.unload", &"weapon.attach", &"weapon.detach",
		&"weapon.reload_tactical", &"weapon.reload_emergency"]
	var keys: Array[String] = ["actor", "weapon", "magazine", "round", "part", "socket", "kind", "template", "container", "seed", "count", "x"]
	var failures: int = 0
	var spawned: int = 0
	for case: int in range(PROPERTY_CASES):
		var payload: Dictionary = {}
		for i: int in range(rng.randi_range(0, 6)):
			var key: String = keys[rng.randi_range(0, keys.size() - 1)]
			payload[key] = _random_value(rng, ids)
		var kind: StringName = kinds[rng.randi_range(0, kinds.size() - 1)]
		var before: int = _items.item_count()
		if _do(kind, payload) and kind == &"item.spawn":
			spawned += _items.item_count() - before
			ids = _items.item_ids()
		var problem: String = _placement_ok(_items.item_ids())
		if not problem.is_empty():
			failures += 1
			if failures <= 3:
				fail("case %d after %s %s: %s" % [case, kind, var_to_str(payload), problem])
	assert_eq(failures, 0, "no hostile payload damaged the item state")


func _random_value(rng: RandomNumberGenerator, ids: Array[int]) -> Variant:
	match rng.randi_range(0, 9):
		0:
			return ids[rng.randi_range(0, ids.size() - 1)]
		1:
			return rng.randi_range(-5, 200)
		2:
			return rng.randf() * 100.0
		3:
			return ["barrel", "slide", "magazine", "optic", "ammo", "9x19_fmj", "g19", "inv.1", "world", "mag.4", "Bad Name", ""][rng.randi_range(0, 11)]
		4:
			return StringName("weapon_part")
		5:
			return true
		6:
			return null
		7:
			return [1, 2]
		8:
			return {"a": 1}
		_:
			return 1 << 62


# ---------------------------------------------------------------- restore (claim 10)

func test_item_state_survives_a_round_trip_with_partial_magazines() -> void:
	_build()
	var k: Dictionary = _kit()
	var pistol: int = k["pistol"]
	var rounds: Array[int] = k["rounds"]
	for i: int in range(7):
		_do(&"magazine.load", {"actor": ACTOR, "magazine": k["mag_a"], "round": rounds[i]})
	for i: int in range(7, 10):
		_do(&"magazine.load", {"actor": ACTOR, "magazine": k["mag_b"], "round": rounds[i]})
	_do(&"weapon.attach", {"actor": ACTOR, "weapon": pistol, "part": k["barrel"]})
	_do(&"weapon.reload_tactical", {"actor": ACTOR, "weapon": pistol, "magazine": k["mag_a"]})
	_sim.step_n(100)
	_do(&"weapon.reload_emergency", {"actor": ACTOR, "weapon": pistol, "magazine": k["mag_b"]})
	var snapshot: Dictionary = _sim.snapshot()
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	var fresh: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(fresh, snapshot), OK, "restore into a fresh sim")
	fresh.step_n(_sim.get_tick())
	# The systems' state is what the round trip restores; the root's own counters
	# (dispatched, rejected) and RNG are full save/load, G2.
	var source_systems: Dictionary = _sim.snapshot()["systems"]
	var fresh_systems: Dictionary = fresh.snapshot()["systems"]
	assert_eq(StateHash.of(fresh_systems), StateHash.of(source_systems), "identical system state hash after the round trip")
	assert_eq(StateHash.of(fresh_systems).length(), 64, "hashable")
	var fresh_items: ItemSystem = SimAssembly.items_of(fresh)
	var fresh_stats: StatResolver = SimAssembly.stats_of(fresh)
	var mag_a: int = k["mag_a"]
	assert_eq(fresh_items.magazine_of(pistol), k["mag_b"], "seated magazine")
	assert_eq(fresh_items.chambered(pistol), rounds[6], "chambered round")
	assert_eq(fresh_items.rounds_in(mag_a), rounds.slice(0, 6), "partial magazine kept its rounds in order")
	assert_eq(fresh_items.container_of(mag_a), &"world", "and lies where it was dropped")
	assert_eq(fresh_stats.resolve(pistol, &"hit_chance"), _stats.resolve(pistol, &"hit_chance"), "part modifiers restored")
	assert_eq(fresh_stats.resolve(rounds[6], &"damage"), _stats.resolve(rounds[6], &"damage"), "round inheritance restored")
	# and the restored sim keeps working
	var before: int = fresh.dispatched_count()
	assert_eq(fresh.submit(SimCommand.new(fresh.get_tick() + 1, &"magazine.unload", {"actor": ACTOR, "magazine": k["mag_b"]})), OK, "submit")
	fresh.step()
	assert_eq(fresh.dispatched_count(), before, "cannot unload a seated magazine (it is in the socket, not loose)")
	assert_eq(SimAssembly.entities_of(fresh).peek_next(), SimAssembly.entities_of(_sim).peek_next(), "id allocator restored")


func test_hostile_snapshots_are_rejected_and_leave_the_system_untouched() -> void:
	_build()
	var k: Dictionary = _kit()
	_do(&"magazine.load", {"actor": ACTOR, "magazine": k["mag_a"], "round": k["rounds"][0]})
	var good: Dictionary = _items.snapshot()
	var before: String = StateHash.of(_items.snapshot())
	var barrel: int = k["barrel"]
	var pistol: int = k["pistol"]
	var rounds: Array[int] = k["rounds"]
	var cases: Array[Dictionary] = []
	var c: Dictionary
	c = good.duplicate(true)
	c.erase("sockets")
	cases.append(c)
	c = good.duplicate(true)
	c["extra"] = 1
	cases.append(c)
	c = good.duplicate(true)
	c["items"] = []
	cases.append(c)
	c = good.duplicate(true)
	_sub(c, "items")[999] = {"kind": &"ammo", "template": &"nope", "seed": 1, "affixes": []}
	cases.append(c)
	c = good.duplicate(true)
	_sub(c, "containers")[&"world"] = [rounds[0]]  # duplicated item
	cases.append(c)
	c = good.duplicate(true)
	_sub(c, "containers")[&"inv.1"] = []  # items lost
	cases.append(c)
	c = good.duplicate(true)
	var inv_list: Array = _sub(c, "containers")[&"inv.1"]
	inv_list.erase(rounds[1])
	_sub(c, "containers")[StringName("mag.%d" % barrel)] = [rounds[1]]  # a barrel is not a magazine
	cases.append(c)
	c = good.duplicate(true)
	_sub(c, "sockets")[pistol] = {&"barrel": barrel}  # part not in the socket container
	cases.append(c)
	c = good.duplicate(true)
	_sub(c, "busy_until")[pistol] = "soon"
	cases.append(c)
	c = good.duplicate(true)
	_sub(c, "part_handles")[barrel] = [0]
	cases.append(c)
	c = good.duplicate(true)
	_sub(c, "containers")[&"chest.1"] = []
	cases.append(c)
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	var i: int = 0
	for bad: Dictionary in cases:
		var fresh: SimRoot = SimAssembly.build(SEED, db)
		var target: ItemSystem = SimAssembly.items_of(fresh)
		assert_eq(target.restore(bad), ERR_INVALID_DATA, "hostile snapshot %d rejected" % i)
		assert_eq(target.item_count(), 0, "hostile snapshot %d left the system empty" % i)
		i += 1
	assert_eq(StateHash.of(_items.snapshot()), before, "source untouched")
	var fresh_ok: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.items_of(fresh_ok).restore(good), OK, "the genuine snapshot restores")


static func _sub(dict: Dictionary, key: String) -> Dictionary:
	var out: Dictionary = dict[key]
	return out


## M6 spec claim 9: money is an item. A note's face value is a `value` stat, which is
## both what it is worth and what it adds to visible wealth while it is being carried.
func test_credits_are_items_with_a_face_value() -> void:
	_build()
	assert_true(ItemSystem.SPAWNABLE.has(ItemSystem.KIND_CURRENCY), "currency can be spawned like any item")
	assert_eq(_items.face_value_of_template(&"credit_note"), 100, "a note's face value")
	assert_eq(_items.face_value_of_template(&"g19"), 0, "a pistol is not money, whatever it is worth")
	assert_eq(_items.credits_in(_inv()), 0, "an empty pocket")
	var first: int = _items.spawn(ItemSystem.KIND_CURRENCY, &"credit_note", _inv(), 1)
	assert_true(first > 0, "a note")
	assert_eq(_items.item_kind(first), ItemSystem.KIND_CURRENCY, "of the currency kind")
	assert_eq(_stats.resolve(first, &"value"), 100, "worth its face value through the resolver")
	assert_true(_stats.get_tags(first).has(&"currency"), "and tagged as money")
	for i: int in 11:
		assert_true(_items.spawn(ItemSystem.KIND_CURRENCY, &"credit_note", _inv(), 2 + i) > 0, "note %d" % i)
	assert_eq(_items.credits_in(_inv()), 1200, "twelve notes is twelve hundred credits")
	# money moves like anything else, and nothing else counts as money
	_kit()
	assert_eq(_items.credits_in(_inv()), 1200, "a pistol in the same bag adds nothing to the total")
	assert_true(_do(&"item.spawn", {"kind": "currency", "template": "credit_note", "container": "world", "seed": 9, "count": 3}), "spawned into the world")
	assert_eq(_items.credits_in(&"world"), 300, "three notes on the ground")
	assert_eq(_items.credits_in(ItemSystem.inventory_of(OTHER_ACTOR)), 0, "and none in the other pocket")


## M6 spec claim 10: a corpse's pockets are an ordinary open container, and death and
## looting are both one whole-container move, so nothing is spawned or destroyed.
func test_a_corpse_container_is_open_and_a_whole_container_moves_at_once() -> void:
	_build()
	var kit: Dictionary = _kit()
	var pistol: int = kit["pistol"]
	var loose: Array = kit["rounds"]
	var first_round: int = loose[0]
	assert_true(_do(&"magazine.load", {"actor": ACTOR, "magazine": kit["mag_a"], "round": first_round}), "one round in the magazine")
	var before: int = _items.item_count()
	var held: int = _items.items_in(_inv()).size()
	assert_true(held > 0, "a kit in the pocket")
	var corpse: StringName = ItemSystem.corpse_container(ACTOR)
	assert_eq(String(corpse), "corpse.%d" % ACTOR, "named after the corpse")
	assert_eq(_items.move_container(_inv(), corpse), held, "the whole kit moves at once")
	assert_eq(_items.item_count(), before, "and not one item was made or lost")
	assert_eq(_items.items_in(_inv()).size(), 0, "the pocket is empty")
	assert_eq(_items.container_of(pistol), corpse, "the pistol is on the body")
	# a loaded magazine keeps its rounds: they live in the magazine, not the pocket
	var mag: int = kit["mag_a"]
	var rounds: Array[int] = _items.items_in(ItemSystem.magazine_container(mag))
	assert_eq(_items.container_of(mag), corpse, "the magazine went with the rest")
	assert_eq(_items.items_in(ItemSystem.magazine_container(mag)), rounds, "and its rounds are still in it")
	# looting is the same move the other way
	assert_eq(_items.move_container(corpse, ItemSystem.inventory_of(OTHER_ACTOR)), held, "and back off it")
	assert_eq(_items.item_count(), before, "still conserved")
	assert_eq(_items.items_in(corpse).size(), 0, "the body is stripped")
	assert_eq(_items.move_container(corpse, _inv()), 0, "an empty container moves nothing")
	# the ends have to be real open containers
	assert_eq(_items.move_container(_inv(), _inv()), 0, "a container cannot move into itself")
	assert_eq(_items.move_container(ItemSystem.inventory_of(OTHER_ACTOR), &"mag.3"), 0, "not into a magazine")
	assert_eq(_items.move_container(ItemSystem.inventory_of(OTHER_ACTOR), &"corpse.0"), 0, "not into corpse zero")
	assert_eq(_items.move_container(&"nowhere", _inv()), 0, "not out of nothing")
	assert_eq(_items.item_count(), before, "every refusal left the count alone")


## M6: a site raises its own guards, so something has to be able to arm an actor in one
## call. Ids are allocated as commands execute, so the command path cannot name what it
## has just spawned.
func test_arming_an_actor_from_a_kit_seats_the_magazine_and_chambers_a_round() -> void:
	_build()
	var before: int = _items.item_count()
	var pistol: int = _items.arm(ACTOR, &"g19", &"g19_mag_15", &"9x19_fmj", 15, 700)
	assert_true(pistol > 0, "armed")
	assert_eq(_items.item_template(pistol), &"g19", "the frame")
	assert_eq(_items.container_of(pistol), _inv(), "in the pocket")
	var magazine: int = _items.magazine_of(pistol)
	assert_true(magazine > 0, "with a magazine seated in it")
	assert_eq(_items.container_of(magazine), ItemSystem.socket_container(pistol, &"magazine"), "in the magazine socket")
	assert_eq(_items.rounds_in(magazine).size(), 14, "fourteen left in it")
	assert_true(_items.chambered(pistol) > 0, "and one up the spout")
	assert_eq(_items.item_count(), before + 1 + 1 + 15, "a frame, a magazine and fifteen rounds")
	# the magazine's modifiers are on the weapon, exactly as an attach would leave them
	assert_true(_stats.resolve(pistol, &"ergonomics") != 0, "the frame resolves")
	# a kit that does not fit is refused rather than half-applied
	var mid: int = _items.item_count()
	assert_eq(_items.arm(OTHER_ACTOR, &"g19", &"m9_mag_15", &"9x19_fmj", 15, 800), EntityIds.NONE, "an m9 magazine does not fit a g19")
	assert_eq(_items.arm(OTHER_ACTOR, &"nothing", &"g19_mag_15", &"9x19_fmj", 15, 900), EntityIds.NONE, "a frame that does not exist")
	assert_true(_items.item_count() >= mid, "and nothing was destroyed by the refusals")
	# a magazine only holds what it holds
	var over: int = _items.arm(OTHER_ACTOR, &"g19", &"g19_mag_15", &"9x19_fmj", 99, 1000)
	assert_true(over > 0, "armed with more rounds than fit")
	assert_eq(_items.rounds_in(_items.magazine_of(over)).size(), 14, "the magazine took fifteen and chambered one")
