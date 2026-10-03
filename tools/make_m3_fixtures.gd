## Writes the M3 replay fixtures (M3 spec claim 12, P3) into tests/replay/: the bunker
## raided through its door, the killbox where a new door beats the wall a raid token was
## cutting, and the walk through the door. Until M7.5 these three were written by hand;
## generating them is M7.5 spec claim 9, so that when the scale changes they are
## rebuilt by code, not edited. At human scale (M7.5 claim 6) the bunker is a storey
## tall: walls of three faces, a 2 m door under a wall face, the roof on top.
##   godot --headless --path . -s tools/make_m3_fixtures.gd
## Then `tools/rerecord_hashes.sh tests/replay/m3-*.json` fills in "expected_hash".
extends SceneTree

const OUT_DIR: String = "res://tests/replay"
const M: int = 1000
## Cells from floor to roof (M7.5 decision 1).
const STOREY: int = 3
## The player is the first entity, so the bunker's pieces are numbered from 2: four
## foundations, then the twelve wall columns in `_bunker`'s order, STOREY faces each.
const FIRST_PIECE_ID: int = 2

var _commands: Array = []


func _initialize() -> void:
	_bunker_fixture()
	_killbox_fixture()
	_walk_fixture()
	quit(0)


## A token with a cutter spawned at tick 40 goes in through the bunker's door.
func _bunker_fixture() -> void:
	_begin()
	_bunker(true)
	_at(40, &"raid.spawn", {"tool": "cutter"})
	_write("m3-bunker", 20261008, 200)


## The same bunker with a wall where the door would be: the token starts cutting it,
## and at tick 60 the player swaps the bottom of that wall for a door, which is cheaper
## to go through.
func _killbox_fixture() -> void:
	_begin()
	_bunker(false)
	_at(40, &"raid.spawn", {"tool": "cutter"})
	# the south wall's middle column: the eighth placed, after the four foundations; its
	# two lowest faces come out and a 2 m door goes in under the third
	var column: int = FIRST_PIECE_ID + 4 + 7 * STOREY
	_at(60, &"build.remove", {"actor": 1, "piece_id": column})
	_at(60, &"build.remove", {"actor": 1, "piece_id": column + 1})
	_place(61, "door_frame", Vector3i(5, 0, 4), "nz")
	_place(61, "door_frame", Vector3i(5, 1, 4), "nz")
	_write("m3-killbox", 20261009, 220)


## The player walks east along the bunker's south side, north past its east wall, back
## west, and in at the door; the last leg north runs into the back wall and is refused.
func _walk_fixture() -> void:
	_begin()
	_bunker(true)
	var tick: int = 10
	for leg: Array in [[150, 0, 37], [0, 150, 23], [-150, 0, 8], [0, 150, 6], [150, 0, 8], [0, 150, 6]]:
		var dx: int = leg[0]
		var dz: int = leg[1]
		var steps: int = leg[2]
		for i: int in steps:
			_at(tick, &"actor.move", {"actor": 1, "dx": dx, "dz": dz})
			tick += 1
	_write("m3-walk", 20261010, 118)


## A 3 × 3 room on the starter plot, a storey high: foundations at its four outer
## corners, three rings of wall columns (west, east, north, south, one column of each
## per ring; the south ring's middle column is the door when `door`), a roof, and a
## crate in the north-east corner for a raid to go for. The player spawns, takes the
## plot, builds.
func _bunker(door: bool) -> void:
	_at(1, &"actor.spawn", {"profile": "arcade", "range_m": 0})
	_at(2, &"land.identify", {"actor": 1, "owner": "player"})
	_at(2, &"land.transfer", {"parcel": "starter_plot", "owner": "player"})
	for corner: Vector3i in [Vector3i(3, 0, 3), Vector3i(7, 0, 3), Vector3i(3, 0, 7), Vector3i(7, 0, 7)]:
		_place(3, "foundation_block", corner, "")
	for i: int in 3:
		_column(Vector3i(4, 0, 4 + i), "nx", false)
		_column(Vector3i(6, 0, 4 + i), "px", false)
		_column(Vector3i(4 + i, 0, 6), "pz", false)
		_column(Vector3i(4 + i, 0, 4), "nz", door and i == 1)
	for x: int in range(4, 7):
		for z: int in range(4, 7):
			_place(3, "floor_panel", Vector3i(x, STOREY - 1, z), "py")
	_place(3, "storage_crate", Vector3i(6, 0, 6), "")


## A wall a storey high, or a 2 m door under a wall face.
func _column(cell: Vector3i, facing: String, door: bool) -> void:
	for row: int in STOREY:
		var piece: String = "door_frame" if door and row < 2 else "wall_panel"
		_place(3, piece, cell + Vector3i(0, row, 0), facing)


# ---------------------------------------------------------------- writing

func _begin() -> void:
	_commands = []


func _at(tick: int, kind: StringName, payload: Dictionary) -> void:
	_commands.append({"tick": tick, "kind": String(kind), "payload": payload})


## A build command for the middle of `cell`.
func _place(tick: int, piece: String, cell: Vector3i, facing: String) -> void:
	_at(tick, &"build.place", {"actor": 1, "piece": piece, "x": cell.x * M + 500, "y": cell.y * M + 500, "z": cell.z * M + 500, "facing": facing})


func _write(name: String, seed: int, ticks: int) -> void:
	var fixture: Dictionary = {"schema_version": 1, "name": name, "seed": seed, "ticks": ticks, "commands": _commands, "expected_hash": ""}
	var file: FileAccess = FileAccess.open("%s/%s.json" % [OUT_DIR, name], FileAccess.WRITE)
	assert(file != null, "open %s" % name)
	file.store_string(JSON.stringify(fixture, "\t") + "\n")
	file.close()
	print("wrote %s: %d commands, %d ticks" % [name, _commands.size(), ticks])
