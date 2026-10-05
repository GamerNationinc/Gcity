## The sandbox's spawn menu (M7.6 spec claim 2, decision 5): pages of what the content
## holds, listed from the content database, so a new weapon file appears here with no
## code: agents with every kit, items, and sites raised with their base at the cursor; and
## the trainer (claims 4–5): god mode, infinite ammo, fly, full health, teleport.
## D-pad left and right change the page, up and down choose, A spawns at the cursor.
## The pane asks the view through the shell's submit with `sandbox_ui.spawn`, which
## `client/sandbox/sandbox_mode.gd` turns into sim commands; it keeps nothing of the sim's.
class_name SandboxApp extends DeviceApp

const KIND_SPAWN: StringName = &"sandbox_ui.spawn"
const PAGES: Array[String] = ["agents", "items", "sites", "trainer", "ai", "time", "inspect", "record"]
const EFFECTS: Array[String] = ["god", "ammo", "fly"]
const EFFECT_NAMES: Dictionary = {"god": "god mode", "ammo": "infinite ammo", "fly": "fly (right trigger up, left down)"}
const ITEM_KINDS: Array[StringName] = [&"weapon_frame", &"weapon_part", &"ammo", &"device_frame", &"device_module"]
## Lines of the list shown at once, round the cursor.
const WINDOW: int = 12

var _label: RichTextLabel
var _page: int = 0
var _cursor: int = 0


func _init() -> void:
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.add_theme_font_size_override("normal_font_size", DeviceShell.SECONDARY_PX)
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_label)


## Every kit the content makes: each weapon frame with each magazine that fits it, full of
## each round of its calibre, as a site spawn's kit.
static func kits(content: ContentDb) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for frame: StringName in content.ids(ItemSystem.KIND_FRAME):
		var f: Dictionary = content.get_entry(ItemSystem.KIND_FRAME, frame)
		var calibre: String = f["calibre"]
		for part: StringName in content.ids(ItemSystem.KIND_PART):
			var p: Dictionary = content.get_entry(ItemSystem.KIND_PART, part)
			var fits: Array = p["fits"]
			var socket: String = p["socket"]
			if socket != "magazine" or not fits.has(String(frame)):
				continue
			var capacity: int = p["capacity"]
			for ammo: StringName in content.ids(ItemSystem.KIND_AMMO):
				if _is_round(content, ammo, calibre):
					out.append({"frame": String(frame), "magazine": String(part), "ammo": String(ammo), "rounds": capacity})
	return out


## Ammunition proper, of `calibre`: tokens and data ride on the ammo kind but are not rounds.
static func _is_round(content: ContentDb, ammo: StringName, calibre: String) -> bool:
	var a: Dictionary = content.get_entry(ItemSystem.KIND_AMMO, ammo)
	var tags: Array = a["tags"]
	var own: String = a["calibre"]
	return own == calibre and tags.has("ammo")


