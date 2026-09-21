## The M3 grey-box world (spec claim set P): parcels as slabs, build pieces as boxes,
## the player as a capsule, a third-person camera with a first-person toggle. Every
## step, shot, reload and piece is a submitted command; the camera and the meshes read
## the sim. This is where feel is judged (P4); correctness is judged headless.
##
## `--demo` after `--` plays a scripted sequence through the same action path;
## `--demo-quit=<s>`, `--screenshot=<path>`, `--screenshot-at=<s>` as in the other views.
class_name WorldView extends Node3D

const M: float = 1000.0
const PROFILE: StringName = &"arcade"
const DUMMY_PROFILE: StringName = &"range_dummy"
const CUTTER: String = "cutter"
const EYE_HEIGHT: float = 1.6
const THIRD_PERSON_BACK: float = 4.0
const THIRD_PERSON_UP: float = 2.2
const LOOK_SPEED: float = 2.0
const AIM_CONE_DEG: float = 15.0
const SAVE_DIR: String = "user://saves/world"

@onready var _host: LocalHost = $LocalHost
@onready var _status: Label = $Overlay/Status
@onready var _camera: Camera3D = $Camera3D

var _player: int = 0
var _dummy: int = 0
var _pistol: int = 0
var _setup_stage: int = 0
## Facing +z at start: the dummy stands 18 m down the z axis.
var _yaw: float = PI
var _first_person: bool = false
var _piece_templates: Array[StringName] = []
var _piece_index: int = 0
var _log: Array[String] = []
var _piece_nodes: Dictionary = {}
var _token_nodes: Dictionary = {}
var _actor_nodes: Dictionary = {}
var _demo: bool = false
var _demo_quit_s: float = -1.0
var _demo_t: float = 0.0
var _demo_next: int = 0
var _demo_script: Array = []
var _demo_walk_ticks: int = 0
var _demo_walk_dir: Vector2 = Vector2.ZERO
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
	_piece_templates = _host.content().ids(&"build_piece")
	_build_static_scene()
	_demo_script = _build_demo_script()


func _build_demo_script() -> Array:
	# [gap before the action in seconds of sim time, action]
	var steps: Array = [
		[1.0, "wield"],
		[0.2, "walk:30"],
		[2.2, "fire"],   # the setup reload keeps the pistol busy for 2 s
		[0.4, "fire"], [0.4, "fire"],
		[0.4, "reload"],
		[0.5, "build_room"],
		[0.8, "raid"],
		[0.3, "look:45"],
		[0.3, "walk:20"],
	]
	var script: Array = []
	var t: float = 0.0
	for step: Array in steps:
		var gap: float = step[0]
		t += gap
		script.append([t, step[1]])
	return script


# ---------------------------------------------------------------- scene

func _build_static_scene() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	light.light_energy = 1.2
	add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	ground.mesh = plane
	ground.material_override = _material(Color(0.32, 0.3, 0.28))
	ground.position = Vector3(0.0, -0.02, 0.0)
	add_child(ground)
	var land: LandSystem = SimAssembly.land_of(_host.sim())
	for id: StringName in land.parcel_ids():
		add_child(_parcel_node(land, id))


func _parcel_node(land: LandSystem, id: StringName) -> MeshInstance3D:
	var record: Dictionary = land.parcel(id)
	var points: PackedVector2Array = PackedVector2Array()
	for v: Variant in record["footprint"]:
		var pair: Array = v
		var px: int = pair[0]
		var pz: int = pair[1]
		points.append(Vector2(float(px) / M, float(pz) / M))
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(points)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in indices:
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(points[i].x, 0.0, points[i].y))
	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	var owner: StringName = record["owner"]
	node.material_override = _material(_owner_colour(owner))
	node.name = "parcel_%s" % id
	return node


func _owner_colour(owner: StringName) -> Color:
	if owner == &"player":
		return Color(0.25, 0.5, 0.3)
	if owner.is_empty():
		return Color(0.4, 0.4, 0.42)
	return Color(0.55, 0.28, 0.25)


func _material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	return m


