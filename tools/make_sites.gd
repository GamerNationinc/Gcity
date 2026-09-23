## Authors the `content/site/` files (M6 spec claims 3–4). A site is content; this is
## how that content is written, the way `tools/make_m4_fixtures.gd` writes fixtures:
## the layout lives here as code because a hand-typed list of four hundred cells is
## not reviewable, and the JSON it emits is the artefact the sim reads.
##   godot --headless --path . -s tools/make_sites.gd
extends SceneTree

const OUT_DIR: String = "res://content/site"

var _pieces: Array = []
var _spawns: Array = []
var _terminals: Array = []


func _initialize() -> void:
	_m4_test_building()
	_cold_storage()
	quit(0)


# ---------------------------------------------------------------- the M4 building

## The M4 test building, unchanged, as a site file: the format proven by the thing
## that already worked (spec claim 3). Lobby with a door and two side windows, a
## corridor north, two rooms with outside windows, the wing roofed.
func _m4_test_building() -> void:
	_begin()
	for f: Vector3i in [Vector3i(-1, 0, -1), Vector3i(5, 0, -1), Vector3i(-1, 0, 4), Vector3i(5, 0, 4),
			Vector3i(3, 0, 4), Vector3i(3, 0, 10), Vector3i(5, 0, 10),
			Vector3i(-1, 0, 6), Vector3i(-1, 0, 10), Vector3i(9, 0, 6), Vector3i(9, 0, 10)]:
		_place("foundation_block", f, "")
	for x: int in 5:
		_place("door_frame" if x == 2 else "wall_panel", Vector3i(x, 0, 0), "nz")
	for z: int in 4:
		_place("window_frame" if z == 2 else "wall_panel", Vector3i(0, 0, z), "nx")
		_place("window_frame" if z == 2 else "wall_panel", Vector3i(4, 0, z), "px")
	for x: int in 4:
		_place("wall_panel", Vector3i(x, 0, 3), "pz")
	for z: int in range(4, 10):
		_place("door_frame" if z == 8 else "wall_panel", Vector3i(4, 0, z), "nx")
		_place("door_frame" if z == 8 else "wall_panel", Vector3i(4, 0, z), "px")
	_place("wall_panel", Vector3i(4, 0, 9), "pz")
	for x: int in range(0, 4):
		_place("wall_panel", Vector3i(x, 0, 7), "nz")
		_place("wall_panel", Vector3i(x, 0, 9), "pz")
	for z: int in range(7, 10):
		_place("window_frame" if z == 8 else "wall_panel", Vector3i(0, 0, z), "nx")
	for x: int in range(5, 9):
		_place("wall_panel", Vector3i(x, 0, 7), "nz")
		_place("wall_panel", Vector3i(x, 0, 9), "pz")
	for z: int in range(7, 10):
		_place("window_frame" if z == 8 else "wall_panel", Vector3i(8, 0, z), "px")
	for z: int in range(4, 10):
		_place("floor_panel", Vector3i(4, 0, z), "py")
	for z: int in range(7, 10):
		for x: int in range(0, 4):
			_place("floor_panel", Vector3i(x, 0, z), "py")
		for x: int in range(5, 9):
			_place("floor_panel", Vector3i(x, 0, z), "py")
	_spawn("guard_sim", Vector3i(2, 0, 3), 270, 1, "")
	_spawn("guard_sim", Vector3i(0, 0, 1), 0, 1, "lobby_round")
	_spawn("guard_sim", Vector3i(4, 0, 4), 90, 1, "wing_patrol")
	_spawn("guard_sim", Vector3i(7, 0, 8), 180, 1, "wing_patrol_reverse")
	_write("m4_test_building", "M4 test building", Vector3i(3, 0, 8), ["starter_plot", "neighbour_north"],
		"The M4 perception building, unchanged, as a site file: a lobby with a door and two side windows, a corridor north, two rooms with outside windows, the wing roofed. Four guards: a post behind the door, a roamer, two patrollers on opposite loops.")


# ---------------------------------------------------------------- Cold Storage

