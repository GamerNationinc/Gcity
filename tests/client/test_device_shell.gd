extends GcityTest

## M5 spec claims 3–5, 13: the shell lists the apps the carried device provides and
## nothing without a device; a pane reports a change only when its reading of the
## sim changed (the redraw-on-change contract); the inventory app's buttons are item
## commands the sim accepts; every label on every pane is at or above the minimum
## type size.

const SEED: int = 20261140

var _sim: SimRoot
var _actors: ActorSystem
var _items: ItemSystem
var _shell: DeviceShell
var _submitted: Array[Dictionary] = []
var _player: int = 0
var _handset: int = 0
var _radio: int = 0


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, Vector3i(3000, 0, 3000))
	var inv: StringName = ItemSystem.inventory_of(_player)
	_handset = _items.spawn(&"device_frame", &"handset", inv, 1)
	_radio = _items.spawn(&"device_module", &"radio_module", inv, 2)
	_shell = DeviceShell.new()
	_shell.setup(db, _submit, InputGlyphs.new())
	for app: String in ["inventory", "map", "quests", "comms", "notes", "drone", "hacking"]:
		var scene: PackedScene = load("res://client/device/apps/%s_app.tscn" % app)
		_shell.register_view(StringName(app), scene)
	var tree: SceneTree = Engine.get_main_loop()
	tree.root.add_child(_shell)


func _teardown() -> void:
	_shell.queue_free()


func _submit(kind: StringName, payload: Dictionary) -> void:
	_submitted.append({"kind": kind, "payload": payload})
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)


func _step() -> void:
	_sim.step()


func _equip() -> void:
	_submit(&"actor.equip_device", {"actor": _player, "device": _handset})
	_step()


func _app_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for a: Dictionary in _shell.available_apps(_sim, _player):
		out.append(a["id"])
	return out


func test_apps_follow_the_carried_device_and_its_modules() -> void:
	_setup()
	assert_eq(_app_ids(), [] as Array[StringName], "no device carried: no apps")
	assert_true(_shell.refresh(_sim, _player), "the first refresh draws")
	assert_eq(_shell.open_app(), &"", "nothing open")
	_equip()
	assert_eq(_app_ids(), [&"inventory", &"map", &"quests", &"comms", &"notes"] as Array[StringName], "the base unit's apps, in order")
	assert_true(_shell.refresh(_sim, _player), "a change: the strip appeared")
	assert_eq(_shell.open_app(), &"inventory", "the first app opens")
	_submit(&"item.attach", {"actor": _player, "weapon": _handset, "part": _radio})
	_step()
	assert_eq(_app_ids(), [&"inventory", &"map", &"quests", &"comms", &"notes", &"drone"] as Array[StringName], "the radio module unlocks the drone app")
	_submit(&"item.detach", {"actor": _player, "weapon": _handset, "socket": "radio"})
	_step()
	assert_eq(_app_ids().size(), 5, "and removing it takes the app away")
	_teardown()


func test_a_pane_reports_a_change_only_when_its_reading_changed() -> void:
	_setup()
	_equip()
	assert_true(_shell.refresh(_sim, _player), "first draw")
	assert_false(_shell.refresh(_sim, _player), "nothing changed: no redraw")
	_step()
	assert_true(_shell.refresh(_sim, _player), "the tick moved: the status line changed")
	assert_false(_shell.refresh(_sim, _player), "and settles again")
	assert_eq(_shell.handle(&"device_next_app", _sim, _player), "handled", "next app")
	assert_eq(_shell.open_app(), &"map", "the map")
	assert_true(_shell.refresh(_sim, _player), "a new pane: a redraw")
	assert_false(_shell.refresh(_sim, _player), "the map settles")
	_actors.set_position(_player, Vector3i(5000, 0, 3000))
	assert_true(_shell.refresh(_sim, _player), "you moved a cell: the map redraws")
	_actors.set_position(_player, Vector3i(5100, 0, 3000))
	assert_false(_shell.refresh(_sim, _player), "within the cell: no redraw")
	assert_eq(_shell.handle(&"device_prev_app", _sim, _player), "handled", "back")
	assert_eq(_shell.handle(&"device_prev_app", _sim, _player), "handled", "wraps")
	assert_eq(_shell.open_app(), &"notes", "to the last app")
	assert_eq(_shell.handle(&"device_back", _sim, _player), "lower", "back with nothing to back out of lowers the device")
	_teardown()