func _box(size: Vector3, colour: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = _material(colour)
	return node


func _capsule(colour: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.3
	mesh.height = 1.8
	node.mesh = mesh
	node.material_override = _material(colour)
	return node


## Rebuilds piece, actor and token meshes to match the sim. Cheap at M3 sizes; a
## diff-based refresh is a G4 item if the profiler says so.
func _sync_scene(sim: SimRoot) -> void:
	var build: BuildSystem = SimAssembly.build_of(sim)
	var present: Dictionary = {}
	for id: int in build.piece_ids():
		present[id] = true
		if _piece_nodes.has(id):
			continue
		var node: MeshInstance3D = _piece_mesh(build, id)
		_piece_nodes[id] = node
		add_child(node)
	for id: int in _piece_nodes.keys():
		if not present.has(id):
			var node: MeshInstance3D = _piece_nodes[id]
			node.queue_free()
			_piece_nodes.erase(id)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	for actor: int in actors.actor_ids():
		if not _actor_nodes.has(actor):
			var node: MeshInstance3D = _capsule(Color(0.2, 0.6, 0.9) if actor == _player else Color(0.85, 0.3, 0.25))
			_actor_nodes[actor] = node
			add_child(node)
		var capsule: MeshInstance3D = _actor_nodes[actor]
		var p: Vector3i = actors.position_of(actor)
		capsule.position = Vector3(float(p.x) / M, 0.9, float(p.z) / M)
		capsule.visible = actors.is_alive(actor) and not (_first_person and actor == _player)
	var raids: RaidTokenSystem = SimAssembly.raids_of(sim)
	var tokens: Dictionary = {}
	for token: int in raids.token_ids():
		tokens[token] = true
		if not _token_nodes.has(token):
			var node: MeshInstance3D = _box(Vector3(0.5, 0.5, 0.5), Color(1.0, 0.85, 0.2))
			_token_nodes[token] = node
			add_child(node)
		var cube: MeshInstance3D = _token_nodes[token]
		var c: Vector3i = raids.cell_of(token)
		cube.position = Vector3(float(c.x) + 0.5, float(c.y) + 0.5, float(c.z) + 0.5)
		var state: String = raids.state_of(token)
		cube.material_override = _material(Color(1.0, 0.85, 0.2) if state == "moving" else (Color(0.9, 0.2, 0.2) if state == "arrived" else Color(0.5, 0.5, 0.5)))


func _piece_mesh(build: BuildSystem, id: int) -> MeshInstance3D:
	var rec: Dictionary = build.piece(id)
	var face: String = rec["face"]
	var kind: StringName = build.kind_of(id)
	var colour: Color = Color(0.6, 0.6, 0.62)
	match kind:
		&"door":
			colour = Color(0.75, 0.55, 0.3)
		&"window":
			colour = Color(0.55, 0.75, 0.9)
		&"hatch":
			colour = Color(0.7, 0.6, 0.4)
		&"crate":
			colour = Color(0.85, 0.7, 0.2)
		&"foundation":
			colour = Color(0.45, 0.45, 0.47)
	var cell: Vector3i = build.cell_of_piece(id)
	var node: MeshInstance3D
	if face.is_empty():
		node = _box(Vector3(0.98, 0.98, 0.98), colour)
		node.position = Vector3(float(cell.x) + 0.5, float(cell.y) + 0.5, float(cell.z) + 0.5)
	else:
		var axis: String = face.split("|")[1]
		var size: Vector3 = Vector3(0.1, 0.98, 0.98) if axis == "x" else (Vector3(0.98, 0.1, 0.98) if axis == "y" else Vector3(0.98, 0.98, 0.1))
		node = _box(size, colour)
		var offset: Vector3 = Vector3(1.0, 0.5, 0.5) if axis == "x" else (Vector3(0.5, 1.0, 0.5) if axis == "y" else Vector3(0.5, 0.5, 1.0))
		node.position = Vector3(cell) + offset
	node.name = "piece_%d" % id
	return node


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	var sim: SimRoot = _host.sim()
	_advance_setup(sim)
	if _demo:
		if _demo_next < _demo_script.size():
			var step: Array = _demo_script[_demo_next]
			var at: float = step[0]
			if _demo_t >= at:
				var action: String = step[1]
				_perform(action)
				_demo_next += 1
		if not _screenshot_path.is_empty() and _demo_t >= _screenshot_at_s:
			_sync_scene(sim)
			_place_camera(sim)
			_render(sim)
			await RenderingServer.frame_post_draw
			_save_screenshot()
		if _demo_quit_s > 0.0 and _demo_t >= _demo_quit_s:
			get_tree().quit()
			return
	else:
		var look: float = Input.get_action_strength("world_look_right") - Input.get_action_strength("world_look_left")
		_yaw -= look * LOOK_SPEED * delta
	_sync_scene(sim)
	_place_camera(sim)
	_render(sim)


func _physics_process(_delta: float) -> void:
	if _demo:
		_demo_t += 1.0 / SimRoot.TICK_HZ  # sim-driven demo clock, see plot_view
	if _setup_stage < 4:
		return
	var sim: SimRoot = _host.sim()
	var input: Vector2 = Vector2.ZERO
	if _demo:
		if _demo_walk_ticks > 0:
			_demo_walk_ticks -= 1
			input = _demo_walk_dir
	else:
		input = Input.get_vector("world_move_left", "world_move_right", "world_move_forward", "world_move_back")
	if input.length_squared() < 0.01:
		return
	var speed: int = SimAssembly.movement_of(sim).speed_of(_player)
	var forward: Vector2 = Vector2(-sin(_yaw), -cos(_yaw))
	var right: Vector2 = Vector2(forward.y, -forward.x)
	var world: Vector2 = (right * input.x - forward * input.y).limit_length(1.0) * float(speed)
	var dx: int = roundi(world.x)
	var dz: int = roundi(world.y)
	if dx == 0 and dz == 0:
		return
	_submit(sim, &"actor.move", {"actor": _player, "dx": dx, "dz": dz})


func _place_camera(sim: SimRoot) -> void:
	if _player == 0:
		return
	var p: Vector3i = SimAssembly.actors_of(sim).position_of(_player)
	var feet: Vector3 = Vector3(float(p.x) / M, 0.0, float(p.z) / M)
	var forward: Vector3 = Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	if _first_person:
		_camera.position = feet + Vector3(0.0, EYE_HEIGHT, 0.0)
		_camera.look_at(_camera.position + forward, Vector3.UP)
	else:
		_camera.position = feet - forward * THIRD_PERSON_BACK + Vector3(0.0, THIRD_PERSON_UP, 0.0)
		_camera.look_at(feet + Vector3(0.0, 1.2, 0.0) + forward * 2.0, Vector3.UP)


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
	for action: String in ["fire", "reload", "wield", "camera", "build_place", "build_remove", "build_next", "raid", "save", "load"]:
		if event.is_action("world_" + action):
			_perform(action)
			return


# ---------------------------------------------------------------- setup and actions

## The player on the plot with the pistol kit, a dummy 18 m away, the plot owned.
func _advance_setup(sim: SimRoot) -> void:
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var items: ItemSystem = SimAssembly.items_of(sim)
	match _setup_stage:
		0:
			_submit(sim, &"actor.spawn", {"profile": String(PROFILE), "range_m": 0})
			_submit(sim, &"actor.spawn", {"profile": String(DUMMY_PROFILE), "range_m": 0})
			_setup_stage = 1
		1:
			var ids: Array[int] = actors.actor_ids()
			if ids.size() < 2:
				return
			_player = ids[0]
			_dummy = ids[1]
			actors.set_position(_player, Vector3i(3000, 0, 3000))
			actors.set_position(_dummy, Vector3i(3000, 0, 21000))
			var inv: String = String(ItemSystem.inventory_of(_player))
			_submit(sim, &"land.identify", {"actor": _player, "owner": "player"})
			_submit(sim, &"land.transfer", {"parcel": "starter_plot", "owner": "player"})
			_submit(sim, &"land.transfer", {"parcel": "neighbour_north", "owner": "player"})
			_submit(sim, &"item.spawn", {"kind": "weapon_frame", "template": "g19", "container": inv, "seed": 1, "count": 1})
			_submit(sim, &"item.spawn", {"kind": "weapon_part", "template": "g19_mag_15", "container": inv, "seed": 4, "count": 2})
			_submit(sim, &"item.spawn", {"kind": "ammo", "template": "9x19_fmj", "container": inv, "seed": 100, "count": 30})
			_setup_stage = 2
		2:
			var inventory: Array[int] = items.items_in(ItemSystem.inventory_of(_player))
			if inventory.size() < 33:
				return
			var mags: Array[int] = []
			var rounds: Array[int] = []
			for id: int in inventory:
				if items.item_kind(id) == &"weapon_frame":
					_pistol = id
				elif items.item_kind(id) == &"weapon_part":
					mags.append(id)
				else:
					rounds.append(id)
			for i: int in 15:
				_submit(sim, &"magazine.load", {"actor": _player, "magazine": mags[0], "round": rounds[i]})
			for i: int in range(15, 30):
				_submit(sim, &"magazine.load", {"actor": _player, "magazine": mags[1], "round": rounds[i]})
			_setup_stage = 3
		3:
			var mags: Array[int] = _loose_mags(items)
			if mags.is_empty() or items.rounds_in(mags[0]).size() < 15:
				return
			_submit(sim, &"weapon.reload_tactical", {"actor": _player, "weapon": _pistol, "magazine": mags[0]})
			_note("t%d ready: player %d, dummy %d at 18 m, pistol %d" % [sim.get_tick(), _player, _dummy, _pistol])
			_setup_stage = 4


func _loose_mags(items: ItemSystem) -> Array[int]:
	var out: Array[int] = []
	for id: int in items.items_in(ItemSystem.inventory_of(_player)):
		if items.item_kind(id) == &"weapon_part":
			out.append(id)
	return out


func _perform(action: String) -> void:
	if _setup_stage < 4:
		return
	var sim: SimRoot = _host.sim()
	var items: ItemSystem = SimAssembly.items_of(sim)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	match action:
		"fire":
			var target: int = _aimed_target(sim)
			if target == 0:
				_note("no target in the aim cone")
				return
			_submit(sim, &"weapon.fire", {"actor": _player, "target": target})
		"reload":
			var mags: Array[int] = _loose_mags(items)
			if mags.is_empty():
				_note("no loose magazine")
				return
			_submit(sim, &"weapon.reload_tactical", {"actor": _player, "weapon": _pistol, "magazine": mags[0]})
		"wield":
			var weapon: int = 0 if actors.wielded(_player) == _pistol else _pistol
			_submit(sim, &"actor.wield", {"actor": _player, "weapon": weapon})
		"camera":
			_first_person = not _first_person
		"build_place":
			var cell: Vector3i = _cell_ahead(sim)
			var t: StringName = _piece_templates[_piece_index]
			var k: Dictionary = _host.content().get_entry(&"piece_kind", LandSystem._as_name(_host.content().get_entry(&"build_piece", t)["kind"]))
			var occupies: String = k["occupies"]
			var facing: String = "" if occupies == "cell" else _facing_ahead()
			var centre: Vector3i = BuildSystem.cell_centre(cell)
			_submit(sim, &"build.place", {"actor": _player, "piece": String(t), "x": centre.x, "y": centre.y, "z": centre.z, "facing": facing})
		"build_remove":
			var build: BuildSystem = SimAssembly.build_of(sim)
			var cell: Vector3i = _cell_ahead(sim)
			var id: int = build.cell_piece_at(cell)
			if id == 0:
				id = build.face_piece_at(BuildSystem.face_key(BuildSystem.cell_of(actors.position_of(_player)), _facing_ahead()))
			if id == 0:
				_note("nothing ahead to remove")
				return
			_submit(sim, &"build.remove", {"actor": _player, "piece_id": id})
		"build_next":
			_piece_index = (_piece_index + 1) % _piece_templates.size()
		"build_room":
			_submit_room(sim)
		"raid":
			_submit(sim, &"raid.spawn", {"tool": CUTTER})
		"save":
			_save_game(sim)
		"load":
			_load_game()
		_:
			if action.begins_with("walk:"):
				_demo_walk_ticks = action.trim_prefix("walk:").to_int()
				_demo_walk_dir = Vector2(0.0, -1.0)
			elif action.begins_with("look:"):
				_yaw += deg_to_rad(float(action.trim_prefix("look:")))
			else:
				_note("unknown action " + action)


## The nearest living actor other than the player within the aim cone of the camera's
## forward direction. Client-side aim; the sim rolls the hit from the distance.
func _aimed_target(sim: SimRoot) -> int:
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var me: Vector3i = actors.position_of(_player)
	var forward: Vector2 = Vector2(-sin(_yaw), -cos(_yaw))
	var best: int = 0
	var best_distance: float = INF
	for actor: int in actors.actor_ids():
		if actor == _player or not actors.is_alive(actor):
			continue
		var p: Vector3i = actors.position_of(actor)
		var to: Vector2 = Vector2(float(p.x - me.x), float(p.z - me.z))
		if to.length() < 1.0:
			continue
		if absf(rad_to_deg(forward.angle_to(to))) > AIM_CONE_DEG:
			continue
		if to.length() < best_distance:
			best_distance = to.length()
			best = actor
	return best


func _facing_ahead() -> String:
	var forward: Vector2 = Vector2(-sin(_yaw), -cos(_yaw))
	if absf(forward.x) > absf(forward.y):
		return "px" if forward.x > 0.0 else "nx"
	return "pz" if forward.y > 0.0 else "nz"


func _cell_ahead(sim: SimRoot) -> Vector3i:
	var p: Vector3i = SimAssembly.actors_of(sim).position_of(_player)
	var cell: Vector3i = BuildSystem.cell_of(p)
	match _facing_ahead():
		"px":
			cell.x += 1
		"nx":
			cell.x -= 1
		"pz":
			cell.z += 1
		_:
			cell.z -= 1
	return cell


## The demo bunker at ground level so the player can walk in: foundation blocks at the
## four outside corners carry twelve walls (one a door) around a 3×3 floor of air, a
## roof of floor panels, and a crate inside. Placed three cells ahead and to the right.
func _submit_room(sim: SimRoot) -> void:
	var p: Vector3i = SimAssembly.actors_of(sim).position_of(_player)
	var base: Vector3i = BuildSystem.cell_of(p) + Vector3i(2, 0, 3)
	for command: Dictionary in room_commands(base, _player):
		_submit(sim, &"build.place", command)
	_note("bunker queued at cell %s" % base)


## The build.place payloads for the ground-level room whose interior is
## base + (0..2, 0, 0..2). Shared with the M3 fixtures by construction of the same list.
static func room_commands(base: Vector3i, actor: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var place: Callable = func(piece: String, cell: Vector3i, facing: String) -> void:
		var centre: Vector3i = BuildSystem.cell_centre(cell)
		out.append({"actor": actor, "piece": piece, "x": centre.x, "y": centre.y, "z": centre.z, "facing": facing})
	for corner: Vector3i in [Vector3i(-1, 0, -1), Vector3i(3, 0, -1), Vector3i(-1, 0, 3), Vector3i(3, 0, 3)]:
		place.call("foundation_block", base + corner, "")
	for i: int in 3:
		place.call("wall_panel", base + Vector3i(0, 0, i), "nx")
		place.call("wall_panel", base + Vector3i(2, 0, i), "px")
		place.call("wall_panel", base + Vector3i(i, 0, 2), "pz")
		place.call("door_frame" if i == 1 else "wall_panel", base + Vector3i(i, 0, 0), "nz")
	for x: int in 3:
		for z: int in 3:
			place.call("floor_panel", base + Vector3i(x, 0, z), "py")
	place.call("storage_crate", base + Vector3i(2, 0, 2), "")
	return out


func _submit(sim: SimRoot, kind: StringName, payload: Dictionary) -> void:
	var err: Error = sim.submit(SimCommand.new(sim.get_tick() + 1, kind, payload))
	if err != OK:
		_note("submit %s failed: %s" % [kind, error_string(err)])


func _note(text: String) -> void:
	_log.append(text)
	if _log.size() > 5:
		_log.pop_front()


# ---------------------------------------------------------------- save and load

func _save_game(sim: SimRoot) -> void:
	var text: String = SaveFile.serialize(sim, _host.content().digest())
	if text.is_empty():
		_note("save failed")
		return
	if DirAccess.make_dir_recursive_absolute(SAVE_DIR) != OK:
		_note("save failed: directory")
		return
	var world: FileAccess = FileAccess.open(SAVE_DIR + "/world.json", FileAccess.WRITE)
	if world == null:
		_note("save failed: %s" % error_string(FileAccess.get_open_error()))
		return
	world.store_string(text)
	world.close()
	_note("saved %d bytes at tick %d" % [text.length(), sim.get_tick()])


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
	for node: MeshInstance3D in _piece_nodes.values():
		node.queue_free()
	_piece_nodes.clear()
	_note("loaded tick %d" % sim.get_tick())


# ---------------------------------------------------------------- panel

func _render(sim: SimRoot) -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Gcity M3 world   tick %d   state %s" % [sim.get_tick(), sim.state_hash().left(12)])
	if _setup_stage < 4:
		lines.append("setting up (stage %d)..." % _setup_stage)
		_status.text = "\n".join(lines)
		return
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var items: ItemSystem = SimAssembly.items_of(sim)
	var combat: CombatSystem = SimAssembly.combat_of(sim)
	var build: BuildSystem = SimAssembly.build_of(sim)
	var portals: PortalGraph = SimAssembly.portals_of(sim)
	var raids: RaidTokenSystem = SimAssembly.raids_of(sim)
	var p: Vector3i = actors.position_of(_player)
	lines.append("player at (%d, %d) mm   yaw %d°   %s" % [p.x, p.z, roundi(rad_to_deg(_yaw)), "first person" if _first_person else "third person"])
	var target: int = _aimed_target(sim)
	var range_m: int = ActorSystem.metres_between(p, actors.position_of(target)) if target != 0 else -1
	var mag: int = items.magazine_of(_pistol)
	lines.append("pistol %s   chamber %s   mag %s" % ["wielded" if actors.wielded(_player) == _pistol else "holstered",
		"loaded" if items.chambered(_pistol) != 0 else "EMPTY", "%d/15" % items.rounds_in(mag).size() if mag != 0 else "none"])
	lines.append("target %s   hit chance %s" % ["#%d at %d m" % [target, range_m] if target != 0 else "none",
		"%d%%" % (combat.hit_chance_at(_player, _pistol, range_m) / 10000) if target != 0 else "-"])
	lines.append("shots %d   hits %d   kills %d   dispatched %d   rejected %d   blocked %d" % [combat.shots(), combat.hits(), combat.kills(), sim.dispatched_count(), sim.rejected_count(), SimAssembly.movement_of(sim).blocked_count()])
	lines.append("piece to place: %s   facing %s   pieces %d   volumes %d" % [_piece_templates[_piece_index], _facing_ahead(), build.piece_ids().size(), portals.volume_count()])
	var plan: Dictionary = portals.raid_plan(StringName(CUTTER))
	var plan_target: int = plan["target"]
	if plan_target != 0:
		var plan_pieces: Array[int] = plan["pieces"]
		lines.append("raid plan: target #%d cost %d via %d crossings" % [plan_target, plan["cost"], plan_pieces.size()])
	for token: int in raids.token_ids():
		lines.append("token %d: %s at %s (breached %d)" % [token, raids.state_of(token), raids.cell_of(token), raids.token(token)["breached"]])
	lines.append("")
	lines.append("[WASD / L stick] move  [Q E / R stick] look  [C / L3] camera  [Space / RB] fire  [R / X] reload  [F / Y] wield")
	lines.append("[Enter / A] place  [Backspace / B] remove  [Tab / LB] next piece  [T / Start] raid  [F5] save  [F9] load")
	if _demo:
		lines.append("DEMO %.1fs  step %d/%d" % [_demo_t, _demo_next, _demo_script.size()])
	for entry: String in _log:
		lines.append(entry)
	_status.text = "\n".join(lines)
