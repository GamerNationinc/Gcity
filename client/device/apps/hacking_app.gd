## The hacking app (the G5 extension exercise): gated on the daemon coprocessor,
## which nothing else provides. The hacking itself arrives with Cold Storage (M6).
class_name HackingApp extends DeviceApp

var _label: RichTextLabel


func _init() -> void:
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.add_theme_font_size_override("normal_font_size", DeviceShell.BODY_PX)
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_label)


func refresh(sim: SimRoot, player: int) -> bool:
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var stats: StatResolver = SimAssembly.stats_of(sim)
	var device: int = actors.device_of(player)
	var memory: int = stats.resolve(device, &"memory_capacity") / 1000 if device != EntityIds.NONE else 0
	return _set_text(_label, "No terminal in reach.\n[font_size=%d]%d concurrent daemons of memory.\nTerminals arrive with Cold Storage (M6).[/font_size]" % [DeviceShell.SECONDARY_PX, memory])


func prompts(_glyphs: InputGlyphs) -> String:
	return "needs a daemon coprocessor: fitted"
