extends GcityTest

## M6 spec claims 5–6: a terminal is an entity a site places; the hack runs a tick a
## tick while the actor stays in reach with the right hardware; moving away loses the
## progress; completion yields the data and leaves a trace until it is wiped. The
## hacking pane drives all of it through commands.

const SEED: int = 20261190
const M: int = 1000
const HACK_TICKS: int = 320

var _sim: SimRoot
var _terminals: TerminalSystem
var _sites: SiteSystem
var _actors: ActorSystem
var _items: ItemSystem
var _player: int = 0
var _terminal: int = 0
var _hacked: Array[Dictionary] = []
var _cancelled: Array[Dictionary] = []


func _setup(with_coprocessor: bool = true) -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	_terminals = SimAssembly.terminals_of(_sim)
	_sites = SimAssembly.sites_of(_sim)
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	var events: EventBus = SimAssembly.combat_of(_sim).events()
	events.subscribe(TerminalSystem.EVENT_HACKED, _on_hacked)
	events.subscribe(TerminalSystem.EVENT_CANCELLED, _on_cancelled)
	_hacked = []
	_cancelled = []
	_player = _actors.spawn(&"arcade", 0)
	_raise_cold_storage()
	assert_true(_sites.raise_site(_player, &"cold_storage"), "the site stands")
	_terminal = _sites.terminals_of(&"cold_storage")[0]
	var inv: StringName = ItemSystem.inventory_of(_player)
	var handset: int = _items.spawn(&"device_frame", &"handset", inv, 1)
	_do(&"actor.equip_device", {"actor": _player, "device": handset})
	if with_coprocessor:
		var module: int = _items.spawn(&"device_module", &"daemon_coprocessor", inv, 2)
		_do(&"item.attach", {"actor": _player, "weapon": handset, "part": module})
	_disarm_the_guards()
	_actors.set_position(_player, _terminals.position_of(_terminal))


## Takes the guards' weapons off them. These tests stand the player at a terminal for
## three hundred ticks to prove the hack runs in real time; since the site started
## arming its own guards that is long enough to be shot dead, which proves something
## else. The mission fixtures are where being shot at belongs.
func _disarm_the_guards() -> void:
	for guard: int in _sites.agents_of(&"cold_storage"):
		_actors.wield(guard, EntityIds.NONE)


func _on_hacked(payload: Dictionary) -> void:
	_hacked.append(payload)


func _on_cancelled(payload: Dictionary) -> void:
	_cancelled.append(payload)


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


func test_a_site_places_its_terminal_and_the_hack_needs_reach_and_hardware() -> void:
	_setup(false)
	assert_eq(_sites.terminals_of(&"cold_storage").size(), 1, "the server the routes converge on")
	assert_eq(_terminals.template_of(_terminal), &"cs_server", "its template")
	assert_eq(_terminals.hack_ticks_of(_terminal), HACK_TICKS, "eight seconds of standing still")
	assert_eq(_terminals.in_reach_of(_player), [_terminal] as Array[int], "standing at it: in reach")
	assert_false(_terminals.can_hack(_player, _terminal), "no coprocessor: the device cannot talk to it")
	assert_false(_do(&"terminal.hack_start", {"actor": _player, "terminal": _terminal}), "so the hack is refused")
	# fit the coprocessor and it opens up
	var inv: StringName = ItemSystem.inventory_of(_player)
	var module: int = _items.spawn(&"device_module", &"daemon_coprocessor", inv, 9)
	assert_true(_do(&"item.attach", {"actor": _player, "weapon": _actors.device_of(_player), "part": module}), "fitted")
	assert_true(_terminals.can_hack(_player, _terminal), "now it can")
	# out of reach, it is refused again
	_actors.set_position(_player, _terminals.position_of(_terminal) + Vector3i(6 * M, 0, 0))
	assert_eq(_terminals.in_reach_of(_player), [] as Array[int], "six metres away: out of reach")
	assert_false(_do(&"terminal.hack_start", {"actor": _player, "terminal": _terminal}), "and the hack is refused")
	assert_false(_do(&"terminal.hack_start", {"actor": _player, "terminal": 999}), "an unknown terminal")
	assert_false(_do(&"terminal.hack_start", {"actor": _player}), "a short payload")


func test_the_hack_runs_in_real_time_and_walking_away_loses_it() -> void:
	_setup()
	assert_true(_do(&"terminal.hack_start", {"actor": _player, "terminal": _terminal}), "started")
	assert_eq(_terminals.hacker_of(_terminal), _player, "the player is on it")
	_sim.step_n(100)
	assert_eq(_terminals.progress_of(_terminal), 101, "a tick a tick, with the world running")
	assert_false(_terminals.is_hacked(_terminal), "not yet")
	# walk out of reach: the progress is gone
	_actors.set_position(_player, _terminals.position_of(_terminal) + Vector3i(4 * M, 0, 0))
	_sim.step()
	assert_eq(_terminals.hacker_of(_terminal), 0, "the hack dropped")
	assert_eq(_terminals.progress_of(_terminal), 0, "and its progress with it")
	assert_eq(_cancelled.size(), 1, "one terminal.hack_cancelled")
	assert_eq(_cancelled[0]["progress"], 101, "which says how far it had got")
	assert_eq(_cancelled[0]["reason"], "out of reach", "and why")
	# back at it, all the way through
	_actors.set_position(_player, _terminals.position_of(_terminal))
	assert_true(_do(&"terminal.hack_start", {"actor": _player, "terminal": _terminal}), "started again from nothing")
	var items_before: int = _items.items_in(ItemSystem.inventory_of(_player)).size()
	_sim.step_n(HACK_TICKS)
	assert_true(_terminals.is_hacked(_terminal), "open")
	assert_eq(_hacked.size(), 1, "one terminal.hacked")
	assert_eq(_hacked[0]["signal"], "signal.data_theft", "carrying the signal the threat director will read")
	assert_eq(_items.items_in(ItemSystem.inventory_of(_player)).size(), items_before + 1, "the data is in the inventory")
	var data: int = _hacked[0]["item"]
	assert_eq(_items.item_template(data), &"cold_storage_data", "the data itself")
	assert_eq(_terminals.hacker_of(_terminal), 0, "nobody is hacking it now")
	assert_false(_do(&"terminal.hack_start", {"actor": _player, "terminal": _terminal}), "and it cannot be hacked twice")


