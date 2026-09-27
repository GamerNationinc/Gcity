extends GcityTest

## M6 spec claims 1 and 15 (and ADR-011): bodies and site stores are holders an actor
## takes from, one item at a time, standing beside them. Your own body is always
## yours; anyone else's, or a store, is `loot`: on land that denies it the take still
## happens and is one violation. An emptied body is gone; a store stays. A site
## stocks its stores when it is raised.

const SEED: int = 20261220
const M: int = 1000
const FAR_CELL: Vector3i = Vector3i(500, 0, 500)

var _sim: SimRoot
var _actors: ActorSystem
var _items: ItemSystem
var _loot: LootSystem
var _player: int = 0
var _other: int = 0
var _violations: Array[Dictionary] = []


func _setup(site_origin: Array = [500, 0, 500]) -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	assert_eq(db.add(SiteSystem.KIND_SITE, &"zz_office", {
		"schema_version": 1, "description": "An office with a locker.", "origin": site_origin, "parcels": [],
		"pieces": [], "points": [], "agents": [],
		"containers": [{"name": "locker", "cell": [3, 0, 3], "items": [{"kind": "goods", "template": "data_drive", "count": 2}, {"kind": "tool", "template": "cutter_handheld", "count": 1}]}],
	}), OK, "the office")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_loot = SimAssembly.loot_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_other = _actors.spawn(&"arcade", 0)
	var violations: Array[Dictionary] = []
	_violations = violations
	SimAssembly.combat_of(_sim).events().subscribe(LandSystem.EVENT_VIOLATION, func(p: Dictionary) -> void: violations.append(p))
	_sim.submit(SimCommand.new(_sim.get_tick() + 1, SiteSystem.COMMAND_RAISE, {"site": "zz_office"}))
	_sim.step()
	assert_eq(_sim.rejected_count(), 0, "raised")


static func _floor_of(cell: Vector3i) -> Vector3i:
	return Vector3i(cell.x * M + M / 2, cell.y * M, cell.z * M + M / 2)


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload))
	_sim.step()
	return _sim.dispatched_count() == before + 1


func _locker() -> int:
	return _loot.holder_ids()[0]


func test_the_site_stocks_its_store() -> void:
	_setup()
	var locker: int = _locker()
	assert_eq(_loot.holder_kind(locker), &"store", "a store")
	assert_eq(_loot.holder_name(locker), &"locker", "named")
	assert_eq(_items.items_in(_loot.container_name(locker)).size(), 3, "two drives and a cutter")


func test_taking_from_a_store_is_one_item_at_a_time_from_beside_it() -> void:
	_setup()
	var locker: int = _locker()
	var first: int = _items.items_in(_loot.container_name(locker))[0]
	_actors.set_position(_player, _floor_of(FAR_CELL + Vector3i(8, 0, 8)))
	assert_false(_do(LootSystem.COMMAND_TAKE, {"actor": _player, "container": locker, "item": first}), "not from across the room")
	_actors.set_position(_player, _floor_of(FAR_CELL + Vector3i(3, 0, 4)))
	assert_true(_do(LootSystem.COMMAND_TAKE, {"actor": _player, "container": locker, "item": first}), "from beside it")
	assert_eq(_items.container_of(first), ItemSystem.inventory_of(_player), "into the inventory")
	assert_false(_do(LootSystem.COMMAND_TAKE, {"actor": _player, "container": locker, "item": first}), "not twice")
	for payload: Dictionary in [{}, {"actor": _player, "container": locker}, {"actor": _player, "container": 99999, "item": first},
			{"actor": "1", "container": locker, "item": first}, {"actor": _player, "container": locker, "item": first, "x": 1}]:
		assert_false(_do(LootSystem.COMMAND_TAKE, payload), "refused: %s" % [payload])
	for item: int in _items.items_in(_loot.container_name(locker)):
		assert_true(_do(LootSystem.COMMAND_TAKE, {"actor": _player, "container": locker, "item": item}), "the rest")
	assert_true(_loot.holder_ids().has(locker), "an empty store stays")
	assert_eq(_violations.size(), 0, "badlands: no one's to steal")


