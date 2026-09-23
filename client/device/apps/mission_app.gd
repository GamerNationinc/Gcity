## The mission app (M6 spec claim 13): the contract and how far it has got, the four
## counters the run is being scored by while it is happening, the summary when it is
## over, and — when the worst has happened — where the body is and what it will cost
## to go back for it.
##
## The counters are shown while the run is on, not only at the end, because a stealth
## score the player cannot see until they are paid is a score they cannot play against.
class_name MissionApp extends DeviceApp

const CURVE_FALLBACK: StringName = &"fixer_standard"

var _label: RichTextLabel


func _init() -> void:
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.add_theme_font_size_override("normal_font_size", DeviceShell.BODY_PX)
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_label)


func refresh(sim: SimRoot, player: int) -> bool:
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	if not actors.is_alive(player):
		return _set_text(_label, "\n".join(_death_screen(sim, player)))
	return _set_text(_label, "\n".join(_mission_screen(sim, player)))


## What the player sees while they are on their feet: the contract, then the run.
func _mission_screen(sim: SimRoot, player: int) -> PackedStringArray:
	var quests: QuestSystem = SimAssembly.quests_of(sim)
	var score: RunScoreSystem = SimAssembly.score_of(sim)
	var content: ContentDb = sim.get_system(&"content")
	var lines: PackedStringArray = PackedStringArray()
	var on_record: Array[StringName] = quests.quests_of(player)
	if on_record.is_empty():
		lines.append("No contract accepted.")
		lines.append(_dim("Take one in the quests app."))
	for quest: StringName in on_record:
		var t: Dictionary = content.get_entry(QuestSystem.KIND_QUEST, quest)
		var status: String = quests.status_of(player, quest)
		lines.append("[color=#ffd866]%s[/color]   [%s]" % [t["title"], status])
		var objectives: Array = t["objectives"]
		var progress: Array[int] = quests.progress_of(player, quest)
		for j: int in objectives.size():
			var o: Dictionary = objectives[j]
			var count: int = o["count"]
			var done: int = progress[j] if j < progress.size() else 0
			lines.append(_dim("  %s %s   %d / %d" % ["✓" if done >= count else "·", o["description"], done, count]))
		var terms: Dictionary = quests.turn_in_of(quest)
		if not terms.is_empty():
			var where: String = terms["parcel"]
			if status == QuestSystem.STATUS_READY:
				lines.append(_dim("  done. hand it in at %s" % where))
			lines.append(_dim("  pays %d × %s, priced by %s" % [terms["notes"], terms["currency"], terms["curve"]]))
	lines.append("")
	lines.append_array(_run_lines(sim, player, score))
	return lines


## The four counters, live while the run is on and frozen once it is over, with what
## the curve makes of them.
func _run_lines(sim: SimRoot, player: int, score: RunScoreSystem) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if not score.has_run(player):
		lines.append(_dim("No run in progress."))
		return lines
	var running: bool = score.is_running(player)
	var counters: Array[int] = score.counters(player)
	var curve: StringName = _curve_of(sim, player)
	var multiplier: int = score.multiplier(player, curve)
	lines.append("[color=#ffd866]%s[/color]" % ("Run in progress" if running else "Run scored"))
	lines.append("  seen %d   alarms %d   bodies %d   traces %d" % [counters[0], counters[1], counters[2], counters[3]])
	if score.is_clean(player):
		lines.append("  [color=#7ee787]nobody saw you[/color]   payout ×%s" % _permille(multiplier))
	else:
		lines.append("  payout ×%s" % _permille(multiplier))
	var payout: int = _payout_of(sim, player, multiplier)
	if payout > 0:
		lines.append(_dim("  that is %d credits at the counter" % payout))
	return lines


## Where the body is, what is on it, and what the law is holding.
func _death_screen(sim: SimRoot, player: int) -> PackedStringArray:
	var corpses: CorpseSystem = SimAssembly.corpses_of(sim)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[color=#ff7b72]You are dead.[/color]")
	var corpse: int = corpses.corpse_of(player)
	if corpse == EntityIds.NONE:
		lines.append(_dim("No body was left."))
		return lines
	var on_it: int = corpses.items_on(corpse).size()
	var cell: Vector3i = BuildSystem.cell_of(corpses.position_of(corpse))
	lines.append("  your body is at %d, %d, %d with %d item%s on it" % [cell.x, cell.y, cell.z, on_it, "" if on_it == 1 else "s"])
	lines.append("")
	lines.append(_dim("Where you died decides what you get back. Inside the law's reach"))
	lines.append(_dim("some of the kit is at the station for a fee, out of your own money."))
	lines.append(_dim("Anywhere else it is all still lying there, and the walk is the price."))
	lines.append("")
	lines.append("[color=#ffd866]Select: come back[/color]")
	return lines


func handle(action: StringName, sim: SimRoot, player: int) -> bool:
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	if action != &"device_select":
		return false
	if actors.is_alive(player):
		note("nothing to do here")
		return true
	submit(&"actor.respawn", {"actor": player})
	return true


func prompts(glyphs: InputGlyphs) -> String:
	return "%s come back" % glyphs.glyph(&"device_select")


## The curve the player's contract is priced by, or the standard one.
func _curve_of(sim: SimRoot, player: int) -> StringName:
	var quests: QuestSystem = SimAssembly.quests_of(sim)
	for quest: StringName in quests.quests_of(player):
		var terms: Dictionary = quests.turn_in_of(quest)
		if not terms.is_empty():
			var curve: String = terms["curve"]
			return StringName(curve)
	return CURVE_FALLBACK


## What the contract would pay at this multiplier, in credits.
func _payout_of(sim: SimRoot, player: int, multiplier: int) -> int:
	var quests: QuestSystem = SimAssembly.quests_of(sim)
	var items: ItemSystem = SimAssembly.items_of(sim)
	for quest: StringName in quests.quests_of(player):
		var terms: Dictionary = quests.turn_in_of(quest)
		if terms.is_empty():
			continue
		var notes: int = terms["notes"]
		var currency_s: String = terms["currency"]
		var paid: int = maxi(1, notes * multiplier / QuestSystem.PAYOUT_ONE)
		return paid * items.face_value_of_template(StringName(currency_s))
	return 0


static func _permille(value: int) -> String:
	return "%d.%02d" % [value / 1000, (value % 1000) / 10]


static func _dim(text: String) -> String:
	return "[font_size=%d]%s[/font_size]" % [DeviceShell.SECONDARY_PX, text]
