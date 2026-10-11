## The showcase renderer: a picture of sim work that a non-programmer can check.
## Builds the real sim (SimAssembly over the shipped content, plus whatever a scenario
## adds), runs one scenario script from tools/showcase/scenarios/, and draws the state
## with labels in plain words: pieces and storeys, every actor coloured by alert state
## (green unaware, amber suspicious, red alerted) with a floating name and status,
## agents' view cones, parcels with their rules, sensors, hack progress, heat, noise.
## A caption banner says what the player would notice; a fixed legend explains colours.
##
## Deterministic capture: each frame steps the sim the scenario's ticks-per-frame and
## saves a PNG, so frames do not depend on the wall clock. tools/showcase.sh turns the
## frames into a GIF. Arguments after `--`: --scenario=<name> --frames=<dir>.
## A tool, not the game: the client view of these systems is M6 Phase 4 (claim 20).
extends Node3D

const M: float = 1000.0
const SEED: int = 20261011
const UNAWARE: Color = Color(0.25, 0.8, 0.35)
const SUSPICIOUS: Color = Color(1.0, 0.72, 0.1)
const ALERTED: Color = Color(0.95, 0.2, 0.2)
const PLAYER: Color = Color(0.2, 0.55, 1.0)

var _scenario: RefCounted
var _sim: SimRoot
var _frames_dir: String = ""
var _frame: int = 0
var _busy: bool = false
var _piece_nodes: Dictionary = {}
var _actor_nodes: Dictionary = {}
var _actor_labels: Dictionary = {}
var _heat_bars: Dictionary = {}
var _cones: Dictionary = {}
var _rings: Array[Dictionary] = []
var _ring_nodes: Array[MeshInstance3D] = []
var _camera: Camera3D
var _caption: Label
var _header: Label
var _legend: Label
var _pinned: Dictionary = {}
var _names: Dictionary = {}
var _watch: Array[int] = []
var _extra: Node3D
var _feed: Label
var _feed_lines: Array[String] = []
var _pending: Array[Array] = []
var _last_heat: Dictionary = {}


func _ready() -> void:
	var name: String = "standing"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			name = arg.trim_prefix("--scenario=")
		elif arg.begins_with("--frames="):
			_frames_dir = arg.trim_prefix("--frames=")
	var script: GDScript = load("res://tools/showcase/scenarios/%s.gd" % name)
	if script == null:
		push_error("showcase: no scenario '%s'" % name)
		get_tree().quit(1)
		return
	var made: Variant = script.new()
	_scenario = made
	var db := ContentDb.new()
	if ContentLoader.load_all(db) != OK:
		push_error("showcase: content")
		get_tree().quit(1)
		return
	_scenario.call("content", db)
	_sim = SimAssembly.build(SEED, db)
	if _sim == null:
		push_error("showcase: assembly")
		get_tree().quit(1)
		return
	_build_stage()
	var bus: EventBus = SimAssembly.combat_of(_sim).events()
	bus.subscribe(PerceptionSystem.EVENT_NOISE, _on_noise)
	bus.subscribe(PerceptionSystem.EVENT_ALERTED, _on_alerted)
	bus.subscribe(SensorSystem.EVENT_ALARM, _on_alarm)
	bus.subscribe(HackSystem.EVENT_COMPLETED, _on_hack)
	bus.subscribe(BuildSystem.EVENT_OPENING, _on_opening)
	bus.subscribe(BuildSystem.EVENT_CHECK_FAILED, _on_check_failed)
	bus.subscribe(SiteSystem.EVENT_SPAWNED, _on_site_spawned)
	_scenario.call("setup", _sim, self)


# ---------------------------------------------------------------- scenario API

## Names an actor on screen ("Bob", "Guard") and, when `watched`, makes it one whose
## heat bar is drawn and whom agents' alert colours are measured against.
func name_actor(actor: int, label: String, watched: bool) -> void:
	_names[actor] = label
	if watched and not _watch.has(actor):
		_watch.append(actor)


## A text label pinned to a world point (metres), e.g. "PRIVATE YARD: no entry".
func pin(key: String, at: Vector3, text: String, colour: Color) -> void:
	var label: Label3D
	if _pinned.has(key):
		label = _pinned[key]
	else:
		label = _label3d(28)
		_pinned[key] = label
		add_child(label)
	label.position = at
	label.text = text
	label.modulate = colour


