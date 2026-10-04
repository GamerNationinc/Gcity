## The sandbox's inspector (M7.6 spec claim 8): toggleable overlays of what the sim
## knows, drawn over the world. It reads sim queries and writes nothing: a test syncs
## every overlay over a running scene and the state hash at every tick is unchanged.
## Lines go in one ImmediateMesh rebuilt each frame; text in a pool of Label3D nodes.
class_name SandboxInspector extends Node3D

const OVERLAYS: Array[String] = ["sight", "awareness", "memory", "paths", "volumes", "support", "bodies", "parcels"]
const NAMES: Dictionary = {
	"sight": "sight lines, eyes and centres", "awareness": "awareness, alert and stance",
	"memory": "last-known positions", "paths": "current paths", "volumes": "portal volumes and breach costs",
	"support": "support depth per piece", "bodies": "body cells", "parcels": "parcel bounds and owners",
}
## Pieces, portals and parcels drawn only within this of the player, in millimetres.
const NEAR_MM: int = 24_000
const M: float = 1000.0
## The tool class breach costs are shown for.
const TOOL: StringName = &"cutter"

var _on: Dictionary = {}
var _mesh := ImmediateMesh.new()
var _lines := MeshInstance3D.new()
var _labels: Array[Label3D] = []
var _label_next: int = 0


func _init() -> void:
	_lines.mesh = _mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	_lines.material_override = material
	add_child(_lines)


func overlay_count() -> int:
	return OVERLAYS.size()


func is_on(overlay: String) -> bool:
	return _on.get(overlay, false)


## Turns an overlay on or off; false for a name that is not one.
func toggle(overlay: String) -> bool:
	if not OVERLAYS.has(overlay):
		return false
	_on[overlay] = not is_on(overlay)
	return true


func set_all(on: bool) -> void:
	for overlay: String in OVERLAYS:
		_on[overlay] = on


## The overlays on, by name, for the HUD.
func on_list() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for overlay: String in OVERLAYS:
		if is_on(overlay):
			out.append(overlay)
	return out


## Redraws every overlay that is on from what the sim knows now. Reads only.
func sync(sim: SimRoot, player: int) -> void:
	_mesh.clear_surfaces()
	_label_next = 0
	if not on_list().is_empty():
		_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		_draw(sim, player)
		# a surface needs a vertex: an overlay with nothing to show still closes cleanly
		_line(Vector3.ZERO, Vector3.ZERO, Color.BLACK)
		_mesh.surface_end()
	for i: int in range(_label_next, _labels.size()):
		_labels[i].visible = false


func _draw(sim: SimRoot, player: int) -> void:
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var perception: PerceptionSystem = SimAssembly.perception_of(sim)
	var here: Vector3i = actors.position_of(player) if actors.has_actor(player) else Vector3i.ZERO
	for agent: int in perception.agent_ids():
		if not actors.is_alive(agent):
			continue
		var feet: Vector3i = actors.position_of(agent)
		if is_on("sight") and actors.has_actor(player):
			var eye: Vector3 = _v(feet + perception.eye_of(agent))
			var centre: Vector3 = _v(actors.centre_of(player))
			_line(eye, centre, Color(0.2, 1.0, 0.3) if perception.can_see(agent, player) else Color(0.6, 0.2, 0.2))
			_cross(eye, 0.15, Color(0.3, 0.8, 1.0))
			_cross(centre, 0.15, Color(1.0, 1.0, 1.0))
		if is_on("awareness"):
			var aw: int = perception.awareness_of(agent, player)
			_label(_v(feet) + Vector3(0.0, 2.6, 0.0), "%d  aw %d%%%s  %s" % [agent, aw * 100 / PerceptionSystem.AWARENESS_MAX,
				"  ALERT" if perception.is_alerted(agent, player) else "", SimAssembly.stances_of(sim).stance_of(agent)])
		if is_on("memory") and perception.has_last_known(agent, player):
			var last: Vector3 = _v(perception.last_known(agent, player)) + Vector3(0.0, 0.1, 0.0)
			_line(_v(feet) + Vector3(0.0, 0.1, 0.0), last, Color(1.0, 0.85, 0.2))
			_cross(last, 0.3, Color(1.0, 0.85, 0.2))
		if is_on("paths"):
			var prev: Vector3 = _v(feet) + Vector3(0.0, 0.05, 0.0)
			for cell: Vector3i in SimAssembly.pathing_of(sim).path_of(agent):
				var next: Vector3 = _cell_floor(cell) + Vector3(0.0, 0.05, 0.0)
				_line(prev, next, Color(0.9, 0.4, 1.0))
				prev = next
	if is_on("bodies"):
		var movement: MovementSystem = SimAssembly.movement_of(sim)
		for actor: int in actors.actor_ids():
			if actors.is_alive(actor):
				var feet_cell: Vector3i = BuildSystem.cell_of(actors.position_of(actor))
				_box(_cell_floor(feet_cell) - Vector3(0.5, 0.0, 0.5), Vector3(1.0, movement.body_cells(actor), 1.0), Color(0.4, 0.9, 1.0))
	if is_on("support"):
		var build: BuildSystem = SimAssembly.build_of(sim)
		var depth: Dictionary = build.supported_set()
		for id: int in build.piece_ids():
			var at: Vector3i = build.cell_of_piece(id)
			if not _near(BuildSystem.cell_centre(at), here):
				continue
			var d: int = depth.get(id, -1)
			var colour: Color = Color(1.0, 0.0, 1.0) if d < 0 else Color(0.2, 1.0, 0.2).lerp(Color(1.0, 0.2, 0.1), minf(float(d) / 6.0, 1.0))
			_cross(_cell_floor(at) + Vector3(0.0, 0.5, 0.0), 0.2, colour)
	if is_on("volumes"):
		_draw_volumes(sim, here)
	if is_on("parcels"):
		_draw_parcels(sim)


