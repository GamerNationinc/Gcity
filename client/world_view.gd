## The grey-box world (M3 spec claim set P; M4 spec claim 18): parcels as slabs, build
## pieces as boxes, actors as capsules with a nose for their facing, a third-person
## camera with a first-person toggle. The M4 building stands north of the start with
## four armed guards in it, drawn in their stance's colour with an awareness bar, a
## last-known-position marker and a sight line to the player; D-pad up swaps every
## guard's profile, D-pad down hides the overlay, Back restarts. Every step, shot,
## reload and piece is a submitted command; the camera and the meshes read the sim.
## This is where feel is judged (P4, time_to_first_shot); correctness is judged headless.
##
## `--demo` after `--` plays a scripted sequence through the same action path;
## `--demo-quit=<s>`, `--screenshot=<path>`, `--screenshot-at=<s>` as in the other views;
## `--demo-loop` repeats the demo until quit and `--capture=<path>` writes frame times.
## `--wilds` (M7 spec claim 16) walks out of the gate instead: the seam's load window,
## then down the road south with the wild ground streamed in around you
## ([TerrainStreamer]). Walking into the gate's opening towards the other side takes it,
## in any mode.
## `--mission` raises Cold Storage as its operator and plays the under route end to end
## (M6 spec claim 13): the player owns nothing, so what you watch is a break-in. The
## route is `MissionDemo`, written there rather than read from the m6-stealth fixture
## because `tests/` is not in the export; the fixture proves the run is clean and this
## shows it.
class_name WorldView extends Node3D

const M: float = 1000.0
const PROFILE: StringName = &"arcade"
const GUARD_PROFILES: Array[String] = ["guard_sim", "guard_arcade"]
const CUTTER: String = "cutter"
const READY: int = 6
## `--mission`: the player turns up 44 m out on the x axis and walks in from there.
const MISSION_SPAWN_M: int = 44
## The street grate, relative to Cold Storage's base.
const GRATE_REL: Vector3i = MissionDemo.GRATE
## The four shapes a build piece is drawn as: a cell box and a wall on each axis.
## How often the HUD's state hash is recomputed: every 30 s of sim time. Hashing the
## world is not free: 62 ms on the Deck with Cold Storage raised in the wilds (M7.5 gate
## item 30), so once a second it set the mission demo's 1 % low at 14 fps.
const DIGEST_EVERY_TICKS: int = 1200
const PIECE_SHAPES: Array[String] = ["cell", "x", "y", "z"]
const PIECE_SIZES: Dictionary[String, Vector3] = {
	"cell": Vector3(0.98, 0.98, 0.98),
	"x": Vector3(0.1, 0.98, 0.98),
	"y": Vector3(0.98, 0.1, 0.98),
	"z": Vector3(0.98, 0.98, 0.1),
}
const KIT_ITEMS: int = 17
const STANCE_COLOURS: Dictionary = {
	&"hold": Color(0.55, 0.65, 0.5), &"advance": Color(0.95, 0.5, 0.15), &"flank": Color(0.7, 0.35, 0.85),
	&"retreat": Color(0.3, 0.55, 0.95), &"investigate": Color(0.95, 0.85, 0.25), &"surrender": Color(0.95, 0.95, 0.95),
}
## How far over a guard's floor its awareness bar hangs: clear of a 1.8 m capsule.
const BAR_OVER_FLOOR: float = 2.1
## How far over the floor a last-known marker sits: half its own height.
const MARKER_OVER_FLOOR: float = 0.15
## Pulled back from 4 m and 2.2 m after the 2026-10-01 Deck run: from 4 m the capsule
## filled the middle of the screen. M8 claim 6 replaces this with a spring arm.
const THIRD_PERSON_BACK: float = 6.0
const THIRD_PERSON_UP: float = 2.8
## Over the right shoulder, so the ground ahead of the player is not behind the capsule.
const THIRD_PERSON_SIDE: float = 0.9
const LOOK_SPEED: float = 2.0
const AIM_CONE_DEG: float = 15.0
const SAVE_DIR: String = "user://saves/world"

@onready var _host: LocalHost = $LocalHost
@onready var _steam: SteamHost = $SteamHost
@onready var _status: Label = $Overlay/Status
@onready var _camera: Camera3D = $Camera3D

var _player: int = 0
var _pistol: int = 0
var _guards: Array[int] = []
var _guard_profile: int = 0
var _overlay: bool = true
var _setup_stage: int = 0
## Facing +z at start: the building's door is ten metres down the z axis.
var _yaw: float = PI
var _first_person: bool = false
var _glyphs: InputGlyphs = InputGlyphs.new()
## The device (M5 spec claims 3, 5, 8): its own viewport, redrawn only on change, shown
## over the world while raised; raising pauses where the land says `safe`.
var _device_viewport: SubViewport
var _device_screen: TextureRect
var _shell: DeviceShell
var _device_raised: bool = false
var _device_pressed_at: float = -1.0
const RESTART_HOLD_S: float = 1.5
var _piece_templates: Array[StringName] = []
var _piece_index: int = 0
var _log: Array[String] = []
## shape -> MultiMeshInstance3D, and the checksum of the piece ids last drawn.
var _piece_holders: Dictionary = {}
var _piece_signature: int = -1
## The HUD's state hash, and the tick it was taken on.
var _digest: String = ""
var _digest_tick: int = -1000
var _token_nodes: Dictionary = {}
var _actor_nodes: Dictionary = {}
var _bar_nodes: Dictionary = {}
var _line_nodes: Dictionary = {}
var _marker_nodes: Dictionary = {}
var _demo: bool = false
var _demo_quit_s: float = -1.0
var _demo_t: float = 0.0
var _demo_next: int = 0
var _demo_script: Array = []
var _demo_walk_ticks: int = 0
var _demo_walk_dir: Vector2 = Vector2.ZERO
var _screenshot_path: String = ""
var _screenshot_at_s: float = -1.0
## `--capture=<path>` writes every frame's time to JSON at quit (standards §4.2);
## `--demo-loop` restarts the demo when its script ends, for the thermal soak.
var _capture_path: String = ""
var _frame_usec: PackedInt32Array = PackedInt32Array()
var _demo_loop: bool = false
var _demo_loops: int = 0
## `--mission`: raise Cold Storage instead of the M4 building and play the under route
## end to end (M6 spec claim 13). The route lives in `MissionDemo`.
var _mission: bool = false
## `--wilds`: the demo walks out through the gate.
var _wilds: bool = false
## The ground drawn around the player, and each gate's frame and the curtain drawn across
## it while someone is in it (the seam).
var _ground: TerrainStreamer
var _curtains: Dictionary = {}
var _mission_steps: Array[Dictionary] = []
var _mission_index: int = 0
var _mission_wait: int = 0
var _mission_patience: int = 0
var _operator: int = 0
## The run log (`RunLog`): one file per launch. The `_seen_*` fields are what it last
## wrote, so it writes changes rather than every frame.
var _run_log: RunLog
## `--create`: the creator tool (M7.5 spec claims 14–15) on Cold Storage's open lot.
var _create: bool = false
var _creator: SiteCreator
var _creator_menu: bool = false
var _creator_menu_index: int = 0
var _creator_menu_entries: Array[String] = []
var _creator_cursor_node: MeshInstance3D
var _creator_face_node: MeshInstance3D
var _creator_marker_nodes: Array[MeshInstance3D] = []
var _creator_presses: Array[Dictionary] = []
var _creator_press_next: int = 0
var _creator_press_wait: int = 0
var _seen: Dictionary = {}
var _seen_rejected: int = 0
var _seen_move: String = ""
var _seen_look: int = 0
var _submitted_kinds: Dictionary = {}
var _frame_commands: Array[String] = []
var _beat_usec: int = 0
var _beat_frames: int = 0
var _beat_worst_usec: int = 0


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
		elif arg.begins_with("--capture="):
			_capture_path = arg.trim_prefix("--capture=")
		elif arg == "--demo-loop":
			_demo_loop = true
		elif arg == "--mission":
			_mission = true
		elif arg == "--wilds":
			_wilds = true
		elif arg == "--create":
			_create = true
	_run_log = RunLog.open(OS.get_cmdline_user_args())
	Input.joy_connection_changed.connect(_on_joy_changed)
	_piece_templates = _host.content().ids(&"build_piece")
	_glyphs.set_deck(_steam.is_deck())
	_glyphs.set_controller_active(_steam.is_deck() or not Input.get_connected_joypads().is_empty())
	_build_static_scene()
	_build_device()
	_demo_script = _build_demo_script()
	_mission_steps = MissionDemo.steps()
	if _create:
		_creator = SiteCreator.new(_host.content())
		_creator_presses = CreatorDemo.presses()
		_build_creator_nodes()


func _build_demo_script() -> Array:
	# [gap before the action in seconds of sim time, action]
	if _wilds:
		return _timed([
			[1.0, "look:180"],   # face south, the gate a metre and a half ahead
			[0.5, "walk:30"],    # into the opening and on: the gate is taken
			[3.0, "walk:400"],   # out of the load window and down the road
			[12.0, "look:-35"],
			[0.5, "walk:300"],
			[9.0, "look:70"],
			[0.5, "walk:300"],
		])
	var steps: Array = [
		[1.0, "wield"],
		[0.5, "device"],          # on the owned plot: the device pauses the world
		[0.6, "device:device_next_app"], [0.6, "device:device_next_app"], [0.6, "device:device_next_app"],
		[0.6, "device:device_prev_app"], [0.6, "device:device_prev_app"], [0.6, "device:device_prev_app"],
		[0.6, "device:device_down"], [0.3, "device:device_down"], [0.3, "device:device_down"],
		[0.6, "device"],          # lowered: time runs again
		[0.5, "walk:33"],   # up the street beside the lobby
		[1.1, "look:90"],   # face +x
		[0.1, "walk:20"],   # in front of the door: the post inside starts to notice
		[0.7, "look:-90"],  # face +z
		[0.1, "walk:20"],   # through the door
		[0.8, "fire"], [0.4, "fire"], [0.4, "fire"],
		[0.4, "reload"],
		[6.8, "restart"],   # the Deck's own way back after a death
	]
	return _timed(steps)


