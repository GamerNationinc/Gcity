extends GcityTest

## M6 claim 6 in the portal graph: excavated basement cells are air in the flood fill,
## earth is solid, and the uncut ground separates the basement from the street, so a
## tunnel is its own volume, a grate over it is an edge, and a cut joins them.

const SEED: int = 20261020
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


func _cell(cx: int, cy: int, cz: int) -> Vector3i:
	return BuildSystem.cell_of(FAR + Vector3i(cx * M + 500, cy * M + 500, cz * M + 500))


func _at(cx: int, cy: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, cy * M + 500, cz * M + 500)


## A five-cell tunnel at storey -1, x 0..4, with a grate over its west end.
func _tunnel() -> int:
	var cells: Array[Vector3i] = []
	for x: int in 5:
		cells.append(_cell(x, -1, 0))
	assert_eq(_build.excavate(cells), OK, "dug")
	assert_true(_build.place(_player, &"foundation_block", _at(0, 0, 1), "") > 0, "foundation beside the grate")
	var grate: int = _build.place(_player, &"street_grate", _at(0, -1, 0), "py")
	assert_true(grate > 0, "grate")
	return grate


func test_a_tunnel_is_a_volume_under_the_street_and_its_grate_an_edge() -> void:
	_setup()
	var grate: int = _tunnel()
	var tunnel: int = _portals.node_at(_cell(2, -1, 0))
	assert_true(tunnel > PortalGraph.EXTERIOR, "the tunnel is an enclosed volume")
	assert_eq(_portals.node_at(_cell(4, -1, 0)), tunnel, "all of it, end to end")
	assert_eq(_portals.cells_in(tunnel), 5, "five cells")
	assert_eq(_portals.node_at(_cell(2, -1, 3)), PortalGraph.SOLID, "earth beside it is solid")
	assert_true(_portals.edges_of(tunnel).has([grate, PortalGraph.EXTERIOR] as Array[int]), "the grate joins it to the street")
	assert_false(_build.breach(grate).is_empty(), "cut")
	assert_eq(_portals.node_at(_cell(2, -1, 0)), PortalGraph.EXTERIOR, "open to the street now")


func test_the_ground_numbering_above_is_unchanged_by_a_basement_layer() -> void:
	# a building with no excavation keeps the volumes it had before claim 6
	_setup()
	for c: Vector3i in [Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(1, 0, 0)]:
		assert_true(_build.place(_player, &"foundation_block", _at(c.x, c.y, c.z), "") > 0, "foundation")
	assert_true(_build.place(_player, &"floor_panel", _at(0, 0, 0), "py") > 0, "roof")
	assert_eq(_portals.volume_count(), 1, "one sealed cell")
	assert_eq(_portals.node_at(_cell(0, 0, 0)), 1, "volume 1")