## One page's entries: what A spawns, each with the label it is listed by. The trainer
## page shows each effect's state for `player`, read from `sim` (null: all off).
static func entries(content: ContentDb, page: String, sim: SimRoot = null, player: int = 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if page == "record":
		out.append({"spawn": "record", "label": "save this session as a replay fixture (user://fixtures)"})
	elif page == "inspect":
		for overlay: String in SandboxInspector.OVERLAYS:
			out.append({"spawn": "inspect", "overlay": overlay, "label": "%s (on/off; the HUD lists what is on)" % SandboxInspector.NAMES[overlay]})
		out.append({"spawn": "inspect", "overlay": "all", "label": "every overlay on"})
		out.append({"spawn": "inspect", "overlay": "none", "label": "every overlay off"})
	elif page == "ai":
		for effect: String in SandboxSystem.AI_EFFECTS:
			for on: bool in [true, false]:
				out.append({"spawn": "ai", "effect": effect, "on": on, "label": "every guard %s%s" % ["" if on else "not ", effect]})
	elif page == "time":
		out.append({"spawn": "time", "step": true, "label": "step one tick (while held)"})
		for rate: Vector2i in LocalHost.RATES:
			var name: String = "hold" if rate.x == 0 else ("x%d" % rate.x if rate.y == 1 else "x1/%d" % rate.y)
			out.append({"spawn": "time", "step": false, "num": rate.x, "den": rate.y, "label": name})
	elif page == "trainer":
		for effect: String in EFFECTS:
			var on: bool = sim != null and SandboxAssembly.sandbox_of(sim).trainer_on(player, effect)
			out.append({"spawn": "trainer", "effect": effect, "on": not on, "label": "%s: %s" % [EFFECT_NAMES[effect], "ON" if on else "off"]})
		out.append({"spawn": "heal", "label": "full health"})
		out.append({"spawn": "teleport", "label": "teleport to the cursor"})
	elif page == "agents":
		var all_kits: Array[Dictionary] = kits(content)
		for profile: StringName in content.ids(PerceptionSystem.KIND_AGENT):
			out.append({"spawn": "agent", "profile": String(profile), "kit": {}, "label": "%s, unarmed" % profile})
			for kit: Dictionary in all_kits:
				out.append({"spawn": "agent", "profile": String(profile), "kit": kit,
					"label": "%s, %s with %s" % [profile, kit["frame"], kit["ammo"]]})
	elif page == "sites":
		for site: StringName in content.ids(SiteSystem.KIND_SITE):
			out.append({"spawn": "site", "site": String(site), "label": "%s, its base at the cursor" % site})
	else:
		for kind: StringName in ITEM_KINDS:
			for id: StringName in content.ids(kind):
				var t: Dictionary = content.get_entry(kind, id)
				var tags: Array = t.get("tags", [])
				var count: int = 15 if kind == ItemSystem.KIND_AMMO and tags.has("ammo") else 1
				out.append({"spawn": "item", "kind": String(kind), "template": String(id), "count": count,
					"label": "%s %s%s" % [kind, id, " x%d" % count if count > 1 else ""]})
	return out


func refresh(sim: SimRoot, player: int) -> bool:
	var list: Array[Dictionary] = entries(SimAssembly.content_of(sim), PAGES[_page], sim, player)
	_cursor = clampi(_cursor, 0, maxi(0, list.size() - 1))
	var lines: PackedStringArray = PackedStringArray()
	var tabs: PackedStringArray = PackedStringArray()
	for i: int in PAGES.size():
		tabs.append(("[ %s ]" if i == _page else "  %s  ") % PAGES[i])
	lines.append("  ".join(tabs))
	var first: int = clampi(_cursor - WINDOW / 2, 0, maxi(0, list.size() - WINDOW))
	for i: int in range(first, mini(list.size(), first + WINDOW)):
		var entry: Dictionary = list[i]
		lines.append("%s %s" % [">" if i == _cursor else " ", entry["label"]])
	lines.append("%d of %d" % [_cursor + 1, list.size()])
	return _set_text(_label, "\n".join(lines))


func focus() -> String:
	return "%s page: %s" % [PAGES[_page], super.focus()]


func handle(action: StringName, sim: SimRoot, player: int) -> bool:
	match action:
		&"device_left", &"device_right":
			_page = posmod(_page + (1 if action == &"device_right" else -1), PAGES.size())
			_cursor = 0
		&"device_up", &"device_down":
			var size: int = entries(SimAssembly.content_of(sim), PAGES[_page], sim, player).size()
			if size < 2:
				note("nothing else on this page")
				return true
			# wraps: at either end a press still moves
			_cursor = posmod(_cursor + (1 if action == &"device_down" else -1), size)
		&"device_select":
			var list: Array[Dictionary] = entries(SimAssembly.content_of(sim), PAGES[_page], sim, player)
			if list.is_empty():
				note("nothing on this page to spawn")
				return true
			var entry: Dictionary = list[clampi(_cursor, 0, list.size() - 1)].duplicate(true)
			entry.erase("label")
			submit(KIND_SPAWN, entry)
		_:
			return false
	return true


func prompts(glyphs: InputGlyphs) -> String:
	return glyphs.line([[&"device_left", "page"], [&"device_up", "choose"], [&"device_select", "spawn at the cursor"]])
