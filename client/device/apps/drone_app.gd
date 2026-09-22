## The drone app (M5 spec claim 3): exists to prove the hardware gate. It is offered
## only when the carried device provides `radio`; the drones themselves are M7.
class_name DroneApp extends DeviceApp

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
	var gain: int = stats.resolve(device, &"antenna_gain") / 1000 if device != EntityIds.NONE else 0
	return _set_text(_label, "No drone in range.\n[font_size=%d]link budget: %d m of antenna, %d %% battery reserve.\nDrones arrive with the route graph (M7).[/font_size]" % [DeviceShell.SECONDARY_PX, gain, stats.resolve(device, &"battery_reserve") / 10 if device != EntityIds.NONE else 0])


func prompts(_glyphs: InputGlyphs) -> String:
	return "needs a radio module: fitted"
