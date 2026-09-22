extends GcityTest

## M5 spec claim 11: every world action has a prompt in the active device's names;
## the controller's names are Deck or Xbox by what is connected; keyboard names are
## hidden while a controller is active and controller names while the keyboard is.


func _world_actions() -> Array[StringName]:
	var out: Array[StringName] = []
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("world_"):
			out.append(action)
	out.sort()
	return out


func test_every_world_action_has_a_controller_glyph_and_a_keyboard_name() -> void:
	var glyphs := InputGlyphs.new()
	var actions: Array[StringName] = _world_actions()
	assert_true(actions.size() >= 18, "the world's actions are in the input map (%d)" % actions.size())
	glyphs.set_controller_active(true)
	glyphs.set_deck(true)
	var pad_only: Array[StringName] = [&"world_save", &"world_load"]  # F5 and F9: debug keys with no pad binding by design
	for action: StringName in actions:
		var g: String = glyphs.glyph(action)
		if pad_only.has(action):
			assert_eq(g, "", "%s has no controller glyph: a keyboard-only debug action" % action)
			continue
		assert_false(g.is_empty(), "%s has a Deck glyph" % action)
		assert_false(g.contains("Space") or g.contains("Enter") or g.contains("Escape"), "%s shows no keyboard name under a controller (%s)" % [action, g])
	glyphs.set_controller_active(false)
	for action: StringName in actions:
		var g: String = glyphs.glyph(action)
		assert_false(g.is_empty(), "%s has a keyboard name" % action)
		assert_false(g.contains("L1") or g.contains("R1") or g.contains("stick") or g.contains("D-pad") or g == "View" or g == "Menu", "%s shows no pad name under a keyboard (%s)" % [action, g])


func test_deck_and_xbox_name_the_same_button_differently() -> void:
	var glyphs := InputGlyphs.new()
	glyphs.set_controller_active(true)
	glyphs.set_deck(true)
	assert_eq(glyphs.glyph(&"world_build_next"), "L1", "the left shoulder is L1 on a Deck")
	assert_eq(glyphs.glyph(&"world_restart"), "View", "the back button is View")
	assert_eq(glyphs.glyph(&"world_profile"), "D-pad up", "the D-pad")
	glyphs.set_deck(false)
	assert_eq(glyphs.glyph(&"world_build_next"), "LB", "and LB on an Xbox pad")
	assert_eq(glyphs.glyph(&"world_fire"), "RB", "fire on the right shoulder")
	assert_eq(glyphs.prompt(&"world_fire", "fire"), "[RB] fire", "a prompt")
	assert_eq(glyphs.prompt(&"world_save", "save"), "", "no pad binding, no prompt")
	assert_eq(glyphs.line([[&"world_fire", "fire"], [&"world_save", "save"], [&"world_reload", "reload"]]), "[RB] fire  [X] reload", "a line drops the unbound")


func test_the_last_event_decides_the_active_device() -> void:
	var glyphs := InputGlyphs.new()
	glyphs.set_deck(true)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	glyphs.note(key)
	assert_false(glyphs.is_controller_active(), "a key: keyboard active")
	assert_eq(glyphs.glyph(&"world_fire"), "Space", "the key's own name")
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	button.pressed = true
	glyphs.note(button)
	assert_true(glyphs.is_controller_active(), "a pad button: controller active")
	assert_eq(glyphs.glyph(&"world_fire"), "R1", "fire on R1")
	var nudge := InputEventJoypadMotion.new()
	nudge.axis = JOY_AXIS_LEFT_X
	nudge.axis_value = 0.1
	glyphs.note(key)
	glyphs.note(nudge)
	assert_false(glyphs.is_controller_active(), "a stick at rest does not claim the controller")
	nudge.axis_value = 0.9
	glyphs.note(nudge)
	assert_true(glyphs.is_controller_active(), "a real stick move does")
	assert_eq(glyphs.glyph(&"world_move_forward"), "L stick", "the stick's name")


func test_the_action_manifest_names_every_world_action() -> void:
	var text: String = read_text("res://steam_input/game_actions.vdf")
	assert_true(text.contains('"world"') and text.contains('"device"'), "two action sets")
	for name: String in ["fire", "reload", "wield", "camera", "place", "remove", "next_piece", "raid", "device", "overlay", "profile", "restart", "move", "look"]:
		assert_true(text.contains('"%s"' % name), "the manifest names %s" % name)
	for key: String in ["Set_World", "Set_Device", "Action_Fire", "Action_Lower"]:
		assert_true(text.count(key) >= 2, "%s is declared and localised" % key)
