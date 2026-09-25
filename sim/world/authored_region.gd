## An authored region (design doc §5.1): the city. Flat ground at the build grid's
## ground level, exactly as the sim had it before regions existed, so nothing built or
## played in the city before M7 moves; what stands there is whatever is built. It covers
## a box, and its gates are the only ways out.
class_name AuthoredRegion extends Region

## [x0, z0, x1, z1] in millimetres, half-open on the high sides.
var _bounds: Array[int] = []
var _gates: Array[Dictionary] = []


func _init(id: StringName, bounds: Array[int], gate_list: Array[Dictionary]) -> void:
	super(id)
	_bounds = bounds
	_gates = gate_list


func contains(x: int, z: int) -> bool:
	return x >= _bounds[0] and z >= _bounds[1] and x < _bounds[2] and z < _bounds[3]


## Below the city's ground level is ground. Nothing was ever built or walked there; saying
## so is what lets the rules that ask the ground — a foundation needs ground under it, a
## room ends at the ground — be one rule in the city and the wilds, and the same rule the
## city always had.
func is_solid(cell: Vector3i) -> bool:
	return cell.y < BuildSystem.GROUND_CELL_Y


## At or below the ground level a cell is carried, as it always was in the city.
func stands_on_ground(cell: Vector3i) -> bool:
	return cell.y <= BuildSystem.GROUND_CELL_Y


func gates() -> Array[Dictionary]:
	return _gates.duplicate(true)
