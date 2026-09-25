## What every region answers (design doc §5.1; M7 spec claim 13). **Nothing outside
## sim/world names an implementation of this**: movement, perception, hydration, sites
## and saving ask [Regions], which asks the region a place is in, and neither ever
## branches on which kind that is. `tools/check_dependencies.py` enforces it.
##
## Cells are the build grid's 1 m cells, positions integer millimetres, the frame the
## one world frame with the gate at its origin.
class_name Region extends RefCounted

var _id: StringName


func _init(id: StringName) -> void:
	_id = id


func id() -> StringName:
	return _id


## Whether a ground-plane position is in this region.
func contains(_x: int, _z: int) -> bool:
	assert(false, "every region says what it covers")
	return false


## Whether the ground itself fills a cell: rock and soil, not anything built.
func is_solid(_cell: Vector3i) -> bool:
	assert(false, "every region says what its ground is")
	return false


## Whether the ground carries an actor standing in this cell.
func stands_on_ground(_cell: Vector3i) -> bool:
	assert(false, "every region says what its ground carries")
	return false


## The level, in cells, an actor stands at in the column over a ground position.
func standing_cell_y(_x: int, _z: int) -> int:
	return BuildSystem.GROUND_CELL_Y


## Changes the ground in a cell, solid or not (M7 spec claim 15). False where the ground
## is not the region's to change: the city's is built on, not dug.
func set_ground(_cell: Vector3i, _solid: bool) -> bool:
	return false


## How many levels a single horizontal step may climb onto the ground: walking uphill.
func step_levels() -> int:
	return 0


## The gates out of this region: [{"node", "x", "z", "half_width_mm"}], or none.
func gates() -> Array[Dictionary]:
	return [] as Array[Dictionary]
