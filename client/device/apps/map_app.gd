## The map app (M5 spec claim 3): parcels and their owners, the build, the guards
## you know of, and where you stand, top down and centred on you, drawn from the sim
## each refresh.
##
## Two pages (M7 spec claim 16), select to switch. The local page is the one above. The
## world page is the route graph: the places you have found and the roads out of them,
## the sites your contracts are bound to whether you have been there or not (the fixer
## told you where), and you on it. What you have not found is not drawn: that is the
## fog, and discovery (claim 15) is what lifts it.
class_name MapApp extends DeviceApp

const PX_PER_M: float = 8.0
## The world page's scale: forty metres to a pixel, which puts a few kilometres of the
## graph round you on the device's screen.
const WORLD_M_PER_PX: float = 40.0
const PAGE_LOCAL: int = 0
const PAGE_WORLD: int = 1

var _last_key: String = ""
var _parcels: Array[Dictionary] = []
var _pieces: Array[Vector3i] = []
var _me: Vector3i = Vector3i.ZERO
var _others: Array[Vector3i] = []
var _me_yaw: float = 0.0
var _page: int = PAGE_LOCAL
## The world page's draw cache, rebuilt from the sim every refresh: road segments as
## pairs of points in millimetres, found places as [x, z, kind], bound sites as
## [x, z, contract].
var _roads: PackedVector2Array = PackedVector2Array()
var _places: Array[Array] = []
var _sites: Array[Array] = []


func handle(action: StringName, _sim: SimRoot, _player: int) -> bool:
	if action != &"device_select":
		return false
	_page = PAGE_WORLD if _page == PAGE_LOCAL else PAGE_LOCAL
	_last_key = ""
	return true


func refresh(sim: SimRoot, player: int) -> bool:
	if _page == PAGE_WORLD:
		return _refresh_world(sim, player)
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


## The world page from the sim: found places, the roads out of them, the bound sites.
func _refresh_world(sim: SimRoot, player: int) -> bool:
	var routes: RouteGraph = SimAssembly.routes_of(sim)
	var discovery: Discovery = SimAssembly.discovery_of(sim)
	var binder: SiteBinder = SimAssembly.binder_of(sim)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	_me = actors.position_of(player)
	_roads = PackedVector2Array()
	_places = []
	for id: int in routes.edge_ids():
		var rec: Dictionary = routes.edge(id)
		var a: int = rec["a"]
		var b: int = rec["b"]
		if not discovery.is_found(a) and not discovery.is_found(b):
			continue
		var pa: Vector2i = routes.position_of(a)
		var pb: Vector2i = routes.position_of(b)
		_roads.append(Vector2(pa))
		_roads.append(Vector2(pb))
	for node: int in discovery.found_nodes():
		var at: Vector2i = routes.position_of(node)
		_places.append([at.x, at.y, String(routes.kind_of(node))])
	_sites = []
	for quest: StringName in binder.bound_quests():
		var site: int = binder.node_of(quest)
		var at: Vector2i = routes.position_of(site)
		_sites.append([at.x, at.y, String(quest)])
	var key: String = "w|%d|%d|%d|%d|%d" % [_me.x / 40_000, _me.z / 40_000, _places.size(), _sites.size(), _roads.size()]
	if key == _last_key:
		return false
	_last_key = key
	queue_redraw()
	return true


func _draw() -> void:
	if _page == PAGE_WORLD:
		_draw_world()
		return
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


func _draw_world() -> void:
	var centre: Vector2 = size / 2.0
	var scale_px: float = 1.0 / (WORLD_M_PER_PX * 1000.0)
	var flip: Vector2 = Vector2(scale_px, -scale_px)
	var me: Vector2 = Vector2(float(_me.x), float(_me.z))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.12, 0.1))
	for i: int in range(0, _roads.size(), 2):
		draw_line(centre + (_roads[i] - me) * flip, centre + (_roads[i + 1] - me) * flip, Color(0.85, 0.75, 0.4, 0.8), 2.0)
	for place: Array in _places:
		var x: int = place[0]
		var z: int = place[1]
		var kind: String = place[2]
		var colour: Color = Color.WHITE if kind == "gate" else (Color(0.85, 0.3, 0.25) if kind == "settlement" else (Color(0.35, 0.5, 0.95) if kind == "poi" else Color(0.6, 0.6, 0.6)))
		draw_circle(centre + (Vector2(float(x), float(z)) - me) * flip, 4.0 if kind != "crossing" else 2.0, colour)
	for site: Array in _sites:
		var x: int = site[0]
		var z: int = site[1]
		var name: String = site[2]
		var at: Vector2 = centre + (Vector2(float(x), float(z)) - me) * flip
		draw_rect(Rect2(at - Vector2(5, 5), Vector2(10, 10)), Color(1.0, 0.8, 0.2), false, 2.0)
		draw_string(ThemeDB.fallback_font, at + Vector2(8, 4), name.replace("_", " "), HORIZONTAL_ALIGNMENT_LEFT, -1, DeviceShell.SECONDARY_PX, Color(1.0, 0.85, 0.4))
	draw_circle(centre, 5.0, Color(0.3, 0.7, 1.0))
	draw_string(ThemeDB.fallback_font, Vector2(8, 24), "the world   north up   1 px = %d m   you: (%d, %d) km" % [int(WORLD_M_PER_PX), _me.x / 1_000_000, _me.z / 1_000_000],
		HORIZONTAL_ALIGNMENT_LEFT, -1, DeviceShell.SECONDARY_PX, Color(0.9, 0.9, 0.9))


func prompts(glyphs: InputGlyphs) -> String:
	var switch: String = glyphs.glyph(&"device_select") if glyphs != null else "select"
	if _page == PAGE_WORLD:
		return "the world: places you have found, roads out of them, your contracts' sites   %s: this block" % switch
	return "centred on you; green yours, red owned by others, grey unowned   %s: the world" % switch
