## The comms app (M5 spec claim 3): the radio traffic the sim carries. At M5 that is
## the squads' state: reports in flight, deliveries, and who is alerted to you.
class_name CommsApp extends DeviceApp

var _label: RichTextLabel


func _init() -> void:
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.add_theme_font_size_override("normal_font_size", DeviceShell.BODY_PX)
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_label)


func refresh(sim: SimRoot, player: int) -> bool:
	var squads: SquadSystem = SimAssembly.squads_of(sim)
	var perception: PerceptionSystem = SimAssembly.perception_of(sim)
	var stances: StanceSystem = SimAssembly.stances_of(sim)
	var stats: StatResolver = SimAssembly.stats_of(sim)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var device: int = actors.device_of(player)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("antenna gain: %d m   reports delivered: %d   in flight: %d" % [stats.resolve(device, &"antenna_gain") / 1000 if device != EntityIds.NONE else 0, squads.delivered_count(), squads.pending_count()])
	var agents: Array[int] = perception.agent_ids()
	if agents.is_empty():
		lines.append("[font_size=%d]no traffic[/font_size]" % DeviceShell.SECONDARY_PX)
	for agent: int in agents:
		if not actors.is_alive(agent):
			continue
		lines.append("[font_size=%d]squad %d  #%d  %s  %s%s[/font_size]" % [DeviceShell.SECONDARY_PX, perception.squad_of(agent), agent, stances.stance_of(agent),
			"radio" if squads.has_radio(agent) else "no radio", "   ALERTED to you" if perception.is_alerted(agent, player) else ""])
	return _set_text(_label, "\n".join(lines))


func prompts(_glyphs: InputGlyphs) -> String:
	return "read-only: what the sim's radios carry"
