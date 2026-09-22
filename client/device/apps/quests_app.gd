## The quests app (M5 spec claims 3, 9): every quest on record with its status and
## objectives; select accepts, secondary abandons. Offers are the director's (M6).
class_name QuestsApp extends DeviceApp

var _cursor: int = 0
var _label: RichTextLabel


func _init() -> void:
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.add_theme_font_size_override("normal_font_size", DeviceShell.BODY_PX)
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_label)


func refresh(sim: SimRoot, player: int) -> bool:
	var quests: QuestSystem = SimAssembly.quests_of(sim)
	var content: ContentDb = sim.get_system(&"content")
	var ids: Array[StringName] = quests.quest_ids()
	if ids.is_empty():
		return _set_text(_label, "No contracts on record.")
	_cursor = clampi(_cursor, 0, ids.size() - 1)
	var lines: PackedStringArray = PackedStringArray()
	for i: int in ids.size():
		var t: Dictionary = content.get_entry(QuestSystem.KIND_QUEST, ids[i])
		var status: String = quests.status_of(player, ids[i])
		var head: String = "%s   [%s]" % [t["title"], status if not status.is_empty() else "offered"]
		lines.append(("[color=#ffd866]> %s[/color]" if i == _cursor else "  %s") % head)
		if i == _cursor:
			lines.append("[font_size=%d]    %s[/font_size]" % [DeviceShell.SECONDARY_PX, t["text"]])
			var objectives: Array = t["objectives"]
			var progress: Array[int] = quests.progress_of(player, ids[i])
			for j: int in objectives.size():
				var o: Dictionary = objectives[j]
				var count: int = o["count"]
				lines.append("[font_size=%d]    · %s   %d / %d[/font_size]" % [DeviceShell.SECONDARY_PX, o["description"], progress[j] if j < progress.size() else 0, count])
			var reward: Array = t["reward"]
			var reward_text: PackedStringArray = PackedStringArray()
			for r: Variant in reward:
				var rd: Dictionary = r
				reward_text.append("%s ×%d" % [rd["template"], rd["count"]])
			lines.append("[font_size=%d]    reward: %s[/font_size]" % [DeviceShell.SECONDARY_PX, ", ".join(reward_text)])
	return _set_text(_label, "\n".join(lines))


func handle(action: StringName, sim: SimRoot, player: int) -> bool:
	var quests: QuestSystem = SimAssembly.quests_of(sim)
	var ids: Array[StringName] = quests.quest_ids()
	if ids.is_empty():
		return false
	var quest: StringName = ids[clampi(_cursor, 0, ids.size() - 1)]
	match action:
		&"device_up":
			_cursor = maxi(_cursor - 1, 0)
			return true
		&"device_down":
			_cursor = mini(_cursor + 1, ids.size() - 1)
			return true
		&"device_select":
			if quests.status_of(player, quest).is_empty():
				submit(&"quest.accept", {"actor": player, "quest": String(quest)})
			else:
				note("already on record")
			return true
		&"device_secondary":
			if quests.status_of(player, quest) == QuestSystem.STATUS_ACTIVE:
				submit(&"quest.abandon", {"actor": player, "quest": String(quest)})
			else:
				note("nothing to abandon")
			return true
	return false


func prompts(glyphs: InputGlyphs) -> String:
	return glyphs.line([[&"device_up", "up"], [&"device_down", "down"], [&"device_select", "accept"], [&"device_secondary", "abandon"]])
