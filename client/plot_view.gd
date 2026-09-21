## The M2 plot view (spec claim 20): a top-down debug view of the parcels around the
## player, the container, its sockets and installed modules, and a panel with the
## resolved power and heat numbers. Input moves a cursor and submits commands; every
## number on screen is read from the sim, and the client writes no sim state.
##
## `--demo` after `--` plays a scripted sequence through the same action path;
## `--demo-quit=<s>` quits after that many seconds; `--screenshot=<path>` with
## `--screenshot-at=<s>` saves the rendered frame (tools/screenshot.sh).
extends Control

const M: int = 1000
const CONTAINER: StringName = &"container_20ft"
const EAST: StringName = &"neighbour_east"
const SAVE_SLOT: String = "plot"
const SAVE_DIR: String = "user://saves/" + SAVE_SLOT
const PX_PER_M: float = 24.0
## Screen position of world (-2 m, -2 m); z grows upward on screen.
const ORIGIN: Vector2 = Vector2(40.0, 760.0)
const CANVAS_RIGHT: float = 800.0

@onready var _host: LocalHost = $LocalHost
@onready var _status: Label = $Status

var _player: int = 0
var _setup_stage: int = 0
var _cursor: Vector3i = Vector3i(2 * M, 0, 4 * M)
var _templates: Array[StringName] = []
var _template_index: int = 0
var _log: Array[String] = []
var _demo: bool = false
var _demo_quit_s: float = -1.0
var _demo_t: float = 0.0
var _demo_next: int = 0
var _demo_script: Array = []
var _screenshot_path: String = ""
var _screenshot_at_s: float = -1.0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--demo":
			_demo = true
		elif arg.begins_with("--demo-quit="):
			_demo_quit_s = float(arg.trim_prefix("--demo-quit="))
		elif arg.begins_with("--screenshot="):
			_screenshot_path = arg.trim_prefix("--screenshot=")
		elif arg.begins_with("--screenshot-at="):
			_screenshot_at_s = float(arg.trim_prefix("--screenshot-at="))
	_templates = _host.content().ids(&"module")
	_demo_script = _build_demo_script()


## The scripted sequence: build out the container, hit a refusal, fix it, buy the
## neighbour, place a second container, save. Movement is client-side.
func _build_demo_script() -> Array:
	var script: Array = []
	var t: float = 1.0
	var add: Callable = func(action: String) -> void:
		script.append([t, action])
		t += 0.15
	add.call("place")
	add.call("install")           # power rack at (0, 0)
	add.call("next_module")       # sustainment
	add.call("next_module")       # work station
	add.call("right"); add.call("right")
	add.call("install")           # work station at (2, 0)
	add.call("next_module")       # hydroponics
	add.call("next_module")       # power rack
	add.call("next_module")       # sustainment
	add.call("right"); add.call("right"); add.call("right")
	add.call("install")           # sustainment at (5, 0)
	for _i: int in 5:
		add.call("left")
	add.call("up")
	add.call("install")           # sustainment at (0, 1)
	add.call("next_module")       # hydroponics
	add.call("install")           # refused: no room
	add.call("next_module"); add.call("next_module"); add.call("next_module")
	add.call("next_module")       # hydroponics again after a full cycle
	add.call("remove")            # sustainment at (0, 1) goes
	add.call("install")           # hydroponics at (0, 1)
	add.call("transfer")
	for _i: int in 20:
		add.call("right")
	add.call("down")
	add.call("place")             # second container on the bought neighbour
	add.call("save")
	return script


func _process(delta: float) -> void:
	var sim: SimRoot = _host.sim()
	_advance_setup(sim)
	if _demo:
		_demo_t += delta
		# One action per frame: a command submitted this frame applies on the next
		# tick, and later actions may depend on what it produced.
		if _demo_next < _demo_script.size():
			var step: Array = _demo_script[_demo_next]
			var at: float = step[0]
			if _demo_t >= at:
				var action: String = step[1]
				_perform(action)
				_demo_next += 1
		if not _screenshot_path.is_empty() and _demo_t >= _screenshot_at_s:
			_render(sim)
			queue_redraw()
			await RenderingServer.frame_post_draw
			_save_screenshot()
		if _demo_quit_s > 0.0 and _demo_t >= _demo_quit_s:
			get_tree().quit()
			return
	_render(sim)
	queue_redraw()


