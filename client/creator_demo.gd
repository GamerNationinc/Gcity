## What `--create --demo` builds (M7.5 spec claim 14), as presses of the creator tool
## the view plays a few ticks apart: a one-storey hut on Cold Storage's open lot, three
## cells square, walls a storey high with a two-cell doorway on the south, a roof, a
## guard post inside facing the door and a terminal in the back corner; then it saves.
## Written as presses, not as pieces, so the demo goes through the tool exactly as a
## player's hands would.
class_name CreatorDemo extends RefCounted

## The hut's south-west corner, in cells.
const CORNER: Vector3i = Vector3i(41, 0, 45)
## Quarter turns from the wall facing a camera at yaw PI (looking along +z) gives, to
## put a wall on each side: the camera's own side is nz.
const TURNS: Dictionary = {"nz": 0, "px": 1, "pz": 2, "nx": 3}
## Ticks between presses.
const PACE: int = 6


## Each {"at": Vector3i, "piece": StringName, "turns": int} or {"save": true}.
static func presses() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for x: int in 3:
		for z: int in 3:
			out.append({"at": CORNER + Vector3i(x, 0, z), "piece": &"foundation_block", "turns": 0})
	for row: int in [1, 2, 3]:
		for i: int in 3:
			out.append(_wall(Vector3i(i, row, 0), "nz", &"door_frame" if i == 1 and row < 3 else &"wall_panel"))
			out.append(_wall(Vector3i(i, row, 2), "pz", &"wall_panel"))
			out.append(_wall(Vector3i(0, row, i), "nx", &"wall_panel"))
			out.append(_wall(Vector3i(2, row, i), "px", &"wall_panel"))
	for x: int in 3:
		for z: int in 3:
			out.append({"at": CORNER + Vector3i(x, 4, z), "piece": &"floor_panel", "turns": 0})
	# the guard looks south at the door: away from a camera on the north side
	out.append({"at": CORNER + Vector3i(1, 1, 2), "piece": SiteCreator.GUARD_POST, "turns": 2})
	out.append({"at": CORNER + Vector3i(2, 1, 2), "piece": SiteCreator.TERMINAL, "turns": 0})
	out.append({"save": true})
	return out


static func _wall(rel: Vector3i, facing: String, piece: StringName) -> Dictionary:
	var turns: int = TURNS[facing]
	return {"at": CORNER + rel, "piece": piece, "turns": turns}
