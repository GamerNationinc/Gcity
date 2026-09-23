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
	for app: String in ["inventory", "map", "quests", "comms", "notes", "drone", "hacking", "mission"]:
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
	assert_eq(_app_ids(), [&"inventory", &"mission", &"map", &"quests", &"comms", &"notes"] as Array[StringName], "the base unit's apps, in order")
	assert_true(_shell.refresh(_sim, _player), "a change: the strip appeared")
	assert_eq(_shell.open_app(), &"inventory", "the first app opens")
	_submit(&"item.attach", {"actor": _player, "weapon": _handset, "part": _radio})
	_step()
	assert_eq(_app_ids(), [&"inventory", &"mission", &"map", &"quests", &"comms", &"notes", &"drone"] as Array[StringName], "the radio module unlocks the drone app")
	_submit(&"item.detach", {"actor": _player, "weapon": _handset, "socket": "radio"})
	_step()
	assert_eq(_app_ids().size(), 6, "and removing it takes the app away")
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
	assert_eq(_shell.open_app(), &"mission", "the mission app sits second, by its order")
	assert_true(_shell.refresh(_sim, _player), "a new pane: a redraw")
	assert_eq(_shell.handle(&"device_next_app", _sim, _player), "handled", "on again")
	assert_eq(_shell.open_app(), &"map", "the map")
	assert_true(_shell.refresh(_sim, _player), "a new pane: a redraw")
	assert_false(_shell.refresh(_sim, _player), "the map settles")
	_actors.set_position(_player, Vector3i(5000, 0, 3000))
	assert_true(_shell.refresh(_sim, _player), "you moved a cell: the map redraws")
	_actors.set_position(_player, Vector3i(5100, 0, 3000))
	assert_false(_shell.refresh(_sim, _player), "within the cell: no redraw")
	assert_eq(_shell.handle(&"device_prev_app", _sim, _player), "handled", "back")
	assert_eq(_shell.handle(&"device_prev_app", _sim, _player), "handled", "back again")
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
	# rows in spawn order: 0 handset, 1-2 its bays, 3 radio module, 4 pistol, 5-8 its
	# four non-magazine sockets, 9 magazine, 10 barrel, 11 loose rounds
	_go(4)
	_submitted.clear()
	assert_eq(_shell.handle(&"device_select", _sim, _player), "handled", "select the pistol")
	_step()
	assert_eq(_actors.wielded(_player), pistol, "wielded through actor.wield")
	_go(9)
	assert_eq(_shell.handle(&"device_select", _sim, _player), "handled", "select the magazine")
	_step()
	assert_eq(_items.magazine_of(pistol), mag, "swapped in through weapon.reload_tactical")
	_sim.step_n(90)
	# the magazine moved into the pistol's socket, so it left the list: the rounds are row 10
	_go(10)
	_submitted.clear()
	_shell.handle(&"device_select", _sim, _player)
	assert_eq(_submitted.size(), 0, "no loose magazine with room: nothing submitted")
	var mag2: int = _items.spawn(&"weapon_part", &"g19_mag_15", inv, 6)
	_shell.refresh(_sim, _player)
	_go(11)  # the new magazine took row 10; the rounds moved to 11
	_submitted.clear()
	_shell.handle(&"device_select", _sim, _player)
	assert_eq(_submitted.size(), 15, "fifteen magazine.load commands: a full magazine in one press")
	_step()
	assert_eq(_items.rounds_in(mag2).size(), 15, "loaded")
	_go(9)  # the barrel
	_submitted.clear()
	_shell.handle(&"device_select", _sim, _player)
	_step()
	assert_eq(_items.socket_part(pistol, &"barrel"), barrel, "fitted through item.attach")
	_go(1)
	_submitted.clear()
	_shell.handle(&"device_select", _sim, _player)
	assert_eq(_submitted.size(), 0, "an empty bay does nothing")
	_go(3)
	_shell.handle(&"device_select", _sim, _player)
	_step()
	assert_eq(_items.socket_part(_handset, &"radio"), _radio, "the module fitted to the carried device")
	_teardown()


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


## Opens the named app by stepping the strip, or says it never appeared.
func _open(app: StringName) -> bool:
	for i: int in 12:
		if _shell.open_app() == app:
			return true
		_shell.handle(&"device_next_app", _sim, _player)
		_shell.refresh(_sim, _player)
	return false


## True when the open pane's text contains `needle`.
func _pane_says(needle: String) -> bool:
	for node: Node in _all_nodes(_shell):
		if node is RichTextLabel:
			var rich: RichTextLabel = node
			if rich.text.contains(needle):
				return true
	return false


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


## M6 spec claim 13: the mission pane shows the contract, the four counters while the
## run is happening rather than only when it is paid, and the death screen that offers
## the way back.
func test_the_mission_pane_shows_the_run_while_it_is_happening() -> void:
	_setup()
	_equip()
	_shell.refresh(_sim, _player)
	assert_true(_open(&"mission"), "the mission app opens with no hardware at all")
	assert_true(_pane_says("No contract accepted"), "nothing taken on yet")
	assert_true(_pane_says("No run in progress"), "and no run")
	_submit(&"quest.accept", {"actor": _player, "quest": "cold_storage"})
	_step()
	_submit(&"run.begin", {"actor": _player})
	_step()
	_shell.refresh(_sim, _player)
	assert_true(_pane_says("Cold Storage"), "the contract by name")
	assert_true(_pane_says("Run in progress"), "the run is on")
	assert_true(_pane_says("seen 0   alarms 0   bodies 0   traces 0"), "the four counters, live")
	assert_true(_pane_says("nobody saw you"), "and what that is worth so far")
	# a sighting moves the pane, because a score you cannot see is one you cannot play
	var perception: PerceptionSystem = SimAssembly.perception_of(_sim)
	var guard: int = perception.spawn(&"guard_sim", BuildSystem.cell_of(Vector3i(400000, 0, 400000)), 0, 1, "")
	SimAssembly.combat_of(_sim).events().emit(PerceptionSystem.EVENT_ALERTED, {"observer": guard, "contact": _player, "tick": _sim.get_tick()})
	assert_true(_shell.refresh(_sim, _player), "the pane redraws")
	assert_true(_pane_says("seen 1"), "one sighting")
	assert_false(_pane_says("nobody saw you"), "and the bonus is gone")
	_teardown()


func test_the_death_screen_offers_the_way_back() -> void:
	_setup()
	_equip()
	_shell.refresh(_sim, _player)
	assert_true(_open(&"mission"), "the mission app")
	_actors.damage_node(_player, &"body", 999999)
	assert_false(_actors.is_alive(_player), "down")
	assert_true(_shell.refresh(_sim, _player), "the pane changed")
	assert_true(_pane_says("You are dead"), "the death screen")
	assert_true(_pane_says("your body is at"), "where the body is")
	assert_true(_pane_says("Select: come back"), "and what to press")
	_submitted.clear()
	assert_eq(_shell.handle(&"device_select", _sim, _player), "handled", "pressed")
	assert_eq(_submitted.size(), 1, "one command")
	assert_eq(_submitted[0]["kind"], &"actor.respawn", "the way back")
	_teardown()