func _save_screenshot() -> void:
	var path: String = _screenshot_path
	_screenshot_path = ""
	var image: Image = get_viewport().get_texture().get_image()
	var err: Error = image.save_png(path)
	if err != OK:
		push_error("screenshot: cannot save %s: %s" % [path, error_string(err)])
		return
	print("screenshot saved: %s" % path)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	for action: String in ["up", "down", "left", "right", "place", "install", "remove", "next_module", "transfer", "save", "load"]:
		if event.is_action("plot_" + action):
			_perform(action)
			return


## Spawns the player, identifies them and hands them the plot, over the first ticks.
func _advance_setup(sim: SimRoot) -> void:
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	match _setup_stage:
		0:
			_submit(sim, &"actor.spawn", {"profile": "arcade", "range_m": 0})
			_setup_stage = 1
		1:
			var ids: Array[int] = actors.actor_ids()
			if ids.is_empty():
				return
			_player = ids[0]
			_submit(sim, &"land.identify", {"actor": _player, "owner": "player"})
			_submit(sim, &"land.transfer", {"parcel": "starter_plot", "owner": "player"})
			_setup_stage = 2
		2:
			if SimAssembly.land_of(sim).owner_of(&"starter_plot") == &"player":
				_note("t%d plot ready: player %d owns starter_plot" % [sim.get_tick(), _player])
				_setup_stage = 3


func _perform(action: String) -> void:
	if _setup_stage < 3:
		return
	var sim: SimRoot = _host.sim()
	var structures: StructureSystem = SimAssembly.structures_of(sim)
	var step: int = _pitch()
	match action:
		"up":
			_cursor.z += step
		"down":
			_cursor.z -= step
		"left":
			_cursor.x -= step
		"right":
			_cursor.x += step
		"place":
			_submit(sim, &"structure.place", {"actor": _player, "template": String(CONTAINER), "x": _cursor.x, "y": 0, "z": _cursor.z, "rotation": 0})
		"install":
			var s: int = _structure_under_cursor(structures)
			if s == 0:
				_note("no structure under the cursor")
				return
			var cell: Vector2i = _cell_under_cursor(structures, s)
			_submit(sim, &"module.install", {"actor": _player, "structure": s, "template": String(_templates[_template_index]), "col": cell.x, "row": cell.y})
		"remove":
			var s: int = _structure_under_cursor(structures)
			if s == 0:
				_note("no structure under the cursor")
				return
			var cell: Vector2i = _cell_under_cursor(structures, s)
			var occupied: Dictionary = structures.occupancy(s)
			var key: String = "%d,%d" % [cell.x, cell.y]
			if not occupied.has(key):
				_note("no module at (%d, %d)" % [cell.x, cell.y])
				return
			var module_id: int = occupied[key]
			_submit(sim, &"module.remove", {"actor": _player, "structure": s, "module": module_id})
		"next_module":
			_template_index = (_template_index + 1) % _templates.size()
		"transfer":
			_submit(sim, &"land.transfer", {"parcel": String(EAST), "owner": "player"})
		"save":
			_save_game(sim)
		"load":
			_load_game()
		_:
			_note("unknown action " + action)


func _pitch() -> int:
	var t: Dictionary = _host.content().get_entry(&"structure", CONTAINER)
	var sockets: Dictionary = t["sockets"]
	return sockets["pitch"]


func _structure_under_cursor(structures: StructureSystem) -> int:
	for id: int in structures.structure_ids():
		var r: Array[int] = structures.footprint_of(id)
		if _cursor.x >= r[0] and _cursor.x < r[2] and _cursor.z >= r[1] and _cursor.z < r[3]:
			return id
	return 0


func _cell_under_cursor(structures: StructureSystem, s: int) -> Vector2i:
	var origin: Vector3i = structures.position_of(s)
	var pitch: int = _pitch()
	return Vector2i((_cursor.x - origin.x) / pitch, (_cursor.z - origin.z) / pitch)


func _submit(sim: SimRoot, kind: StringName, payload: Dictionary) -> void:
	var err: Error = sim.submit(SimCommand.new(sim.get_tick() + 1, kind, payload))
	if err != OK:
		_note("submit %s failed: %s" % [kind, error_string(err)])


func _note(text: String) -> void:
	_log.append(text)
	if _log.size() > 6:
		_log.pop_front()


# ---------------------------------------------------------------- save and load

