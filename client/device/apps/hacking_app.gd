## The hacking app (M6 spec claim 13; gated on the daemon coprocessor since G5): the
## terminals and spoofable sensors within reach, nearest first, with what each will
## take; select hacks a terminal (or logs out of one this player left logged in) or
## spoofs a sensor, secondary logs out. While an action runs the pane shows its
## progress and, for a hack, how far it is heard. It reads the sim and submits
## commands: the targets are rebuilt from the sim every refresh.
class_name HackingApp extends DeviceApp

## How far off a target is listed; hacking it still needs the player beside it.
const REACH_MM: int = 12000

var _cursor: int = 0
var _label: RichTextLabel


func _init() -> void:
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.add_theme_font_size_override("normal_font_size", DeviceShell.BODY_PX)
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_label)


## [[kind ("terminal" | "sensor"), id, distance mm], ...] within reach, nearest first.
static func targets(sim: SimRoot, player: int) -> Array[Array]:
	var hacks: HackSystem = SimAssembly.hacks_of(sim)
	var sensors: SensorSystem = SimAssembly.sensors_of(sim)
	var here: Vector3i = SimAssembly.actors_of(sim).position_of(player)
	var out: Array[Array] = []
	for terminal: int in hacks.terminal_ids():
		var d: int = PerceptionSystem.distance_mm(here, hacks.terminal_position(terminal))
		if d <= REACH_MM:
			out.append(["terminal", terminal, d])
	for sensor: int in sensors.sensor_ids():
		if not sensors.is_spoofable(sensor):
			continue
		var c: Vector3i = sensors.cells_of(sensor)[0]
		var d: int = PerceptionSystem.distance_mm(here, BuildSystem.cell_centre(c))
		if d <= REACH_MM:
			out.append(["sensor", sensor, d])
	out.sort_custom(func(a: Array, b: Array) -> bool:
		var da: int = a[2]
		var db: int = b[2]
		var ia: int = a[1]
		var ib: int = b[1]
		return da < db or (da == db and ia < ib))
	return out


func refresh(sim: SimRoot, player: int) -> bool:
	var hacks: HackSystem = SimAssembly.hacks_of(sim)
	var sensors: SensorSystem = SimAssembly.sensors_of(sim)
	var lines: PackedStringArray = PackedStringArray()
	var kind: String = hacks.action_kind(player)
	if not kind.is_empty():
		var progress: Array[int] = hacks.progress_of(player)
		var done: int = progress[0]
		var total: int = progress[1]
		var percent: int = done * 100 / total
		var bar: String = "#".repeat(percent / 10) + "-".repeat(10 - percent / 10)
		var target: int = hacks.action_target(player)
		var name: String = String(hacks.terminal_name(target)) if kind != HackSystem.KIND_SPOOF else String(sensors.profile_of(target))
		lines.append("[color=#ff9e64]%s %s   [%s] %d%%[/color]" % [kind, name, bar, percent])
		if kind == HackSystem.KIND_HACK:
			lines.append("[font_size=%d]    heard %d m around you. Hold still.[/font_size]" % [DeviceShell.SECONDARY_PX, hacks.terminal_noise_mm(target) / 1000])
		else:
			lines.append("[font_size=%d]    hold still[/font_size]" % DeviceShell.SECONDARY_PX)
	var list: Array[Array] = targets(sim, player)
	if list.is_empty():
		lines.append("No terminal or sensor in reach.")
		return _set_text(_label, "\n".join(lines))
	_cursor = clampi(_cursor, 0, list.size() - 1)
	for i: int in list.size():
		var entry: Array = list[i]
		var what: String = entry[0]
		var id: int = entry[1]
		var d: int = entry[2]
		var head: String = ""
		if what == "terminal":
			var state: String = "ready"
			if hacks.logged_in_by(id) == player:
				state = "logged in: log out"
			elif hacks.is_hacked(id):
				state = "done"
			head = "%s   terminal   %d m   [%s]" % [hacks.terminal_name(id), d / 1000, state]
		else:
			head = "%s   sensor   %d m   [%s]" % [sensors.profile_of(id), d / 1000, "quiet" if sensors.is_spoofed(id) else "spoof"]
		lines.append(("[color=#ffd866]> %s[/color]" if i == _cursor else "  %s") % head)
	return _set_text(_label, "\n".join(lines))


func handle(action: StringName, sim: SimRoot, player: int) -> bool:
	var list: Array[Array] = targets(sim, player)
	if list.is_empty():
		return false
	var entry: Array = list[clampi(_cursor, 0, list.size() - 1)]
	var what: String = entry[0]
	var id: int = entry[1]
	var hacks: HackSystem = SimAssembly.hacks_of(sim)
	match action:
		&"device_up":
			_cursor = posmod(_cursor - 1, list.size())
			return true
		&"device_down":
			_cursor = posmod(_cursor + 1, list.size())
			return true
		&"device_select":
			if what == "sensor":
				submit(HackSystem.COMMAND_SPOOF, {"actor": player, "sensor": id})
			elif hacks.logged_in_by(id) == player:
				submit(HackSystem.COMMAND_LOGOUT, {"actor": player, "terminal": id})
			elif hacks.is_hacked(id):
				note("already done")
			else:
				submit(HackSystem.COMMAND_START, {"actor": player, "terminal": id})
			return true
		&"device_secondary":
			if what == "terminal" and hacks.logged_in_by(id) == player:
				submit(HackSystem.COMMAND_LOGOUT, {"actor": player, "terminal": id})
			else:
				note("nothing to log out of")
			return true
	return false


func prompts(glyphs: InputGlyphs) -> String:
	return glyphs.line([[&"device_up", "up"], [&"device_down", "down"], [&"device_select", "hack"], [&"device_secondary", "log out"]])