## [gap, action] steps to [time, action].
static func _timed(steps: Array) -> Array:
	var script: Array = []
	var t: float = 0.0
	for step: Array in steps:
		var gap: float = step[0]
		t += gap
		script.append([t, step[1]])
	return script


# ---------------------------------------------------------------- the device

func _build_device() -> void:
	_device_viewport = SubViewport.new()
	_device_viewport.size = Vector2i(DeviceShell.WIDTH, DeviceShell.HEIGHT)
	_device_viewport.transparent_bg = true
	_device_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_device_viewport)
	_shell = DeviceShell.new()
	_shell.setup(_host.content(), _submit_from_device, _glyphs)
	for app: String in ["inventory", "map", "quests", "comms", "notes", "drone", "hacking", "mission"]:
		var scene: PackedScene = load("res://client/device/apps/%s_app.tscn" % app)
		_shell.register_view(StringName(app), scene)
	_device_viewport.add_child(_shell)
	_device_screen = TextureRect.new()
	_device_screen.texture = _device_viewport.get_texture()
	_device_screen.position = Vector2((1280 - DeviceShell.WIDTH) / 2.0, 120.0)
	_device_screen.size = Vector2(DeviceShell.WIDTH, DeviceShell.HEIGHT)
	_device_screen.visible = false
	$Overlay.add_child(_device_screen)


func _submit_from_device(kind: StringName, payload: Dictionary) -> void:
	_submit(_host.sim(), kind, payload)


func _raise_device(raise: bool) -> void:
	if raise == _device_raised or _setup_stage < READY:
		return
	var sim: SimRoot = _host.sim()
	_device_raised = raise
	_device_screen.visible = raise
	_steam.activate_action_set(raise)
	if raise:
		var rights: Dictionary = SimAssembly.land_of(sim).rights_at(SimAssembly.actors_of(sim).position_of(_player), _player)
		var safe: bool = rights[&"safe"]
		if safe and not sim.is_paused():
			_submit(sim, &"sim.pause", {"actor": _player})
		_shell.note("")
		_device_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	elif sim.is_paused():
		_submit(sim, &"sim.resume", {"actor": _player})


func _refresh_device() -> void:
	if not _device_raised or _setup_stage < READY:
		return
	if _shell.refresh(_host.sim(), _player):
		_device_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


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
	# the streamed ground ends a couple of hundred metres out: fog it away
	e.fog_enabled = true
	e.fog_light_color = e.background_color
	e.fog_density = 0.012
	env.environment = e
	add_child(env)
	# the city's ground past the streamed chunks: a backdrop a hand's width under the
	# drawn ground, north of the city's edge only (the wilds are all streamed)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 200.0)
	ground.mesh = plane
	ground.material_override = _material(Color(0.32, 0.3, 0.28))
	ground.position = Vector3(0.0, -0.1, 100.0)
	add_child(ground)
	_ground = TerrainStreamer.new()
	add_child(_ground)
	_build_gates()
	var land: LandSystem = SimAssembly.land_of(_host.sim())
	for id: StringName in land.parcel_ids():
		add_child(_parcel_node(land, id))


## Every authored region's gates: two posts and a lintel, and a curtain across the
## opening shown while the player is in it or in its load window.
func _build_gates() -> void:
	var regions: Regions = SimAssembly.regions_of(_host.sim())
	for region: StringName in regions.region_ids():
		for gate: Dictionary in regions.gates_of(region):
			var gx: int = gate["x"]
			var gz: int = gate["z"]
			var half: int = gate["half_width_mm"]
			var node: int = gate["node"]
			# the opening runs along x if a point at its end, just inside, is in it
			var along_x: bool = regions.gate_at(Vector3i(gx + half, 0, gz + BuildSystem.CELL - 1)) == node
			var side: Vector3 = Vector3(float(half) / M, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, float(half) / M)
			var centre: Vector3 = Vector3(float(gx) / M, 0.0, float(gz) / M)
			for sign: float in [-1.0, 1.0]:
				var post: MeshInstance3D = _box(Vector3(0.4, 4.5, 0.4), Color(0.25, 0.22, 0.2))
				post.position = centre + side * sign + Vector3(0.0, 2.25, 0.0)
				add_child(post)
			var lintel: MeshInstance3D = _box(Vector3(2.0 * side.length() + 0.4, 0.4, 0.4), Color(0.25, 0.22, 0.2))
			lintel.position = centre + Vector3(0.0, 4.5, 0.0)
			lintel.rotation.y = 0.0 if along_x else PI / 2.0
			add_child(lintel)
			var curtain := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(2.0 * side.length(), 4.3)
			curtain.mesh = quad
			var glow := StandardMaterial3D.new()
			glow.albedo_color = Color(0.6, 0.8, 1.0, 0.35)
			glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			glow.cull_mode = BaseMaterial3D.CULL_DISABLED
			curtain.material_override = glow
			curtain.position = centre + Vector3(0.0, 2.15, 0.0)
			curtain.rotation.y = 0.0 if along_x else PI / 2.0
			curtain.visible = false
			add_child(curtain)
			_curtains[node] = curtain


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
	var nose: MeshInstance3D = _box(Vector3(0.25, 0.12, 0.12), Color(0.1, 0.1, 0.1))
	nose.name = "nose"
	nose.position = Vector3(0.38, 0.55, 0.0)
	node.add_child(nose)
	return node


## Rebuilds piece, actor and token meshes to match the sim. Cheap at M3 sizes; a
## diff-based refresh is a G4 item if the profiler says so.
func _sync_scene(sim: SimRoot) -> void:
	_sync_pieces(SimAssembly.build_of(sim))
	if _create:
		_sync_creator()
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	_sync_ground(sim, actors)
	var perception: PerceptionSystem = SimAssembly.perception_of(sim)
	var stances: StanceSystem = SimAssembly.stances_of(sim)
	for actor: int in actors.actor_ids():
		if not _actor_nodes.has(actor):
			var node: MeshInstance3D = _capsule(Color(0.2, 0.6, 0.9) if actor == _player else Color(0.85, 0.3, 0.25))
			if actor == _player:
				node.add_child(_facing_arrow())
			_actor_nodes[actor] = node
			add_child(node)
		var capsule: MeshInstance3D = _actor_nodes[actor]
		var p: Vector3i = actors.position_of(actor)
		capsule.position = Vector3(float(p.x) / M, float(p.y) / M + 0.9, float(p.z) / M)
		var alive: bool = actors.is_alive(actor)
		capsule.visible = not (_first_person and actor == _player)
		if not alive:
			# down: a dark slab where the body fell
			capsule.position.y = float(p.y) / M + 0.15
			capsule.scale = Vector3(1.0, 0.15, 1.0)
			capsule.material_override = _material(Color(0.15, 0.13, 0.13))
		if actor == _player:
			capsule.rotation.y = _yaw + PI / 2.0
		elif perception.is_agent(actor):
			capsule.rotation.y = -deg_to_rad(float(perception.facing_of(actor)))
			if alive:
				var stance: StringName = stances.stance_of(actor)
				var colour: Color = STANCE_COLOURS[stance] if STANCE_COLOURS.has(stance) else Color(0.85, 0.3, 0.25)
				capsule.material_override = _material(colour)
			_sync_guard_overlay(actor, alive, p, perception)
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


## The ground streamed around the player, and the curtain across a gate they are in.
func _sync_ground(sim: SimRoot, actors: ActorSystem) -> void:
	var regions: Regions = SimAssembly.regions_of(sim)
	_ground.watch(regions, SimAssembly.routes_of(sim))
	if _player == 0:
		return
	var p: Vector3i = actors.position_of(_player)
	_ground.update(p)
	var in_gate: int = regions.gate_at(p)
	for key: Variant in _curtains:
		var node: int = key
		var curtain: MeshInstance3D = _curtains[key]
		curtain.visible = in_gate == node


## The awareness bar over a guard, its sight line to the player, and where it last
## knew the player to be (M4 spec claim 18).
func _sync_guard_overlay(guard: int, alive: bool, p: Vector3i, perception: PerceptionSystem) -> void:
	if not _bar_nodes.has(guard):
		var new_bar: MeshInstance3D = _box(Vector3(1.0, 0.08, 0.08), Color(0.3, 0.9, 0.3))
		var new_line: MeshInstance3D = _box(Vector3(0.04, 0.04, 1.0), Color(1.0, 0.3, 0.2))
		var new_marker: MeshInstance3D = _box(Vector3(0.3, 0.3, 0.3), Color(0.95, 0.85, 0.25))
		_bar_nodes[guard] = new_bar
		_line_nodes[guard] = new_line
		_marker_nodes[guard] = new_marker
		add_child(new_bar)
		add_child(new_line)
		add_child(new_marker)
	var bar: MeshInstance3D = _bar_nodes[guard]
	var line: MeshInstance3D = _line_nodes[guard]
	var marker: MeshInstance3D = _marker_nodes[guard]
	var show: bool = _overlay and alive and _player != 0
	bar.visible = show
	line.visible = false
	marker.visible = false
	if not show:
		return
	var fraction: float = float(perception.awareness_of(guard, _player)) / float(PerceptionSystem.AWARENESS_MAX)
	bar.position = bar_position(p)
	bar.scale = Vector3(maxf(fraction, 0.02), 1.0, 1.0)
	bar.material_override = _material(Color(0.95, 0.2, 0.2) if perception.is_alerted(guard, _player) else Color(0.3, 0.9, 0.3).lerp(Color(0.95, 0.6, 0.1), fraction))
	if perception.can_see(guard, _player):
		var ends: PackedVector3Array = sight_ends(_host.sim(), guard, _player)
		var a: Vector3 = ends[0]
		var b: Vector3 = ends[1]
		var length: float = a.distance_to(b)
		if length > 0.05:
			line.visible = true
			line.position = (a + b) / 2.0
			line.scale = Vector3(1.0, 1.0, length)
			line.look_at(b, Vector3.UP)
	elif perception.has_last_known(guard, _player):
		var last: Vector3i = perception.last_known(guard, _player)
		marker.visible = true
		marker.position = marker_position(last)