func test_your_own_body_is_yours_and_an_emptied_body_is_gone() -> void:
	_setup()
	var pistol: int = _items.spawn(ItemSystem.KIND_FRAME, &"g19", ItemSystem.inventory_of(_player), 1)
	var body: int = _loot.make_corpse(_player, _floor_of(FAR_CELL + Vector3i(1, 0, 1)))
	assert_true(_items.move_item(pistol, _loot.container_name(body)), "the pistol on the body")
	assert_eq(_loot.holder_kind(body), &"corpse", "a body")
	assert_eq(_loot.owner_of(body), _player, "the player's")
	_actors.set_position(_player, _floor_of(FAR_CELL + Vector3i(1, 0, 2)))
	assert_true(_do(LootSystem.COMMAND_TAKE, {"actor": _player, "container": body, "item": pistol}), "taken back")
	assert_false(_loot.holder_ids().has(body), "an emptied body is gone")


func test_someone_elses_body_or_store_on_land_that_denies_loot_is_a_violation() -> void:
	_setup([3, 0, 3])  # the office on the starter plot
	assert_true(SimAssembly.land_of(_sim).transfer(&"starter_plot", "npc.somebody"), "somebody's plot")
	var theirs: int = _items.spawn(ItemSystem.KIND_FRAME, &"g19", ItemSystem.inventory_of(_other), 1)
	var mine: int = _items.spawn(ItemSystem.KIND_FRAME, &"g19", ItemSystem.inventory_of(_player), 2)
	var their_body: int = _loot.make_corpse(_other, _floor_of(Vector3i(2, 0, 2)))
	var my_body: int = _loot.make_corpse(_player, _floor_of(Vector3i(3, 0, 3)))
	_items.move_item(theirs, _loot.container_name(their_body))
	_items.move_item(mine, _loot.container_name(my_body))
	_actors.set_position(_player, _floor_of(Vector3i(3, 0, 2)))
	assert_true(_do(LootSystem.COMMAND_TAKE, {"actor": _player, "container": my_body, "item": mine}), "my own body")
	assert_eq(_violations.size(), 0, "is never a crime")
	assert_true(_do(LootSystem.COMMAND_TAKE, {"actor": _player, "container": their_body, "item": theirs}), "their body: the take proceeds")
	assert_eq(_violations.size(), 1, "one loot violation")
	_actors.set_position(_player, _floor_of(Vector3i(6, 0, 7)))
	var drive: int = _items.items_in(_loot.container_name(_locker()))[0]
	assert_true(_do(LootSystem.COMMAND_TAKE, {"actor": _player, "container": _locker(), "item": drive}), "the locker too")
	assert_eq(_violations.size(), 2, "another")
	var right: StringName = _violations[1]["right"]
	assert_eq(right, &"loot", "of loot")


func test_holders_survive_the_save_and_bad_state_is_refused() -> void:
	_setup()
	var body: int = _loot.make_corpse(_player, _floor_of(FAR_CELL))
	_items.move_item(_items.spawn(ItemSystem.KIND_FRAME, &"g19", ItemSystem.inventory_of(_player), 1), _loot.container_name(body))
	var db: ContentDb = _sim.get_system(&"content")
	var loaded: SimRoot = SimAssembly.load_save(SaveFile.parse(SaveFile.serialize(_sim, db.digest())), db)
	assert_true(loaded != null, "loads")
	assert_eq(loaded.state_hash(), _sim.state_hash(), "the same")
	var fresh: LootSystem = SimAssembly.loot_of(SimAssembly.build(SEED, db))
	for bad: Dictionary in [{}, {"holders": []}, {"holders": {}, "x": 1},
			{"holders": {1: {"kind": "vault", "owner": 0, "site": "", "name": "", "pos": [0, 0, 0]}}},
			{"holders": {"1": {"kind": "store", "owner": 0, "site": "", "name": "", "pos": [0, 0, 0]}}}]:
		assert_eq(fresh.restore(bad), ERR_INVALID_DATA, "rejects %s" % [bad])


func test_assembly_refuses_a_store_it_cannot_stock() -> void:
	for items: Array in [[{"kind": "goods", "template": "nothing", "count": 1}], [{"kind": "nope", "template": "data_drive", "count": 1}], [{"kind": "goods", "template": "data_drive", "count": 0}]]:
		var db := ContentDb.new()
		assert_eq(ContentLoader.load_all(db), OK, "content loads")
		assert_eq(db.add(SiteSystem.KIND_SITE, &"zz_bad", {"schema_version": 1, "description": "x", "origin": [0, 0, 0], "parcels": [],
			"pieces": [], "points": [], "agents": [], "containers": [{"name": "box", "cell": [0, 0, 0], "items": items}]}), OK, "added")
		assert_true(SimAssembly.build(SEED, db) == null, "refused: %s" % [items])
