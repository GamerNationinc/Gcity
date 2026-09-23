## The hacking app (M6 spec claim 6): the terminals in reach, the hack running on
## the one you chose, and how far it has to go. The device cannot pause on a site
## (ADR-006 C), so the progress bar runs with the world running and a guard walking:
## that is the mission's core tension, played rather than described.
class_name HackingApp extends DeviceApp

var _cursor: int = 0
var _label: RichTextLabel


func _init() -> void:
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.add_theme_font_size_override("normal_font_size", DeviceShell.BODY_PX)
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_label)


func refresh(sim: SimRoot, player: int) -> bool:
	var terminals: TerminalSystem = SimAssembly.terminals_of(sim)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var stats: StatResolver = SimAssembly.stats_of(sim)
	var content: ContentDb = sim.get_system(&"content")
	var device: int = actors.device_of(player)
	var reach: Array[int] = terminals.in_reach_of(player)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%d concurrent daemons   %d terminals in reach" % [stats.resolve(device, &"memory_capacity") / 1000 if device != EntityIds.NONE else 0, reach.size()])
	if reach.is_empty():
		lines.append("[font_size=%d]No terminal in reach. Stand beside one.[/font_size]" % DeviceShell.SECONDARY_PX)
		return _set_text(_label, "\n".join(lines))
	_cursor = clampi(_cursor, 0, reach.size() - 1)
	for i: int in reach.size():
		var terminal: int = reach[i]
		var t: Dictionary = content.get_entry(TerminalSystem.KIND_TERMINAL, terminals.template_of(terminal))
		var state: String = ""
		if terminals.is_hacked(terminal):
			state = "OPEN   (a trace: wipe it)"
		elif terminals.hacker_of(terminal) == player:
			var ticks: int = terminals.hack_ticks_of(terminal)
			var done: int = terminals.progress_of(terminal)
			state = "%s  %d %%   %.1f s left" % [_bar(done, ticks), done * 100 / ticks, float(ticks - done) / SimRoot.TICK_HZ]
		elif not terminals.can_hack(player, terminal):
			var requires_s: String = t["requires"]
			state = "locked: needs a %s in the device" % requires_s
		else:
			state = "ready"
		lines.append(("[color=#ffd866]> %s   %s[/color]" if i == _cursor else "  %s   %s") % [t["title"], state])
	return _set_text(_label, "\n".join(lines))


static func _bar(done: int, total: int) -> String:
	var filled: int = done * 20 / maxi(total, 1)
	return "[%s%s]" % ["=".repeat(filled), " ".repeat(20 - filled)]


func handle(action: StringName, sim: SimRoot, player: int) -> bool:
	var terminals: TerminalSystem = SimAssembly.terminals_of(sim)
	var reach: Array[int] = terminals.in_reach_of(player)
	if reach.is_empty():
		return false
	var terminal: int = reach[clampi(_cursor, 0, reach.size() - 1)]
	match action:
		&"device_up":
			_cursor = posmod(_cursor - 1, reach.size())
			return true
		&"device_down":
			_cursor = posmod(_cursor + 1, reach.size())
			return true
		&"device_select":
			if terminals.is_hacked(terminal):
				submit(&"terminal.wipe", {"actor": player, "terminal": terminal})
				note("wiping the log")
			elif terminals.hacker_of(terminal) == player:
				submit(&"terminal.hack_cancel", {"actor": player, "terminal": terminal})
				note("cancelled; the progress is gone")
			elif terminals.can_hack(player, terminal):
				submit(&"terminal.hack_start", {"actor": player, "terminal": terminal})
				note("stay in reach: moving away loses it")
			else:
				note("the device cannot talk to this one")
			return true
		&"device_secondary":
			if terminals.hacker_of(terminal) == player:
				submit(&"terminal.hack_cancel", {"actor": player, "terminal": terminal})
			return true
	return false


func prompts(glyphs: InputGlyphs) -> String:
	return glyphs.line([[&"device_up", "up"], [&"device_down", "down"], [&"device_select", "hack / wipe"], [&"device_secondary", "stop"]])
