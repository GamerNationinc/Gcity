extends GcityTest

## M6 spec claim 12 (and ADR-011): a hack is a timed, stationary action gated by the
## device's hardware. Its progress each tick is the device's resolved memory; it stops
## on a step, a shot, a hit or a death; it is heard every second; it yields the
## terminal's item, leaves the terminal logged in until a logout, and is a `loot`
## offence where the right is denied. A spoof is the same work against a spoofable
## sensor and keeps it quiet for the sensor's spoof ticks.
##
## The test site far out in badlands (FAR_CELL = (500, 0, 500)): terminal `core` at
## (2, 0, 0), 100 000 work, 5 m of noise, yielding a data drive, 20 ticks to log out;
## a power monitor on the +x face of (6, 0, 0) with its window and supports.

const SEED: int = 20261190
const M: int = 1000
const FAR_CELL: Vector3i = Vector3i(500, 0, 500)

var _sim: SimRoot
var _actors: ActorSystem
var _items: ItemSystem
var _hacks: HackSystem
var _sensors: SensorSystem
var _player: int = 0
var _device: int = 0
var _module: int = 0
var _completed: Array[Dictionary] = []
var _logouts: Array[Dictionary] = []
var _noises: Array[Dictionary] = []
var _violations: Array[Dictionary] = []


func _site(origin: Array) -> Dictionary:
	return {
		"schema_version": 1, "description": "A lab.", "origin": origin, "parcels": [],
		"pieces": [
			{"piece": "foundation_block", "cell": [6, 0, -1], "facing": ""},
			{"piece": "foundation_block", "cell": [6, 0, 1], "facing": ""},
			{"piece": "window_frame", "cell": [6, 0, 0], "facing": "px"},
		],
		"points": [], "agents": [],
		"sensors": [{"sensor": "power_monitor", "squad": 0, "cell": [6, 0, 0], "facing": "px", "cells": []}],
		"terminals": [{"name": "core", "cell": [2, 0, 0], "hack_work": 100000, "requires": "daemon_coprocessor",
			"noise_mm": 5000, "yields": {"kind": "goods", "template": "data_drive"}, "logout_ticks": 20}],
	}


func _setup(origin: Array = [500, 0, 500], with_module: bool = true) -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	assert_eq(db.add(SiteSystem.KIND_SITE, &"zz_lab", _site(origin)), OK, "the lab")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_hacks = SimAssembly.hacks_of(_sim)
	_sensors = SimAssembly.sensors_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	var inv: StringName = ItemSystem.inventory_of(_player)
	_device = _items.spawn(ItemSystem.KIND_DEVICE_FRAME, &"handset", inv, 1)
	_module = _items.spawn(ItemSystem.KIND_DEVICE_MODULE, &"daemon_coprocessor", inv, 2)
	var completed: Array[Dictionary] = []
	var logouts: Array[Dictionary] = []
	var noises: Array[Dictionary] = []
	var violations: Array[Dictionary] = []
	_completed = completed
	_logouts = logouts
	_noises = noises
	_violations = violations
	var events: EventBus = SimAssembly.combat_of(_sim).events()
	events.subscribe(HackSystem.EVENT_COMPLETED, func(p: Dictionary) -> void: completed.append(p))
	events.subscribe(HackSystem.EVENT_LOGOUT, func(p: Dictionary) -> void: logouts.append(p))
	events.subscribe(BreachSystem.EVENT_NOISE, func(p: Dictionary) -> void: noises.append(p))
	events.subscribe(LandSystem.EVENT_VIOLATION, func(p: Dictionary) -> void: violations.append(p))
	var ox: int = origin[0]
	var oy: int = origin[1]
	var oz: int = origin[2]
	var o: Vector3i = Vector3i(ox, oy, oz)
	var at: int = _sim.get_tick() + 1
	_sim.submit(SimCommand.new(at, SiteSystem.COMMAND_RAISE, {"site": "zz_lab"}))
	if with_module:
		_sim.submit(SimCommand.new(at, &"item.attach", {"actor": _player, "weapon": _device, "part": _module}))
	_sim.submit(SimCommand.new(at, &"actor.equip_device", {"actor": _player, "device": _device}))
	_sim.step()
	assert_eq(_sim.rejected_count(), 0, "raised and equipped")
	_actors.set_position(_player, _floor_of(o + Vector3i(2, 0, 1)))


static func _floor_of(cell: Vector3i) -> Vector3i:
	return Vector3i(cell.x * M + M / 2, cell.y * M, cell.z * M + M / 2)


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


func _core() -> int:
	return _hacks.terminal_ids()[0]


