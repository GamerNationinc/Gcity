## The hand-built M4 test building (spec claim 14, design doc §16 M4): a lobby with a
## door to the street and a window in each side wall, a corridor north out of it, and two
## rooms off the corridor, each with a window on its outside wall. Built from M3
## pieces through `build.place` commands, so the client demo and the M4 fixtures
## raise the same walls from the same list. Four guards: a static post in the lobby,
## two patrollers through the wing on opposite loops, and a roamer round the lobby
## (design doc §15.3). The patrol routes are `content/patrol_route/` files with the
## absolute cells below, which is why the building has one fixed place in the world.
class_name M4Building extends RefCounted

## The lobby's south-west interior cell. Lobby x 3..7, z 8..11; corridor x 7,
## z 12..17; room A x 3..6, z 15..17; room B x 8..11, z 15..17. All on the player's
## two parcels.
const BASE: Vector3i = Vector3i(3, 0, 8)
## Where the player stands at the start: on the street, off the door's axis so the
## post inside cannot see it until it steps in front of the door.
const PLAYER_START: Vector3i = Vector3i(2500, 0, 1500)

const WALL: String = "wall_panel"
const DOOR: String = "door_frame"
const WINDOW: String = "window_frame"
const FOUNDATION: String = "foundation_block"
const ROOF: String = "floor_panel"


## The build.place payloads, foundations first, then walls in an order that keeps
## every piece within its span of a foundation already present.
static func commands(actor: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var place: Callable = func(piece: String, rel: Vector3i, facing: String) -> void:
		var centre: Vector3i = BuildSystem.cell_centre(BASE + rel)
		out.append({"actor": actor, "piece": piece, "x": centre.x, "y": centre.y, "z": centre.z, "facing": facing})
	# ground foundations just outside every wall run; none inside a walkable interior
	for f: Vector3i in [Vector3i(-1, 0, -1), Vector3i(5, 0, -1), Vector3i(-1, 0, 4), Vector3i(5, 0, 4),
			Vector3i(3, 0, 4), Vector3i(3, 0, 10), Vector3i(5, 0, 10),
			Vector3i(-1, 0, 6), Vector3i(-1, 0, 10), Vector3i(9, 0, 6), Vector3i(9, 0, 10)]:
		place.call(FOUNDATION, f, "")
	# lobby: interior x 0..4, z 0..3; the door at x 2 in the street wall, a window in
	# each side wall, the opening to the corridor at x 4: nothing in the wing can look
	# down the door's axis to the street, and the side windows look along the street
	for x: int in 5:
		place.call(DOOR if x == 2 else WALL, Vector3i(x, 0, 0), "nz")
	for z: int in 4:
		place.call(WINDOW if z == 2 else WALL, Vector3i(0, 0, z), "nx")
		place.call(WINDOW if z == 2 else WALL, Vector3i(4, 0, z), "px")
	for x: int in 4:
		place.call(WALL, Vector3i(x, 0, 3), "pz")
	# corridor: interior x 4, z 4..9; room doors at z 8; a wall across the north end
	for z: int in range(4, 10):
		place.call(DOOR if z == 8 else WALL, Vector3i(4, 0, z), "nx")
		place.call(DOOR if z == 8 else WALL, Vector3i(4, 0, z), "px")
	place.call(WALL, Vector3i(4, 0, 9), "pz")
	# room A: interior x 0..3, z 7..9, window west
	for x: int in range(0, 4):
		place.call(WALL, Vector3i(x, 0, 7), "nz")
		place.call(WALL, Vector3i(x, 0, 9), "pz")
	for z: int in range(7, 10):
		place.call(WINDOW if z == 8 else WALL, Vector3i(0, 0, z), "nx")
	# room B: interior x 5..8, z 7..9, window east
	for x: int in range(5, 9):
		place.call(WALL, Vector3i(x, 0, 7), "nz")
		place.call(WALL, Vector3i(x, 0, 9), "pz")
	for z: int in range(7, 10):
		place.call(WINDOW if z == 8 else WALL, Vector3i(8, 0, z), "px")
	# roofs over the corridor and both rooms, so they are enclosed volumes with entry
	# edges for the squad planner; the lobby is a courtyard (its middle is beyond span)
	for z: int in range(4, 10):
		place.call(ROOF, Vector3i(4, 0, z), "py")
	for z: int in range(7, 10):
		for x: int in range(0, 4):
			place.call(ROOF, Vector3i(x, 0, z), "py")
		for x: int in range(5, 9):
			place.call(ROOF, Vector3i(x, 0, z), "py")
	return out


## The agent.spawn payloads for the four guards. Facing: 0 = +x, 90 = +z, 270 = -z.
static func guards(profile: String) -> Array[Dictionary]:
	var spawn: Callable = func(rel: Vector3i, facing: int, route: String) -> Dictionary:
		var cell: Vector3i = BASE + rel
		return {"profile": profile, "cell": [cell.x, cell.y, cell.z], "facing": facing, "squad": 1, "route": route}
	return [
		spawn.call(Vector3i(2, 0, 3), 270, ""),                      # the lobby post, straight behind the door
		spawn.call(Vector3i(0, 0, 1), 0, "lobby_round"),             # the roamer
		spawn.call(Vector3i(4, 0, 4), 90, "wing_patrol"),            # patroller, corridor first
		spawn.call(Vector3i(7, 0, 8), 180, "wing_patrol_reverse"),   # patroller, room B first
	]
