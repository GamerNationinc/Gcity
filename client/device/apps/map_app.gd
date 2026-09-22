## The map app (M5 spec claim 3): parcels and their owners, the build, the guards
## you know of, and where you stand, top down and centred on you, drawn from the sim
## each refresh (what the sim holds, not what you know: fog of war is M7).
class_name MapApp extends DeviceApp

const PX_PER_M: float = 8.0

var _last_key: String = ""
var _parcels: Array[Dictionary] = []
var _pieces: Array[Vector3i] = []
var _me: Vector3i = Vector3i.ZERO
var _others: Array[Vector3i] = []
var _me_yaw: float = 0.0


func refresh(sim: SimRoot, player: int) -> bool:
	var land: LandSystem = SimAssembly.land_of(sim)
	var build: BuildSystem = SimAssembly.build_of(sim)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	_me = actors.position_of(player)
	_pieces = []
	for id: int in build.piece_ids():
		_pieces.append(build.cell_of_piece(id))
	_others = []
	for actor: int in actors.actor_ids():
		if actor != player and actors.is_alive(actor):
			_others.append(actors.position_of(actor))
	_parcels = []
	for id: StringName in land.parcel_ids():
		var record: Dictionary = land.parcel(id)
		var owner: StringName = record["owner"]
		var points: PackedVector2Array = PackedVector2Array()
		for v: Variant in record["footprint"]:
			var pair: Array = v
			var px: int = pair[0]
			var pz: int = pair[1]
			points.append(Vector2(float(px), float(pz)))
		_parcels.append({"id": id, "owner": owner, "points": points})
	var key: String = "%s|%d|%d|%d" % [BuildSystem.cell_of(_me), _pieces.size(), _others.size(), _parcels.size()]
	if key == _last_key:
		return false
	_last_key = key
	queue_redraw()
	return true


func _draw() -> void:
	var centre: Vector2 = size / 2.0
	var scale_px: float = PX_PER_M / 1000.0
	# north (+z) up the screen
	var flip: Vector2 = Vector2(scale_px, -scale_px)
	for p: Dictionary in _parcels:
		var pts: PackedVector2Array = PackedVector2Array()
		var points: PackedVector2Array = p["points"]
		for v: Vector2 in points:
			pts.append(centre + (v - Vector2(float(_me.x), float(_me.z))) * flip)
		var owner: StringName = p["owner"]
		var colour: Color = Color(0.25, 0.5, 0.3, 0.6) if owner == &"player" else (Color(0.4, 0.4, 0.42, 0.5) if owner.is_empty() else Color(0.55, 0.28, 0.25, 0.5))
		draw_colored_polygon(pts, colour)
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.9, 0.9, 0.9, 0.6), 1.0)
	for c: Vector3i in _pieces:
		var at: Vector2 = centre + (Vector2(float(c.x * 1000), float((c.z + 1) * 1000)) - Vector2(float(_me.x), float(_me.z))) * flip
		draw_rect(Rect2(at, Vector2(PX_PER_M, PX_PER_M)), Color(0.75, 0.75, 0.78))
	for o: Vector3i in _others:
		var at: Vector2 = centre + (Vector2(float(o.x), float(o.z)) - Vector2(float(_me.x), float(_me.z))) * flip
		draw_circle(at, 4.0, Color(0.9, 0.35, 0.3))
	draw_circle(centre, 5.0, Color(0.3, 0.7, 1.0))
	draw_string(ThemeDB.fallback_font, Vector2(8, 24), "north up   1 square = 1 m   you: (%d, %d) m" % [_me.x / 1000, _me.z / 1000], HORIZONTAL_ALIGNMENT_LEFT, -1, DeviceShell.SECONDARY_PX, Color(0.9, 0.9, 0.9))


func prompts(_glyphs: InputGlyphs) -> String:
	return "centred on you; green yours, red owned by others, grey unowned"