## Where the scene draws a sim position, in metres.
static func view_of(mm: Vector3i) -> Vector3:
	return Vector3(float(mm.x) / M, float(mm.y) / M, float(mm.z) / M)


## An awareness bar hangs over the guard's head from the floor it stands on (M7.5 claim 11).
static func bar_position(feet: Vector3i) -> Vector3:
	return view_of(feet) + Vector3(0.0, BAR_OVER_FLOOR, 0.0)


## A last-known marker sits on the floor where the player was remembered.
static func marker_position(last: Vector3i) -> Vector3:
	return view_of(last) + Vector3(0.0, MARKER_OVER_FLOOR, 0.0)


## A sight line runs as the sim's does: from the guard's eyes to the target's centre.
static func sight_ends(sim: SimRoot, guard: int, target: int) -> PackedVector3Array:
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var perception: PerceptionSystem = SimAssembly.perception_of(sim)
	return PackedVector3Array([view_of(actors.position_of(guard) + perception.eye_of(guard)), view_of(actors.centre_of(target))])


## The first-person camera stands at the sim's own eyes for the actor.
static func eye_position(sim: SimRoot, actor: int) -> Vector3:
	return view_of(SimAssembly.actors_of(sim).position_of(actor) + SimAssembly.perception_of(sim).eye_of(actor))


## Draws every standing piece as a handful of multimeshes rather than one node each.
##
## A flat arrow on the ground 1.4 m ahead of the player, pointing where the stick's up
## walks: the nose is behind the capsule from a camera that follows it (Deck run,
## 2026-10-01). A child of the capsule, so it turns with it (nose along local +x).
func _facing_arrow() -> MeshInstance3D:
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.6, 0.8, 0.03)
	var arrow := MeshInstance3D.new()
	arrow.name = "facing"
	arrow.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.85, 0.2)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# drawn over the capsule: from a camera behind it, the ground ahead is behind it too
	material.no_depth_test = true
	material.render_priority = 1
	arrow.material_override = material
	# the prism's apex is its +y: lay it flat (apex to -z), then turn -z to +x
	arrow.basis = Basis(Vector3.UP, -PI / 2.0) * Basis(Vector3.RIGHT, -PI / 2.0)
	arrow.position = Vector3(1.4, -0.86, 0.0)
	return arrow


## A piece was a MeshInstance3D with its own BoxMesh and its own material, so a site
## cost one draw call per piece: measured on the Deck, the 93-piece M4 building ran at
## 68 fps and Cold Storage's 363 pieces at 37, under the 40 fps floor. Pieces come in
## four shapes — a cell box and a wall on each axis — so four multimeshes with a colour
## per instance draw the lot, and the rebuild only happens when the build changes.
func _sync_pieces(build: BuildSystem) -> void:
	var ids: Array[int] = build.piece_ids()
	var signature: int = ids.size()
	for id: int in ids:
		signature = (signature * 31 + id) & 0x3FFFFFFF
	if signature == _piece_signature:
		return
	_piece_signature = signature
	var buckets: Dictionary = {}
	for id: int in ids:
		var rec: Dictionary = build.piece(id)
		var face: String = rec["face"]
		var cell: Vector3i = build.cell_of_piece(id)
		var shape: String = "cell"
		var offset: Vector3 = Vector3(0.5, 0.5, 0.5)
		if not face.is_empty():
			var axis: String = face.split("|")[1]
			shape = axis
			offset = Vector3(1.0, 0.5, 0.5) if axis == "x" else (Vector3(0.5, 1.0, 0.5) if axis == "y" else Vector3(0.5, 0.5, 1.0))
		if not buckets.has(shape):
			buckets[shape] = []
		var list: Array = buckets[shape]
		list.append([Vector3(cell) + offset, _piece_colour(build.kind_of(id))])
	for shape: String in PIECE_SHAPES:
		var holder: MultiMeshInstance3D = _piece_holder(shape)
		var list: Array = buckets.get(shape, [])
		var multi: MultiMesh = holder.multimesh
		multi.instance_count = list.size()
		for i: int in list.size():
			var entry: Array = list[i]
			var where: Vector3 = entry[0]
			var colour: Color = entry[1]
			multi.set_instance_transform(i, Transform3D(Basis(), where))
			multi.set_instance_color(i, colour)


## The multimesh for one piece shape, made on first use.
func _piece_holder(shape: String) -> MultiMeshInstance3D:
	if _piece_holders.has(shape):
		return _piece_holders[shape]
	var mesh := BoxMesh.new()
	mesh.size = PIECE_SIZES[shape]
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = mesh
	var holder := MultiMeshInstance3D.new()
	holder.multimesh = multi
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	holder.material_override = material
	holder.name = "pieces_%s" % shape
	add_child(holder)
	_piece_holders[shape] = holder
	return holder


## Drops the batches so the next sync rebuilds them: a fresh sim has fresh pieces and
## the old checksum would say nothing had changed.
func _forget_pieces() -> void:
	for holder: MultiMeshInstance3D in _piece_holders.values():
		holder.queue_free()
	_piece_holders.clear()
	_piece_signature = -1


static func _piece_colour(kind: StringName) -> Color:
	match kind:
		&"door":
			return Color(0.75, 0.55, 0.3)
		&"window":
			return Color(0.55, 0.75, 0.9)
		&"hatch":
			return Color(0.7, 0.6, 0.4)
		&"crate":
			return Color(0.85, 0.7, 0.2)
		&"foundation":
			return Color(0.45, 0.45, 0.47)
	return Color(0.6, 0.6, 0.62)


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	_log_frame(delta)
	if not _capture_path.is_empty():
		_frame_usec.append(int(delta * 1_000_000.0))
	var sim: SimRoot = _host.sim()
	if _demo and not _mission and not _create:
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
		if _demo_loop and _demo_next >= _demo_script.size() and _setup_stage == READY:
			_demo_t = 0.0
			_demo_next = 0
			_demo_loops += 1
		if _demo_quit_s > 0.0 and _demo_t + float(_demo_loops) * _demo_script[_demo_script.size() - 1][0] >= _demo_quit_s:
			_save_capture()
			get_tree().quit()
			return
	elif (_mission or _create) and _demo:
		if not _screenshot_path.is_empty() and _demo_t >= _screenshot_at_s:
			_sync_scene(sim)
			_place_camera(sim)
			_render(sim)
			await RenderingServer.frame_post_draw
			_save_screenshot()
		if _demo_quit_s > 0.0 and _demo_t >= _demo_quit_s:
			_save_capture()
			get_tree().quit()
			return
	if not _device_raised and (not _demo or _handed_back()):
		var look: float = Input.get_action_strength("world_look_right") - Input.get_action_strength("world_look_left")
		_yaw -= look * LOOK_SPEED * delta
	_sync_scene(sim)
	_place_camera(sim)
	_render(sim)
	_refresh_device()


func _physics_process(_delta: float) -> void:
	if _demo or _mission:
		_demo_t += 1.0 / SimRoot.TICK_HZ  # sim-driven demo clock, see plot_view
	var sim: SimRoot = _host.sim()
	# on the sim's clock, not the frame's: set up at a frame rate's pace, a demo started
	# on a different tick on the Deck than headless and met the guards somewhere else
	_advance_setup(sim)
	if _setup_stage < READY:
		return
	if _mission and _demo and _mission_index < _mission_steps.size():
		# --mission --demo drives the route itself; --mission alone hands it to you, and so
		# does the demo once its route is done (Deck test, 2026-10-04: the buttons stayed dead)
		_mission_tick(sim)
		return
	if _create:
		_creator_tick(sim)
		if _demo:
			return
	var input: Vector2 = Vector2.ZERO
	if _demo and not _handed_back():
		if _demo_walk_ticks > 0:
			_demo_walk_ticks -= 1
			input = _demo_walk_dir
	else:
		input = Input.get_vector("world_move_left", "world_move_right", "world_move_forward", "world_move_back")
		_log_sticks(input)
	if _device_raised or input.length_squared() < 0.01 or not SimAssembly.actors_of(sim).is_alive(_player):
		return
	var speed: int = SimAssembly.movement_of(sim).speed_of(_player)
	var world: Vector2 = ground_move(_yaw, input) * float(speed)
	var dx: int = roundi(world.x)
	var dz: int = roundi(world.y)
	if dx == 0 and dz == 0:
		return
	if _take_gate(sim, dx, dz):
		return
	_submit(sim, &"actor.move", {"actor": _player, "dx": dx, "dz": dz})


## Whether a scripted mission demo has finished its route and handed the controls to
## whoever holds the Deck.
func _handed_back() -> bool:
	return _mission and _demo and _setup_stage >= READY and _mission_index >= _mission_steps.size()


## The stick, seen from a camera at `yaw`, as a direction on the ground (x, z): up is
## the camera's forward and right is the screen's right. Until the 2026-10-01 Deck run
## right was the camera's left, so the stick strafed backwards.
static func ground_move(yaw: float, input: Vector2) -> Vector2:
	var forward: Vector2 = Vector2(-sin(yaw), -cos(yaw))
	var right: Vector2 = Vector2(-forward.y, forward.x)
	return (right * input.x - forward * input.y).limit_length(1.0)


