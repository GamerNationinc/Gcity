extends GcityTest

## M6 spec claims 14–16, the items' side: bodies, impounds and site stores are
## holding containers (`corpse.<id>`, `impound.<id>`, `store.<id>`). A top-level item
## moves between an inventory, the world and a holding container whole: a pistol
## keeps its parts and its magazine, the magazine its rounds, and no id is made or
## lost. An emptied holding container is gone.

const SEED: int = 20261210

var _sim: SimRoot
var _items: ItemSystem
var _player: int = 0
var _pistol: int = 0
var _mag: int = 0


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	_items = SimAssembly.items_of(_sim)
	_player = SimAssembly.actors_of(_sim).spawn(&"arcade", 0)
	var inv: String = String(ItemSystem.inventory_of(_player))
	var at: int = _sim.get_tick() + 1
	for c: Array in [["weapon_frame", "g19", 1, 1], ["weapon_part", "g19_mag_15", 2, 1], ["weapon_part", "g19_barrel", 3, 1], ["ammo", "9x19_fmj", 10, 5]]:
		_sim.submit(SimCommand.new(at, &"item.spawn", {"kind": c[0], "template": c[1], "container": inv, "seed": c[2], "count": c[3]}))
	_sim.step()
	var held: Array[int] = _items.items_in(ItemSystem.inventory_of(_player))
	_pistol = held[0]
	_mag = held[1]
	var barrel: int = held[2]
	at = _sim.get_tick() + 1
	_sim.submit(SimCommand.new(at, &"weapon.attach", {"actor": _player, "weapon": _pistol, "part": barrel}))
	for i: int in 5:
		_sim.submit(SimCommand.new(at, &"magazine.load", {"actor": _player, "magazine": _mag, "round": held[3 + i]}))
	_sim.step()
	_sim.submit(SimCommand.new(_sim.get_tick() + 1, &"weapon.reload_tactical", {"actor": _player, "weapon": _pistol, "magazine": _mag}))
	_sim.step_n(100)
	assert_eq(_sim.rejected_count(), 0, "a loaded pistol with a barrel")
	assert_eq(_items.magazine_of(_pistol), _mag, "the magazine is in it")


func _all_ids() -> Array[int]:
	var snap: Dictionary = _items.snapshot()
	var items: Dictionary = snap["items"]
	var out: Array[int] = []
	for k: Variant in items:
		var id: int = k
		out.append(id)
	out.sort()
	return out


func test_a_loaded_pistol_moves_to_a_body_whole_and_back() -> void:
	_setup()
	var before: Array[int] = _all_ids()
	var rounds: int = _items.rounds_in(_mag).size()
	var body: StringName = ItemSystem.holding_container(&"corpse", 77)
	assert_eq(body, &"corpse.77", "named by kind and id")
	assert_true(_items.move_item(_pistol, body), "the pistol goes to the body")
	assert_eq(_items.container_of(_pistol), body, "it is there")
	assert_eq(_items.magazine_of(_pistol), _mag, "with its magazine")
	assert_eq(_items.rounds_in(_mag).size(), rounds, "and every round in it")
	assert_false(_items.items_in(ItemSystem.inventory_of(_player)).has(_pistol), "not in the inventory")
	assert_eq(_all_ids(), before, "no id made or lost")
	var db: ContentDb = _sim.get_system(&"content")
	var loaded: SimRoot = SimAssembly.load_save(SaveFile.parse(SaveFile.serialize(_sim, db.digest())), db)
	assert_true(loaded != null, "a save with a body in it loads")
	assert_eq(loaded.state_hash(), _sim.state_hash(), "to the same state")
	assert_true(_items.move_item(_pistol, ItemSystem.inventory_of(_player)), "and back")
	assert_false(_items.items_in(body).size() > 0, "the body is empty")
	var containers: Dictionary = _items.snapshot()["containers"]
	assert_false(containers.has(body), "and gone")


func test_only_top_level_items_move_and_only_to_known_holders() -> void:
	_setup()
	var round: int = _items.rounds_in(_mag)[0]
	assert_false(_items.move_item(round, &"corpse.5"), "a round in a magazine does not leave it on its own")
	assert_false(_items.move_item(_mag, &"corpse.5"), "nor a magazine in a pistol")
	for bad: StringName in [&"vault.5", &"corpse.x", &"corpse.0", &"corpse.-3", &"corpse.05", &"corpse", &"mag.5"]:
		assert_false(_items.move_item(_pistol, bad), "no such holder: %s" % bad)
	assert_false(_items.move_item(999999, &"corpse.5"), "no such item")
	for prefix: StringName in [&"corpse", &"impound", &"store"]:
		assert_true(_items.move_item(_pistol, ItemSystem.holding_container(prefix, 9)), "a %s holds" % prefix)
	assert_true(_items.move_item(_pistol, ItemSystem.WORLD), "and the world")


func test_a_store_can_be_stocked_by_spawning_into_it() -> void:
	_setup()
	var store: StringName = ItemSystem.holding_container(&"store", 3)
	var card: int = _items.spawn(ItemSystem.KIND_GOODS, &"data_drive", store, 4)
	assert_true(card > 0, "spawned into the store")
	assert_eq(_items.items_in(store), [card] as Array[int], "it holds it")
	_sim.submit(SimCommand.new(_sim.get_tick() + 1, &"item.spawn", {"kind": "goods", "template": "data_drive", "container": "store.3", "seed": 5, "count": 1}))
	_sim.step()
	assert_eq(_items.items_in(store).size(), 1, "but the spawn command still only fills inventories and the world")
