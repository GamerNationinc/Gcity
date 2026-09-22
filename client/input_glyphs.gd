## On-screen prompts in the active input device's own glyphs (standards §8.3, §8.4;
## M5 spec claim 11): a controller's button names, Deck or Xbox by what is connected,
## with keyboard names hidden while a controller is active, and the reverse. The
## glyph set is text: the names Valve prints on the hardware, which the Deck Verified
## check asks for. Steam's PNG glyphs replace the text when the app id is ours and the
## action manifest resolves (debt: the manifest cannot be bound under the test app).
class_name InputGlyphs extends RefCounted

const DECK: Dictionary = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Menu", JOY_BUTTON_GUIDE: "Steam",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down", JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
	JOY_BUTTON_PADDLE1: "L4", JOY_BUTTON_PADDLE2: "R4", JOY_BUTTON_PADDLE3: "L5", JOY_BUTTON_PADDLE4: "R5",
}
const XBOX: Dictionary = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Menu", JOY_BUTTON_GUIDE: "Xbox",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down", JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
	JOY_BUTTON_PADDLE1: "P1", JOY_BUTTON_PADDLE2: "P2", JOY_BUTTON_PADDLE3: "P3", JOY_BUTTON_PADDLE4: "P4",
}
const AXES_DECK: Dictionary = {JOY_AXIS_LEFT_X: "L stick", JOY_AXIS_LEFT_Y: "L stick", JOY_AXIS_RIGHT_X: "R stick", JOY_AXIS_RIGHT_Y: "R stick", JOY_AXIS_TRIGGER_LEFT: "L2", JOY_AXIS_TRIGGER_RIGHT: "R2"}
const AXES_XBOX: Dictionary = {JOY_AXIS_LEFT_X: "LS", JOY_AXIS_LEFT_Y: "LS", JOY_AXIS_RIGHT_X: "RS", JOY_AXIS_RIGHT_Y: "RS", JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT"}

var _controller_active: bool = false
var _deck: bool = true


## The last event decides the active device: a pad button or stick makes the
## controller active, a key or mouse makes the keyboard active.
func note(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		_controller_active = true
	elif event is InputEventKey or event is InputEventMouseButton:
		_controller_active = false


func set_deck(deck: bool) -> void:
	_deck = deck


func set_controller_active(active: bool) -> void:
	_controller_active = active


func is_controller_active() -> bool:
	return _controller_active


## The glyph for an action in the active device's names, or "" if the action has no
## binding for that device. Several bindings for one device join with " / ".
func glyph(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	var names: PackedStringArray = PackedStringArray()
	for event: InputEvent in InputMap.action_get_events(action):
		var name: String = _name_of(event)
		if not name.is_empty() and not names.has(name):
			names.append(name)
	return " / ".join(names)


## "[glyph] label", or "" when the action has no binding on the active device.
func prompt(action: StringName, label: String) -> String:
	var g: String = glyph(action)
	if g.is_empty():
		return ""
	return "[%s] %s" % [g, label]


## The prompts of several actions on one line, empty ones dropped.
func line(pairs: Array) -> String:
	var out: PackedStringArray = PackedStringArray()
	for pair: Array in pairs:
		var action: StringName = pair[0]
		var label: String = pair[1]
		var p: String = prompt(action, label)
		if not p.is_empty():
			out.append(p)
	return "  ".join(out)


func _name_of(event: InputEvent) -> String:
	if _controller_active:
		if event is InputEventJoypadButton:
			var button: int = (event as InputEventJoypadButton).button_index
			var table: Dictionary = DECK if _deck else XBOX
			return table.get(button, "")
		if event is InputEventJoypadMotion:
			var axis: int = (event as InputEventJoypadMotion).axis
			var axes: Dictionary = AXES_DECK if _deck else AXES_XBOX
			return axes.get(axis, "")
		return ""
	if event is InputEventKey:
		# the physical key's name: what is printed on a US layout, which is what the
		# input map binds; a localised label is a later item with the rest of the text
		var key: InputEventKey = event
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return OS.get_keycode_string(code)
	if event is InputEventMouseButton:
		return "Mouse %d" % (event as InputEventMouseButton).button_index
	return ""
