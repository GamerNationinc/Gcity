## Renders generated worlds in 3D for inspection (M7): terrain, roads, places, towns and
## the wild region's voxel ground, from the same sim classes the game runs. Not the
## client: nothing here streams anything, and claim 16's world view is where that
## belongs. This exists so a person can look at what the generator makes.
##
##   godot --path . -s tools/render_world.gd -- --seed=20261250 --mode=overview --out=/tmp/w.png
##   godot --path . -s tools/render_world.gd -- --seed=20261250 --mode=closeup --out=/tmp/c.png
##
## `overview` draws the whole world south of the gate at a coarse grid, heights
## exaggerated so the land reads at that scale. `closeup` draws a kilometre around the
## first point of interest from the voxel ground itself, a column per two metres, so
## cuttings, bridges and the step of the cells show.
extends SceneTree

const OVERVIEW_STEP_MM: int = 250_000
const OVERVIEW_EXAGGERATION: float = 6.0
const CLOSEUP_HALF_MM: int = 500_000
const CLOSEUP_STEP_MM: int = 2_000
const SIZE: Vector2i = Vector2i(1600, 1000)

var _seed: int = 20261250
var _mode: String = "overview"
var _out: String = "world.png"


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--mode="):
			_mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	root.size = SIZE
	var db := ContentDb.new()
	if ContentLoader.load_all(db) != OK:
		push_error("render_world: content did not load")
		quit(1)
		return
	var sim: SimRoot = SimAssembly.build(_seed, db)
	var routes: RouteGraph = SimAssembly.routes_of(sim)
	var terrain: Terrain = SimAssembly.terrain_of(sim)
	var regions: Regions = SimAssembly.regions_of(sim)
	var scene := Node3D.new()
	root.add_child(scene)
	_lights(scene)
	if _mode == "closeup":
		_closeup(scene, routes, terrain, regions)
	else:
		_overview(scene, routes, terrain)
	_capture.call_deferred()


func _capture() -> void:
	for i: int in 8:
		await process_frame
	var image: Image = root.get_texture().get_image()
	var err: Error = image.save_png(_out)
	print("render_world: seed %d %s -> %s (%s)" % [_seed, _mode, _out, error_string(err)])
	quit(0 if err == OK else 1)


func _lights(scene: Node3D) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	scene.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.72, 0.82)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.environment = e
	scene.add_child(env)


# ---------------------------------------------------------------- overview

func _overview(scene: Node3D, routes: RouteGraph, terrain: Terrain) -> void:
	var r: int = RouteGraph.WORLD_RADIUS_MM
	var x0: int = -r
	var x1: int = r
	var z0: int = -r
	var z1: int = 0
	var nx: int = (x1 - x0) / OVERVIEW_STEP_MM + 1
	var nz: int = (z1 - z0) / OVERVIEW_STEP_MM + 1
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	var lo: float = 1e9
	var hi: float = -1e9
	for iz: int in nz:
		for ix: int in nx:
			var h: float = terrain.ground_mm(x0 + ix * OVERVIEW_STEP_MM, z0 + iz * OVERVIEW_STEP_MM) / 1000.0
			heights[iz * nx + ix] = h
			lo = minf(lo, h)
			hi = maxf(hi, h)
	var km: float = 1.0 / 1000.0
	var mesh := _grid_mesh(nx, nz, func(ix: int, iz: int) -> Vector3:
		return Vector3((x0 + ix * OVERVIEW_STEP_MM) * km * km, heights[iz * nx + ix] * OVERVIEW_EXAGGERATION * km, (z0 + iz * OVERVIEW_STEP_MM) * km * km),
		func(ix: int, iz: int) -> Color:
			return _height_colour(heights[iz * nx + ix], lo, hi))
	scene.add_child(mesh)
	# roads, at the road's own height, lifted a little so they read over the ground
	var lines := ImmediateMesh.new()
	var road_mat := StandardMaterial3D.new()
	road_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	road_mat.vertex_color_use_as_albedo = true
	lines.surface_begin(Mesh.PRIMITIVE_LINES, road_mat)
	for id: int in routes.edge_ids():
		var rec: Dictionary = routes.edge(id)
		var length: int = rec["length"]
		var steps: int = maxi(1, length / 500_000)
		var from: int = rec["a"]
		var colour: Color = Color(0.95, 0.85, 0.3) if routes.node_town(from) == EntityIds.NONE else Color(0.9, 0.4, 0.2)
		for i: int in steps:
			for along: int in [length * i / steps, length * (i + 1) / steps]:
				var at: Vector2i = terrain.road_at(id, along)
				lines.surface_set_color(colour)
				lines.surface_add_vertex(Vector3(at.x * km * km, terrain.road_mm(id, along) / 1000.0 * OVERVIEW_EXAGGERATION * km + 0.05, at.y * km * km))
	lines.surface_end()
	var road_node := MeshInstance3D.new()
	road_node.mesh = lines
	scene.add_child(road_node)
	for node: int in routes.node_ids():
		var at: Vector2i = routes.position_of(node)
		var kind: StringName = routes.kind_of(node)
		var size: float = 0.35 if kind == RouteGraph.KIND_GATE else (0.22 if kind == RouteGraph.KIND_SETTLEMENT else (0.15 if kind == RouteGraph.KIND_POI else 0.06))
		var palette: Dictionary = {RouteGraph.KIND_GATE: Color.WHITE, RouteGraph.KIND_SETTLEMENT: Color(0.85, 0.2, 0.2), RouteGraph.KIND_POI: Color(0.2, 0.3, 0.9)}
		var colour: Color = palette.get(kind, Color(0.3, 0.3, 0.3))
		if routes.node_town(node) != EntityIds.NONE:
			continue
		_marker(scene, Vector3(at.x * km * km, terrain.node_height_mm(node) / 1000.0 * OVERVIEW_EXAGGERATION * km + size, at.y * km * km), size, colour)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 26, 14)
	cam.look_at_from_position(cam.position, Vector3(0, 0, -14), Vector3.UP)
	cam.fov = 60
	scene.add_child(cam)
	cam.current = true
	print("render_world: %d places, %d roads, %d towns, ground %.0f to %.0f m" % [routes.node_count(), routes.edge_count(), routes.town_count(), lo, hi])