## Writes the Steam Cloud file set for this slot (docs/steam-cloud.md): the world
## first, then its meta record.
func _save_game(sim: SimRoot) -> void:
	var text: String = SaveFile.serialize(sim, _host.content().digest())
	if text.is_empty():
		_note("save failed: unserialisable state")
		return
	var err: Error = DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if err != OK:
		_note("save failed: %s" % error_string(err))
		return
	var world: FileAccess = FileAccess.open(SAVE_DIR + "/world.json", FileAccess.WRITE)
	if world == null:
		_note("save failed: %s" % error_string(FileAccess.get_open_error()))
		return
	world.store_string(text)
	world.close()
	var meta: Dictionary = {
		"schema_version": 1, "seed": sim.get_seed(), "tick": sim.get_tick(),
		"last_played_unix": int(Time.get_unix_time_from_system()),
		"game_version": ProjectSettings.get_setting("application/config/version", "dev"),
		"content_digest": _host.content().digest(), "save_schema_version": SaveFile.SCHEMA_VERSION,
	}
	var meta_file: FileAccess = FileAccess.open(SAVE_DIR + "/meta.json", FileAccess.WRITE)
	if meta_file == null:
		_note("meta write failed: %s" % error_string(FileAccess.get_open_error()))
		return
	meta_file.store_string(JSON.stringify(meta, "\t", true))
	meta_file.close()
	_note("saved %d bytes at tick %d to %s" % [text.length(), sim.get_tick(), SAVE_DIR])


func _load_game() -> void:
	var handle: FileAccess = FileAccess.open(SAVE_DIR + "/world.json", FileAccess.READ)
	if handle == null:
		_note("load failed: %s" % error_string(FileAccess.get_open_error()))
		return
	var file: SaveFile = SaveFile.parse(handle.get_as_text())
	if not file.is_valid():
		_note("load refused: %s" % file.error)
		return
	var sim: SimRoot = SimAssembly.load_save(file, _host.content())
	if sim == null:
		_note("load refused by the sim")
		return
	_host.adopt(sim)
	_note("loaded tick %d" % sim.get_tick())


# ---------------------------------------------------------------- rendering

func _to_screen(x: int, z: int) -> Vector2:
	return ORIGIN + Vector2((float(x) / M + 2.0) * PX_PER_M, -(float(z) / M + 2.0) * PX_PER_M)


func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, CANVAS_RIGHT, size.y), Color(0.09, 0.1, 0.12))
	if _setup_stage < 3:
		return
	var sim: SimRoot = _host.sim()
	var land: LandSystem = SimAssembly.land_of(sim)
	var structures: StructureSystem = SimAssembly.structures_of(sim)
	for id: StringName in land.parcel_ids():
		var record: Dictionary = land.parcel(id)
		var points: PackedVector2Array = PackedVector2Array()
		for v: Variant in record["footprint"]:
			var pair: Array = v
			var vx: int = pair[0]
			var vz: int = pair[1]
			points.append(_to_screen(vx, vz))
		var owner: StringName = record["owner"]
		var fill: Color = Color(0.2, 0.55, 0.3, 0.35) if owner == &"player" else (Color(0.6, 0.25, 0.2, 0.35) if not owner.is_empty() else Color(0.4, 0.4, 0.4, 0.25))
		draw_colored_polygon(points, fill)
		var outline: PackedVector2Array = points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, Color(0.9, 0.9, 0.9, 0.7), 2.0)
		draw_string(ThemeDB.fallback_font, points[0] + Vector2(6.0, -6.0), "%s  [%s]" % [id, owner if not owner.is_empty() else "unowned"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8))
	var pitch: int = _pitch()
	for s: int in structures.structure_ids():
		var r: Array[int] = structures.footprint_of(s)
		var top_left: Vector2 = _to_screen(r[0], r[3])
		var bottom_right: Vector2 = _to_screen(r[2], r[1])
		draw_rect(Rect2(top_left, bottom_right - top_left), Color(0.25, 0.45, 0.8, 0.5))
		draw_rect(Rect2(top_left, bottom_right - top_left), Color(0.6, 0.8, 1.0), false, 2.0)
		var origin: Vector3i = structures.position_of(s)
		var occupied: Dictionary = structures.occupancy(s)
		var t: Dictionary = _host.content().get_entry(&"structure", CONTAINER)
		var sockets: Dictionary = t["sockets"]
		var cols: int = sockets["cols"]
		var rows: int = sockets["rows"]
		for c: int in cols:
			for w: int in rows:
				var cell_tl: Vector2 = _to_screen(origin.x + c * pitch, origin.z + (w + 1) * pitch)
				var cell_size: Vector2 = Vector2(pitch, pitch) / M * PX_PER_M
				var key: String = "%d,%d" % [c, w]
				if occupied.has(key):
					var module_id: int = occupied[key]
					draw_rect(Rect2(cell_tl + Vector2.ONE, cell_size - Vector2(2, 2)), _module_colour(structures.module_template(s, module_id)))
				draw_rect(Rect2(cell_tl, cell_size), Color(1, 1, 1, 0.25), false, 1.0)
		draw_string(ThemeDB.fallback_font, top_left + Vector2(4.0, -4.0), "#%d %s" % [s, structures.template_of(s)], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.9, 1.0))
	var c: Vector2 = _to_screen(_cursor.x, _cursor.z)
	draw_line(c + Vector2(-10, 0), c + Vector2(10, 0), Color(1, 0.9, 0.2), 2.0)
	draw_line(c + Vector2(0, -10), c + Vector2(0, 10), Color(1, 0.9, 0.2), 2.0)


