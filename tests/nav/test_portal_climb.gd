extends GcityTest

## M6 spec claim 2 in the portal graph: a stair or a ladder between two volumes is an
## edge tagged `climb`, priced at the piece's climb_ticks whatever the tool (it is
## climbed, not breached). Mantles and jumps cross open air inside one volume, so they
## never separate two volumes and add no edges.

const SEED: int = 20261013
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)

var _sim: SimRoot
var _build: BuildSystem
var _portals: PortalGraph
var _player: int = 0


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_build = SimAssembly.build_of(_sim)
	_portals = SimAssembly.portals_of(_sim)
	_player = SimAssembly.actors_of(_sim).spawn(&"arcade", 0)


func _at(cx: int, cy: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, cy * M + 500, cz * M + 500)


## A sealed cell at storey 0 (foundations round it, the ground under it) under a sealed
## cell at storey 1 (walls and a roof), with a ladder in the floor between them.
func _two_storey_column() -> int:
	for d: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		assert_true(_build.place(_player, &"foundation_block", _at(d.x, 0, d.z), "") > 0, "foundation %s" % d)
	var ladder: int = _build.place(_player, &"ladder_hatch", _at(0, 0, 0), "py")
	assert_true(ladder > 0, "ladder in the floor")
	for facing: String in ["px", "nx", "pz", "nz"]:
		assert_true(_build.place(_player, &"wall_panel", _at(0, 1, 0), facing) > 0, "wall %s" % facing)
	assert_true(_build.place(_player, &"floor_panel", _at(0, 1, 0), "py") > 0, "roof")
	return ladder


func test_a_ladder_between_two_volumes_is_a_climb_edge_at_its_ticks() -> void:
	_setup()
	var ladder: int = _two_storey_column()
	var below: int = _portals.node_at(BuildSystem.cell_of(_at(0, 0, 0)))
	var above: int = _portals.node_at(BuildSystem.cell_of(_at(0, 1, 0)))
	assert_true(below > PortalGraph.EXTERIOR and above > PortalGraph.EXTERIOR and below != above, "two sealed volumes")
	assert_true(_portals.edges_of(below).has([ladder, above] as Array[int]), "joined by the ladder")
	assert_eq(_portals.edge_move(ladder), &"climb", "tagged climb")
	for tool: StringName in [&"cutter", &"breacher"]:
		assert_eq(_portals.edge_cost(ladder, tool), _build.climb_ticks_of(ladder), "climbed, not breached, with %s" % tool)
	var path: Dictionary = _portals.cheapest_path(below, above, &"cutter")
	assert_eq(path["pieces"], [ladder] as Array[int], "the cheapest way up is the ladder")


func test_a_stair_is_priced_as_a_climb_and_other_pieces_are_not_tagged() -> void:
	_setup()
	assert_true(_build.place(_player, &"foundation_block", _at(1, 0, 0), "") > 0, "foundation")
	var stair: int = _build.place(_player, &"stair_steel", _at(0, 0, 0), "nx")
	assert_true(stair > 0, "stair")
	assert_eq(_portals.edge_cost(stair, &"breacher"), 20, "a stair costs its climb ticks")
	assert_eq(_portals.edge_move(stair), &"climb", "tagged climb")
	var wall: int = _build.place(_player, &"wall_panel", _at(1, 1, 0), "px")
	assert_true(wall > 0, "a wall")
	assert_eq(_portals.edge_move(wall), &"", "a wall is breached, not a move")
	assert_eq(_portals.edge_move(999), &"", "an unknown piece has no move")