func unpin(key: String) -> void:
	if _pinned.has(key):
		var label: Label3D = _pinned[key]
		label.queue_free()
		_pinned.erase(key)


## A flat tinted slab over a parcel's footprint (metres), for showing land rules.
func slab(at: Vector3, size: Vector2, colour: Color) -> void:
	var node: MeshInstance3D = _box(Vector3(size.x, 0.04, size.y), colour)
	node.position = at + Vector3(size.x / 2.0, 0.03, size.y / 2.0)
	_extra.add_child(node)


func place_camera(eye: Vector3, target: Vector3, ortho_size: float) -> void:
	_camera.position = eye
	_camera.look_at(target, Vector3.UP)
	if ortho_size > 0.0:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = ortho_size


static func world(mm: Vector3i) -> Vector3:
	return Vector3(float(mm.x) / M, float(mm.y) / M, float(mm.z) / M)


# ---------------------------------------------------------------- stage

func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.11, 0.12, 0.15)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -30, 0)
	add_child(sun)
	_camera = Camera3D.new()
	_camera.fov = 50.0
	add_child(_camera)
	_extra = Node3D.new()
	add_child(_extra)
	var layer := CanvasLayer.new()
	add_child(layer)
	_header = _label2d(17, Vector2(18, 12))
	layer.add_child(_header)
	_legend = _label2d(16, Vector2(900, 12))
	_legend.text = "KEY\nblue  = player\ngreen = guard/camera unaware\namber = suspicious / remembers\nred   = alerted\ncone  = what it can see\nrings = noise\nred dot = alarm sensor\ncyan post = hack target\nyellow dots = patrol route"
	layer.add_child(_legend)
	var banner := ColorRect.new()
	banner.color = Color(0, 0, 0, 0.7)
	banner.position = Vector2(0, 700)
	banner.size = Vector2(1280, 100)
	layer.add_child(banner)
	_feed = _label2d(16, Vector2(18, 470))
	layer.add_child(_feed)
	_caption = _label2d(26, Vector2(24, 718))
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD
	_caption.size = Vector2(1230, 80)
	layer.add_child(_caption)


func _label2d(size: int, at: Vector2) -> Label:
	var label := Label.new()
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	return label


func _label3d(size: int) -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0012
	label.font_size = size
	label.outline_size = 10
	label.outline_modulate = Color.BLACK
	return label


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	if _sim == null or _busy:
		return
	var end: int = _scenario.call("end_tick")
	if _sim.get_tick() >= end:
		get_tree().quit(0)
		return
	var per_frame: int = _scenario.call("ticks_per_frame", _sim.get_tick())
	for i: int in per_frame:
		_scenario.call("before_tick", _sim, self, _sim.get_tick() + 1)
		_sim.step()
		_heat_changes()
		_flush_notes()
	_sync(float(per_frame) / float(SimRoot.TICK_HZ))
	var caption: String = _scenario.call("caption", _sim.get_tick())
	_caption.text = caption
	var speed: String = "" if per_frame <= 4 else "   FAST-FORWARD x%d" % (per_frame / 4)
	var title: String = _scenario.call("title")
	_header.text = "%s\nsim time %.1f s (tick %d)%s" % [title, float(_sim.get_tick()) / float(SimRoot.TICK_HZ), _sim.get_tick(), speed]
	if not _frames_dir.is_empty():
		_busy = true
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		var path: String = "%s/f%05d.png" % [_frames_dir, _frame]
		if image.save_png(path) != OK:
			push_error("showcase: cannot save %s" % path)
		_frame += 1
		_busy = false


## The event feed: what just happened, in words, with the sim time it happened at.
## Notes from one tick are shown cause first (a lower `order`), whatever order the bus
## delivered them in: a door check before the alarm it set off.
func note(text: String, order: int = 5) -> void:
	_pending.append([order, _pending.size(), "%5.1f s  %s" % [float(_sim.get_tick()) / float(SimRoot.TICK_HZ), text]])


