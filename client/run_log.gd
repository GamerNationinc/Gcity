## A plain-text log of one run of the client, one file per launch, so that what happened
## on the Deck can be read back afterwards (CEOGG, Deck run 2026-10-01: "there should be
## a detailed log every time it runs so we know exactly what happened"). It records the
## machine and the launch, every action pressed and released, where the sticks point and
## which way that moves the player, every command the client submits and every one the
## sim rejects, what changed in the world the player can see, a heartbeat each second,
## and every engine error and warning. Lines are flushed once a frame, so a crash loses
## at most the frame it happened in.
##
## Files: `user://logs/runs/run-<date>_<time>.log` (on Linux
## `~/.local/share/godot/app_userdata/Gcity/logs/runs/`); the newest `KEEP` are kept.
class_name RunLog extends RefCounted

const DIR: String = "user://logs/runs"
const KEEP: int = 30

var _file: FileAccess
var _started_usec: int = Time.get_ticks_usec()
var _pending: PackedStringArray = PackedStringArray()
var _mutex: Mutex = Mutex.new()
var _engine_log: EngineLog


## Opens a new file and writes the header. Null if the file cannot be opened; the game
## runs without a log rather than not at all.
static func open(args: PackedStringArray) -> RunLog:
	DirAccess.make_dir_recursive_absolute(DIR)
	var stamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var path: String = "%s/run-%s.log" % [DIR, stamp]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("RunLog: cannot open %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return null
	var log := RunLog.new()
	log._file = file
	log._prune()
	log._header(path, args)
	log._engine_log = EngineLog.new(log)
	OS.add_logger(log._engine_log)
	return log


## One line: wall seconds since launch, the sim tick (-1 before there is one), a short
## category and the text.
func line(tick: int, category: String, text: String) -> void:
	var t: float = float(Time.get_ticks_usec() - _started_usec) / 1_000_000.0
	_mutex.lock()
	_pending.append("%9.3f  t%-6d %-8s %s" % [t, tick, category, text])
	_mutex.unlock()


## Writes what has been logged since the last flush. Called once a frame.
func flush() -> void:
	_mutex.lock()
	var lines: PackedStringArray = _pending
	_pending = PackedStringArray()
	_mutex.unlock()
	if lines.is_empty() or _file == null:
		return
	for entry: String in lines:
		_file.store_line(entry)
	_file.flush()


func close(tick: int, why: String) -> void:
	line(tick, "end", why)
	if _engine_log != null:
		OS.remove_logger(_engine_log)
		_engine_log = null
	flush()
	_file = null


func path() -> String:
	return _file.get_path_absolute() if _file != null else ""


func _header(path_: String, args: PackedStringArray) -> void:
	line(-1, "start", "Gcity run log, %s" % Time.get_datetime_string_from_system(false, true))
	line(-1, "start", "file %s" % ProjectSettings.globalize_path(path_))
	var version: Dictionary = Engine.get_version_info()
	line(-1, "build", "Godot %s, %s, game version %s" % [version["string"], "exported" if OS.has_feature("template") else "from the editor binary",
		ProjectSettings.get_setting("application/config/version", "unset")])
	line(-1, "build", "executable %s" % OS.get_executable_path())
	line(-1, "launch", "user args %s" % [args])
	line(-1, "machine", "%s %s, %s, %d cores" % [OS.get_name(), OS.get_version(), OS.get_processor_name(), OS.get_processor_count()])
	line(-1, "machine", "GPU %s (%s), %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_api_version()])
	var screen: int = DisplayServer.window_get_current_screen()
	line(-1, "machine", "screen %s at %.0f Hz, window %s" % [DisplayServer.screen_get_size(screen), DisplayServer.screen_get_refresh_rate(screen), DisplayServer.window_get_size()])
	line(-1, "machine", "Steam Deck env: SteamDeck=%s, SteamAppId=%s, SteamGameId=%s" % [OS.get_environment("SteamDeck"), OS.get_environment("SteamAppId"), OS.get_environment("SteamGameId")])
	joypads()
	flush()


## The connected controllers by name; logged at the start and on every change.
func joypads() -> void:
	var pads: Array[int] = Input.get_connected_joypads()
	if pads.is_empty():
		line(-1, "input", "controllers: none (the Deck's controls only reach the game as a pad through Steam Input)")
	for pad: int in pads:
		line(-1, "input", "controller %d: %s, guid %s" % [pad, Input.get_joy_name(pad), Input.get_joy_guid(pad)])


func _prune() -> void:
	var names: PackedStringArray = DirAccess.get_files_at(DIR)
	var runs: Array[String] = []
	for name: String in names:
		if name.begins_with("run-") and name.ends_with(".log"):
			runs.append(name)
	runs.sort()
	for i: int in maxi(0, runs.size() - KEEP):
		DirAccess.remove_absolute("%s/%s" % [DIR, runs[i]])


## The engine's own errors and warnings (script errors included) into the run log.
## Called from any thread, so it only queues; `RunLog.line` takes the lock.
class EngineLog extends Logger:
	var _owner: WeakRef

	func _init(owner: RunLog) -> void:
		_owner = weakref(owner)

	func _log_error(function: String, file: String, line_no: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var owner: RunLog = _owner.get_ref()
		if owner == null:
			return
		var kind: String = ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"][clampi(error_type, 0, 3)]
		var where: String = "%s:%d in %s" % [file, line_no, function]
		# a push_error's own place is in the engine; the script that called it is more use
		for trace: ScriptBacktrace in script_backtraces:
			if trace.get_frame_count() > 0:
				where = "%s:%d in %s" % [trace.get_frame_file(0), trace.get_frame_line(0), trace.get_frame_function(0)]
				break
		owner.line(-1, "engine", "%s: %s (%s)" % [kind, rationale if not rationale.is_empty() else code, where])

	func _log_message(message: String, error: bool) -> void:
		var owner: RunLog = _owner.get_ref()
		if owner == null:
			return
		owner.line(-1, "stderr" if error else "stdout", message.strip_edges())
