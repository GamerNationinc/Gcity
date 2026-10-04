## Authors the `content/site/` files (M6 spec claims 3–4). A site is content; this is
## how that content is written, the way `tools/make_m4_fixtures.gd` writes fixtures:
## the layout lives here as code because a hand-typed list of four hundred cells is
## not reviewable, and the JSON it emits is the artefact the sim reads.
##   godot --headless --path . -s tools/make_sites.gd
##
## Human scale (M7.5 spec decisions 1 and 3, claim 6): a person is two cells tall, a
## storey is three, and an opening is a column of faces. A wall is three wall faces; a
## door is two door faces under a wall face (a 2 m door); a window is a wall face, a
## window face and a wall face (a sill at 1 m, so a person sees through it and does not
## walk through it); a tall window is two window faces under a wall face, for the one
## window a route climbs in by.
extends SceneTree

const OUT_DIR: String = "res://content/site"
## Cells from one floor to the next.
const STOREY: int = 3

var _pieces: Array = []
var _spawns: Array = []
var _terminals: Array = []


func _initialize() -> void:
	_m4_test_building()
	_cold_storage()
	quit(0)


# ---------------------------------------------------------------- the M4 building

## The M4 test building as a site file, at human scale: one storey on the ground. Lobby
## with a door and two side windows, a corridor north, two rooms with outside windows,
## the wing roofed.
func _m4_test_building() -> void:
	_begin()
	for f: Vector3i in [Vector3i(-1, 0, -1), Vector3i(5, 0, -1), Vector3i(-1, 0, 4), Vector3i(5, 0, 4),
			Vector3i(3, 0, 4), Vector3i(3, 0, 10), Vector3i(5, 0, 10),
			Vector3i(-1, 0, 6), Vector3i(-1, 0, 10), Vector3i(9, 0, 6), Vector3i(9, 0, 10)]:
		_place("foundation_block", f, "")
	for x: int in 5:
		if x == 2:
			_door("door_frame", Vector3i(x, 0, 0), "nz")
		else:
			_wall(Vector3i(x, 0, 0), "nz")
	for z: int in 4:
		_wall_or_window(z == 2, Vector3i(0, 0, z), "nx")
		_wall_or_window(z == 2, Vector3i(4, 0, z), "px")
	for x: int in 4:
		_wall(Vector3i(x, 0, 3), "pz")
	for z: int in range(4, 10):
		for facing: String in ["nx", "px"]:
			if z == 8:
				_door("door_frame", Vector3i(4, 0, z), facing)
			else:
				_wall(Vector3i(4, 0, z), facing)
	_wall(Vector3i(4, 0, 9), "pz")
	for x: int in range(0, 4):
		_wall(Vector3i(x, 0, 7), "nz")
		_wall(Vector3i(x, 0, 9), "pz")
	for z: int in range(7, 10):
		_wall_or_window(z == 8, Vector3i(0, 0, z), "nx")
	for x: int in range(5, 9):
		_wall(Vector3i(x, 0, 7), "nz")
		_wall(Vector3i(x, 0, 9), "pz")
	for z: int in range(7, 10):
		_wall_or_window(z == 8, Vector3i(8, 0, z), "px")
	# the roof, one storey up: the top of the third row of cells
	for z: int in range(4, 10):
		_place("floor_panel", Vector3i(4, STOREY - 1, z), "py")
	for z: int in range(7, 10):
		for x: int in range(0, 4):
			_place("floor_panel", Vector3i(x, STOREY - 1, z), "py")
		for x: int in range(5, 9):
			_place("floor_panel", Vector3i(x, STOREY - 1, z), "py")
	_spawn("guard_sim", Vector3i(2, 0, 3), 270, 1, "")
	_spawn("guard_sim", Vector3i(0, 0, 1), 0, 1, "lobby_round")
	_spawn("guard_sim", Vector3i(4, 0, 4), 90, 1, "wing_patrol")
	_spawn("guard_sim", Vector3i(7, 0, 8), 180, 1, "wing_patrol_reverse")
	_write("m4_test_building", "M4 test building", Vector3i(3, 0, 8), ["starter_plot", "neighbour_north"],
		"The M4 perception building as a site file, at human scale: one 3 m storey with 2 m doors and sill windows. A lobby with a door and two side windows, a corridor north, two rooms with outside windows, the wing roofed. Four guards: a post behind the door, a roamer, two patrollers on opposite loops.")


# ---------------------------------------------------------------- Cold Storage