func _flush_notes() -> void:
	if _pending.is_empty():
		return
	_pending.sort_custom(func(a: Array, b: Array) -> bool:
		var oa: int = a[0]
		var ob: int = b[0]
		if oa != ob:
			return oa < ob
		var ia: int = a[1]
		var ib: int = b[1]
		return ia < ib)
	for entry: Array in _pending:
		var line: String = entry[2]
		_feed_lines.append(line)
	_pending.clear()
	while _feed_lines.size() > 8:
		_feed_lines.remove_at(0)
	_feed.text = "WHAT JUST HAPPENED\n" + "\n".join(_feed_lines)


func _who(actor: int) -> String:
	if _names.has(actor):
		var n: String = _names[actor]
		return n
	return "#%d" % actor


func _on_alerted(p: Dictionary) -> void:
	var observer: int = p["observer"]
	var contact: int = p["contact"]
	if _names.has(observer) and _names.has(contact):
		note("%s spotted %s" % [_who(observer), _who(contact)])


func _on_alarm(p: Dictionary) -> void:
	var actor: int = p["actor"]
	note("ALARM: %s tripped, raised against %s" % [p["sensor"], _who(actor)], 3)


func _on_opening(p: Dictionary) -> void:
	var actor: int = p["actor"]
	var open: bool = p["open"]
	if _names.has(actor):
		note("%s %s a door" % [_who(actor), "opened" if open else "closed"], 1)


func _on_check_failed(p: Dictionary) -> void:
	var actor: int = p["actor"]
	var value: int = p["value"]
	note("Door check FAILED: %s's %s is %d, over the door's limit" % [_who(actor), p["standing"], value], 2)


## A site appeared: name its agents, and draw its parcels, exfil zone, sensors, hack
## targets and patrol routes, which the sim holds but nothing else would show.
func _on_site_spawned(p: Dictionary) -> void:
	var site: StringName = p["site"]
	var ox: int = p["x"]
	var oy: int = p["y"]
	var oz: int = p["z"]
	var origin: Vector3i = Vector3i(ox, oy, oz)
	var content: ContentDb = _sim.get_system(ContentDb.SYSTEM_ID)
	var t: Dictionary = content.get_entry(SiteSystem.KIND_SITE, site)
	var perception: PerceptionSystem = SimAssembly.perception_of(_sim)
	var fresh: int = 0
	for agent: int in perception.agent_ids():
		if not _names.has(agent):
			fresh += 1
			_names[agent] = "Guard %d" % (_names.size() + 1)
	var pieces: Array = t["pieces"]
	note("site.spawn \"%s\": %d pieces and %d guards appeared in one step" % [site, pieces.size(), fresh], 1)
	var land: LandSystem = SimAssembly.land_of(_sim)
	var parcels: Array = t["parcels"]
	for v: Variant in parcels:
		var pr: Dictionary = v
		var pid: String = pr["id"]
		var land_id: StringName = SiteSystem.parcel_id(site, pid)
		_footprint_slab(pr["footprint"], origin, Color(0.55, 0.35, 0.15, 0.35))
		var f: Array = pr["footprint"]
		var first: Array = f[0]
		var fx: int = first[0]
		var fz: int = first[1]
		pin("parcel_" + String(land_id), Vector3(origin.x + fx + 0.5, 0.3, origin.z + fz + 0.5), "parcel owned by '%s'" % land.owner_of(land_id), Color(1.0, 0.75, 0.45))
	_footprint_slab(t["exfil"], origin, Color(0.2, 0.9, 0.4, 0.35))
	var ex: Array = t["exfil"]
	var c0: Array = ex[0]
	var ex_x: int = c0[0]
	var ex_z: int = c0[1]
	pin("exfil_" + String(site), Vector3(origin.x + ex_x + 1.5, 0.3, origin.z + ex_z + 1.0), "EXIT ZONE\n(leave here with the goods)", Color(0.5, 1.0, 0.6))
	var targets: Dictionary = SimAssembly.hacks_of(_sim).snapshot()["targets"]
	for k: Variant in targets:
		var target_id: int = k
		var rec: Dictionary = targets[k]
		var cell: Array = rec["cell"]
		var cx: int = cell[0]
		var cy: int = cell[1]
		var cz: int = cell[2]
		var box: MeshInstance3D = _box(Vector3(0.35, 0.9, 0.35), Color(0.2, 0.95, 1.0))
		box.position = Vector3(cx + 0.5, cy + 0.45, cz + 0.5)
		_extra.add_child(box)
		pin("hack_%d" % target_id, Vector3(cx + 0.5, cy + 1.4, cz + 0.5), "hack target: %s" % rec["target"], Color(0.6, 1.0, 1.0))
	for agent: int in perception.agent_ids():
		var route_s: String = perception.route_of(agent)
		if route_s.is_empty():
			continue
		var route: Dictionary = content.get_entry(PerceptionSystem.KIND_ROUTE, StringName(route_s))
		var ro: Vector3i = perception.route_origin_of(agent)
		var cells: Array = route["cells"]
		for rc: Variant in cells:
			var rv: Vector3i = PathingSystem._vec(rc) + ro
			var dot: MeshInstance3D = _box(Vector3(0.18, 0.05, 0.18), Color(0.95, 0.95, 0.5))
			dot.position = Vector3(rv.x + 0.5, rv.y + 0.06, rv.z + 0.5)
			_extra.add_child(dot)