func test_a_hack_takes_its_work_over_the_device_memory_and_yields_the_drive() -> void:
	_setup()
	var core: int = _core()
	assert_eq(_hacks.terminal_name(core), &"core", "the terminal is placed and named")
	assert_true(_do(HackSystem.COMMAND_START, {"actor": _player, "terminal": core}), "the hack starts")
	assert_eq(_hacks.progress_of(_player), [2000, 100000] as Array[int], "2 000 work a tick: the handset's memory and the coprocessor's")
	_sim.step_n(48)
	assert_eq(_completed.size(), 0, "a tick short, still working")
	_sim.step()
	assert_eq(_completed.size(), 1, "done in 50 ticks")
	var ev: Dictionary = _completed[0]
	var actor: int = ev["actor"]
	var terminal: int = ev["terminal"]
	var name: StringName = ev["name"]
	assert_eq(actor, _player, "the player's hack")
	assert_eq(terminal, core, "of the core")
	assert_eq(name, &"core", "named for the counters")
	var drives: int = 0
	for item: int in _items.items_in(ItemSystem.inventory_of(_player)):
		if _items.item_template(item) == &"data_drive":
			drives += 1
	assert_eq(drives, 1, "the drive is in the inventory")
	assert_true(_hacks.is_logged_in(core), "the terminal is left logged in")
	assert_eq(_noises.size(), 2, "heard at the start and a second in")
	var range_mm: int = _noises[0]["range_mm"]
	assert_eq(range_mm, 5000, "at the terminal's noise")
	assert_false(_do(HackSystem.COMMAND_START, {"actor": _player, "terminal": core}), "a hacked terminal is not hacked twice")
	assert_eq(_violations.size(), 0, "badlands: nothing to steal from")


func test_logging_out_takes_its_ticks_and_clears_the_trace() -> void:
	_setup()
	var core: int = _core()
	assert_false(_do(HackSystem.COMMAND_LOGOUT, {"actor": _player, "terminal": core}), "nothing to log out of yet")
	_do(HackSystem.COMMAND_START, {"actor": _player, "terminal": core})
	_sim.step_n(60)
	assert_true(_hacks.is_logged_in(core), "logged in")
	var stranger: int = _actors.spawn(&"arcade", 0)
	_actors.set_position(stranger, _actors.position_of(_player))
	assert_false(_do(HackSystem.COMMAND_LOGOUT, {"actor": stranger, "terminal": core}), "only who logged in logs out")
	assert_true(_do(HackSystem.COMMAND_LOGOUT, {"actor": _player, "terminal": core}), "the logout starts")
	_sim.step_n(18)
	assert_true(_hacks.is_logged_in(core), "a tick short")
	_sim.step()
	assert_false(_hacks.is_logged_in(core), "logged out")
	assert_eq(_logouts.size(), 1, "one hack.logout")


func test_a_step_a_shot_a_hit_or_a_death_stops_the_hack() -> void:
	_setup()
	var core: int = _core()
	var events: EventBus = SimAssembly.combat_of(_sim).events()
	var stops: Array[Callable] = [
		func() -> void: _actors.set_position(_player, _actors.position_of(_player) + Vector3i(0, 0, 100)),
		func() -> void: events.emit(CombatSystem.EVENT_FIRE, {"shooter": _player, "weapon": 0, "target": 0, "round": 0, "tags": [] as Array}),
		func() -> void: events.emit(CombatSystem.EVENT_HIT, {"shooter": 0, "weapon": 0, "target": _player, "node": &"body", "damage": 0, "range_m": 0, "tags": [] as Array, "killed": false}),
	]
	for stop: Callable in stops:
		assert_true(_do(HackSystem.COMMAND_START, {"actor": _player, "terminal": core}), "started")
		_sim.step_n(10)
		stop.call()
		_sim.step()
		assert_false(_hacks.is_hacking(_player), "stopped")
		_actors.set_position(_player, _floor_of(FAR_CELL + Vector3i(2, 0, 1)))
	assert_true(_do(HackSystem.COMMAND_START, {"actor": _player, "terminal": core}), "started")
	_actors.damage_node(_player, &"body", 1_000_000)
	_sim.step()
	assert_false(_hacks.is_hacking(_player), "the dead stop hacking")
	_sim.step_n(100)
	assert_eq(_completed.size(), 0, "nothing was ever finished")