func test_a_hacked_terminal_is_a_trace_until_it_is_wiped() -> void:
	_setup()
	assert_eq(_terminals.traces(), 0, "nothing left behind yet")
	assert_true(_do(&"terminal.hack_start", {"actor": _player, "terminal": _terminal}), "started")
	_sim.step_n(HACK_TICKS)
	assert_eq(_terminals.traces(), 1, "a terminal left open is a trace")
	assert_eq(_terminals.hack_count(), 1, "one hack")
	_actors.set_position(_player, _terminals.position_of(_terminal) + Vector3i(9 * M, 0, 0))
	assert_false(_do(&"terminal.wipe", {"actor": _player, "terminal": _terminal}), "not from across the room")
	_actors.set_position(_player, _terminals.position_of(_terminal))
	assert_true(_do(&"terminal.wipe", {"actor": _player, "terminal": _terminal}), "wiped")
	assert_eq(_terminals.traces(), 0, "no trace")
	assert_false(_do(&"terminal.wipe", {"actor": _player, "terminal": _terminal}), "and nothing left to wipe")
	assert_eq(_items.items_in(ItemSystem.inventory_of(_player)).size() > 0, true, "the data you took stays taken")


func test_the_hacking_pane_drives_it_through_commands() -> void:
	_setup()
	var shell := DeviceShell.new()
	var db: ContentDb = SimAssembly.content_of(_sim)
	shell.setup(db, _submit_from_pane, InputGlyphs.new())
	for app: String in ["inventory", "map", "quests", "comms", "notes", "drone", "hacking", "mission"]:
		var scene: PackedScene = load("res://client/device/apps/%s_app.tscn" % app)
		shell.register_view(StringName(app), scene)
	var tree: SceneTree = Engine.get_main_loop()
	tree.root.add_child(shell)
	shell.refresh(_sim, _player)
	# the coprocessor is fitted, so the hacking app is offered; walk to it
	var opened: bool = false
	for i: int in 8:
		if shell.open_app() == &"hacking":
			opened = true
			break
		shell.handle(&"device_next_app", _sim, _player)
		shell.refresh(_sim, _player)
	assert_true(opened, "the hacking app is in the strip")
	shell.handle(&"device_select", _sim, _player)
	_sim.step()
	assert_eq(_terminals.hacker_of(_terminal), _player, "select started the hack")
	_sim.step_n(50)
	assert_true(shell.refresh(_sim, _player), "the pane redraws as the progress moves")
	shell.handle(&"device_secondary", _sim, _player)
	_sim.step()
	assert_eq(_terminals.hacker_of(_terminal), 0, "and the secondary stops it")
	shell.queue_free()


func _submit_from_pane(kind: StringName, payload: Dictionary) -> void:
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "the pane's command")


func test_restore_round_trip_and_rejections() -> void:
	_setup()
	assert_true(_do(&"terminal.hack_start", {"actor": _player, "terminal": _terminal}), "started")
	_sim.step_n(40)
	var snap: Dictionary = _sim.snapshot()
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "restored mid-hack")
	assert_eq(other.restore_root(snap), OK, "root restored")
	var terminals: TerminalSystem = SimAssembly.terminals_of(other)
	assert_eq(terminals.progress_of(_terminal), 41, "the hack carried over")
	assert_eq(terminals.hacker_of(_terminal), _player, "with its hacker")
	_sim.step_n(10)
	other.step_n(10)
	assert_eq(other.state_hash(), _sim.state_hash(), "hashes agree")
	var state: Dictionary = _terminals.snapshot()
	assert_eq(terminals.restore({}), ERR_INVALID_DATA, "empty")
	var bad: Dictionary = state.duplicate(true)
	var all: Dictionary = bad["terminals"]
	var rec: Dictionary = all[_terminal]
	rec["progress"] = HACK_TICKS + 5
	assert_eq(terminals.restore(bad), ERR_INVALID_DATA, "progress past the end")
	bad = state.duplicate(true)
	all = bad["terminals"]
	rec = all[_terminal]
	rec["actor"] = 0
	assert_eq(terminals.restore(bad), ERR_INVALID_DATA, "progress with no hacker")
	assert_eq(terminals.snapshot(), state, "rejections leave the state untouched")


## Cold Storage stands on `cold_storage_lot`, which the operator owns; a builder can
## only raise it on land that is theirs, so the test takes the lot first exactly as
## the client does before raising a site on owned ground.
func _raise_cold_storage() -> void:
	var at: int = _sim.get_tick() + 1
	assert_eq(_sim.submit(SimCommand.new(at, &"land.identify", {"actor": _player, "owner": "player"})), OK, "identify")
	assert_eq(_sim.submit(SimCommand.new(at, &"land.transfer", {"parcel": "cold_storage_lot", "owner": "player"})), OK, "transfer")
	_sim.step()