func test_the_inventory_app_fits_loads_wields_and_swaps_through_commands() -> void:
	_setup()
	_equip()
	var inv: StringName = ItemSystem.inventory_of(_player)
	var pistol: int = _items.spawn(&"weapon_frame", &"g19", inv, 3)
	var mag: int = _items.spawn(&"weapon_part", &"g19_mag_15", inv, 4)
	var barrel: int = _items.spawn(&"weapon_part", &"g19_barrel", inv, 5)
	for i: int in 20:
		_items.spawn(&"ammo", &"9x19_fmj", inv, 100 + i)
	_shell.refresh(_sim, _player)
	assert_eq(_shell.open_app(), &"inventory", "inventory open")
	# rows by kind, then name: 0 pistol, 1-4 its four non-magazine sockets, 5 magazine,
	# 6 barrel, 7 loose rounds, 8 handset, 9-10 its bays, 11 radio module
	_go(0)
	_submitted.clear()
	assert_eq(_shell.handle(&"device_select", _sim, _player), "handled", "select the pistol")
	_step()
	assert_eq(_actors.wielded(_player), pistol, "wielded through actor.wield")
	_go(5)
	assert_eq(_shell.handle(&"device_select", _sim, _player), "handled", "select the magazine")
	_step()
	assert_eq(_items.magazine_of(pistol), mag, "swapped in through weapon.reload_tactical")
	_sim.step_n(90)
	# the magazine moved into the pistol's socket, so it left the list: the rounds are row 6
	_go(6)
	_submitted.clear()
	_shell.handle(&"device_select", _sim, _player)
	assert_eq(_submitted.size(), 0, "no loose magazine with room: nothing submitted")
	var mag2: int = _items.spawn(&"weapon_part", &"g19_mag_15", inv, 6)
	_shell.refresh(_sim, _player)
	_go(7)  # the new magazine took row 5; the barrel moved to 6, the rounds to 7
	_submitted.clear()
	_shell.handle(&"device_select", _sim, _player)
	assert_eq(_submitted.size(), 15, "fifteen magazine.load commands: a full magazine in one press")
	_step()
	assert_eq(_items.rounds_in(mag2).size(), 15, "loaded")
	_go(6)  # the barrel
	_submitted.clear()
	_shell.handle(&"device_select", _sim, _player)
	_step()
	assert_eq(_items.socket_part(pistol, &"barrel"), barrel, "fitted through item.attach")
	_go(8)
	_submitted.clear()
	_shell.handle(&"device_select", _sim, _player)
	assert_eq(_submitted.size(), 0, "an empty bay does nothing")
	_go(10)
	_shell.handle(&"device_select", _sim, _player)
	_step()
	assert_eq(_items.socket_part(_handset, &"radio"), _radio, "the module fitted to the carried device")
	_teardown()


## M6 claim 19: the hacking pane lists the targets in reach with their state, starts,
## cancels and logs out through commands, shows the slots and a progress bar, and the
## panel turns see-through while a hack runs so the world stays visible behind it.
func test_the_hacking_pane_starts_cancels_and_logs_out_through_commands() -> void:
	_setup()
	_equip()
	var coprocessor: int = _items.spawn(&"device_module", &"daemon_coprocessor", ItemSystem.inventory_of(_player), 9)
	_submit(&"item.attach", {"actor": _player, "weapon": _handset, "part": coprocessor})
	_step()
	var hacks: HackSystem = SimAssembly.hacks_of(_sim)
	var terminal: int = hacks.place(&"cold_storage_terminal", BuildSystem.cell_of(_actors.position_of(_player)), EntityIds.NONE)
	hacks.place(&"cold_storage_terminal", BuildSystem.cell_of(_actors.position_of(_player)) + Vector3i(9, 0, 0), EntityIds.NONE)
	_open(&"hacking")
	_shell.refresh(_sim, _player)
	var text: String = _pane_text(&"hacking")
	assert_true(text.contains("daemons 0 / 2"), "the slots: %s" % text)
	assert_true(text.contains("cold storage terminal") and text.contains("ready"), "the terminal in reach, ready")
	assert_eq(text.count("cold storage terminal"), 1, "the one out of reach is not listed")
	assert_false(_shell.see_through(), "solid while nothing runs")
	_submitted.clear()
	_shell.handle(&"device_select", _sim, _player)
	assert_eq(_submitted, [{"kind": &"hack.start", "payload": {"actor": _player, "target": terminal}}] as Array[Dictionary], "select starts it")
	_step()
	_sim.step_n(299)
	_shell.refresh(_sim, _player)
	text = _pane_text(&"hacking")
	assert_true(text.contains("50 %") and text.contains("#"), "a progress bar half way: %s" % text)
	assert_true(_shell.see_through(), "see-through while it runs")
	_submitted.clear()
	_shell.handle(&"device_secondary", _sim, _player)
	assert_eq(_submitted, [{"kind": &"hack.cancel", "payload": {"actor": _player}}] as Array[Dictionary], "secondary cancels")
	_step()
	assert_false(hacks.is_hacking(_player), "cancelled")
	_shell.refresh(_sim, _player)
	assert_false(_shell.see_through(), "solid again")
	_shell.handle(&"device_select", _sim, _player)
	_step()
	_sim.step_n(600)
	_shell.refresh(_sim, _player)
	text = _pane_text(&"hacking")
	assert_true(text.contains("logged in") and text.contains("daemons 1 / 2"), "done, logged in, its daemon held: %s" % text)
	_submitted.clear()
	_shell.handle(&"device_select", _sim, _player)
	assert_eq(_submitted, [{"kind": &"hack.logout", "payload": {"actor": _player, "target": terminal}}] as Array[Dictionary], "select logs out")
	_step()
	assert_eq(hacks.logins_of(_player), [] as Array[int], "logged out")
	_shell.refresh(_sim, _player)
	assert_true(_pane_text(&"hacking").contains("done"), "and the terminal shows done")
	_teardown()