# ---------------------------------------------------------------- close-up

func _closeup(scene: Node3D, routes: RouteGraph, terrain: Terrain, regions: Regions) -> void:
	var centre: Vector2i = Vector2i.ZERO
	for node: int in routes.node_ids():
		if routes.kind_of(node) == RouteGraph.KIND_POI:
			centre = routes.position_of(node)
			break
	var n: int = CLOSEUP_HALF_MM * 2 / CLOSEUP_STEP_MM + 1
	var levels := PackedInt32Array()
	levels.resize(n * n)
	var on_road := PackedByteArray()
	on_road.resize(n * n)
	var lo: int = 1_000_000
	var hi: int = -1_000_000
	for iz: int in n:
		for ix: int in n:
			var x: int = centre.x - CLOSEUP_HALF_MM + ix * CLOSEUP_STEP_MM
			var z: int = centre.y - CLOSEUP_HALF_MM + iz * CLOSEUP_STEP_MM
			var y: int = regions.standing_cell_y(x, z)
			# tools may look behind Region (rule 5 is about sim/ and client/): the wild
			# region knows which columns carry a road
			var wild: WildRegion = regions.region_at(x, z) as WildRegion
			var road: bool = wild != null and wild._column(Terrain._floor_div(x, 1000), Terrain._floor_div(z, 1000)).y != WildRegion.NO_ROAD
			levels[iz * n + ix] = y
			on_road[iz * n + ix] = 1 if road else 0
			lo = mini(lo, y)
			hi = maxi(hi, y)
	var scale: float = 1.0 / 20.0
	var mesh := _grid_mesh(n, n, func(ix: int, iz: int) -> Vector3:
		return Vector3((ix * CLOSEUP_STEP_MM - CLOSEUP_HALF_MM) / 1000.0 * scale, levels[iz * n + ix] * scale, (iz * CLOSEUP_STEP_MM - CLOSEUP_HALF_MM) / 1000.0 * scale),
		func(ix: int, iz: int) -> Color:
			if on_road[iz * n + ix] == 1:
				return Color(0.35, 0.33, 0.3)
			return _height_colour(levels[iz * n + ix], lo, hi))
	scene.add_child(mesh)
	var cam := Camera3D.new()
	cam.position = Vector3(-14, 22, 30)
	cam.look_at_from_position(cam.position, Vector3(0, (lo + hi) * 0.5 * scale, 0), Vector3.UP)
	cam.fov = 55
	scene.add_child(cam)
	cam.current = true
	print("render_world: close-up of %s, standing levels %d to %d, %d road columns" % [centre, lo, hi, on_road.count(1)])


# ---------------------------------------------------------------- helpers

func _grid_mesh(nx: int, nz: int, point: Callable, colour: Callable) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz: int in nz - 1:
		for ix: int in nx - 1:
			for corner: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var cx: int = ix + corner.x
				var cz: int = iz + corner.y
				var c: Color = colour.call(cx, cz)
				st.set_color(c)
				var p: Vector3 = point.call(cx, cz)
				st.add_vertex(p)
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	node.material_override = mat
	return node


func _marker(scene: Node3D, at: Vector3, size: float, colour: Color) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	var node := MeshInstance3D.new()
	node.mesh = sphere
	node.material_override = mat
	node.position = at
	scene.add_child(node)


static func _height_colour(h: float, lo: float, hi: float) -> Color:
	var t: float = 0.0 if hi <= lo else clampf((h - lo) / (hi - lo), 0.0, 1.0)
	if t < 0.5:
		return Color(0.25, 0.42, 0.2).lerp(Color(0.55, 0.5, 0.3), t * 2.0)
	return Color(0.55, 0.5, 0.3).lerp(Color(0.85, 0.85, 0.82), (t - 0.5) * 2.0)
