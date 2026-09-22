## Time-to-complete for each core device task (M5 spec claim 14; ADR-006 verification):
##   godot --headless --path . -s tools/bench_device.gd
## the ticks a task takes from the pane opening to the command landing, driven through
## the same shell the player uses, one action per press. Ticks at 40 Hz, plus a
## human's press interval (0.35 s per press on a controller) for the wall-clock figure.
extends SceneTree

const PRESS_S: float = 0.35


func _initialize() -> void:
	print("task                                    presses   sim ticks   seconds (at %.2f s a press)" % PRESS_S)
	_task("load a magazine from loose rounds", _load_magazine)
	_task("swap a magazine into the pistol", _swap_magazine)
	_task("attach a part", _attach_part)
	_task("accept a quest", _accept_quest)
	_task("find your parcel on the map", _find_parcel)
	_task("lower the device", _lower)
	quit(0)


var _sim: SimRoot
var _shell: DeviceShell
var _player: int = 0
var _presses: int = 0
var _items: ItemSystem
var _actors: ActorSystem


func _task(name: String, body: Callable) -> void:
	_setup()
	var start: int = _sim.get_tick()
	_presses = 0
	body.call()
	var ticks: int = _sim.get_tick() - start
	print("%-40s %5d %11d   %.2f" % [name, _presses, ticks, _presses * PRESS_S + float(ticks) / SimRoot.TICK_HZ])


func _press(action: StringName) -> void:
	_presses += 1
	var outcome: String = _shell.handle(action, _sim, _player)
	if outcome == "":
		pass
	_sim.step()
	_shell.refresh(_sim, _player)


func _setup() -> void:
	var db := ContentDb.new()
	ContentLoader.load_all(db)
	_sim = SimAssembly.build(20261160, db)
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, Vector3i(3000, 0, 3000))
	var inv: StringName = ItemSystem.inventory_of(_player)
	var handset: int = _items.spawn(&"device_frame", &"handset", inv, 1)
	_items.spawn(&"weapon_frame", &"g19", inv, 2)
	_items.spawn(&"weapon_part", &"g19_mag_15", inv, 3)
	_items.spawn(&"weapon_part", &"g19_barrel", inv, 4)
	for i: int in 20:
		_items.spawn(&"ammo", &"9x19_fmj", inv, 100 + i)
	_sim.submit(SimCommand.new(_sim.get_tick() + 1, &"actor.equip_device", {"actor": _player, "device": handset}))
	_sim.submit(SimCommand.new(_sim.get_tick() + 1, &"land.identify", {"actor": _player, "owner": "player"}))
	_sim.submit(SimCommand.new(_sim.get_tick() + 1, &"land.transfer", {"parcel": "starter_plot", "owner": "player"}))
	_sim.step()
	_shell = DeviceShell.new()
	_shell.setup(db, _submit, InputGlyphs.new())
	for app: String in ["inventory", "map", "quests", "comms", "notes", "drone", "hacking"]:
		var scene: PackedScene = load("res://client/device/apps/%s_app.tscn" % app)
		_shell.register_view(StringName(app), scene)
	root.add_child(_shell)
	_shell.refresh(_sim, _player)


func _submit(kind: StringName, payload: Dictionary) -> void:
	_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload))


## Rows in spawn order: 0 handset, 1-2 bays, 3 pistol, 4-7 sockets, 8 magazine, 9 barrel,
## 10 rounds. The cursor starts at 0 and wraps, so a row is min(row, rows - row) presses.
func _go(row: int) -> void:
	var rows: int = 11
	if row <= rows - row:
		for i: int in row:
			_press(&"device_down")
	else:
		for i: int in rows - row:
			_press(&"device_up")


func _load_magazine() -> void:
	# the pane opens on the inventory with the cursor at the top: the loose rounds are
	# the last row, one press up
	_go(10)
	_press(&"device_select")
	_sim.step_n(2)


## In play the pistol is already wielded; the task is reaching the magazine and
## pressing. (Wielding it first costs three more presses.)
func _swap_magazine() -> void:
	_sim.submit(SimCommand.new(_sim.get_tick() + 1, &"actor.wield", {"actor": _player, "weapon": _of_kind(ItemSystem.KIND_FRAME)}))
	_sim.step()
	_shell.refresh(_sim, _player)
	_go(8)
	_press(&"device_select")
	_sim.step_n(2)


func _attach_part() -> void:
	_sim.submit(SimCommand.new(_sim.get_tick() + 1, &"actor.wield", {"actor": _player, "weapon": _of_kind(ItemSystem.KIND_FRAME)}))
	_sim.step()
	_shell.refresh(_sim, _player)
	_go(9)
	_press(&"device_select")
	_sim.step_n(2)


func _of_kind(kind: StringName) -> int:
	for id: int in _items.items_in(ItemSystem.inventory_of(_player)):
		if _items.item_kind(id) == kind:
			return id
	return 0


func _accept_quest() -> void:
	_press(&"device_next_app")
	_press(&"device_next_app")   # inventory -> map -> quests
	_press(&"device_select")
	_sim.step_n(2)


func _find_parcel() -> void:
	_press(&"device_next_app")   # the map is one press away and needs no aiming
	_sim.step_n(2)


func _lower() -> void:
	_press(&"device_back")
