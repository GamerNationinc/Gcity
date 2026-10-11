extends GcityTest

## M6 spec claim 15: credits are a per-actor integer balance in the wallet system,
## changed only by registered sources and never negative. Property: over 10 000
## generated changes the balance equals the sum of the accepted changes, is never
## negative, and every refused change left it as it was.

const SEED: int = 20261041
const SEED_PROPERTY: int = 20261042
const PROPERTY_CASES: int = 10_000

var _sim: SimRoot
var _wallet: WalletSystem
var _player: int = 0
var _changes: Array[Dictionary] = []


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_wallet = SimAssembly.wallet_of(_sim)
	_player = SimAssembly.actors_of(_sim).spawn(&"arcade", 0)
	var sink: Array[Dictionary] = []
	_changes = sink
	SimAssembly.combat_of(_sim).events().subscribe(WalletSystem.EVENT_CHANGED, func(p: Dictionary) -> void: sink.append(p))
	assert_eq(_wallet.register_source(&"zz_test"), OK, "a test source")


func test_only_registered_sources_change_a_balance_and_never_below_zero() -> void:
	_setup()
	assert_eq(_wallet.balance_of(_player), 0, "empty to start")
	assert_false(_wallet.credit(_player, 100, &"zz_nothing"), "an unregistered source is refused")
	assert_true(_wallet.credit(_player, 100, &"zz_test"), "a registered one is not")
	assert_eq(_wallet.balance_of(_player), 100, "100")
	assert_false(_wallet.debit(_player, 101, &"zz_test"), "no more than is there")
	assert_eq(_wallet.balance_of(_player), 100, "unchanged")
	assert_true(_wallet.debit(_player, 100, &"zz_test"), "all of it")
	assert_eq(_wallet.balance_of(_player), 0, "back to 0")
	assert_false(_wallet.credit(_player, 0, &"zz_test"), "no zero credit")
	assert_false(_wallet.credit(_player, -5, &"zz_test"), "no negative credit")
	assert_false(_wallet.credit(999, 5, &"zz_test"), "no unknown actor")
	assert_eq(_changes, [{"actor": _player, "amount": 100, "source": &"zz_test", "balance": 100}, {"actor": _player, "amount": -100, "source": &"zz_test", "balance": 0}], "two wallet.changed")
	assert_eq(_wallet.register_source(&"zz_test"), ERR_ALREADY_EXISTS, "a source registers once")


func test_balances_survive_the_restore_and_bad_ones_are_refused() -> void:
	_setup()
	assert_true(_wallet.credit(_player, 750, &"zz_test"), "credited")
	var snap: Dictionary = _wallet.snapshot()
	assert_eq(_wallet.restore(snap.duplicate(true)), OK, "restores")
	assert_eq(_wallet.balance_of(_player), 750, "kept")
	for bad: Dictionary in [{"balances": {_player: -1}}, {"balances": {_player: 0}}, {"balances": {999: 5}}, {"balances": {_player: "5"}}, {}]:
		assert_eq(_wallet.restore(bad), ERR_INVALID_DATA, "refused: %s" % str(bad))
	assert_eq(_wallet.balance_of(_player), 750, "and nothing changed")


func test_property_the_balance_is_the_sum_of_accepted_changes() -> void:
	_setup()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	var expected: int = 0
	var wrong: int = 0
	var refused: int = 0
	for i: int in PROPERTY_CASES:
		var amount: int = rng.randi_range(-20, 400)
		var ok: bool
		if rng.randi_range(0, 1) == 0:
			ok = _wallet.credit(_player, amount, &"zz_test")
			if ok:
				expected += amount
		else:
			ok = _wallet.debit(_player, amount, &"zz_test")
			if ok:
				expected -= amount
		if not ok:
			refused += 1
		if _wallet.balance_of(_player) != expected or _wallet.balance_of(_player) < 0:
			wrong += 1
	assert_eq(wrong, 0, "always the sum of accepted changes, never negative")
	assert_true(refused > 500 and refused < 9500, "both outcomes covered (%d refused)" % refused)