## The mission site (design doc §15.2): a slab, two storeys on it, a service tunnel
## that is a gap left in the slab, and three routes in that converge on the server room.
##
## Heights, relative to the base cell (a person's feet):
##   y 0–1   the slab: foundations on the ground and concrete blocks on them, two cells
##           deep, except the tunnel column (x 4, z -2..8): the tunnel is the gap, 2 m
##           tall, its floor the ground
##   y 2–4   the ground floor and the street on the slab around it: lobby x 0..4 z 0..3
##           with its street door at x 2 (a door check: the front route), a stair well
##           at x 2 z 4, a back hall x 0..4 z 4..8, the server room x 1..3 z 9..11
##           behind one door
##   y 5–7   the upper floor over the front of it, reached by the inside flight or by
##           the fire stair outside the east wall to a tall maintenance window (the side
##           route); the roof on top
## The under route: cut the grate in the street at x 4, z -2 (a floor panel the player
## removes), climb down into the tunnel, walk north under the building, and climb the
## ladder into the back hall, past the lobby entirely.
func _cold_storage() -> void:
	_begin()
	var ground: int = 2
	var upper: int = ground + STOREY
	# --- the slab: two cells of it, with the tunnel left open through both
	for x: int in range(-2, 8):
		for z: int in range(-4, 14):
			if x == 4 and z >= -2 and z <= 8:
				continue
			_place("foundation_block", Vector3i(x, 0, z), "")
			_place("concrete_block", Vector3i(x, 1, z), "")
	# --- the ground floor over the tunnel column: a grate in the street, floors inside,
	# and the ladder's opening at the north end
	_place("floor_panel", Vector3i(4, ground, -2), "ny")   # the grate: cut it to get in
	for z: int in range(-1, 9):
		_place("roof_hatch" if z == 8 else "floor_panel", Vector3i(4, ground, z), "ny")
	for y: int in range(0, ground + 1):
		_place("stair_flight", Vector3i(4, y, -2), "px")  # the ladder down from the grate
	for y: int in range(0, ground + 1):
		_place("stair_flight", Vector3i(4, y, 8), "nx")   # and up into the back hall
	# --- ground floor walls
	for x: int in 5:
		if x == 2:
			_door("door_check", Vector3i(x, ground, 0), "nz")
		else:
			_wall(Vector3i(x, ground, 0), "nz")
	for z: int in range(0, 12):
		if z == 1:
			_warehouse_door(Vector3i(0, ground, z), "nx")
		else:
			_wall(Vector3i(0, ground, z), "nx")
		_wall(Vector3i(4, ground, z), "px")
	for x: int in [0, 1, 3, 4]:
		_wall(Vector3i(x, ground, 3), "pz")
	for x: int in range(1, 4):
		if x == 2:
			_door("door_frame", Vector3i(x, ground, 8), "pz")
		else:
			_wall(Vector3i(x, ground, 8), "pz")
	_wall(Vector3i(0, ground, 9), "px")
	_wall(Vector3i(4, ground, 9), "nx")
	# the side passages north of the hall are walled from the archive: from M6 to M7.5 they
	# opened into it, and a person in the hall walked round its token-checked door (gate
	# item 36). They still open into the server room beside its doorway, which has no lock;
	# walled, the guards camp the room after a kill and the death run cannot get back in,
	# because an alerted guard never stands down (G6 debt, M9's)
	_wall(Vector3i(0, ground, 11), "px")
	_wall(Vector3i(4, ground, 11), "nx")
	# the back wall runs the building's full width: from M6 to M7.5 it stopped a cell short
	# at both corners, and a person walked in from the north to the server room (gate item 27)
	for x: int in 5:
		_wall(Vector3i(x, ground, 11), "pz")
	# --- the inside flight, lobby to upper floor, up the stair well: a flight face on
	# every cell from the ground floor to the upper one, so each level is climbed onto
	for y: int in range(ground, upper + 1):
		_place("stair_flight", Vector3i(2, y, 4), "nx")
	# --- the upper floor, with the stair well left open
	for x: int in 5:
		for z: int in range(0, 12):
			if x == 2 and z == 4:
				continue
			_place("floor_panel", Vector3i(x, upper, z), "ny")
	for x: int in 5:
		_wall(Vector3i(x, upper, 0), "nz")
	for z: int in range(0, 9):
		_wall(Vector3i(0, upper, z), "nx")
		if z == 7:
			_tall_window(Vector3i(4, upper, z), "px")
		else:
			_wall(Vector3i(4, upper, z), "px")
	for x: int in 5:
		_wall(Vector3i(x, upper, 8), "pz")
	# the roof
	for x: int in 5:
		for z: int in range(0, 9):
			_place("floor_panel", Vector3i(x, upper + STOREY, z), "ny")
	# --- the fire stair outside the east wall: the side route. It is caged: anything a
	# person can climb through, a guard can see through, so a tall window looks out as far
	# as a door would, and without the cage's outer walls the upper floor watched the road
	# east and north of the building. Its outer sides, east and north, are walls; the
	# flight is its south side, which is also the way in.
	for y: int in range(ground, upper + 1):
		_place("stair_flight", Vector3i(5, y, 7), "nz")
	for y: int in range(ground, upper + STOREY):
		_place("wall_panel", Vector3i(5, y, 7), "px")
		_place("wall_panel", Vector3i(5, y, 7), "pz")
	# --- the step up off the street (M6 spec claim 1's rules applied to the site's own
	# edge): the slab is two cells above the pavement, and a level change needs something
	# to climb, so a building nobody can walk up to is a building nobody can rob. Each
	# landing is a hatch, because a solid floor panel is the ceiling of the cell below
	# and refuses to be climbed through.
	for y: int in range(1, ground + 1):
		_place("roof_hatch", Vector3i(4, y, -5), "ny")
		_place("stair_flight", Vector3i(4, y, -5), "nz")
	# --- the guards (design doc §15.3): a lobby post, two upstairs, one roaming
	_armed_spawn("guard_sim", Vector3i(2, ground, 2), 270, 2, "")
	_armed_spawn("guard_sim", Vector3i(1, ground, 7), 90, 2, "cs_hall_round")
	_armed_spawn("guard_sim", Vector3i(1, upper, 2), 90, 2, "cs_upper_patrol")
	_armed_spawn("guard_sim", Vector3i(3, upper, 6), 270, 2, "cs_upper_patrol_reverse")
	# --- the archive, behind its own door at the back of the server room (standards §11
	# Q4, the M6 extension exercise): a second machine for a second contract, reached
	# with a maintenance token or through a wall. It sits north of everything the first
	# contract's routes touch.
	for x: int in [1, 3]:
		_wall(Vector3i(x, ground, 10), "pz")
	_door("door_archive", Vector3i(2, ground, 10), "pz")
	# the server the three routes converge on, in the back room
	_terminal("cs_server", Vector3i(2, ground, 10))
	_terminal("cs_archive", Vector3i(2, ground, 11))
	_write("cold_storage", "Cold Storage", Vector3i(40, 0, 40), ["cold_storage_lot"],
		"The first contract's site (design doc §15) at human scale: a two-cell slab, a token-checked lobby door, a 3 m loading door off the west street, a stair well up to a tall window off a caged fire stair, and a 2 m tunnel under the slab, entered by cutting a street grate. One server room.")


