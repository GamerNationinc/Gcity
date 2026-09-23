## The stealth run the world view's demo plays (M6 spec claim 13): the under route
## through Cold Storage, end to end, as a list of steps the view walks one at a time.
##
## This is the same route `tools/make_m6_fixtures.gd` records as `m6-stealth`, written
## again here rather than read from it, because `tests/` is not in the export and a
## demo that only runs from a source checkout is not a demo. The fixture is what proves
## the run is clean; this is what shows it.
class_name MissionDemo extends RefCounted

const SITE: StringName = &"cold_storage"
## The cell south of the building the roamer must be past before the hall is crossed.
const HALL_LINE: int = 4
## Long enough for the roamer's loop, short enough that the demo does not stall.
const PATIENCE: int = 900

enum Step { WALK, CLIMB, CUT, HACK, WIPE, PATCH, WAIT_CLEAR, DONE }


## The run, in order. Cells are relative to the site's base.
static func steps() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"do": Step.WALK, "rel": Vector3i(4, 0, -5), "ground": true})
	out.append({"do": Step.CLIMB, "dy": 1})
	out.append({"do": Step.WALK, "rel": Vector3i(4, 1, -4)})
	out.append({"do": Step.WALK, "rel": Vector3i(4, 1, -2)})
	out.append({"do": Step.CUT})
	out.append({"do": Step.CLIMB, "dy": -1})
	for i: int in 10:
		out.append({"do": Step.WALK, "rel": Vector3i(4, 0, -1 + i)})
	out.append({"do": Step.WAIT_CLEAR})
	out.append({"do": Step.CLIMB, "dy": 1})
	out.append({"do": Step.WALK, "rel": Vector3i(3, 1, 8)})
	out.append({"do": Step.WALK, "rel": Vector3i(2, 1, 8)})
	out.append({"do": Step.WALK, "rel": Vector3i(2, 1, 9)})
	out.append({"do": Step.WALK, "rel": Vector3i(1, 1, 10)})
	out.append({"do": Step.HACK})
	out.append({"do": Step.WIPE})
	out.append({"do": Step.WAIT_CLEAR})
	out.append({"do": Step.WALK, "rel": Vector3i(2, 1, 9)})
	out.append({"do": Step.WALK, "rel": Vector3i(2, 1, 8)})
	out.append({"do": Step.WALK, "rel": Vector3i(3, 1, 8)})
	out.append({"do": Step.WALK, "rel": Vector3i(4, 1, 8)})
	out.append({"do": Step.CLIMB, "dy": -1})
	for i: int in 10:
		out.append({"do": Step.WALK, "rel": Vector3i(4, 0, 7 - i)})
	out.append({"do": Step.CLIMB, "dy": 1})
	out.append({"do": Step.PATCH})
	out.append({"do": Step.WALK, "rel": Vector3i(4, 1, -4)})
	out.append({"do": Step.DONE})
	return out


## True when every living guard on the building's ground floor is south of the hall
## line, which is when the back hall can be crossed unseen.
static func hall_is_clear(sim: SimRoot, player: int, operator: int) -> bool:
	var sites: SiteSystem = SimAssembly.sites_of(sim)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var floor_y: int = sites.cell_of(SITE, Vector3i(0, 1, 0)).y
	var line: int = sites.cell_of(SITE, Vector3i(0, 0, HALL_LINE)).z
	for id: int in actors.actor_ids():
		if id == player or id == operator or not actors.is_alive(id):
			continue
		var cell: Vector3i = BuildSystem.cell_of(actors.position_of(id))
		if cell.y == floor_y and cell.z >= line:
			return false
	return true
