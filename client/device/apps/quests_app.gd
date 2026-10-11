## The quests app (M5 spec claims 3, 9): every quest on record with its status and
## objectives; select accepts, secondary abandons. Offers are the director's (M6). A
## contract (a quest with a fixer) shows the fixer's briefing and, while it runs, its
## four counters live and the tier and credits they would pay now (M6 claim 19).
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
			lines.append_array(_contract_lines(quests, content, player, ids[i], t))
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


## The briefing, the run's counters and the pay now, for a contract; nothing otherwise.
static func _contract_lines(quests: QuestSystem, content: ContentDb, player: int, quest: StringName, t: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var giver_v: Variant = t.get("giver", "")
	var giver: String = giver_v if typeof(giver_v) == TYPE_STRING else ""
	if giver.is_empty():
		return out
	var f: Dictionary = content.get_entry(QuestSystem.KIND_FIXER, StringName(giver))
	var lines: Dictionary = f["lines"]
	out.append("[font_size=%d]    %s: \"%s\"[/font_size]" % [DeviceShell.SECONDARY_PX, f["name"], lines["briefing"]])
	var run: Dictionary = quests.run_of(player, quest)
	if run.is_empty():
		return out
	var c: Dictionary = run["counters"]
	var exfil: bool = run["exfil"]
	var scoring: Dictionary = t["scoring"]
	out.append("[font_size=%d]    detected %d   alarms %d   bodies %d   traces %d%s[/font_size]" % [DeviceShell.SECONDARY_PX, c["times_detected"], c["alarms_raised"], c["bodies"], c["traces_left"], "   (out of the site)" if exfil else ""])
	var scored: Array = QuestSystem.score(scoring, c)
	var milli: int = scored[0]
	var tier: String = scored[1]
	var base: int = f["base_credits"]
	out.append("[font_size=%d]    pays now: %s x%d.%d = %d credits[/font_size]" % [DeviceShell.SECONDARY_PX, tier if not tier.is_empty() else "no tier", milli / 1000, milli % 1000 / 100, base * milli / 1000])
	return out


func handle(action: StringName, sim: SimRoot, player: int) -> bool:
	var quests: QuestSystem = SimAssembly.quests_of(sim)
	var ids: Array[StringName] = quests.quest_ids()
	if ids.is_empty():
		return false
	var quest: StringName = ids[clampi(_cursor, 0, ids.size() - 1)]
	match action:
		&"device_up":
			_cursor = posmod(_cursor - 1, ids.size())
			return true
		&"device_down":
			_cursor = posmod(_cursor + 1, ids.size())
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
