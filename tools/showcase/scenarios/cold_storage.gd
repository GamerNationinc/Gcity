## Showcase for M6 claim 13 (Cold Storage, authored). The site rises from its content
## file, then the tour peels it storey by storey: storey 1 (the terminal and two
## patrols), the ground floor (the lobby camera's view, the post behind the front door),
## the basement and the city's tunnel. The three ways in are drawn as coloured paths:
## FRONT (orange), SIDE (purple), UNDER (cyan); the under route never crosses the
## camera's view.
extends RefCounted

const O: Vector3i = Vector3i(40, 0, 10)

const FRONT: Array[Vector3i] = [Vector3i(2, 0, -3), Vector3i(2, 0, -2), Vector3i(2, 0, -1), Vector3i(2, 0, 0), Vector3i(2, 0, 1), Vector3i(3, 0, 1), Vector3i(4, 0, 1), Vector3i(5, 0, 1), Vector3i(5, 0, 3), Vector3i(5, 0, 5), Vector3i(8, 0, 5), Vector3i(9, 0, 5), Vector3i(9, 1, 6), Vector3i(7, 1, 5), Vector3i(5, 1, 5), Vector3i(3, 1, 5), Vector3i(2, 1, 6)]
const SIDE: Array[Vector3i] = [Vector3i(13, 0, 2), Vector3i(12, 0, 2), Vector3i(11, 0, 2), Vector3i(11, 0, 1), Vector3i(10, 1, 1), Vector3i(9, 1, 1), Vector3i(8, 1, 1), Vector3i(7, 1, 2), Vector3i(7, 1, 3), Vector3i(7, 1, 4), Vector3i(6, 1, 5), Vector3i(4, 1, 5), Vector3i(3, 1, 6)]
const UNDER: Array[Vector3i] = [Vector3i(0, 0, -3), Vector3i(1, 0, -3), Vector3i(1, -1, -3), Vector3i(2, -1, -3), Vector3i(3, -1, -3), Vector3i(4, -1, -3), Vector3i(4, -1, -2), Vector3i(4, -1, -1), Vector3i(4, -1, 0), Vector3i(4, -1, 2), Vector3i(4, -1, 4), Vector3i(6, -1, 4), Vector3i(7, -1, 4), Vector3i(7, 0, 5), Vector3i(9, 0, 5), Vector3i(9, 1, 6), Vector3i(6, 1, 6), Vector3i(4, 1, 6), Vector3i(2, 1, 7)]

var _phase: int = 0


func title() -> String:
	return "Gcity M6 claim 13: COLD STORAGE, three ways in"


func content(_db: ContentDb) -> void:
	pass


func _abs(cells: Array[Vector3i]) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for c: Vector3i in cells:
		out.append(c + O)
	return out


func setup(_sim: SimRoot, view: Node3D) -> void:
	var o: Vector3 = Vector3(O.x + 6, 0, O.z + 3)
	view.call("slab", Vector3(O.x - 4, -0.02, O.z - 8), Vector2(24, 22), Color(0.3, 0.32, 0.36))
	view.call("place_camera", o + Vector3(-13, 18, -17), o + Vector3(0, -0.5, 0), 22.0)


func before_tick(sim: SimRoot, view: Node3D, tick: int) -> void:
	var o: Vector3 = Vector3(O.x, 0, O.z)
	match tick:
		20:
			sim.submit(SimCommand.new(tick, &"site.spawn", {"site": "cold_storage", "origin": [O.x, O.y, O.z]}))
		24:
			view.call("marker_path", _abs(FRONT), Color(1.0, 0.55, 0.1))
			view.call("marker_path", _abs(SIDE), Color(0.75, 0.4, 1.0))
			view.call("marker_path", _abs(UNDER), Color(0.2, 0.9, 1.0))
			view.call("pin", "front", o + Vector3(2.5, 0.4, -3.6), "FRONT: keycard door\n(lobby camera watches it)", Color(1.0, 0.7, 0.35))
			view.call("pin", "side", o + Vector3(13.5, 0.4, 2.6), "SIDE: up the crate,\nin by the window", Color(0.85, 0.6, 1.0))
			view.call("pin", "under", o + Vector3(-0.5, 0.4, -4.4), "UNDER: street grate,\ntunnel, basement", Color(0.5, 0.95, 1.0))
			_phase = 1
		200:
			view.call("cutaway", 1)
			view.call("pin", "floor", o + Vector3(5, 3.2, 8.5), "STOREY 1: server room (terminal),\nmaintenance room, two patrols", Color(1, 1, 1))
			_phase = 2
		400:
			view.call("cutaway", 0)
			view.call("unpin", "floor")
			view.call("pin", "floor0", o + Vector3(5, 2.2, 8.5), "GROUND: lobby with camera and post,\nhall, stairs up and down", Color(1, 1, 1))
			_phase = 3
		600:
			view.call("cutaway", -1)
			view.call("unpin", "floor0")
			view.call("pin", "floorb", o + Vector3(5, 1.0, 8.5), "BASEMENT and the city's tunnel\n(a separate parcel under the street)", Color(1, 1, 1))
			_phase = 4


func ticks_per_frame(_tick: int) -> int:
	return 4


func end_tick() -> int:
	return 800


func caption(_tick: int) -> String:
	match _phase:
		0:
			return "Cold Storage is about to rise from one content file: three storeys, five guards, a camera, a terminal with the data."
		1:
			return "Three ways in. FRONT (orange): the keycard door, under the camera. SIDE (purple): climb the yard crate, in by the alarmed window. UNDER (cyan): cut the street grate, crawl the tunnel."
		2:
			return "Roof off. Storey 1: the server-room terminal (cyan post) holds the data; two guards patrol; the maintenance window has an alarm (red dot)."
		3:
			return "Ground floor: the lobby camera watches the front door, a guard stands behind it. The cyan path comes up the basement stairs outside the camera's view."
	return "Basement and the city's service tunnel under the street. The UNDER route is the only one the lobby camera never sees (checked by a test over its whole sweep)."