# ---------------------------------------------------------------- openings

## A wall: three wall faces, one storey high, from `rel` up.
func _wall(rel: Vector3i, facing: String) -> void:
	for row: int in STOREY:
		_place("wall_panel", rel + Vector3i(0, row, 0), facing)


## A door: two faces of `piece` (2 m) under a wall face.
func _door(piece: String, rel: Vector3i, facing: String) -> void:
	_place(piece, rel, facing)
	_place(piece, rel + Vector3i(0, 1, 0), facing)
	_place("wall_panel", rel + Vector3i(0, 2, 0), facing)


## A loading door the height of the storey (M7.5 Q4): three warehouse door faces.
func _warehouse_door(rel: Vector3i, facing: String) -> void:
	for row: int in STOREY:
		_place("door_warehouse", rel + Vector3i(0, row, 0), facing)


## A window with a sill: a wall face, a window face, a wall face.
func _window(rel: Vector3i, facing: String) -> void:
	_place("wall_panel", rel, facing)
	_place("window_frame", rel + Vector3i(0, 1, 0), facing)
	_place("wall_panel", rel + Vector3i(0, 2, 0), facing)


## A window a person climbs in by: two window faces under a wall face.
func _tall_window(rel: Vector3i, facing: String) -> void:
	_place("window_frame", rel, facing)
	_place("window_frame", rel + Vector3i(0, 1, 0), facing)
	_place("wall_panel", rel + Vector3i(0, 2, 0), facing)


func _wall_or_window(window: bool, rel: Vector3i, facing: String) -> void:
	if window:
		_window(rel, facing)
	else:
		_wall(rel, facing)


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