## Walking from a gate's opening towards the other side of the edge takes the gate
## (`region.enter`): the seam, with its load window. True if it was asked for.
func _take_gate(sim: SimRoot, dx: int, dz: int) -> bool:
	var regions: Regions = SimAssembly.regions_of(sim)
	if regions.in_transit(_player):
		return true
	var p: Vector3i = SimAssembly.actors_of(sim).position_of(_player)
	if regions.gate_at(p) == EntityIds.NONE:
		return false
	var ahead: Vector3i = p + Vector3i(signi(dx), 0, signi(dz)) * BuildSystem.CELL
	if not regions.crosses_edge(p, ahead):
		return false
	_submit(sim, Regions.COMMAND_ENTER, {"actor": _player, "region": String(regions.region_at(ahead.x, ahead.z).id())})
	_note("t%d through the gate to %s" % [sim.get_tick(), regions.region_at(ahead.x, ahead.z).id()])
	return true


func _place_camera(sim: SimRoot) -> void:
	if _player == 0:
		return
	var p: Vector3i = SimAssembly.actors_of(sim).position_of(_player)
	var feet: Vector3 = Vector3(float(p.x) / M, float(p.y) / M, float(p.z) / M)
	var forward: Vector3 = Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	if _first_person:
		_camera.position = eye_position(sim, _player)
		_camera.look_at(_camera.position + forward, Vector3.UP)
	else:
		var side: Vector3 = Vector3(-forward.z, 0.0, forward.x) * THIRD_PERSON_SIDE
		_camera.position = feet - forward * THIRD_PERSON_BACK + side + Vector3(0.0, THIRD_PERSON_UP, 0.0)
		_camera.look_at(feet + side + Vector3(0.0, 1.0, 0.0) + forward * 4.0, Vector3.UP)


