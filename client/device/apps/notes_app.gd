## The notes app (the G5 extension exercise): what the sim knows about the player,
## in one pane. Content named it; this view is its one registration.
class_name NotesApp extends DeviceApp

var _label: RichTextLabel


func _init() -> void:
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.add_theme_font_size_override("normal_font_size", DeviceShell.BODY_PX)
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_label)


func refresh(sim: SimRoot, player: int) -> bool:
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var items: ItemSystem = SimAssembly.items_of(sim)
	var progression: ProgressionSystem = SimAssembly.progression_of(sim)
	var land: LandSystem = SimAssembly.land_of(sim)
	var lines: PackedStringArray = PackedStringArray()
	var health: Dictionary = actors.health_of(player)
	var parts: PackedStringArray = PackedStringArray()
	for node: StringName in health:
		parts.append("%s %d / %d" % [node, health[node] / 1000, actors.max_health(player, node) / 1000])
	lines.append("condition: %s" % " ".join(parts))
	lines.append("[font_size=%d]carrying %d items; standing on %s[/font_size]" % [DeviceShell.SECONDARY_PX, items.items_in(ItemSystem.inventory_of(player)).size(), land.parcel_at(actors.position_of(player))])
	for skill: StringName in progression.skill_ids():
		lines.append("[font_size=%d]%s: %d xp, level %d[/font_size]" % [DeviceShell.SECONDARY_PX, skill, progression.xp_of(player, skill), progression.level_of(player, skill)])
	return _set_text(_label, "\n".join(lines))


func prompts(_glyphs: InputGlyphs) -> String:
	return "read-only"