## The mission site (design doc §15.2): a slab of ground, two storeys on it, a
## service tunnel that is a gap left in the slab, and three routes in that converge
## on the server room.
##
## Levels, relative to the base cell:
##   level 0   the slab: foundations everywhere the site stands, except the tunnel
##             column (x 4, z -2..8), which is the gap the tunnel runs through
##   level 1   the ground floor and the street around it: lobby x 0..4 z 0..3 with
##             its street door at x 2 (a door check: the front route), a stair well
##             at x 2 z 4..5, a back hall x 0..4 z 6..8, the server room x 1..3
##             z 9..11 behind one door
##   level 2   the upper floor over all of it, reached by the inside flight or by the
##             fire stair outside the east wall to a maintenance window (the side
##             route)
## The under route: cut the grate in the street at x 4, z -2 (a floor panel the
## player removes), climb down into the tunnel, walk north under the building, and
## climb the ladder into the back hall, past the lobby entirely.
func _cold_storage() -> void:
	_begin()
	# --- the slab: the ground the site stands on, with the tunnel left open
	for x: int in range(-2, 8):
		for z: int in range(-4, 14):
			if x == 4 and z >= -2 and z <= 8:
				continue
			_place("foundation_block", Vector3i(x, 0, z), "")
	# --- the ground floor over the tunnel column: a grate in the street, floors
	# inside, and the ladder's opening at the north end
	_place("floor_panel", Vector3i(4, 1, -2), "ny")   # the grate: cut it to get in
	for z: int in range(-1, 9):
		_place("roof_hatch" if z == 8 else "floor_panel", Vector3i(4, 1, z), "ny")
	_place("stair_flight", Vector3i(4, 0, -2), "px")  # the ladder down from the grate
	_place("stair_flight", Vector3i(4, 1, -2), "px")
	_place("stair_flight", Vector3i(4, 0, 8), "nx")   # and up into the back hall
	_place("stair_flight", Vector3i(4, 1, 8), "nx")
	# --- ground floor walls
	for x: int in 5:
		_place("door_check" if x == 2 else "wall_panel", Vector3i(x, 1, 0), "nz")
	for z: int in range(0, 12):
		_place("wall_panel", Vector3i(0, 1, z), "nx")
		_place("wall_panel", Vector3i(4, 1, z), "px")
	for x: int in [0, 1, 3, 4]:
		_place("wall_panel", Vector3i(x, 1, 3), "pz")
	for x: int in range(1, 4):
		_place("door_frame" if x == 2 else "wall_panel", Vector3i(x, 1, 8), "pz")
	_place("wall_panel", Vector3i(0, 1, 9), "px")
	_place("wall_panel", Vector3i(4, 1, 9), "nx")
	for x: int in range(1, 4):
		_place("wall_panel", Vector3i(x, 1, 11), "pz")
	# --- the inside flight, lobby to upper floor, in the stair well
	_place("stair_flight", Vector3i(2, 1, 4), "nx")
	_place("stair_flight", Vector3i(2, 2, 4), "nx")
	# --- the upper floor, with the stair well left open
	for x: int in 5:
		for z: int in range(0, 12):
			if x == 2 and z == 4:
				continue
			_place("floor_panel", Vector3i(x, 2, z), "ny")
	for x: int in 5:
		_place("wall_panel", Vector3i(x, 2, 0), "nz")
	for z: int in range(0, 9):
		_place("wall_panel", Vector3i(0, 2, z), "nx")
		_place("window_frame" if z == 7 else "wall_panel", Vector3i(4, 2, z), "px")
	for x: int in 5:
		_place("wall_panel", Vector3i(x, 2, 8), "pz")
	# the roof
	for x: int in 5:
		for z: int in range(0, 9):
			_place("floor_panel", Vector3i(x, 3, z), "ny")
	# --- the fire stair outside the east wall: the side route
	_place("stair_flight", Vector3i(5, 1, 7), "px")
	_place("stair_flight", Vector3i(5, 2, 7), "px")
	# --- the step up off the street (M6 spec claim 1's rules applied to the site's own
	# edge): the slab is a metre above the pavement, and a level change needs something
	# to climb, so a building nobody can walk up to is a building nobody can rob. The
	# landing is a hatch, because a solid floor panel is the ceiling of the cell below
	# and refuses to be climbed through.
	_place("roof_hatch", Vector3i(4, 1, -5), "ny")
	_place("stair_flight", Vector3i(4, 1, -5), "nz")
	# --- the guards (design doc §15.3): a lobby post, two upstairs, one roaming
	_armed_spawn("guard_sim", Vector3i(2, 1, 2), 270, 2, "")
	_armed_spawn("guard_sim", Vector3i(1, 1, 7), 90, 2, "cs_hall_round")
	_armed_spawn("guard_sim", Vector3i(1, 2, 2), 90, 2, "cs_upper_patrol")
	_armed_spawn("guard_sim", Vector3i(3, 2, 6), 270, 2, "cs_upper_patrol_reverse")
	# the server the three routes converge on, in the back room
	_terminal("cs_server", Vector3i(2, 1, 10))
	_write("cold_storage", "Cold Storage", Vector3i(40, 0, 40), ["cold_storage_lot"],
		"The first contract's site (design doc §15): a slab of ground, a lobby whose street door checks for a token, a stair well to an upper floor with a maintenance window off the outside fire stair, and a service tunnel that is a gap in the slab, entered by cutting a street grate. Three routes in, one server room.")


# ---------------------------------------------------------------- writing

func _begin() -> void:
	_pieces = []
	_spawns = []
	_terminals = []


func _place(piece: String, rel: Vector3i, facing: String) -> void:
	_pieces.append({"piece": piece, "rel": [rel.x, rel.y, rel.z], "facing": facing})


func _terminal(terminal: String, rel: Vector3i) -> void:
	_terminals.append({"terminal": terminal, "rel": [rel.x, rel.y, rel.z]})


func _spawn(profile: String, rel: Vector3i, facing: int, squad: int, route: String) -> void:
	_spawns.append({"profile": profile, "rel": [rel.x, rel.y, rel.z], "facing": facing, "squad": squad, "route": route})


## A guard with something in its hands. The M4 building's guards stay unarmed: its
## client arms them itself and its fixtures were recorded that way.
func _armed_spawn(profile: String, rel: Vector3i, facing: int, squad: int, route: String) -> void:
	_spawns.append({"profile": profile, "rel": [rel.x, rel.y, rel.z], "facing": facing, "squad": squad, "route": route,
		"kit": {"frame": "g19", "magazine": "g19_mag_15", "ammo": "9x19_fmj", "rounds": 15}})


func _write(id: String, title: String, base: Vector3i, parcels: Array, description: String) -> void:
	var site: Dictionary = {
		"schema_version": 1, "description": description, "title": title,
		"base": [base.x, base.y, base.z], "parcels": parcels,
		"pieces": _pieces, "spawns": _spawns, "terminals": _terminals,
	}
	var file: FileAccess = FileAccess.open("%s/%s.json" % [OUT_DIR, id], FileAccess.WRITE)
	assert(file != null, "open %s" % id)
	file.store_string(JSON.stringify(site, "\t") + "\n")
	file.close()
	print("wrote %s: %d pieces, %d spawns, %d terminals" % [id, _pieces.size(), _spawns.size(), _terminals.size()])
