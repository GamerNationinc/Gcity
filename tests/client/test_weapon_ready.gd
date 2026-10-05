extends GcityTest

## CEOGG's 2026-10-05 sandbox run: a g19, an empty magazine and loose rounds in the
## pockets, and no way found to load and fire. One press must leave the gun in hand,
## its magazine filled from the loose rounds and a round chambered.

const SEED: int = 20261005

var _sim: SimRoot
var _actors: ActorSystem
var _items: ItemSystem
var _player: int


func _build() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	_sim = SimAssembly.build(SEED, db)
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_player = _actors.spawn(&"arcade", 0)


func _run(plan: Dictionary) -> void:
	var commands: Array = plan["commands"]
	for command: Array in commands:
		var kind: StringName = command[0]
		var payload: Dictionary = command[1]
		assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	var before: int = _sim.rejected_count()
	_sim.step()
	assert_eq(_sim.rejected_count(), before, "the sim takes every command")


func test_one_press_fills_a_magazine_swaps_it_in_and_chambers_a_round() -> void:
	_build()
	var inv: StringName = ItemSystem.inventory_of(_player)
	var pistol: int = _items.spawn(&"weapon_frame", &"g19", inv, 1)
	var mag: int = _items.spawn(&"weapon_part", &"g19_mag_15", inv, 2)
	for i: int in 15:
		_items.spawn(&"ammo", &"9x19_fmj", inv, 100 + i)
	assert_eq(WeaponReady.first_firearm(_items, _player), pistol, "the g19 is the firearm carried")
	var plan: Dictionary = WeaponReady.plan(_sim, _player, pistol)
	_run(plan)
	assert_eq(_items.magazine_of(pistol), mag, "the magazine is in the gun")
	assert_ne(_items.chambered(pistol), EntityIds.NONE, "a round is chambered")
	assert_eq(_items.rounds_in(mag).size(), 14, "the other 14 are in the magazine")
	var said: String = plan["say"]
	assert_true(said.contains("chambered"), "it says so (%s)" % said)


func test_it_says_why_when_nothing_fits() -> void:
	_build()
	var inv: StringName = ItemSystem.inventory_of(_player)
	var pistol: int = _items.spawn(&"weapon_frame", &"g19", inv, 1)
	var none: Dictionary = WeaponReady.plan(_sim, _player, pistol)
	var commands: Array = none["commands"]
	var said: String = none["say"]
	assert_eq(commands.size(), 0, "no magazine: nothing sent")
	assert_true(said.contains("no magazine"), "and it says so (%s)" % said)
	_items.spawn(&"weapon_part", &"g19_mag_15", inv, 2)
	var empty: Dictionary = WeaponReady.plan(_sim, _player, pistol)
	var empty_commands: Array = empty["commands"]
	var empty_said: String = empty["say"]
	assert_eq(empty_commands.size(), 0, "no rounds: nothing sent")
	assert_true(empty_said.contains("no 9x19 rounds"), "and it says so (%s)" % empty_said)


func test_an_m9_magazine_is_not_put_in_a_g19() -> void:
	_build()
	var inv: StringName = ItemSystem.inventory_of(_player)
	var pistol: int = _items.spawn(&"weapon_frame", &"g19", inv, 1)
	_items.spawn(&"weapon_part", &"m9_mag_15", inv, 2)
	_items.spawn(&"ammo", &"9x19_fmj", inv, 3)
	var plan: Dictionary = WeaponReady.plan(_sim, _player, pistol)
	var commands: Array = plan["commands"]
	assert_eq(commands.size(), 0, "the m9's magazine does not fit")


## CEOGG's 18:18 sandbox run: four pulls during a reload were refused with nothing said.
func test_a_pull_during_the_reload_says_so() -> void:
	_build()
	var inv: StringName = ItemSystem.inventory_of(_player)
	var pistol: int = _items.spawn(&"weapon_frame", &"g19", inv, 1)
	_items.spawn(&"weapon_part", &"g19_mag_15", inv, 2)
	for i: int in 15:
		_items.spawn(&"ammo", &"9x19_fmj", inv, 100 + i)
	assert_eq(WeaponReady.busy_reason(_items, pistol, _sim.get_tick(), false), "", "a gun at rest is not busy")
	_run(WeaponReady.plan(_sim, _player, pistol))
	var said: String = WeaponReady.busy_reason(_items, pistol, _sim.get_tick() + 1, true)
	assert_true(said.contains("reloading") and said.contains("s"), "mid-reload it says so and how long (%s)" % said)
	_sim.step_n(90)
	assert_eq(WeaponReady.busy_reason(_items, pistol, _sim.get_tick() + 1, true), "", "and after the reload, nothing")