func _open(app: StringName) -> void:
	for i: int in 10:
		_shell.refresh(_sim, _player)
		if _shell.open_app() == app:
			return
		_shell.handle(&"device_next_app", _sim, _player)
	assert_eq(_shell.open_app(), app, "opened %s" % app)


func _pane_text(app: StringName) -> String:
	for node: Node in _all_nodes(_shell):
		if node is RichTextLabel and node.get_parent().name == String(app):
			var rich: RichTextLabel = node
			return rich.text
	return ""


## M6 claim 19: the shell bar shows the credit balance, read from the wallet, and a
## change of balance redraws it.
func test_the_shell_bar_shows_the_credit_balance() -> void:
	_setup()
	_equip()
	var wallet: WalletSystem = SimAssembly.wallet_of(_sim)
	assert_eq(wallet.register_source(&"test.grant"), OK, "a test source")
	_shell.refresh(_sim, _player)
	assert_true(_status_text().contains("credits 0"), "no credits yet: %s" % _status_text())
	assert_false(_shell.refresh(_sim, _player), "settled")
	assert_true(wallet.credit(_player, 250, &"test.grant"), "credited")
	assert_true(_shell.refresh(_sim, _player), "the balance changed: a redraw")
	assert_true(_status_text().contains("credits 250"), "the new balance: %s" % _status_text())
	_teardown()


func _status_text() -> String:
	for node: Node in _all_nodes(_shell):
		if node is Label:
			var label: Label = node
			if label.text.contains("tick"):
				return label.text
	return ""


## M6 claim 19 (M5 debt 11): rows are grouped by kind (weapons, tools, magazines,
## parts, rounds, devices, modules, keys) and named in order within a kind, whatever
## order the items came in; a frame's sockets stay under it.
func test_the_inventory_sorts_by_kind_then_name() -> void:
	_setup()
	_equip()
	var inv: StringName = ItemSystem.inventory_of(_player)
	_items.spawn(&"key_item", &"maintenance_key", inv, 3)
	_items.spawn(&"ammo", &"9x19_fmj", inv, 4)
	_items.spawn(&"weapon_part", &"g19_barrel", inv, 5)
	_items.spawn(&"tool", &"plasma_cutter", inv, 6)
	_items.spawn(&"key_item", &"cold_storage_keycard", inv, 7)
	_items.spawn(&"weapon_part", &"g19_mag_15", inv, 8)
	_items.spawn(&"tool", &"breaching_kit", inv, 9)
	_items.spawn(&"weapon_frame", &"g19", inv, 10)
	_shell.refresh(_sim, _player)
	var names: Array[String] = []
	for line: String in _inventory_text().split("\n"):
		var plain: String = line.replace("[color=#ffd866]> ", "").replace("[/color]", "").strip_edges()
		if not plain.contains(":"):
			names.append(plain.get_slice(" ", 0))
	assert_eq(names, ["g19", "breaching_kit", "plasma_cutter", "g19_mag_15", "g19_barrel", "9x19_fmj", "handset", "radio_module", "cold_storage_keycard", "maintenance_key"] as Array[String], "kind, then name")
	_go(1)
	_submitted.clear()
	assert_eq(_shell.handle(&"device_select", _sim, _player), "handled", "select a socket row")
	assert_eq(_submitted.size(), 0, "the pistol's first socket row sits under it (empty, nothing to do)")
	_teardown()


