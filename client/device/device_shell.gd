## The device's shell (design doc §12.2; M5 spec claims 3–5, 8): an app strip, a
## secure indicator, the open app's pane and its prompts. The shell knows nothing of
## any app: apps are `content/device_app/` entries whose hardware requirement the
## equipped device provides, and their views are registered by id before the first
## refresh (`register_view`); an app with no registered view fails startup. Nothing
## of the sim's is kept between frames: `refresh` rebuilds from the sim and returns
## whether anything changed, so the viewport it lives in redraws only then (§12.4).
class_name DeviceShell extends Control

const KIND_APP: StringName = &"device_app"
const BODY_PX: int = 22
const SECONDARY_PX: int = 18
const WIDTH: int = 896
const HEIGHT: int = 560

var _views: Dictionary[StringName, PackedScene] = {}
var _content: ContentDb
var _submit: Callable = Callable()
var _open_app: StringName = &""
var _pane: DeviceApp = null
var _last_strip: String = ""
var _last_status: String = ""
var _last_prompts: String = ""
var _note_text: String = ""
var _note_shown: String = ""
var _glyphs: InputGlyphs = null

var _strip: Label
var _status: Label
var _pane_holder: Control
var _prompts: Label
var _note: Label


func setup(content: ContentDb, submit: Callable, glyphs: InputGlyphs) -> void:
	_content = content
	_submit = submit
	_glyphs = glyphs


func register_view(app: StringName, scene: PackedScene) -> void:
	_views[app] = scene


## Built in `_init`, not `_ready`: the headless test runner adds the shell to a tree
## that is not processing, and the panes must exist before the first refresh.
func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	size = Vector2(WIDTH, HEIGHT)
	var back := ColorRect.new()
	back.color = Color(0.07, 0.08, 0.1, 0.96)
	back.size = size
	add_child(back)
	_strip = _label(Vector2(24, 14), BODY_PX)
	_status = _label(Vector2(24, 50), SECONDARY_PX)
	_status.modulate = Color(0.8, 0.85, 0.9)
	_pane_holder = Control.new()
	_pane_holder.position = Vector2(24, 84)
	_pane_holder.size = Vector2(WIDTH - 48, HEIGHT - 84 - 64)
	add_child(_pane_holder)
	_prompts = _label(Vector2(24, HEIGHT - 58), SECONDARY_PX)
	_note = _label(Vector2(24, HEIGHT - 32), SECONDARY_PX)
	_note.modulate = Color(0.95, 0.85, 0.5)


func _label(at: Vector2, px: int) -> Label:
	var l := Label.new()
	l.position = at
	l.add_theme_font_size_override("font_size", px)
	add_child(l)
	return l


## The apps the equipped device offers, in content order: [{id, title, icon}].
func available_apps(sim: SimRoot, player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var items: ItemSystem = SimAssembly.items_of(sim)
	var device: int = actors.device_of(player)
	if device == EntityIds.NONE:
		return out
	var provides: Array[StringName] = items.provides_of(device)
	var entries: Array[Array] = []
	for id: StringName in _content.ids(KIND_APP):
		var t: Dictionary = _content.get_entry(KIND_APP, id)
		var requires_s: String = t["requires"]
		if not requires_s.is_empty() and not provides.has(StringName(requires_s)):
			continue
		var order: int = t["order"]
		entries.append([order, String(id)])
	entries.sort()
	for e: Array in entries:
		var id_s: String = e[1]
		var t: Dictionary = _content.get_entry(KIND_APP, StringName(id_s))
		out.append({"id": StringName(id_s), "title": t["title"], "icon": t["icon"]})
	return out


func open_app() -> StringName:
	return _open_app


func note(text: String) -> void:
	_note_text = text


## Rebuilds the shell from the sim. Returns true when anything visible changed.
func refresh(sim: SimRoot, player: int) -> bool:
	var changed: bool = false
	var apps: Array[Dictionary] = available_apps(sim, player)
	var ids: Array[StringName] = []
	for a: Dictionary in apps:
		ids.append(a["id"])
	if apps.is_empty():
		_open_app = &""
	elif not ids.has(_open_app):
		_open_app = ids[0]
	var strip: PackedStringArray = PackedStringArray()
	for a: Dictionary in apps:
		var id: StringName = a["id"]
		strip.append(("[ %s %s ]" if id == _open_app else "  %s %s  ") % [a["icon"], a["title"]])
	var strip_text: String = "  ".join(strip) if not apps.is_empty() else "no device carried"
	if strip_text != _last_strip:
		_last_strip = strip_text
		_strip.text = strip_text
		changed = true
	var land: LandSystem = SimAssembly.land_of(sim)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var rights: Dictionary = land.rights_at(actors.position_of(player), player)
	var safe: bool = rights[&"safe"]
	var status: String = "%s   tick %d   %s" % ["SECURE: time stopped" if sim.is_paused() else ("SECURE: safe to pause" if safe else "EXPOSED: time runs"), sim.get_tick(), "parcel %s" % land.parcel_at(actors.position_of(player))]
	if status != _last_status:
		_last_status = status
		_status.text = status
		changed = true
	if _pane != null and _pane.name != String(_open_app):
		_pane.queue_free()
		_pane = null
	if _pane == null and not _open_app.is_empty():
		assert(_views.has(_open_app), "app '%s' has no registered view" % _open_app)
		var scene: PackedScene = _views[_open_app]
		var instance: Node = scene.instantiate()
		_pane = instance
		_pane.name = String(_open_app)
		_pane.bind(_submit, note)
		_pane.size = _pane_holder.size
		_pane_holder.add_child(_pane)
		changed = true
	if _pane != null:
		if _pane.refresh(sim, player):
			changed = true
		var prompts: String = "%s   %s" % [_glyphs.line([[&"device_prev_app", "prev"], [&"device_next_app", "next"], [&"world_device", "lower"]]), _pane.prompts(_glyphs)]
		if prompts != _last_prompts:
			_last_prompts = prompts
			_prompts.text = prompts
			changed = true
	if _note_text != _note_shown:
		_note_shown = _note_text
		_note.text = _note_text
		changed = true
	return changed


## A device action. Returns "lower" when the shell wants the device lowered,
## "handled" when used, "" otherwise.
func handle(action: StringName, sim: SimRoot, player: int) -> String:
	var apps: Array[Dictionary] = available_apps(sim, player)
	if action == &"device_next_app" or action == &"device_prev_app":
		if apps.size() < 2:
			return "handled"
		var index: int = 0
		for i: int in apps.size():
			if apps[i]["id"] == _open_app:
				index = i
		index = posmod(index + (1 if action == &"device_next_app" else -1), apps.size())
		_open_app = apps[index]["id"]
		_note_text = ""
		return "handled"
	if _pane != null and _pane.handle(action, sim, player):
		return "handled"
	if action == &"device_back":
		return "lower"
	return ""