func _footprint_slab(footprint: Variant, origin: Vector3i, colour: Color) -> void:
	var f: Array = footprint
	var lo: Vector2i = Vector2i(1 << 30, 1 << 30)
	var hi: Vector2i = Vector2i(-(1 << 30), -(1 << 30))
	for v: Variant in f:
		var pair: Array = v
		var x: int = pair[0]
		var z: int = pair[1]
		lo = Vector2i(mini(lo.x, x), mini(lo.y, z))
		hi = Vector2i(maxi(hi.x, x), maxi(hi.y, z))
	slab(Vector3(origin.x + lo.x, 0.0, origin.z + lo.y), Vector2(hi.x - lo.x, hi.y - lo.y), colour)


func _on_hack(p: Dictionary) -> void:
	var actor: int = p["actor"]
	var applied: bool = p["applied"]
	note("%s finished a hack%s" % [_who(actor), "" if applied else " (nothing to affect)"])


func _heat_changes() -> void:
	var standing: StandingSystem = SimAssembly.standing_of(_sim)
	for w: int in _watch:
		var now: int = standing.standing_of(w, &"heat")
		var before: int = _last_heat.get(w, 0)
		if now > before:
			note("%s HEAT +%d  (now %d)" % [_who(w), now - before, now], 4)
		elif now < before:
			note("%s HEAT cooled -%d  (now %d)" % [_who(w), before - now, now])
		_last_heat[w] = now


func _on_noise(p: Dictionary) -> void:
	var x: int = p["x"]
	var y: int = p["y"]
	var z: int = p["z"]
	var loud: int = p["loudness"]
	_rings.append({"pos": Vector3(float(x) / M, float(y) / M + 0.05, float(z) / M), "r": float(loud) / M, "age": 0.0})