func _module_colour(template: StringName) -> Color:
	var h: float = float(String(template).hash() % 360) / 360.0
	return Color.from_hsv(h, 0.6, 0.9, 0.9)


func _render(sim: SimRoot) -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Gcity M2 plot   seed %d   tick %d" % [sim.get_seed(), sim.get_tick()])
	lines.append("state %s" % sim.state_hash().left(16))
	lines.append("content %d entries %s" % [_host.content().count(), _host.content().digest().left(12)])
	lines.append("dispatched %d   rejected %d" % [sim.dispatched_count(), sim.rejected_count()])
	lines.append("")
	if _setup_stage < 3:
		lines.append("setting up the plot (stage %d)..." % _setup_stage)
		_status.text = "\n".join(lines)
		return
	var land: LandSystem = SimAssembly.land_of(sim)
	var structures: StructureSystem = SimAssembly.structures_of(sim)
	var parcel: StringName = land.parcel_at(_cursor)
	var rights: Dictionary = land.rights_at(_cursor, _player)
	var held: PackedStringArray = PackedStringArray()
	for right: StringName in LandSystem.RIGHTS:
		held.append(("+" if rights[right] else "-") + String(right))
	lines.append("CURSOR x %d  z %d mm" % [_cursor.x, _cursor.z])
	lines.append("  parcel %s  owner %s" % [parcel if not parcel.is_empty() else "(unparcelled)", land.owner_of(parcel) if not land.owner_of(parcel).is_empty() else "none"])
	lines.append("  district %s" % land.district_of(parcel))
	lines.append("  rights " + " ".join(held))
	lines.append("  violations %d" % land.violation_count())
	lines.append("")
	lines.append("PARCELS")
	for id: StringName in land.parcel_ids():
		lines.append("  %-16s %s" % [id, land.owner_of(id) if not land.owner_of(id).is_empty() else "unowned"])
	lines.append("")
	lines.append("STRUCTURES")
	for s: int in structures.structure_ids():
		lines.append("  #%d %s at (%d, %d)   power %d W   heat %d W" % [s, structures.template_of(s), structures.position_of(s).x, structures.position_of(s).z, structures.power_available(s), structures.heat_headroom(s)])
		for module_id: int in structures.module_ids(s):
			var rec: Dictionary = structures.structure(s)
			var modules: Dictionary = rec["modules"]
			var m: Dictionary = modules[module_id]
			lines.append("     #%d %s at (%d, %d)" % [module_id, m["template"], m["col"], m["row"]])
	if structures.structure_ids().is_empty():
		lines.append("  none")
	lines.append("")
	lines.append("MODULE to install: %s" % _templates[_template_index])
	var s_here: int = _structure_under_cursor(structures)
	if s_here != 0:
		var cell: Vector2i = _cell_under_cursor(structures, s_here)
		lines.append("  target #%d cell (%d, %d)" % [s_here, cell.x, cell.y])
	lines.append("")
	lines.append("[arrows / dpad] move   [Space / A] place")
	lines.append("[Enter / X] install   [R / B] remove")
	lines.append("[Tab / Y] next module   [T / Start] buy east")
	lines.append("[F5 / LB] save   [F9 / RB] load")
	if _demo:
		lines.append("DEMO %.1fs  step %d/%d" % [_demo_t, _demo_next, _demo_script.size()])
	lines.append("")
	for entry: String in _log:
		lines.append(entry)
	_status.text = "\n".join(lines)
