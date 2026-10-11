extends GcityTest

## M6 spec claim 17 / ADR-007 verification, the item conservation property: over
## 10 000 generated streams of spawn, transfer, death (with the city's recovery),
## respawn, take, drop and deliver, every item id lies in exactly one container after
## every step, and the set of ids changes only by spawning (delivery hands an item to
## a fixer's container; it is still there). Streams run back to back on one sim (a
## fresh sim per stream would cost minutes): each is 1 to 4 random operations by random
## actors on random items and places, so stream after stream starts from whatever the
## last one left, deaths, bodies, piles and empty wallets included. Spawning pauses
## while POPULATION items exist, so the check after every step stays cheap.

const SEED: int = 20261180
const SEED_PROPERTY: int = 20261181
const STREAMS: int = 10_000
const M: int = 1000
## Spawning stops while this many items exist, so a check stays cheap
const POPULATION: int = 300

var _sim: SimRoot
var _actors: ActorSystem
var _items: ItemSystem
var _corpses: CorpseSystem
var _people: Array[int] = []
var _expected: Dictionary = {}


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_corpses = SimAssembly.corpses_of(_sim)
	# a docklands lot next to the starter plot: deaths there call on the city
	assert_eq(SimAssembly.land_of(_sim).add_parcel(&"zz_docks", &"docklands", &"zz_corp", [[0, -4000], [6000, -4000], [6000, 0], [0, 0]], -1000, 3000), OK, "docks")
	var wallet: WalletSystem = SimAssembly.wallet_of(_sim)
	assert_eq(wallet.register_source(&"zz_test"), OK, "a source")
	for i: int in 3:
		var a: int = _actors.spawn(&"arcade", 0)
		_people.append(a)
		wallet.credit(a, 2000, &"zz_test")
	_sim.submit(SimCommand.new(1, &"land.identify", {"actor": _people[0], "owner": "player"}))
	_sim.submit(SimCommand.new(1, &"land.transfer", {"parcel": "starter_plot", "owner": "player"}))
	_sim.step()


func _do(kind: StringName, payload: Dictionary) -> void:
	_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload))
	_sim.step()


## Every item in exactly one container, and the ids are exactly the expected set.
func _conserved() -> String:
	var containers: Dictionary = _items.snapshot()["containers"]
	var seen: Dictionary = {}
	for name: Variant in containers:
		var list: Array = containers[name]
		for v: Variant in list:
			if seen.has(v):
				return "item %s in two containers" % str(v)
			seen[v] = name
	var ids: Array[int] = _items.item_ids()
	if seen.size() != ids.size():
		return "%d items but %d placed" % [ids.size(), seen.size()]
	if ids.size() != _expected.size():
		return "%d items but %d spawned" % [ids.size(), _expected.size()]
	for id: int in ids:
		if not _expected.has(id) or not seen.has(id):
			return "item %d appeared from nowhere" % id
	return ""


func _pick(rng: RandomNumberGenerator, list: Array) -> Variant:
	return list[rng.randi_range(0, list.size() - 1)]


func test_property_items_are_conserved_across_death_recovery_and_hands() -> void:
	_setup()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	var templates: Array = [[&"ammo", &"9x19_fmj"], [&"weapon_part", &"g19_mag_15"], [&"weapon_frame", &"g19"], [&"key_item", &"cold_storage_keycard"]]
	var spots: Array[Vector3i] = [Vector3i(1500, 0, 1500), Vector3i(2500, 0, 1500), Vector3i(1500, 0, -1500), Vector3i(2500, 0, -1500)]
	var violations: int = 0
	var kinds: Dictionary = {}
	for stream: int in STREAMS:
		for op: int in rng.randi_range(1, 4):
			var who: int = _pick(rng, _people)
			var roll: int = rng.randi_range(0, 99)
			var kind: String
			if roll < 25 and _items.item_count() < POPULATION:
				kind = "spawn"
				var t: Array = _pick(rng, templates)
				var t_kind: StringName = t[0]
				var t_template: StringName = t[1]
				var id: int = _items.spawn(t_kind, t_template, ItemSystem.inventory_of(who), rng.randi_range(1, 1_000_000))
				if id != EntityIds.NONE:
					_expected[id] = true
			elif roll < 25:
				kind = "full"
			elif roll < 40:
				kind = "move"
				if _actors.is_alive(who):
					var spot: Vector3i = _pick(rng, spots)
					_actors.set_position(who, spot)
			elif roll < 60:
				kind = "take"
				var places: Array[StringName] = _corpses.place_ids()
				if not places.is_empty():
					var place: StringName = _pick(rng, places)
					var held: Array[int] = _items.items_in(place)
					if not held.is_empty():
						_do(CorpseSystem.COMMAND_TAKE, {"actor": who, "from": String(place), "item": _pick(rng, held)})
			elif roll < 75:
				kind = "drop"
				var mine: Array[int] = _items.items_in(ItemSystem.inventory_of(who))
				if not mine.is_empty():
					_do(CorpseSystem.COMMAND_DROP, {"actor": who, "item": _pick(rng, mine)})
			elif roll < 83:
				kind = "die"
				_actors.damage_node(who, &"body", 100000)
			elif roll < 93:
				kind = "respawn"
				_do(ActorSystem.COMMAND_RESPAWN, {"actor": who})
			else:
				kind = "deliver"
				var mine_d: Array[int] = _items.items_in(ItemSystem.inventory_of(who))
				if not mine_d.is_empty():
					var given: int = _pick(rng, mine_d)
					_items.hand_over(who, given, &"marlow")
			var so_far: int = kinds.get(kind, 0)
			kinds[kind] = so_far + 1
			var broken: String = _conserved()
			if not broken.is_empty():
				violations += 1
				if violations <= 3:
					fail("stream %d, %s: %s" % [stream, kind, broken])
	assert_eq(violations, 0, "items conserved over %d streams" % STREAMS)
	assert_true(_corpses.place_ids().size() > 0, "bodies and piles were made (%d places at the end)" % _corpses.place_ids().size())
	assert_true(_items.items_in(ItemSystem.base_of(_people[0])).size() > 0, "the city brought something home")
	for k: String in ["spawn", "take", "drop", "die", "respawn", "deliver"]:
		var n: int = kinds.get(k, 0)
		assert_true(n > 100, "%s exercised (%d)" % [k, n])