## The volume the player stands in, and for each pair of volumes near it the cheapest
## way between them for a cutter and what it costs (a label per portal buried the view).
func _draw_volumes(sim: SimRoot, here: Vector3i) -> void:
	var portals: PortalGraph = SimAssembly.portals_of(sim)
	var build: BuildSystem = SimAssembly.build_of(sim)
	var node: int = portals.node_at(BuildSystem.cell_of(here))
	_label(_v(here) + Vector3(0.0, 2.9, 0.0), "volume %d%s" % [node, ", %d cells" % portals.cells_in(node) if node > 0 else ""])
	# one label per pair of volumes: the cheapest way between them for a cutter, and its cost
	var best: Dictionary = {}
	for n: int in portals.node_ids():
		for edge: Array in portals.edges_of(n):
			var piece: int = edge[0]
			var other: int = edge[1]
			if not build.has_piece(piece) or not _near(BuildSystem.cell_centre(build.cell_of_piece(piece)), here):
				continue
			var cost: int = portals.edge_cost(piece, TOOL)
			var key: Vector2i = Vector2i(mini(n, other), maxi(n, other))
			if cost < 0:
				continue
			var known: Array = best.get(key, [])
			var better: bool = known.is_empty()
			if not better:
				var known_cost: int = known[0]
				var known_piece: int = known[1]
				better = cost < known_cost or (cost == known_cost and piece < known_piece)
			if better:
				best[key] = [cost, piece]
	for key: Variant in best:
		var pair: Vector2i = key
		var pick: Array = best[key]
		var piece_id: int = pick[1]
		var cost_v: int = pick[0]
		_label(_cell_floor(build.cell_of_piece(piece_id)) + Vector3(0.0, 1.2, 0.0), "volumes %d|%d: %s, cost %d" % [pair.x, pair.y, build.template_of(piece_id), cost_v])


## Every parcel's footprint on its floor, with its owner at the middle.
func _draw_parcels(sim: SimRoot) -> void:
	var land: LandSystem = SimAssembly.land_of(sim)
	for id: StringName in land.parcel_ids():
		var p: Dictionary = land.parcel(id)
		var footprint: Array = p.get("footprint", [])
		if footprint.size() < 3:
			continue
		var y: float = 0.05
		var mid: Vector3 = Vector3.ZERO
		for i: int in footprint.size():
			var a: Array = footprint[i]
			var b: Array = footprint[(i + 1) % footprint.size()]
			var ax: int = a[0]
			var az: int = a[1]
			var bx: int = b[0]
			var bz: int = b[1]
			_line(Vector3(ax / M, y, az / M), Vector3(bx / M, y, bz / M), Color(1.0, 0.6, 0.1))
			mid += Vector3(ax / M, y, az / M)
		mid /= float(footprint.size())
		_label(mid + Vector3(0.0, 0.5, 0.0), "%s: %s" % [id, land.owner_of(id)])


func _near(a: Vector3i, b: Vector3i) -> bool:
	return absi(a.x - b.x) <= NEAR_MM and absi(a.z - b.z) <= NEAR_MM and absi(a.y - b.y) <= NEAR_MM


static func _v(mm: Vector3i) -> Vector3:
	return Vector3(mm.x / M, mm.y / M, mm.z / M)


static func _cell_floor(cell: Vector3i) -> Vector3:
	return Vector3(cell.x + 0.5, cell.y, cell.z + 0.5)


func _line(a: Vector3, b: Vector3, colour: Color) -> void:
	_mesh.surface_set_color(colour)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(colour)
	_mesh.surface_add_vertex(b)


func _cross(at: Vector3, r: float, colour: Color) -> void:
	_line(at - Vector3(r, 0.0, 0.0), at + Vector3(r, 0.0, 0.0), colour)
	_line(at - Vector3(0.0, r, 0.0), at + Vector3(0.0, r, 0.0), colour)
	_line(at - Vector3(0.0, 0.0, r), at + Vector3(0.0, 0.0, r), colour)


func _box(low: Vector3, size: Vector3, colour: Color) -> void:
	var c: Array[Vector3] = []
	for i: int in 8:
		c.append(low + Vector3(size.x if (i & 1) != 0 else 0.0, size.y if (i & 2) != 0 else 0.0, size.z if (i & 4) != 0 else 0.0))
	for pair: Vector2i in [Vector2i(0, 1), Vector2i(2, 3), Vector2i(4, 5), Vector2i(6, 7), Vector2i(0, 2), Vector2i(1, 3),
			Vector2i(4, 6), Vector2i(5, 7), Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7)]:
		_line(c[pair.x], c[pair.y], colour)


func _label(at: Vector3, text: String) -> void:
	if _label_next >= _labels.size():
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 48
		label.pixel_size = 0.004
		label.outline_size = 8
		add_child(label)
		_labels.append(label)
	var l: Label3D = _labels[_label_next]
	_label_next += 1
	l.visible = true
	l.position = at
	l.text = text


## How many labels the last sync showed, for the tests.
func label_count() -> int:
	return _label_next