func test_hacking_needs_the_hardware_and_to_be_there() -> void:
	_setup([500, 0, 500], false)
	var core: int = _core()
	assert_false(_do(HackSystem.COMMAND_START, {"actor": _player, "terminal": core}), "no coprocessor: no hack")
	assert_true(_do(&"item.attach", {"actor": _player, "weapon": _device, "part": _module}), "fitted")
	_actors.set_position(_player, _floor_of(FAR_CELL + Vector3i(9, 0, 9)))
	assert_false(_do(HackSystem.COMMAND_START, {"actor": _player, "terminal": core}), "too far away")
	_actors.set_position(_player, _floor_of(FAR_CELL + Vector3i(2, 0, 1)))
	for payload: Dictionary in [{}, {"actor": _player}, {"actor": _player, "terminal": 999999}, {"actor": "1", "terminal": core},
			{"actor": _player, "terminal": core, "x": 1}, {"actor": 999999, "terminal": core}]:
		assert_false(_do(HackSystem.COMMAND_START, payload), "refused: %s" % [payload])
	assert_true(_do(HackSystem.COMMAND_START, {"actor": _player, "terminal": core}), "now it starts")
	assert_false(_do(HackSystem.COMMAND_START, {"actor": _player, "terminal": core}), "one at a time")


func test_a_spoof_quiets_the_monitor_for_its_ticks() -> void:
	_setup()
	var monitor: int = _sensors.sensor_ids()[0]
	_actors.set_position(_player, _floor_of(FAR_CELL + Vector3i(6, 0, 0)))
	assert_true(_do(HackSystem.COMMAND_SPOOF, {"actor": _player, "sensor": monitor}), "the spoof starts")
	assert_eq(_hacks.progress_of(_player), [2000, 80000] as Array[int], "its work is the sensor's spoof_work")
	_sim.step_n(39)
	assert_true(_sensors.is_spoofed(monitor), "done in 40 ticks: quiet")
	_sim.step_n(1199)
	assert_true(_sensors.is_spoofed(monitor), "for its spoof ticks")
	_sim.step_n(2)
	assert_false(_sensors.is_spoofed(monitor), "and then not")
	assert_eq(_violations.size(), 0, "badlands again")


func test_hacking_someone_elses_terminal_is_one_loot_violation() -> void:
	_setup([2, 0, 2])  # on the starter plot
	assert_true(SimAssembly.land_of(_sim).transfer(&"starter_plot", "npc.somebody"), "somebody's plot")
	_actors.set_position(_player, _floor_of(Vector3i(4, 0, 3)))
	assert_true(_do(HackSystem.COMMAND_START, {"actor": _player, "terminal": _core()}), "the crime proceeds")
	_sim.step_n(60)
	assert_eq(_violations.size(), 1, "one violation")
	var right: StringName = _violations[0]["right"]
	assert_eq(right, &"loot", "of loot")
	assert_eq(_completed.size(), 1, "and it went through")


func test_a_save_mid_hack_finishes_the_same_way_and_bad_state_is_refused() -> void:
	_setup()
	_do(HackSystem.COMMAND_START, {"actor": _player, "terminal": _core()})
	_sim.step_n(20)
	var db: ContentDb = _sim.get_system(&"content")
	var loaded: SimRoot = SimAssembly.load_save(SaveFile.parse(SaveFile.serialize(_sim, db.digest())), db)
	assert_true(loaded != null, "loads")
	loaded.step_n(40)
	_sim.step_n(40)
	assert_eq(loaded.state_hash(), _sim.state_hash(), "finishes the same way")
	var fresh: HackSystem = SimAssembly.hacks_of(SimAssembly.build(SEED, db))
	for bad: Dictionary in [{}, {"terminals": {}, "actions": {}, "completed": -1}, {"terminals": [], "actions": {}, "completed": 0},
			{"terminals": {1: {"site": "nowhere", "name": "core", "hacked": false, "logged_in_by": 0}}, "actions": {}, "completed": 0},
			{"terminals": {}, "actions": {}, "completed": 0, "x": 1}]:
		assert_eq(fresh.restore(bad), ERR_INVALID_DATA, "rejects %s" % [bad])


func test_assembly_refuses_a_terminal_it_cannot_honour() -> void:
	for patch: Dictionary in [{"yields": {"kind": "goods", "template": "nothing"}}, {"yields": {"kind": "nope", "template": "data_drive"}},
			{"hack_work": 0}, {"logout_ticks": 0}, {"requires": ""}]:
		var db := ContentDb.new()
		assert_eq(ContentLoader.load_all(db), OK, "content loads")
		var site: Dictionary = _site([500, 0, 500])
		var terminals: Array = site["terminals"]
		var t: Dictionary = terminals[0]
		t.merge(patch, true)
		assert_eq(db.add(SiteSystem.KIND_SITE, &"zz_lab", site), OK, "added")
		assert_true(SimAssembly.build(SEED, db) == null, "assembly refuses %s" % [patch])
