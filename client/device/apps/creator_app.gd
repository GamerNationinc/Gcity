## The creator app (M7.5 spec claim 15): save the lot as a site file, or open a saved or
## shipped one. Files, not sim state, so the pane asks the view to do either through the
## shell's submit with a `creator.` kind, which the world view takes for itself and never
## sends to the sim. Offered only where the client grants `creator` (`--create`).
class_name CreatorApp extends DeviceApp

const KIND_SAVE: StringName = &"creator.save"
const KIND_OPEN: StringName = &"creator.open"

var _label: RichTextLabel
var _cursor: int = 0


func _init() -> void:
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.add_theme_font_size_override("normal_font_size", DeviceShell.BODY_PX)
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_label)


## "save", then every site that can be opened: the autosave, the player's own, the shipped.
static func entries() -> Array[String]:
	var out: Array[String] = ["save"]
	out.append_array(SiteCreator.openable())
	return out


static func label_of(entry: String) -> String:
	return "Save this site" if entry == "save" else "Open %s" % entry.get_file().get_basename()


func refresh(_sim: SimRoot, _player: int) -> bool:
	var list: Array[String] = entries()
	_cursor = clampi(_cursor, 0, list.size() - 1)
	var lines: PackedStringArray = PackedStringArray()
	for i: int in list.size():
		lines.append("%s %s" % [">" if i == _cursor else " ", label_of(list[i])])
	return _set_text(_label, "\n".join(lines))


func handle(action: StringName, _sim: SimRoot, _player: int) -> bool:
	var list: Array[String] = entries()
	match action:
		&"device_up":
			_cursor = maxi(0, _cursor - 1)
		&"device_down":
			_cursor = mini(list.size() - 1, _cursor + 1)
		&"device_select":
			var entry: String = list[clampi(_cursor, 0, list.size() - 1)]
			if entry == "save":
				submit(KIND_SAVE, {})
			else:
				submit(KIND_OPEN, {"path": entry})
		_:
			return false
	return true


func prompts(glyphs: InputGlyphs) -> String:
	return glyphs.line([[&"device_up", "up"], [&"device_down", "down"], [&"device_select", "save / open"]])
