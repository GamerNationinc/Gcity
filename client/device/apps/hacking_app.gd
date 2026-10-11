## The hacking app (M6 spec claim 19; gated on the daemon coprocessor, the G5
## extension exercise): the daemon slots in use, then every target in reach and every
## terminal the player is logged in to, each with its state. Select starts a ready
## target or logs out of one held; secondary cancels the running hack. While a hack
## runs the pane shows a progress bar and asks the shell to go see-through, so the
## world stays visible behind it (the hack is interrupted by anything that happens
## there).
class_name HackingApp extends DeviceApp

const BAR: int = 20

var _cursor: int = 0
var _label: RichTextLabel


func _init() -> void:
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.add_theme_font_size_override("normal_font_size", DeviceShell.BODY_PX)
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_label)


## The targets listed: those in reach, then logged-in ones out of reach, by id.
static func _listed(hacks: HackSystem, player: int) -> Array[int]:
	var out: Array[int] = hacks.targets_in_reach(player)
	for id: int in hacks.logins_of(player):
		if not out.has(id):
			out.append(id)
	out.sort()
	return out


func refresh(sim: SimRoot, player: int) -> bool:
	var hacks: HackSystem = SimAssembly.hacks_of(sim)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("daemons %d / %d" % [hacks.slots_in_use(player), hacks.capacity(player)])
	var listed: Array[int] = _listed(hacks, player)
	if listed.is_empty():
		lines.append("No terminal in reach.")
		return _set_text(_label, "\n".join(lines))
	_cursor = clampi(_cursor, 0, listed.size() - 1)
	var running: int = hacks.running_target(player)
	var held: Array[int] = hacks.logins_of(player)
	for i: int in listed.size():
		var id: int = listed[i]
		var state: String = "ready   %d s" % (hacks.target_ticks(id) / SimRoot.TICK_HZ)
		if id == running:
			var total: int = hacks.target_ticks(id)
			var done: int = total - hacks.ticks_left(player)
			var filled: int = done * BAR / total
			state = "running   [%s%s] %d %%" % ["#".repeat(filled), "-".repeat(BAR - filled), done * 100 / total]
		elif held.has(id):
			state = "logged in"
		elif hacks.is_done(id):
			state = "done"
		var row: String = "%s   %s" % [String(hacks.target_name(id)).replace("_", " "), state]
		lines.append(("[color=#ffd866]> %s[/color]" if i == _cursor else "  %s") % row)
	return _set_text(_label, "\n".join(lines))


func see_through(sim: SimRoot, player: int) -> bool:
	return SimAssembly.hacks_of(sim).is_hacking(player)


func handle(action: StringName, sim: SimRoot, player: int) -> bool:
	var hacks: HackSystem = SimAssembly.hacks_of(sim)
	var listed: Array[int] = _listed(hacks, player)
	if action == &"device_secondary":
		if hacks.is_hacking(player):
			submit(HackSystem.COMMAND_CANCEL, {"actor": player})
		else:
			note("nothing running")
		return true
	if listed.is_empty():
		return false
	var target: int = listed[clampi(_cursor, 0, listed.size() - 1)]
	match action:
		&"device_up":
			_cursor = posmod(_cursor - 1, listed.size())
			return true
		&"device_down":
			_cursor = posmod(_cursor + 1, listed.size())
			return true
		&"device_select":
			if hacks.logins_of(player).has(target):
				submit(HackSystem.COMMAND_LOGOUT, {"actor": player, "target": target})
			elif hacks.is_hacking(player):
				note("a hack is running: stand still")
			elif hacks.is_done(target):
				note("already done")
			else:
				submit(HackSystem.COMMAND_START, {"actor": player, "target": target})
			return true
	return false


func prompts(glyphs: InputGlyphs) -> String:
	return glyphs.line([[&"device_up", "up"], [&"device_down", "down"], [&"device_select", "hack / log out"], [&"device_secondary", "cancel"]])
