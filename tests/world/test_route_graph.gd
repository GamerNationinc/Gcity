extends GcityTest

## M7 spec claim 1: the route graph is generated from the world seed alone, before
## anything else exists, and everything else is a consumer of it.
##
## The claim that is easiest to break later is the one about the shared RNG. If
## generation ever draws from `sim.rng()`, the world becomes a function of how many
## other systems drew before it — which means adding a system somewhere else silently
## changes the map. That has a test of its own here.

const SEED: int = 20261250
const M: int = 1000

var _sim: SimRoot
var _routes: RouteGraph


func _setup(world: int = SEED) -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(world, db)
	_routes = SimAssembly.routes_of(_sim)


func test_a_world_has_a_gate_at_the_origin_and_places_around_it() -> void:
	_setup()
	assert_true(_routes.node_count() >= RouteGraph.NODES_MIN, "a world of places (%d)" % _routes.node_count())
	assert_eq(_routes.node_ids()[0], 1, "the first node is node one")
	assert_eq(_routes.kind_of(1), RouteGraph.KIND_GATE, "and it is the city gate")
	assert_eq(_routes.position_of(1), Vector2i.ZERO, "the world is measured from it")
	assert_eq(_routes.world_seed(), SEED, "the graph knows the world it came from")
	var kinds: Dictionary = {}
	for node: int in _routes.node_ids():
		var kind: StringName = _routes.kind_of(node)
		assert_true(RouteGraph.KINDS.has(kind), "node %d is a kind the graph knows" % node)
		kinds[kind] = true
	assert_true(kinds.size() >= 3, "a world is not all one kind of place (%d kinds)" % kinds.size())
	assert_eq(_routes.kind_of(99999), &"", "and a node that is not one has no kind")


func test_nodes_are_spread_out_enough_that_an_edge_is_a_journey() -> void:
	_setup()
	var ids: Array[int] = _routes.node_ids()
	var closest: int = RouteGraph.WORLD_RADIUS_MM
	for i: int in ids.size():
		for j: int in range(i + 1, ids.size()):
			var a: Vector2i = _routes.position_of(ids[i])
			var b: Vector2i = _routes.position_of(ids[j])
			var d: int = RouteGraph._length_mm(a.x, a.y, b.x, b.y)
			closest = mini(closest, d)
	assert_true(closest >= RouteGraph.MIN_SPACING_MM, "nothing is closer than the spacing (%d mm)" % closest)


func test_every_corridor_is_wide_enough_to_walk_down() -> void:
	_setup()
	assert_true(_routes.edge_count() >= _routes.node_count() - 1, "enough edges to join everything")
	for id: int in _routes.edge_ids():
		var rec: Dictionary = _routes.edge(id)
		var a: int = rec["a"]
		var b: int = rec["b"]
		var width: int = rec["width"]
		assert_true(a < b, "edge %d is stored one way round only" % id)
		assert_true(a != b, "edge %d joins two different places" % id)
		assert_true(_routes.has_node(a) and _routes.has_node(b), "edge %d joins places that exist" % id)
		assert_true(width >= RouteGraph.MIN_WIDTH_MM, "edge %d is %d mm wide" % [id, width])
		assert_true(width <= RouteGraph.MAX_WIDTH_MM, "and not absurdly so")
	assert_eq(_routes.edge(99999), {}, "an edge that is not one is nothing")


func test_the_graph_agrees_with_itself_about_who_is_next_to_whom() -> void:
	_setup()
	for node: int in _routes.node_ids():
		for other: int in _routes.neighbours(node):
			assert_true(_routes.neighbours(other).has(node), "%d and %d agree" % [node, other])
			var id: int = _routes.edge_between(node, other)
			assert_true(id != EntityIds.NONE, "and there is an edge between them")
			assert_eq(_routes.edge_between(other, node), id, "the same edge either way round")
		assert_eq(_routes.edges_at(node).size(), _routes.neighbours(node).size(), "one edge a neighbour")
	assert_eq(_routes.edges_at(99999), [] as Array[int], "nothing meets at a node that is not one")


## The one that matters. Generation draws from its own generator, seeded from the
## world, and never from the sim's — otherwise adding a system somewhere else would
## change the map.
func test_generating_the_world_does_not_touch_the_sims_own_randomness() -> void:
	_setup()
	var before: int = _sim.rng().state
	_routes.generate(SEED + 1)
	assert_eq(_sim.rng().state, before, "generating a whole world drew nothing from the sim")
	_routes.generate(SEED)
	assert_eq(_sim.rng().state, before, "nor did generating it back")


## Two sims built the same way hold the same world; two built differently do not.
func test_the_seed_is_the_world() -> void:
	_setup()
	var first: Array[Vector2i] = _positions(_routes)
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var other: RouteGraph = SimAssembly.routes_of(SimAssembly.build(SEED, db))
	assert_eq(_positions(other), first, "the same seed is the same world")
	var elsewhere: RouteGraph = SimAssembly.routes_of(SimAssembly.build(SEED + 1, db))
	assert_true(_positions(elsewhere) != first, "a different seed is somewhere else")


## The world is a function of its seed, so the seed is all the save holds of it.
func test_the_snapshot_is_the_seed_and_restoring_regenerates() -> void:
	_setup()
	assert_eq(_routes.snapshot(), {"seed": SEED}, "a world is its seed")
	var before: Array[Vector2i] = _positions(_routes)
	_routes.generate(SEED + 7)
	assert_true(_positions(_routes) != before, "somewhere else now")
	assert_eq(_routes.restore({"seed": SEED}), OK, "restored")
	assert_eq(_positions(_routes), before, "and it is the same world again")
	assert_eq(_routes.restore({}), ERR_INVALID_DATA, "empty")
	assert_eq(_routes.restore({"seed": "1"}), ERR_INVALID_DATA, "a seed that is not a number")
	assert_eq(_routes.restore({"seed": 1, "extra": 2}), ERR_INVALID_DATA, "an unknown key")
	assert_eq(_positions(_routes), before, "and the rejections left the world alone")


func _positions(graph: RouteGraph) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for node: int in graph.node_ids():
		out.append(graph.position_of(node))
	return out
