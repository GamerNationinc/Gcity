extends GcityTest

## M6 spec claim 17, city softening (ADR-007 C): when a player dies where the district's
## law_index is at or above city_recovery.min_law_index, each item in the body comes
## back to the player's base container with probability law_index / 1000, drawn from
## sim.rng() in container order; each returned item costs city_recovery.fee credits and
## the return stops at the first item the wallet cannot pay for. The rest stays.

const SEED: int = 20261170
const M: int = 1000
const DOCKS: Vector3i = Vector3i(700 * M, 0, 700 * M)

var _sim: SimRoot
var _actors: ActorSystem
var _items: ItemSystem
var _wallet: WalletSystem
var _player: int = 0


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_wallet = SimAssembly.wallet_of(_sim)
	var x0: int = DOCKS.x
	var z0: int = DOCKS.z
	assert_eq(SimAssembly.land_of(_sim).add_parcel(&"zz_docks", &"docklands", &"zz_corp", [[x0, z0], [x0 + 10000, z0], [x0 + 10000, z0 + 10000], [x0, z0 + 10000]], -1000, 3000), OK, "a docklands parcel (law 500)")
	_player = _actors.spawn(&"arcade", 0)
	for payload: Dictionary in [{"actor": _player, "owner": "player"}]:
		_sim.submit(SimCommand.new(1, &"land.identify", payload))
	_sim.submit(SimCommand.new(1, &"land.transfer", {"parcel": "starter_plot", "owner": "player"}))
	_sim.step()
	assert_eq(_wallet.register_source(&"zz_test"), OK, "a test source")


## Twelve rounds in the inventory; dies at `at`. Returns the items in container order.
func _die_at(at: Vector3i) -> Array[int]:
	var inv: StringName = ItemSystem.inventory_of(_player)
	for i: int in 12:
		_items.spawn(&"ammo", &"9x19_fmj", inv, i + 1)
	var order: Array[int] = _items.items_in(inv)
	_actors.set_position(_player, at)
	_actors.damage_node(_player, &"body", 100000)
	return order


## The items a fresh copy of the sim's generator would send home with `credits`.
func _expected(order: Array[int], law: int, credits: int, fee: int) -> Array[int]:
	var probe := RandomNumberGenerator.new()
	probe.seed = _sim.rng().seed
	probe.state = _sim.rng().state
	var out: Array[int] = []
	var left: int = credits
	for item: int in order:
		if probe.randi_range(0, 999) >= law:
			continue
		if left < fee:
			break
		left -= fee
		out.append(item)
	return out


func test_nothing_comes_home_below_the_law_threshold() -> void:
	_setup()
	assert_true(_wallet.credit(_player, 10000, &"zz_test"), "credits")
	var state: int = _sim.rng().state
	_die_at(Vector3i(1500, 0, 1500))  # the starter plot: law 250
	assert_eq(_items.items_in(ItemSystem.base_of(_player)), [] as Array[int], "nothing home")
	assert_eq(_sim.rng().state, state, "and no draws")
	assert_eq(_wallet.balance_of(_player), 10000, "no fee")


func test_items_come_home_by_seeded_draw_for_a_fee_each() -> void:
	_setup()
	assert_true(_wallet.credit(_player, 10000, &"zz_test"), "credits")
	var inv: StringName = ItemSystem.inventory_of(_player)
	for i: int in 12:
		_items.spawn(&"ammo", &"9x19_fmj", inv, i + 1)
	var order: Array[int] = _items.items_in(inv)
	var expected: Array[int] = _expected(order, 500, 10000, 100)
	assert_true(expected.size() > 0 and expected.size() < 12, "the seed sends some home and leaves some (%d)" % expected.size())
	_actors.set_position(_player, DOCKS + Vector3i(2500, 0, 2500))
	_actors.damage_node(_player, &"body", 100000)
	assert_eq(_items.items_in(ItemSystem.base_of(_player)), expected, "exactly the drawn items, in order")
	assert_eq(_wallet.balance_of(_player), 10000 - 100 * expected.size(), "100 credits each")
	var corpse: StringName = SimAssembly.corpses_of(_sim).corpse_of(_player)
	assert_eq(_items.items_in(corpse).size(), 12 - expected.size(), "the rest stays in the body")


func test_the_return_stops_at_the_first_item_the_wallet_cannot_pay_for() -> void:
	_setup()
	assert_true(_wallet.credit(_player, 250, &"zz_test"), "enough for two")
	var inv: StringName = ItemSystem.inventory_of(_player)
	for i: int in 12:
		_items.spawn(&"ammo", &"9x19_fmj", inv, i + 1)
	var order: Array[int] = _items.items_in(inv)
	var expected: Array[int] = _expected(order, 500, 250, 100)
	assert_eq(expected.size(), 2, "two paid for")
	_actors.set_position(_player, DOCKS + Vector3i(2500, 0, 2500))
	_actors.damage_node(_player, &"body", 100000)
	assert_eq(_items.items_in(ItemSystem.base_of(_player)), expected, "two home")
	assert_eq(_wallet.balance_of(_player), 50, "never below zero")


func test_a_guard_has_no_base_to_come_home_to() -> void:
	_setup()
	var guard: int = SimAssembly.perception_of(_sim).spawn(&"guard_sim", BuildSystem.cell_of(DOCKS + Vector3i(2500, 0, 2500)), 0, 1, "")
	_items.spawn(&"ammo", &"9x19_fmj", ItemSystem.inventory_of(guard), 1)
	var state: int = _sim.rng().state
	_actors.damage_node(guard, &"body", 1_000_000)
	assert_eq(_sim.rng().state, state, "no draws for the homeless")
	assert_eq(_items.items_in(SimAssembly.corpses_of(_sim).corpse_of(guard)).size(), 1, "the round stays in the body")