func _sync(dt: float) -> void:
	var build: BuildSystem = SimAssembly.build_of(_sim)
	var present: Dictionary = {}
	for id: int in build.piece_ids():
		present[id] = true
		var open: bool = build.is_open(id)
		if _piece_nodes.has(id):
			var existing: MeshInstance3D = _piece_nodes[id]
			var was: bool = existing.get_meta("open", false)
			if was == open:
				continue
			existing.queue_free()
		var node: MeshInstance3D = _piece_mesh(build, id, open)
		node.set_meta("open", open)
		_piece_nodes[id] = node
		add_child(node)
	for id: int in _piece_nodes.keys():
		if not present.has(id):
			var gone: MeshInstance3D = _piece_nodes[id]
			gone.queue_free()
			_piece_nodes.erase(id)
	var actors: ActorSystem = SimAssembly.actors_of(_sim)
	var perception: PerceptionSystem = SimAssembly.perception_of(_sim)
	var standing: StandingSystem = SimAssembly.standing_of(_sim)
	for actor: int in actors.actor_ids():
		if not _names.has(actor):
			continue
		var agent: bool = perception.is_agent(actor)
		if not _actor_nodes.has(actor):
			var node: MeshInstance3D = _capsule()
			_actor_nodes[actor] = node
			add_child(node)
			var label: Label3D = _label3d(30)
			_actor_labels[actor] = label
			add_child(label)
		var capsule: MeshInstance3D = _actor_nodes[actor]
		var tag: Label3D = _actor_labels[actor]
		var feet: Vector3 = world(actors.position_of(actor))
		capsule.position = feet + Vector3(0, 0.9, 0)
		var label_text: String = _names[actor]
		var colour: Color = PLAYER
		if agent:
			capsule.rotation.y = -deg_to_rad(float(perception.facing_of(actor)))
			var state: String = "unaware"
			colour = UNAWARE
			var seen: PackedStringArray = PackedStringArray()
			for w: int in _watch:
				if perception.is_alerted(actor, w):
					var who: String = _names[w]
					seen.append(who)
				elif seen.is_empty() and perception.has_last_known(actor, w):
					colour = SUSPICIOUS
					state = "remembers %s" % _names[w]
				elif perception.awareness_of(actor, w) > PerceptionSystem.AWARENESS_MAX / 20 and seen.is_empty():
					colour = SUSPICIOUS
					state = "suspicious"
			if not seen.is_empty():
				colour = ALERTED
				state = "ALERTED: " + ", ".join(seen)
			label_text += "\n" + state
			_sync_cone(actor, feet, colour)
		else:
			capsule.rotation.y = 0.0
		if not actors.is_alive(actor):
			colour = Color(0.2, 0.2, 0.2)
			label_text += "\n(down)"
		capsule.material_override = _material(colour)
		tag.position = feet + Vector3(0, 2.35, 0)
		tag.modulate = colour.lightened(0.35)
		if _watch.has(actor):
			var heat: int = standing.standing_of(actor, &"heat")
			label_text += "\nHEAT %d" % heat
			_sync_heat_bar(actor, feet, heat)
		tag.text = label_text
	# sensors: a dot on each watched piece, red while live, green once spoofed
	_sync_sensors()
	# noise rings
	for c: MeshInstance3D in _ring_nodes:
		c.queue_free()
	_ring_nodes.clear()
	var kept: Array[Dictionary] = []
	for ring: Dictionary in _rings:
		var age: float = ring["age"]
		age += dt
		ring["age"] = age
		if age < 1.0:
			kept.append(ring)
	_rings = kept
	for ring: Dictionary in _rings:
		var age: float = ring["age"]
		var r: float = ring["r"]
		var torus := TorusMesh.new()
		var rad: float = maxf(0.2, r * minf(1.0, age / 0.4))
		torus.inner_radius = rad - 0.06
		torus.outer_radius = rad
		var node := MeshInstance3D.new()
		node.mesh = torus
		node.material_override = _material(Color(1.0, 0.85, 0.3, clampf(0.8 - age * 0.8, 0.0, 1.0)))
		node.position = ring["pos"]
		add_child(node)
		_ring_nodes.append(node)


var _sensor_nodes: Dictionary = {}


func _sync_sensors() -> void:
	var sensors: SensorSystem = SimAssembly.sensors_of(_sim)
	var build: BuildSystem = SimAssembly.build_of(_sim)
	var recs: Dictionary = sensors.snapshot()["sensors"]
	for k: Variant in recs:
		var piece: int = k
		if not build.has_piece(piece):
			continue
		var node: MeshInstance3D
		if _sensor_nodes.has(piece):
			node = _sensor_nodes[piece]
		else:
			node = MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.16
			sphere.height = 0.32
			node.mesh = sphere
			_sensor_nodes[piece] = node
			add_child(node)
			var cells: Array[Vector3i] = build.cells_of_piece(piece)
			var a: Vector3 = Vector3(cells[0]) + Vector3(0.5, 0.5, 0.5)
			var b: Vector3 = Vector3(cells[cells.size() - 1]) + Vector3(0.5, 0.5, 0.5)
			node.position = (a + b) / 2.0 + Vector3(0, 0.45, 0)
		node.material_override = _material(Color(0.3, 1.0, 0.4) if sensors.is_spoofed(piece) else Color(1.0, 0.15, 0.15))