## Frame times to JSON: all of them, and the final five minutes on their own
## (standards §4.2: first-minute numbers are fiction on a 15 W part).
func _save_capture() -> void:
	if _capture_path.is_empty():
		return
	var all: Array[int] = []
	for v: int in _frame_usec:
		all.append(v)
	var final: Array[int] = []
	var budget: int = 5 * 60 * 1_000_000
	var spent: int = 0
	for i: int in range(all.size() - 1, -1, -1):
		if spent >= budget:
			break
		final.push_front(all[i])
		spent += all[i]
	var report: Dictionary = {
		"frames": all.size(), "demo_loops": _demo_loops, "seconds": float(spent) / 1_000_000.0 if all.size() == final.size() else -1.0,
		"engine": Engine.get_version_info()["string"], "os": OS.get_name(), "cpu": OS.get_processor_name(), "gpu": RenderingServer.get_video_adapter_name(),
		"all_usec": _frame_stats(all), "final_5_min_usec": _frame_stats(final),
	}
	var file: FileAccess = FileAccess.open(_capture_path, FileAccess.WRITE)
	if file == null:
		push_error("capture: cannot save %s: %s" % [_capture_path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("capture saved: %s (%d frames, %d loops)" % [_capture_path, all.size(), _demo_loops])


## The 1 % and 0.1 % lows are the 99th and 99.9th percentile frame times.
static func _frame_stats(samples: Array[int]) -> Dictionary:
	if samples.is_empty():
		return {"count": 0}
	var sorted: Array[int] = samples.duplicate()
	sorted.sort()
	var total: int = 0
	for v: int in sorted:
		total += v
	return {"count": sorted.size(), "mean": total / sorted.size(), "p50": sorted[sorted.size() / 2],
		"p99": sorted[mini(sorted.size() - 1, sorted.size() * 99 / 100)], "p999": sorted[mini(sorted.size() - 1, sorted.size() * 999 / 1000)], "max": sorted[sorted.size() - 1],
		"low_1pct_fps": 1_000_000.0 / float(sorted[mini(sorted.size() - 1, sorted.size() * 99 / 100)]), "low_01pct_fps": 1_000_000.0 / float(sorted[mini(sorted.size() - 1, sorted.size() * 999 / 1000)])}


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
	_glyphs.note(event)
	_log_input(event)
	if event.is_echo():
		return
	# the device button: a short press raises or lowers, a long hold restarts
	if event.is_action("world_device") and _create:
		if event.is_pressed():
			_creator_open_menu(not _creator_menu)
		return
	if event.is_action("world_device"):
		if event.is_pressed():
			_device_pressed_at = Time.get_ticks_msec() / 1000.0
		elif _device_pressed_at >= 0.0:
			var held: float = Time.get_ticks_msec() / 1000.0 - _device_pressed_at
			_device_pressed_at = -1.0
			if held >= RESTART_HOLD_S:
				_perform("restart")
			else:
				_raise_device(not _device_raised)
		return
	if not event.is_pressed():
		return
	if _mission and _demo and not _handed_back():
		return  # the scripted route has the controls until it is done
	if _create:
		_creator_input(event)
		return
	if _device_raised:
		for action: String in ["device_up", "device_down", "device_left", "device_right", "device_select", "device_secondary", "device_back", "device_prev_app", "device_next_app"]:
			if event.is_action(action):
				var outcome: String = _shell.handle(StringName(action), _host.sim(), _player)
				if outcome == "lower":
					_raise_device(false)
				else:
					_device_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
				return
		return
	for action: String in ["fire", "reload", "wield", "camera", "build_place", "build_remove", "build_next", "raid", "save", "load", "profile", "overlay", "restart"]:
		if event.is_action("world_" + action):
			_perform(action)
			return


# ---------------------------------------------------------------- setup and actions

## The player on the street with the pistol kit and both parcels owned; the M4
## Cold Storage raised by its operator, and the player turning up on the street with a
## handset and a coprocessor and nothing else (M6 spec claim 13). The player owns
## nothing, so the demo that follows is a break-in rather than a tour. Since M7 claim 10
## the player takes the contract first, which binds its place out in the wilds, and the
## operator raises the building there: the map shows where, and the gate is the way out.
func _advance_mission_setup(sim: SimRoot) -> void:
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var items: ItemSystem = SimAssembly.items_of(sim)
	var sites: SiteSystem = SimAssembly.sites_of(sim)
	match _setup_stage:
		0:
			_submit(sim, &"actor.spawn", {"profile": String(PROFILE), "range_m": 0})
			_setup_stage = 1
		1:
			var ids: Array[int] = actors.actor_ids()
			if ids.is_empty():
				return
			_operator = ids[0]
			_submit(sim, &"land.identify", {"actor": _operator, "owner": "corp.coldchain"})
			_submit(sim, &"actor.spawn", {"profile": String(PROFILE), "range_m": MISSION_SPAWN_M})
			_setup_stage = 2
		2:
			if _player == 0:
				var ids2: Array[int] = actors.actor_ids()
				if ids2.size() < 2:
					return
				_player = ids2[ids2.size() - 1]
				_submit(sim, &"quest.accept", {"actor": _player, "quest": String(MissionDemo.SITE)})
				_submit(sim, &"site.raise", {"actor": _operator, "site": String(MissionDemo.SITE), "quest": String(MissionDemo.SITE)})
				return
			if not sites.is_raised(MissionDemo.SITE):
				return
			var inv: String = String(ItemSystem.inventory_of(_player))
			_submit(sim, &"item.spawn", {"kind": "device_frame", "template": "handset", "container": inv, "seed": 1, "count": 1})
			_submit(sim, &"item.spawn", {"kind": "device_module", "template": "daemon_coprocessor", "container": inv, "seed": 2, "count": 1})
			# a pistol as well, because a player who is seen should have a choice; the
			# scripted route never draws it, which is the point of the score
			_submit_kit(sim, _player, 3, 4, 30)
			_setup_stage = 3
		3:
			if items.items_in(ItemSystem.inventory_of(_player)).size() < 2 + 1 + 2 + 30:
				return
			var handset: int = _kind_in(items, _player, ItemSystem.KIND_DEVICE_FRAME)
			var module: int = _kind_in(items, _player, ItemSystem.KIND_DEVICE_MODULE)
			_submit(sim, &"actor.equip_device", {"actor": _player, "device": handset})
			_submit(sim, &"item.attach", {"actor": _player, "weapon": handset, "part": module})
			var frame: int = _load_all_mags(items, _player)
			if frame != 0:
				_submit(sim, &"actor.wield", {"actor": _player, "weapon": frame})
			_setup_stage = 4
		4:
			if actors.device_of(_player) == EntityIds.NONE:
				return
			_submit(sim, &"run.begin", {"actor": _player})
			_setup_stage = 5
		5:
			var refused: int = sim.rejected_count()
			var node: int = SimAssembly.binder_of(sim).node_of(MissionDemo.SITE)
			_note("t%d mission: Cold Storage raised at node %d, %d m out; player %d in town%s" % [
				sim.get_tick(), node, SimAssembly.routes_of(sim).distance_between(1, node), _player,
				"" if refused == 0 else ", %d commands refused setting up" % refused])
			_mission_steps = MissionDemo.travel(sim)
			_mission_steps.append_array(MissionDemo.steps())
			_setup_stage = READY


func _kind_in(items: ItemSystem, actor: int, kind: StringName) -> int:
	for id: int in items.items_in(ItemSystem.inventory_of(actor)):
		if items.item_kind(id) == kind:
			return id
	return EntityIds.NONE


## One step of the route a tick: the whole run, played rather than described. Each
## case submits at most one command, so the demo moves at the pace a player would.
func _mission_tick(sim: SimRoot) -> void:
	if _mission_index >= _mission_steps.size():
		return
	if _mission_wait > 0:
		_mission_wait -= 1
		return
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var sites: SiteSystem = SimAssembly.sites_of(sim)
	var step: Dictionary = _mission_steps[_mission_index]
	var kind: int = step["do"]
	match kind:
		MissionDemo.Step.WALK:
			var rel: Vector3i = step["rel"]
			var cell: Vector3i = sites.cell_of(MissionDemo.SITE, rel)
			var target: Vector3i = BuildSystem.cell_centre(cell)
			var here: Vector3i = actors.position_of(_player)
			var speed: int = SimAssembly.movement_of(sim).speed_of(_player)
			var dx: int = clampi(target.x - here.x, -speed, speed)
			var dz: int = clampi(target.z - here.z, -speed, speed)
			if dx == 0 and dz == 0:
				_mission_index += 1
				return
			if dx != 0:
				dz = 0
			_submit(sim, &"actor.move", {"actor": _player, "dx": dx, "dz": dz, "dy": 0})
		MissionDemo.Step.POINT:
			var at: Vector2i = step["at"]
			var here2: Vector3i = actors.position_of(_player)
			var pace: int = SimAssembly.movement_of(sim).speed_of(_player)
			var mx: int = clampi(at.x - here2.x, -pace, pace)
			var mz: int = clampi(at.y - here2.z, -pace, pace)
			if SimAssembly.regions_of(sim).in_transit(_player):
				return
			if mx == 0 and mz == 0:
				_mission_index += 1
				return
			var axis: bool = step.get("axis", false)
			if axis and mx != 0:
				mz = 0
			_submit(sim, &"actor.move", {"actor": _player, "dx": mx, "dz": mz, "dy": 0})
		MissionDemo.Step.GATE:
			var region: String = step["region"]
			_submit(sim, Regions.COMMAND_ENTER, {"actor": _player, "region": region})
			_note("t%d through the gate to %s" % [sim.get_tick(), region])
			_mission_index += 1
		MissionDemo.Step.CLIMB:
			var dy: int = step["dy"]
			_submit(sim, &"actor.move", {"actor": _player, "dx": 0, "dz": 0, "dy": dy})
			_mission_index += 1
		MissionDemo.Step.CUT:
			var grate: int = _grate(sim)
			if grate != EntityIds.NONE:
				_submit(sim, &"build.remove", {"actor": _player, "piece_id": grate})
			_mission_index += 1
		MissionDemo.Step.PATCH:
			var centre: Vector3i = BuildSystem.cell_centre(sites.cell_of(MissionDemo.SITE, GRATE_REL))
			_submit(sim, &"build.place", {"actor": _player, "piece": "floor_panel", "x": centre.x, "y": centre.y, "z": centre.z, "facing": "ny"})
			_mission_index += 1
		MissionDemo.Step.HACK:
			var terminals: TerminalSystem = SimAssembly.terminals_of(sim)
			var terminal: int = sites.terminals_of(MissionDemo.SITE)[0]
			_submit(sim, &"terminal.hack_start", {"actor": _player, "terminal": terminal})
			_mission_wait = terminals.hack_ticks_of(terminal) + 2
			_mission_index += 1
		MissionDemo.Step.WIPE:
			var terminal2: int = sites.terminals_of(MissionDemo.SITE)[0]
			_submit(sim, &"terminal.wipe", {"actor": _player, "terminal": terminal2})
			_mission_index += 1
		MissionDemo.Step.WAIT_CLEAR:
			_mission_patience += 1
			if MissionDemo.hall_is_clear(sim, _player, _operator) or _mission_patience > MissionDemo.PATIENCE:
				_mission_patience = 0
				_mission_index += 1
		MissionDemo.Step.DONE:
			_submit(sim, &"run.end", {"actor": _player})
			var score: RunScoreSystem = SimAssembly.score_of(sim)
			_note("t%d run scored: seen %d, alarms %d, bodies %d, traces %d" % [
				sim.get_tick(), score.times_detected(_player), score.alarms_raised(_player),
				score.bodies(_player), score.traces_left(_player)])
			_mission_index += 1
			_note("t%d the route is done: the controls are yours" % sim.get_tick())


func _grate(sim: SimRoot) -> int:
	var sites: SiteSystem = SimAssembly.sites_of(sim)
	var build: BuildSystem = SimAssembly.build_of(sim)
	return build.face_piece_at(BuildSystem.face_key(sites.cell_of(MissionDemo.SITE, GRATE_REL), "ny"))


## building raised from `M4Building.commands`; four guards spawned and armed the same
## way the player is, through commands. Stages wait for the sim to catch up.
func _advance_setup(sim: SimRoot) -> void:
	if _mission:
		_advance_mission_setup(sim)
		return
	if _create:
		_advance_create_setup(sim)
		return
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var items: ItemSystem = SimAssembly.items_of(sim)
	match _setup_stage:
		0:
			_submit(sim, &"actor.spawn", {"profile": String(PROFILE), "range_m": 0})
			_setup_stage = 1
		1:
			var ids: Array[int] = actors.actor_ids()
			if ids.is_empty():
				return
			_player = ids[0]
			actors.set_position(_player, M4Building.PLAYER_START)
			_submit(sim, &"land.identify", {"actor": _player, "owner": "player"})
			_submit(sim, &"land.transfer", {"parcel": "starter_plot", "owner": "player"})
			_submit(sim, &"land.transfer", {"parcel": "neighbour_north", "owner": "player"})
			for command: Dictionary in M4Building.commands(_player, _host.content()):
				_submit(sim, &"build.place", command)
			# `--wilds` is a walk out of town, not a fight: no guards
			if not _wilds:
				for guard: Dictionary in M4Building.guards(GUARD_PROFILES[_guard_profile], _host.content()):
					_submit(sim, &"agent.spawn", guard)
			_submit_kit(sim, _player, 1, 2, 30)
			var inv: String = String(ItemSystem.inventory_of(_player))
			_submit(sim, &"item.spawn", {"kind": "device_frame", "template": "handset", "container": inv, "seed": 7, "count": 1})
			_submit(sim, &"item.spawn", {"kind": "device_module", "template": "radio_module", "container": inv, "seed": 8, "count": 1})
			_submit(sim, &"item.spawn", {"kind": "device_module", "template": "daemon_coprocessor", "container": inv, "seed": 9, "count": 1})
			_setup_stage = 2
		2:
			var ids: Array[int] = actors.actor_ids()
			if ids.size() < (1 if _wilds else 5):
				return
			_guards = []
			for id: int in ids:
				if id != _player:
					_guards.append(id)
			for i: int in _guards.size():
				_submit_kit(sim, _guards[i], 10 + i * 100, 11 + i * 100, 15)
			_setup_stage = 3
		3:
			if items.items_in(ItemSystem.inventory_of(_player)).size() < 3 + 30 + 3:
				return
			for guard: int in _guards:
				if items.items_in(ItemSystem.inventory_of(guard)).size() < KIT_ITEMS:
					return
			_pistol = _load_all_mags(items, _player)
			for guard: int in _guards:
				_load_all_mags(items, guard)
			_setup_stage = 4
		4:
			var mags: Array[int] = _loose_mags(items, _player)
			if mags.is_empty() or items.rounds_in(mags[0]).size() < 15:
				return
			for guard: int in _guards:
				var gm: Array[int] = _loose_mags(items, guard)
				if gm.is_empty() or items.rounds_in(gm[0]).size() < 15:
					return
			_submit(sim, &"weapon.reload_tactical", {"actor": _player, "weapon": _pistol, "magazine": mags[0]})
			for id: int in items.items_in(ItemSystem.inventory_of(_player)):
				if items.item_kind(id) == ItemSystem.KIND_DEVICE_FRAME:
					_submit(sim, &"actor.equip_device", {"actor": _player, "device": id})
			for guard: int in _guards:
				var gm: Array[int] = _loose_mags(items, guard)
				_submit(sim, &"actor.wield", {"actor": guard, "weapon": _frame_of(items, guard)})
				_submit(sim, &"weapon.reload_tactical", {"actor": guard, "weapon": _frame_of(items, guard), "magazine": gm[0]})
			_setup_stage = 5
		5:
			for guard: int in _guards:
				if actors.wielded(guard) == 0:
					return
			_note("t%d ready: player %d, %d guards armed (%s), %d pieces, %d rejected" % [sim.get_tick(), _player, _guards.size(), GUARD_PROFILES[_guard_profile], SimAssembly.build_of(sim).piece_ids().size(), sim.rejected_count()])
			_setup_stage = READY


## A G19, magazines and rounds into an actor's inventory. Seeds only need to differ
## per item within one actor's kit.
func _submit_kit(sim: SimRoot, actor: int, frame_seed: int, mag_seed: int, rounds: int) -> void:
	var inv: String = String(ItemSystem.inventory_of(actor))
	_submit(sim, &"item.spawn", {"kind": "weapon_frame", "template": "g19", "container": inv, "seed": frame_seed, "count": 1})
	_submit(sim, &"item.spawn", {"kind": "weapon_part", "template": "g19_mag_15", "container": inv, "seed": mag_seed, "count": rounds / 15})
	_submit(sim, &"item.spawn", {"kind": "ammo", "template": "9x19_fmj", "container": inv, "seed": 100 + frame_seed, "count": rounds})


## Loads every magazine in the actor's inventory fifteen at a time; returns the frame.
func _load_all_mags(items: ItemSystem, actor: int) -> int:
	var sim: SimRoot = _host.sim()
	var frame: int = 0
	var mags: Array[int] = []
	var rounds: Array[int] = []
	for id: int in items.items_in(ItemSystem.inventory_of(actor)):
		# a round is ammo, not "everything else": the device frame and its modules are
		# in this inventory too, and feeding them to a magazine is two refused commands
		# at every start-up
		var kind: StringName = items.item_kind(id)
		if kind == ItemSystem.KIND_FRAME:
			frame = id
		elif kind == ItemSystem.KIND_PART:
			mags.append(id)
		elif kind == ItemSystem.KIND_AMMO:
			rounds.append(id)
	for m: int in mags.size():
		for i: int in 15:
			var index: int = m * 15 + i
			if index < rounds.size():
				_submit(sim, &"magazine.load", {"actor": actor, "magazine": mags[m], "round": rounds[index]})
	return frame


func _frame_of(items: ItemSystem, actor: int) -> int:
	for id: int in items.items_in(ItemSystem.inventory_of(actor)):
		if items.item_kind(id) == &"weapon_frame":
			return id
	return 0


func _loose_mags(items: ItemSystem, actor: int = _player) -> Array[int]:
	var out: Array[int] = []
	for id: int in items.items_in(ItemSystem.inventory_of(actor)):
		if items.item_kind(id) == &"weapon_part":
			out.append(id)
	return out


func _perform(action: String) -> void:
	_record("action", action)
	if action == "restart":
		_restart()
		return
	if _setup_stage < READY:
		return
	var sim: SimRoot = _host.sim()
	var items: ItemSystem = SimAssembly.items_of(sim)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	if not actors.is_alive(_player) and ["fire", "reload", "wield", "build_place", "build_remove", "build_room", "raid"].has(action):
		_note("you are down: restart or load")
		return
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
		"profile":
			_guard_profile = (_guard_profile + 1) % GUARD_PROFILES.size()
			for guard: int in _guards:
				_submit(sim, &"agent.set_profile", {"agent": guard, "profile": GUARD_PROFILES[_guard_profile]})
			_note("guards now %s" % GUARD_PROFILES[_guard_profile])
		"overlay":
			_overlay = not _overlay
		"device":
			_raise_device(not _device_raised)
		_:
			if action.begins_with("device:"):
				var outcome: String = _shell.handle(StringName(action.trim_prefix("device:")), sim, _player)
				if outcome == "lower":
					_raise_device(false)
				_device_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			elif action.begins_with("walk:"):
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
	elif _run_log != null:
		var due: int = sim.get_tick() + 1
		if not _submitted_kinds.has(due):
			_submitted_kinds[due] = []
		var kinds: Array = _submitted_kinds[due]
		kinds.append(String(kind))
		if kind != &"actor.move":  # moves are logged as the stick, not 40 times a second
			_frame_commands.append("%s %s" % [kind, JSON.stringify(payload)])


## The state hash for the HUD, at most `DIGEST_EVERY_TICKS` apart.
##
## `state_hash()` snapshots the whole world and runs SHA-256 over it, so drawing it
## every frame made the HUD cost grow with the size of the site: measured on the Deck,
## Cold Storage's 363 pieces ran at 37 fps against the 93-piece M4 building's 68. It is
## a debugging read-out, and a debugging read-out does not get to set the frame rate.
func _state_digest(sim: SimRoot) -> String:
	var tick: int = sim.get_tick()
	if tick - _digest_tick >= DIGEST_EVERY_TICKS or _digest.is_empty():
		_digest_tick = tick
		_digest = sim.state_hash().left(12)
	return _digest


func _note(text: String) -> void:
	_record("note", text)
	if _mission:
		print(text)  # the mission demo is also run headless for the gate's evidence
	_log.append(text)
	if _log.size() > 5:
		_log.pop_front()


## A fresh sim and a fresh scene, for the Deck: no relaunch after a death.
func _restart() -> void:
	_host.restart()
	for table: Dictionary in [_token_nodes, _actor_nodes, _bar_nodes, _line_nodes, _marker_nodes]:
		for node: Node in table.values():
			node.queue_free()
		table.clear()
	_forget_pieces()
	if _device_raised:
		_device_raised = false
		_device_screen.visible = false
	_player = 0
	_pistol = 0
	_guards = []
	_setup_stage = 0
	_yaw = PI
	_log.clear()
	_demo_next = _demo_script.size()
	if _create:
		_creator = SiteCreator.new(_host.content())
		_creator_menu = false
		_creator_press_next = _creator_presses.size()


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
	_forget_pieces()
	_guards = []
	for id: int in SimAssembly.perception_of(sim).agent_ids():
		_guards.append(id)
	_note("loaded tick %d" % sim.get_tick())


# ---------------------------------------------------------------- panel

func _render(sim: SimRoot) -> void:
	var lines: PackedStringArray = PackedStringArray()
	var title: String = "M6 mission" if _mission else ("creator" if _create else "M5 world")
	lines.append("Gcity %s   tick %d   state %s%s" % [title, sim.get_tick(), _state_digest(sim), "   PAUSED" if sim.is_paused() else ""])
	if _setup_stage < READY:
		lines.append("setting up (stage %d)..." % _setup_stage)
		_status.text = "\n".join(lines)
		return
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var items: ItemSystem = SimAssembly.items_of(sim)
	var combat: CombatSystem = SimAssembly.combat_of(sim)
	var build: BuildSystem = SimAssembly.build_of(sim)
	var perception: PerceptionSystem = SimAssembly.perception_of(sim)
	var stances: StanceSystem = SimAssembly.stances_of(sim)
	var stress: StressSystem = SimAssembly.stress_of(sim)
	var p: Vector3i = actors.position_of(_player)
	if not actors.is_alive(_player):
		lines.append("YOU ARE DOWN   [Esc / Back] restart   [F9] load")
	if _create:
		_render_creator(sim, lines)
		_status.text = "\n".join(lines)
		return
	var regions: Regions = SimAssembly.regions_of(sim)
	lines.append("region %s%s   ground: %d chunks drawn%s" % [regions.region_at(p.x, p.z).id(), "   IN THE GATE (load window)" if regions.in_transit(_player) else "",
		_ground.shown_chunks().size(), "" if _ground.is_settled() else ", streaming"])
	lines.append("player at (%d, %d) mm   yaw %d°   hp %d   %s" % [p.x, p.z, roundi(rad_to_deg(_yaw)), actors.health_of(_player)["body"] / 1000, "first person" if _first_person else "third person"])
	var target: int = _aimed_target(sim)
	var range_m: int = ActorSystem.metres_between(p, actors.position_of(target)) if target != 0 else -1
	var mag: int = items.magazine_of(_pistol)
	lines.append("pistol %s   chamber %s   mag %s" % ["wielded" if actors.wielded(_player) == _pistol else "holstered",
		"loaded" if items.chambered(_pistol) != 0 else "EMPTY", "%d/15" % items.rounds_in(mag).size() if mag != 0 else "none"])
	var last: Dictionary = combat.last_shot()
	var last_text: String = ""
	if not last.is_empty():
		var reason: String = last["reason"]
		var hit: bool = last["hit"]
		last_text = "   last shot by #%d: %s" % [last["shooter"], "no line of sight" if reason == CombatSystem.REASON_NO_LOS else ("hit" if hit else "miss")]
	lines.append("target %s   hit chance %s%s" % ["#%d at %d m" % [target, range_m] if target != 0 else "none",
		"%d%%" % (combat.hit_chance_at(_player, _pistol, range_m) / 10000) if target != 0 else "-", last_text])
	lines.append("all shots %d   hits %d   kills %d   of which guard shots %d   rejected %d   blocked %d   pieces %d" % [combat.shots(), combat.hits(), combat.kills(), stances.fire_count(), sim.rejected_count(), SimAssembly.movement_of(sim).blocked_count(), build.piece_ids().size()])
	for guard: int in _guards:
		if not actors.is_alive(guard):
			lines.append("guard #%d: down" % guard)
			continue
		var gp: Vector3i = actors.position_of(guard)
		var sees: bool = perception.can_see(guard, _player)
		lines.append("guard #%d: %-11s aware %3d%%%s  stress %2d%%  %2d m  %s" % [guard, stances.stance_of(guard), perception.awareness_of(guard, _player) / 10000,
			"!" if perception.is_alerted(guard, _player) else " ", stress.stress_of(guard) / 10000, ActorSystem.metres_between(p, gp), "sees you" if sees else ("remembers" if perception.has_last_known(guard, _player) else "unaware")])
	lines.append("guards: %s   overlay %s   piece to place: %s" % [GUARD_PROFILES[_guard_profile], "on" if _overlay else "off", _piece_templates[_piece_index]])
	lines.append("")
	lines.append(_glyphs.line([[&"world_move_forward", "move"], [&"world_look_left", "look"], [&"world_camera", "camera"], [&"world_fire", "fire"], [&"world_reload", "reload"], [&"world_wield", "wield"]]))
	lines.append(_glyphs.line([[&"world_build_place", "place"], [&"world_build_remove", "remove"], [&"world_build_next", "next piece"], [&"world_device", "device (hold: restart)"], [&"world_profile", "guard profile"], [&"world_overlay", "overlay"], [&"world_restart", "restart"], [&"world_save", "save"], [&"world_load", "load"]]))
	lines.append("steam: %s%s" % [_steam.status(), ("  (%s)" % _steam.persona()) if _steam.is_online() else ""])
	if _run_log != null:
		lines.append("run log: %s" % _run_log.path().get_file())
	if _demo:
		if _mission:
			lines.append("DEMO %.1fs  step %d/%d of the under route" % [_demo_t, _mission_index, _mission_steps.size()])
		else:
			lines.append("DEMO %.1fs  step %d/%d" % [_demo_t, _demo_next, _demo_script.size()])
	for entry: String in _log:
		lines.append(entry)
	_status.text = "\n".join(lines)


# ---------------------------------------------------------------- the run log

func _record(category: String, text: String) -> void:
	if _run_log != null:
		_run_log.line(_host.sim().get_tick() if _host != null and _host.sim() != null else -1, category, text)


func _on_joy_changed(device: int, connected: bool) -> void:
	_record("input", "controller %d %s: %s" % [device, "connected" if connected else "disconnected", Input.get_joy_name(device)])


## Every action pressed or released, and any controller button that is not bound to one.
func _log_input(event: InputEvent) -> void:
	if _run_log != null and event is InputEventJoypadMotion:
		# the sticks and triggers are logged as the stick; anything else that moves is a
		# control the game does not read (a D-pad reported as a hat, say): say so
		var motion: InputEventJoypadMotion = event
		if motion.axis >= JOY_AXIS_SDL_MAX and absf(motion.axis_value) > 0.5:
			_record("input", "unbound axis %d at %.1f" % [motion.axis, motion.axis_value])
		return
	if _run_log == null or event.is_echo() or event is InputEventMouseMotion:
		return
	var named: bool = false
	for action: StringName in InputMap.get_actions():
		var a: String = String(action)
		var ours: bool = (a.begins_with("create_") or a == "world_device" or a == "world_camera") if _create else (a.begins_with("world_") or a.begins_with("device_"))
		if ours and event.is_action(action):
			named = true
			_record("input", "%s %s (%s)" % [a, "pressed" if event.is_pressed() else "released", event.as_text()])
	if not named and event.is_pressed() and (event is InputEventJoypadButton or event is InputEventKey):
		_record("input", "unbound %s" % event.as_text())


## The move stick as a direction (to 45°) and how far it is pushed, and the way that walks
## the player on the ground; the look stick as left, right or still. Changes only.
func _log_sticks(input: Vector2) -> void:
	if _run_log == null:
		return
	var move: String = "still"
	if input.length_squared() >= 0.01:
		var dirs: Array[String] = ["right", "down-right", "down", "down-left", "left", "up-left", "up", "up-right"]
		var octant: int = posmod(roundi(input.angle() / (PI / 4.0)), 8)
		var world: Vector2 = ground_move(_yaw, input)
		move = "%s %s -> walks toward (%+.2f, %+.2f) on x, z; camera faces (%+.2f, %+.2f)" % [dirs[octant], "full" if input.length() > 0.7 else "half",
			world.x, world.y, -sin(_yaw), -cos(_yaw)]
	if move.get_slice(" ->", 0) != _seen_move.get_slice(" ->", 0):
		_seen_move = move
		_record("stick", "move " + move)
	var look_axis: float = Input.get_action_strength("world_look_right") - Input.get_action_strength("world_look_left")
	var look: int = 0 if absf(look_axis) < 0.2 else signi(roundi(signf(look_axis)))
	if look != _seen_look:
		_seen_look = look
		_record("stick", "look %s, yaw %d°" % [["left", "still", "right"][look + 1], roundi(rad_to_deg(_yaw))])


## Once a frame: what changed that the player could see, rejected commands, a
## heartbeat each second, and the write to disk.
func _log_frame(delta: float) -> void:
	if _run_log == null:
		return
	var usec: int = int(delta * 1_000_000.0)
	_beat_frames += 1
	_beat_worst_usec = maxi(_beat_worst_usec, usec)
	_log_commands()
	var sim: SimRoot = _host.sim()
	if sim != null:
		_log_rejections(sim)
		if _setup_stage >= READY and _player != 0:
			_log_changes(sim)
	var now: int = Time.get_ticks_usec()
	if now - _beat_usec >= 1_000_000 and sim != null:
		_beat_usec = now
		var where: String = "-"
		if _player != 0 and _setup_stage >= READY:
			var p: Vector3i = SimAssembly.actors_of(sim).position_of(_player)
			where = "(%.1f, %.1f, %.1f) m, yaw %d°" % [p.x / M, p.y / M, p.z / M, roundi(rad_to_deg(_yaw))]
		_record("beat", "%d fps, worst frame %.1f ms, %d frames; player %s; setup %d/%d; ground %d chunks%s; commands %d ok, %d rejected" % [
			Engine.get_frames_per_second(), _beat_worst_usec / 1000.0, _beat_frames, where, _setup_stage, READY,
			_ground.shown_chunks().size() if _ground != null else 0, "" if _ground == null or _ground.is_settled() else " (streaming)",
			sim.dispatched_count(), sim.rejected_count()])
		_beat_frames = 0
		_beat_worst_usec = 0
	_run_log.flush()


## The frame's commands, a kind sent more than three times in one frame (a site being
## raised) as one line with its first payload.
func _log_commands() -> void:
	var counts: Dictionary = {}
	for entry: String in _frame_commands:
		var kind: String = entry.get_slice(" ", 0)
		var so_far: int = counts.get(kind, 0)
		counts[kind] = so_far + 1
	var told: Dictionary = {}
	for entry: String in _frame_commands:
		var kind: String = entry.get_slice(" ", 0)
		var count: int = counts[kind]
		if count <= 3:
			_record("command", entry)
		elif not told.has(kind):
			told[kind] = true
			_record("command", "%s x%d, the first: %s" % [kind, count, entry.trim_prefix(kind + " ")])
	_frame_commands.clear()


func _log_rejections(sim: SimRoot) -> void:
	var rejected: int = sim.rejected_count()
	if rejected < _seen_rejected:
		_seen_rejected = 0  # a restart or a load: a new sim counts from zero
	if rejected > _seen_rejected:
		var kinds: Array = []
		for due: int in _submitted_kinds:
			if due <= sim.get_tick():
				var those: Array = _submitted_kinds[due]
				kinds.append_array(those)
		_record("rejected", "%d command(s) refused by the sim; submitted for those ticks: %s" % [rejected - _seen_rejected, ", ".join(PackedStringArray(kinds))])
		_seen_rejected = rejected
	for due: int in _submitted_kinds.keys():
		if due <= sim.get_tick():
			_submitted_kinds.erase(due)


func _log_changes(sim: SimRoot) -> void:
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var regions: Regions = SimAssembly.regions_of(sim)
	var combat: CombatSystem = SimAssembly.combat_of(sim)
	var perception: PerceptionSystem = SimAssembly.perception_of(sim)
	var p: Vector3i = actors.position_of(_player)
	var now: Dictionary = {
		"region": String(regions.region_at(p.x, p.z).id()),
		"in the gate": regions.in_transit(_player),
		"alive": actors.is_alive(_player),
		"health": actors.health_of(_player)["body"] / 1000,
		"shots": combat.shots(), "hits": combat.hits(), "kills": combat.kills(),
		"paused": sim.is_paused(),
		"camera": "first person" if _first_person else "third person",
		"device": "raised" if _device_raised else "lowered",
		"wielded": actors.wielded(_player) == _pistol,
	}
	var alerted: Array[String] = []
	for guard: int in _guards:
		if actors.is_alive(guard) and perception.is_alerted(guard, _player):
			alerted.append("#%d" % guard)
	now["guards alerted"] = ", ".join(PackedStringArray(alerted)) if not alerted.is_empty() else "none"
	var blocked: int = SimAssembly.movement_of(sim).blocked_count()
	var was_blocked: int = _seen.get("blocked", blocked)
	if blocked > was_blocked:
		_record("world", "a step was blocked at (%.1f, %.1f, %.1f) m (%d so far)" % [p.x / M, p.y / M, p.z / M, blocked])
	_seen["blocked"] = blocked
	for key: String in now:
		if not _seen.has(key) or _seen[key] != now[key]:
			_record("world", "%s: %s" % [key, now[key]])
			_seen[key] = now[key]


func _exit_tree() -> void:
	if _run_log != null:
		_record("end", "the world view closed")
		_run_log.close(_host.sim().get_tick() if _host.sim() != null else -1, "quit")
		_run_log = null


# ---------------------------------------------------------------- the creator tool

## The creator's controls (M7.5 spec claim 14): the D-pad moves the cursor relative to
## the camera, the bumpers raise and lower it a level, A places, B removes, X turns, Y
## picks the next piece. Controller only: no keyboard binding (CLAUDE.md §10).
const CREATOR_ACTIONS: Array[String] = ["create_up", "create_down", "create_left", "create_right", "create_raise", "create_lower",
	"create_place", "create_remove", "create_turn", "create_next"]
## Where the player stands on arriving: the street edge of Cold Storage's lot.
const CREATOR_START: Vector3i = Vector3i(42500, 0, 41500)
## Every guard post and terminal is drawn as one of these, a fresh set each time they change.
var _creator_marker_sig: String = ""
## A site to open once the lot is set up again (claim 15), or "".
var _creator_open_path: String = ""
## The last placement sent and the reason it would be refused, checked once its tick has
## run: a refused press is said aloud, never silent.
var _creator_pending: Dictionary = {}


## The player on Cold Storage's open lot, theirs with the plots beside it.
func _advance_create_setup(sim: SimRoot) -> void:
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	match _setup_stage:
		0:
			_submit(sim, &"actor.spawn", {"profile": String(PROFILE), "range_m": 0})
			_setup_stage = 1
		1:
			var ids: Array[int] = actors.actor_ids()
			if ids.is_empty():
				return
			_player = ids[0]
			actors.set_position(_player, CREATOR_START)
			_submit(sim, &"land.identify", {"actor": _player, "owner": "player"})
			for lot: String in SiteCreator.LOTS:
				_submit(sim, &"land.transfer", {"parcel": lot, "owner": "player"})
			_setup_stage = 2
		2:
			if SimAssembly.land_of(sim).owner_of(StringName(SiteCreator.LOTS[0])) != &"player":
				return
			_note("t%d creator: the lot is yours; %d build pieces and two markers to place" % [sim.get_tick(), _creator.palette().size() - 2])
			if not _creator_open_path.is_empty():
				_open_site(sim, _creator_open_path)
				_creator_open_path = ""
			_setup_stage = READY


## Each tick: the guard posts a build change left without room go, said aloud; under
## `--demo` the scripted presses play.
func _creator_tick(sim: SimRoot) -> void:
	if _setup_stage < READY:
		return
	for cell: Vector3i in _creator.prune(SimAssembly.movement_of(sim)):
		_note("guard post at %s removed: no room for a guard there now" % cell)
	_creator_check_pending(sim)
	if not _demo or _creator_press_next >= _creator_presses.size():
		return
	if _creator_press_wait > 0:
		_creator_press_wait -= 1
		return
	_creator_press_wait = CreatorDemo.PACE
	var press: Dictionary = _creator_presses[_creator_press_next]
	_creator_press_next += 1
	if press.has("save"):
		_save_site(sim)
		return
	var at: Vector3i = press["at"]
	var piece: StringName = press["piece"]
	var turns: int = press["turns"]
	_creator.set_cursor(at)
	_creator.select(piece)
	_creator.set_turn(turns)
	_creator_press("create_place")


func _creator_check_pending(sim: SimRoot) -> void:
	if _creator_pending.is_empty():
		return
	var due: int = _creator_pending["due"]
	if sim.get_tick() < due:
		return
	var build: BuildSystem = SimAssembly.build_of(sim)
	var cell: Vector3i = _creator_pending["cell"]
	var facing: String = _creator_pending["facing"]
	var piece: StringName = _creator_pending["piece"]
	var id: int = build.cell_piece_at(cell) if facing.is_empty() else build.face_piece_at(BuildSystem.face_key(cell, facing))
	if id == EntityIds.NONE or build.template_of(id) != piece:
		var why: String = _creator_pending["why"]
		_note("%s not placed at %s: %s" % [piece, cell, why])
	_creator_pending = {}


func _creator_input(event: InputEvent) -> void:
	if _setup_stage < READY:
		return
	if _creator_menu:
		if event.is_action("create_up"):
			_creator_menu_index = maxi(0, _creator_menu_index - 1)
		elif event.is_action("create_down"):
			_creator_menu_index = mini(_creator_menu_entries.size() - 1, _creator_menu_index + 1)
		elif event.is_action("create_place"):
			var entry: String = _creator_menu_entries[_creator_menu_index]
			_creator_open_menu(false)
			if entry == "save":
				_save_site(_host.sim())
			else:
				_creator_open_path = entry
				_restart()
		elif event.is_action("create_remove"):
			_creator_open_menu(false)
		return
	for action: String in CREATOR_ACTIONS:
		if event.is_action(action):
			_creator_press(action)
			return
	if event.is_action("world_camera"):
		_perform("camera")


func _creator_press(action: String) -> void:
	var sim: SimRoot = _host.sim()
	var steps: Dictionary = {"create_up": Vector2i(0, -1), "create_down": Vector2i(0, 1), "create_left": Vector2i(-1, 0), "create_right": Vector2i(1, 0)}
	if steps.has(action):
		var dpad: Vector2i = steps[action]
		_creator.move(SiteCreator.camera_step(_yaw, dpad))
		return
	match action:
		"create_raise":
			_creator.rise(1)
		"create_lower":
			_creator.rise(-1)
		"create_turn":
			_creator.turn()
		"create_next":
			_creator.next_piece()
		"create_place":
			var name: StringName = _creator.selected()
			var movement: MovementSystem = SimAssembly.movement_of(sim)
			var payload: Dictionary = _creator.place(_player, _yaw, movement)
			if not payload.is_empty():
				var facing: String = payload["facing"]
				_creator_pending = {"due": sim.get_tick() + 1, "piece": name, "cell": _creator.cursor(), "facing": facing,
					"why": _creator.why_not(sim, _player, name, facing)}
				_submit(sim, &"build.place", payload)
			elif name == SiteCreator.GUARD_POST and not _creator.guard_fits(movement, _creator.cursor()):
				_note("no room for a guard at %s" % _creator.cursor())
			else:
				_record("create", "%s at %s" % [name, _creator.cursor()])
		"create_remove":
			var payload: Dictionary = _creator.remove(SimAssembly.build_of(sim), _player, _yaw)
			if payload.is_empty():
				_record("create", "markers cleared at %s" % _creator.cursor())
			else:
				_submit(sim, &"build.remove", payload)


func _creator_open_menu(open: bool) -> void:
	if _setup_stage < READY:
		return
	_creator_menu = open
	if open:
		_creator_menu_entries = ["save"]
		_creator_menu_entries.append_array(SiteCreator.openable())
		_creator_menu_index = 0


## Writes what stands on the lot to `user://sites/<id>.json` (claim 15).
func _save_site(sim: SimRoot) -> void:
	var now: Dictionary = Time.get_datetime_dict_from_system()
	var id: String = SiteCreator.site_id(now)
	var site: Dictionary = _creator.to_site(SimAssembly.build_of(sim), SimAssembly.movement_of(sim),
		"Site %04d-%02d-%02d %02d:%02d" % [now["year"], now["month"], now["day"], now["hour"], now["minute"]],
		"Built with the creator tool on %04d-%02d-%02d." % [now["year"], now["month"], now["day"]])
	if site.is_empty():
		_note("not saved: nothing built, or a guard post with no room")
		return
	var path: String = SiteCreator.save(site, id)
	if path.is_empty():
		_note("save failed: %s" % id)
		return
	var pieces: Array = site["pieces"]
	var spawns: Array = site["spawns"]
	var terminals: Array = site["terminals"]
	_note("saved %s: %d pieces, %d guards, %d terminals" % [path, pieces.size(), spawns.size(), terminals.size()])


## Raises a saved or shipped site's pieces on the lot, through the sim, to keep working.
func _open_site(sim: SimRoot, path: String) -> void:
	var site: Dictionary = SiteCreator.read(path)
	var commands: Array[Dictionary] = _creator.open(site, _player) if not site.is_empty() else [] as Array[Dictionary]
	if commands.is_empty():
		_note("could not open %s: %s" % [path.get_file(), "unreadable" if site.is_empty() else SiteCreator.problem(site, _host.content())])
		return
	for command: Dictionary in commands:
		_submit(sim, &"build.place", command)
	_note("opened %s: %d pieces" % [path.get_file(), commands.size()])


func _build_creator_nodes() -> void:
	_creator_cursor_node = _box(Vector3(1.04, 1.04, 1.04), Color(1.0, 0.85, 0.2, 0.35))
	var cursor_material: StandardMaterial3D = _creator_cursor_node.material_override
	cursor_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	add_child(_creator_cursor_node)
	_creator_face_node = _box(Vector3(1.0, 1.0, 1.0), Color(1.0, 0.6, 0.1))
	add_child(_creator_face_node)


## The cursor, the face the selected piece would take, and the markers.
func _sync_creator() -> void:
	var cell: Vector3i = _creator.cursor()
	var centre: Vector3 = Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	_creator_cursor_node.visible = not _creator_menu
	_creator_cursor_node.position = centre
	var facing: String = _creator.facing_for(_creator.selected(), _yaw)
	_creator_face_node.visible = not facing.is_empty() and not _creator_menu
	if not facing.is_empty():
		var axis: String = facing.substr(1, 1)
		var sign: float = 1.0 if facing.begins_with("p") else -1.0
		var normal: Vector3 = Vector3(1, 0, 0) if axis == "x" else (Vector3(0, 1, 0) if axis == "y" else Vector3(0, 0, 1))
		_creator_face_node.position = centre + normal * 0.5 * sign
		_creator_face_node.scale = Vector3.ONE - normal * 0.94
	var sig: String = "%s|%s" % [_creator.guard_posts(), _creator.terminal_cells()]
	if sig == _creator_marker_sig:
		return
	_creator_marker_sig = sig
	for node: MeshInstance3D in _creator_marker_nodes:
		node.queue_free()
	_creator_marker_nodes = []
	for post: Dictionary in _creator.guard_posts():
		var at: Vector3i = post["cell"]
		var facing_deg: int = post["facing"]
		var pillar: MeshInstance3D = _box(Vector3(0.4, 1.8, 0.4), Color(0.85, 0.3, 0.25))
		pillar.position = Vector3(at) + Vector3(0.5, 0.9, 0.5)
		var nose: MeshInstance3D = _box(Vector3(0.5, 0.15, 0.15), Color(1.0, 0.85, 0.2))
		nose.position = Vector3(0.35, 0.6, 0.0)
		pillar.add_child(nose)
		pillar.rotation.y = -deg_to_rad(float(facing_deg))
		add_child(pillar)
		_creator_marker_nodes.append(pillar)
	for at: Vector3i in _creator.terminal_cells():
		var box: MeshInstance3D = _box(Vector3(0.5, 1.0, 0.3), Color(0.2, 0.85, 0.9))
		box.position = Vector3(at) + Vector3(0.5, 0.5, 0.5)
		add_child(box)
		_creator_marker_nodes.append(box)


func _render_creator(sim: SimRoot, lines: PackedStringArray) -> void:
	var build: BuildSystem = SimAssembly.build_of(sim)
	var name: StringName = _creator.selected()
	var facing: String = _creator.facing_for(name, _yaw)
	if name == SiteCreator.GUARD_POST:
		facing = "%d°" % _creator.post_facing(_yaw)
	lines.append("CREATOR   pieces %d   guard posts %d   terminals %d   rejected %d" % [build.piece_ids().size(), _creator.guard_posts().size(),
		_creator.terminal_cells().size(), sim.rejected_count()])
	lines.append("piece: %s   cursor %s   facing %s" % [name, _creator.cursor(), "-" if facing.is_empty() else facing])
	lines.append("")
	if _creator_menu:
		lines.append(_glyphs.line([[&"create_up", "up"], [&"create_down", "down"], [&"create_place", "choose"], [&"create_remove", "close"]]))
		for i: int in _creator_menu_entries.size():
			var entry: String = _creator_menu_entries[i]
			lines.append("%s %s" % [">" if i == _creator_menu_index else " ", "Save this site" if entry == "save" else "Open %s" % entry.get_file().get_basename()])
	else:
		lines.append(_glyphs.line([[&"world_move_forward", "walk"], [&"world_look_left", "look"], [&"create_up", "cursor"], [&"create_raise", "up a level"], [&"create_lower", "down a level"]]))
		lines.append(_glyphs.line([[&"create_place", "place"], [&"create_remove", "remove"], [&"create_turn", "turn"], [&"create_next", "next piece"], [&"world_device", "menu: save / open"]]))
	if _run_log != null:
		lines.append("run log: %s" % _run_log.path().get_file())
	if _demo:
		lines.append("DEMO %.1fs  press %d/%d" % [_demo_t, _creator_press_next, _creator_presses.size()])
	for entry: String in _log:
		lines.append(entry)
