## The Steam client's presence, or its absence (M5 spec claim 10; standards §8.2).
## Initialises Steamworks through the pinned GodotSteam GDExtension with the app id
## from `tools/godotsteam.pin` when the Steam client is running, pumps its callbacks,
## and reports "offline" otherwise: the game never requires Steam to run, and nothing
## in the sim knows Steam exists. Steam Input: the in-game action manifest
## (`steam_input/game_actions.vdf`) is registered when Steam is up; until the app id
## is ours, the action sets resolve to nothing and the input map is the fallback.
class_name SteamHost extends Node

const PIN_PATH: String = "res://tools/godotsteam.pin"
const MANIFEST_PATH: String = "res://steam_input/game_actions.vdf"
## Steam Input's controller types (ESteamInputType) that carry Deck glyph names.
const INPUT_TYPE_STEAM_DECK: int = 13

var _online: bool = false
var _app_id: int = 0
var _status: String = "not started"
var _persona: String = ""
var _controller_type: int = 0
var _world_set: int = 0
var _device_set: int = 0


func _ready() -> void:
	_app_id = _read_app_id()
	if not Engine.has_singleton("Steam"):
		_status = "GodotSteam not loaded (run tools/godotsteam.sh)"
		return
	var steam: Object = Engine.get_singleton("Steam")
	var result: Variant = steam.call("steamInitEx", _app_id, true)
	if typeof(result) != TYPE_DICTIONARY:
		_status = "init returned %s" % var_to_str(result)
		return
	var r: Dictionary = result
	var status: int = r.get("status", -1)
	if status != 0:
		_status = "offline: %s" % r.get("verbal", "status %d" % status)
		return
	_online = true
	_status = "online, app %d" % _app_id
	var name_v: Variant = steam.call("getPersonaName")
	_persona = str(name_v)
	var manifest: String = ProjectSettings.globalize_path(MANIFEST_PATH)
	if FileAccess.file_exists(MANIFEST_PATH):
		steam.call("setInputActionManifestFilePath", manifest)
	var input_ok: Variant = steam.call("inputInit", false)
	if typeof(input_ok) == TYPE_BOOL and input_ok:
		_world_set = _as_int(steam.call("getActionSetHandle", "world"))
		_device_set = _as_int(steam.call("getActionSetHandle", "device"))
		_refresh_controllers(steam)


func _process(_delta: float) -> void:
	if _online:
		var steam: Object = Engine.get_singleton("Steam")
		steam.call("run_callbacks")


func _exit_tree() -> void:
	if _online:
		var steam: Object = Engine.get_singleton("Steam")
		steam.call("inputShutdown")
		steam.call("steamShutdown")


func _refresh_controllers(steam: Object) -> void:
	var handles: Variant = steam.call("getConnectedControllers")
	if typeof(handles) != TYPE_ARRAY:
		return
	var list: Array = handles
	if list.is_empty():
		return
	var first: int = _as_int(list[0])
	_controller_type = _as_int(steam.call("getInputTypeForHandle", first))


## Activates the `world` or `device` action set on every controller when the action
## manifest resolved; a no-op otherwise (the input map carries the same actions).
func activate_action_set(device: bool) -> void:
	if not _online:
		return
	var handle: int = _device_set if device else _world_set
	if handle == 0:
		return
	var steam: Object = Engine.get_singleton("Steam")
	var handles: Variant = steam.call("getConnectedControllers")
	if typeof(handles) != TYPE_ARRAY:
		return
	for h: Variant in handles:
		steam.call("activateActionSet", _as_int(h), handle)


func is_online() -> bool:
	return _online


func status() -> String:
	return _status


func persona() -> String:
	return _persona


func app_id() -> int:
	return _app_id


## Whether the connected controller reports as a Steam Deck (its glyph names differ
## from an Xbox pad's); when Steam is down, the machine itself is asked.
func is_deck() -> bool:
	if _online and _controller_type != 0:
		return _controller_type == INPUT_TYPE_STEAM_DECK
	return OS.get_environment("SteamDeck") == "1" or OS.get_processor_name().contains("AMD Custom APU")


func has_action_sets() -> bool:
	return _world_set != 0 and _device_set != 0


func cloud_enabled() -> bool:
	if not _online:
		return false
	var steam: Object = Engine.get_singleton("Steam")
	var app_v: Variant = steam.call("isCloudEnabledForApp")
	var account_v: Variant = steam.call("isCloudEnabledForAccount")
	return typeof(app_v) == TYPE_BOOL and app_v and typeof(account_v) == TYPE_BOOL and account_v


static func _as_int(v: Variant) -> int:
	if typeof(v) == TYPE_INT:
		var i: int = v
		return i
	if typeof(v) == TYPE_FLOAT:
		var f: float = v
		return int(f)
	return 0


## STEAM_APP_ID from the pin file, or 0 (Steam refuses 0, which is the right outcome
## for a build with no pin).
static func _read_app_id() -> int:
	var file: FileAccess = FileAccess.open(PIN_PATH, FileAccess.READ)
	if file == null:
		return 0
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.begins_with("STEAM_APP_ID="):
			return line.trim_prefix("STEAM_APP_ID=").to_int()
	return 0