func _sync_cone(actor: int, feet: Vector3, colour: Color) -> void:
	var perception: PerceptionSystem = SimAssembly.perception_of(_sim)
	var profile: Dictionary = _sim_profile(actor)
	var fov_deg: int = profile["fov_deg"]
	var range_mm: int = profile["sight_range_mm"]
	var fov: float = deg_to_rad(float(fov_deg) / 2.0)
	var reach: float = float(range_mm) / M
	var node: MeshInstance3D
	if _cones.has(actor):
		node = _cones[actor]
	else:
		node = MeshInstance3D.new()
		_cones[actor] = node
		add_child(node)
	var facing: float = deg_to_rad(float(perception.facing_of(actor)))
	node.mesh = _fan(feet + Vector3(0, 0.08, 0), facing, fov, minf(reach, 9.0), Color(colour.r, colour.g, colour.b, 0.13))


func _sim_profile(actor: int) -> Dictionary:
	var perception: PerceptionSystem = SimAssembly.perception_of(_sim)
	var content: ContentDb = _sim.get_system(&"content")
	var agent: Dictionary = content.get_entry(&"agent_profile", perception.profile_of(actor))
	var name: String = agent["perception_profile"]
	return content.get_entry(&"perception_profile", StringName(name))


func _sync_heat_bar(actor: int, feet: Vector3, heat: int) -> void:
	var bar: MeshInstance3D
	if _heat_bars.has(actor):
		bar = _heat_bars[actor]
	else:
		bar = _box(Vector3(0.25, 1.0, 0.25), Color(1.0, 0.45, 0.1))
		_heat_bars[actor] = bar
		add_child(bar)
	var h: float = maxf(0.02, float(heat) / 200.0)
	bar.scale = Vector3(1, h, 1)
	bar.position = feet + Vector3(0.55, h / 2.0, 0)
	bar.visible = heat > 0


func _piece_mesh(build: BuildSystem, id: int, open: bool) -> MeshInstance3D:
	var rec: Dictionary = build.piece(id)
	var face: String = rec["face"]
	var kind: StringName = build.kind_of(id)
	var colour: Color = Color(0.62, 0.62, 0.66)
	match kind:
		&"door": colour = Color(0.78, 0.55, 0.3)
		&"window": colour = Color(0.55, 0.8, 0.98, 0.55)
		&"hatch", &"ladder": colour = Color(0.95, 0.6, 0.15)
		&"grate": colour = Color(0.35, 0.35, 0.42)
		&"stair": colour = Color(0.85, 0.45, 0.2)
		&"crate": colour = Color(0.85, 0.7, 0.2)
		&"foundation": colour = Color(0.42, 0.42, 0.46)
		&"floor": colour = Color(0.56, 0.58, 0.62, 0.5)
	if open:
		colour = Color(colour.r, colour.g, colour.b, 0.25)
	var cell: Vector3i = build.cell_of_piece(id)
	var node: MeshInstance3D
	if face.is_empty():
		node = _box(Vector3(0.98, 0.98, 0.98), colour)
		node.position = Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	else:
		var axis: String = face.split("|")[1]
		var size: Vector3 = Vector3(0.1, 0.98, 0.98) if axis == "x" else (Vector3(0.98, 0.06, 0.98) if axis == "y" else Vector3(0.98, 0.98, 0.1))
		node = _box(size, colour)
		var offset: Vector3 = Vector3(1.0, 0.5, 0.5) if axis == "x" else (Vector3(0.5, 1.0, 0.5) if axis == "y" else Vector3(0.5, 0.5, 1.0))
		node.position = Vector3(cell) + offset
	return node


func _fan(apex: Vector3, facing: float, half: float, length: float, colour: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps: int = 16
	for k: int in steps:
		var a0: float = facing - half + 2.0 * half * float(k) / float(steps)
		var a1: float = facing - half + 2.0 * half * float(k + 1) / float(steps)
		st.add_vertex(apex)
		st.add_vertex(apex + Vector3(cos(a0), 0, sin(a0)) * length)
		st.add_vertex(apex + Vector3(cos(a1), 0, sin(a1)) * length)
	var mesh: ArrayMesh = st.commit()
	mesh.surface_set_material(0, _material(colour))
	return mesh


func _material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	if colour.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _box(size: Vector3, colour: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = _material(colour)
	return node


func _capsule() -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.3
	mesh.height = 1.8
	node.mesh = mesh
	var nose := _box(Vector3(0.35, 0.12, 0.12), Color(0.95, 0.95, 0.95))
	nose.position = Vector3(0.3, 0.55, 0)
	node.add_child(nose)
	return node