func _inventory_text() -> String:
	for node: Node in _all_nodes(_shell):
		if node is RichTextLabel and node.get_parent() is InventoryApp:
			var rich: RichTextLabel = node
			return rich.text
	return ""


## Leaving an app and coming back rebuilds its pane with the cursor at the top (the
## shell frees a pane whose app is no longer open), which is how a row is addressed
## now that the cursor wraps.
func _go(row: int) -> void:
	_shell.handle(&"device_next_app", _sim, _player)
	_shell.refresh(_sim, _player)
	_shell.handle(&"device_prev_app", _sim, _player)
	_shell.refresh(_sim, _player)
	for i: int in row:
		_shell.handle(&"device_down", _sim, _player)


func test_every_pane_meets_the_minimum_type_size() -> void:
	_setup()
	_equip()
	_submit(&"item.attach", {"actor": _player, "weapon": _handset, "part": _radio})
	_step()
	var seen: int = 0
	for i: int in 6:
		_shell.refresh(_sim, _player)
		for node: Node in _all_nodes(_shell):
			if node is Label:
				var label: Label = node
				var px: int = label.get_theme_font_size("font_size")
				assert_true(px >= DeviceShell.SECONDARY_PX, "%s: %d px" % [node.name, px])
				seen += 1
			elif node is RichTextLabel:
				var rich: RichTextLabel = node
				var px: int = rich.get_theme_font_size("normal_font_size")
				assert_true(px >= DeviceShell.BODY_PX, "%s body: %d px" % [node.name, px])
				var text: String = rich.text
				var regex := RegEx.new()
				regex.compile("\\[font_size=(\\d+)\\]")
				for m: RegExMatch in regex.search_all(text):
					assert_true(m.get_string(1).to_int() >= DeviceShell.SECONDARY_PX, "%s inline: %s px" % [node.name, m.get_string(1)])
				seen += 1
		_shell.handle(&"device_next_app", _sim, _player)
	assert_true(seen >= 12, "labels were walked on every pane (%d)" % seen)
	_teardown()


func _all_nodes(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child: Node in node.get_children():
		out.append_array(_all_nodes(child))
	return out


func test_the_extension_exercise_is_content_and_one_registration() -> void:
	_setup()
	_equip()
	# the notes app: content only, no hardware
	assert_true(_app_ids().has(&"notes"), "the sixth app is offered with no module fitted")
	# the hacking app: gated on a module nothing else provides
	assert_false(_app_ids().has(&"hacking"), "hacking waits for its coprocessor")
	var coprocessor: int = _items.spawn(&"device_module", &"daemon_coprocessor", ItemSystem.inventory_of(_player), 9)
	_submit(&"item.attach", {"actor": _player, "weapon": _handset, "part": coprocessor})
	_step()
	assert_eq(_items.provides_of(_handset), [&"daemon_coprocessor"] as Array[StringName], "the bay provides it")
	assert_true(_app_ids().has(&"hacking"), "and the app appears")
	var stats: StatResolver = SimAssembly.stats_of(_sim)
	assert_eq(stats.resolve(_handset, &"memory_capacity"), 2000, "its modifier doubled the memory through the resolver")
	_submit(&"item.detach", {"actor": _player, "weapon": _handset, "socket": "coprocessor"})
	_step()
	assert_false(_app_ids().has(&"hacking"), "and goes when the module does")
	assert_eq(stats.resolve(_handset, &"memory_capacity"), 1000, "the exact prior value")
	# the third quest: content only, over an event that already existed
	var quests: QuestSystem = SimAssembly.quests_of(_sim)
	assert_true(quests.quest_ids().has(&"hold_the_line"), "a third quest on record")
	_submit(&"quest.accept", {"actor": _player, "quest": "hold_the_line"})
	_step()
	var events: EventBus = SimAssembly.combat_of(_sim).events()
	for i: int in 5:
		events.emit(CombatSystem.EVENT_FIRE, {"shooter": 99, "weapon": 0, "target": _player, "round": 0, "tags": []})
	assert_eq(quests.status_of(_player, &"hold_the_line"), QuestSystem.STATUS_COMPLETED, "five shots at you completes it")
	_teardown()
