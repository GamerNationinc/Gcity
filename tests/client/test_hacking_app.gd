extends GcityTest

## M6 spec claim 13: the hacking pane lists the terminals and spoofable sensors in
## reach, nearest first; select hacks, spoofs or logs out through commands the sim
## accepts; while a hack runs the pane shows its progress and how far it is heard.

const SEED: int = 20261200
const M: int = 1000

var _sim: SimRoot
var _actors: ActorSystem
var _items: ItemSystem
var _hacks: HackSystem
var _shell: DeviceShell
var _player: int = 0


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	assert_eq(db.add(SiteSystem.KIND_SITE, &"zz_lab", {
		"schema_version": 1, "description": "A lab.", "origin": [500, 0, 500], "parcels": [],
		"pieces": [
			{"piece": "foundation_block", "cell": [6, 0, -1], "facing": ""},
			{"piece": "foundation_block", "cell": [6, 0, 1], "facing": ""},
			{"piece": "window_frame", "cell": [6, 0, 0], "facing": "px"},
		],
		"points": [], "agents": [],
		"sensors": [{"sensor": "power_monitor", "squad": 0, "cell": [6, 0, 0], "facing": "px", "cells": []}],
		"terminals": [{"name": "core", "cell": [2, 0, 0], "hack_work": 100000, "requires": "daemon_coprocessor",
			"noise_mm": 5000, "yields": {"kind": "goods", "template": "data_drive"}, "logout_ticks": 20}],
	}), OK, "the lab")
	_sim = SimAssembly.build(SEED, db)
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_hacks = SimAssembly.hacks_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	var inv: StringName = ItemSystem.inventory_of(_player)
	var handset: int = _items.spawn(&"device_frame", &"handset", inv, 1)
	var module: int = _items.spawn(&"device_module", &"daemon_coprocessor", inv, 2)
	var at: int = _sim.get_tick() + 1
	_sim.submit(SimCommand.new(at, SiteSystem.COMMAND_RAISE, {"site": "zz_lab"}))
	_sim.submit(SimCommand.new(at, &"item.attach", {"actor": _player, "weapon": handset, "part": module}))
	_sim.submit(SimCommand.new(at, &"actor.equip_device", {"actor": _player, "device": handset}))
	_sim.step()
	assert_eq(_sim.rejected_count(), 0, "raised and equipped")
	_actors.set_position(_player, Vector3i(502 * M + 500, 0, 501 * M + 500))
	_shell = DeviceShell.new()
	_shell.setup(db, _submit, InputGlyphs.new())
	for app: String in ["inventory", "map", "quests", "comms", "notes", "drone", "hacking"]:
		var scene: PackedScene = load("res://client/device/apps/%s_app.tscn" % app)
		_shell.register_view(StringName(app), scene)
	var tree: SceneTree = Engine.get_main_loop()
	tree.root.add_child(_shell)
	while _shell.open_app() != &"hacking":
		assert_eq(_shell.handle(&"device_next_app", _sim, _player), "handled", "next app")
	_shell.refresh(_sim, _player)


func _submit(kind: StringName, payload: Dictionary) -> void:
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)


func _pane_text() -> String:
	var texts: PackedStringArray = PackedStringArray()
	for node: Node in _all_nodes(_shell):
		if node is RichTextLabel:
			var rich: RichTextLabel = node
			texts.append(rich.text)
	return "\n".join(texts)


func _all_nodes(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child: Node in node.get_children():
		out.append_array(_all_nodes(child))
	return out


func test_the_pane_lists_what_is_in_reach_nearest_first() -> void:
	_setup()
	var list: Array[Array] = HackingApp.targets(_sim, _player)
	assert_eq(list.size(), 2, "the terminal and the monitor")
	var first: String = list[0][0]
	assert_eq(first, "terminal", "the terminal is nearer")
	assert_true(_pane_text().contains("core") and _pane_text().contains("power_monitor"), "both shown")
	_actors.set_position(_player, Vector3i(560 * M, 0, 560 * M))
	assert_eq(HackingApp.targets(_sim, _player).size(), 0, "out of reach, nothing listed")
	_shell.queue_free()


func test_select_hacks_shows_progress_and_then_logs_out() -> void:
	_setup()
	assert_eq(_shell.handle(&"device_select", _sim, _player), "handled", "select the terminal")
	_sim.step()
	assert_true(_hacks.is_hacking(_player), "the hack runs")
	_shell.refresh(_sim, _player)
	assert_true(_pane_text().contains("hack core") and _pane_text().contains("heard 5 m"), "progress and noise shown")
	_sim.step_n(60)
	assert_true(_hacks.is_logged_in(_hacks.terminal_ids()[0]), "done, logged in")
	_shell.refresh(_sim, _player)
	assert_true(_pane_text().contains("logged in: log out"), "the pane offers the logout")
	assert_eq(_shell.handle(&"device_secondary", _sim, _player), "handled", "log out")
	_sim.step_n(25)
	assert_false(_hacks.is_logged_in(_hacks.terminal_ids()[0]), "logged out through the pane")
	_shell.queue_free()


func test_select_spoofs_a_sensor() -> void:
	_setup()
	_actors.set_position(_player, Vector3i(506 * M + 500, 0, 500 * M + 500))
	_shell.refresh(_sim, _player)
	var list: Array[Array] = HackingApp.targets(_sim, _player)
	var first: String = list[0][0]
	assert_eq(first, "sensor", "beside the window the monitor is nearest")
	assert_eq(_shell.handle(&"device_select", _sim, _player), "handled", "select it")
	_sim.step_n(45)
	var sensors: SensorSystem = SimAssembly.sensors_of(_sim)
	assert_true(sensors.is_spoofed(sensors.sensor_ids()[0]), "spoofed through the pane")
	_shell.queue_free()
