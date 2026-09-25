extends GcityTest

## M7 spec claim 1: the route graph is generated from the world seed alone, before
## anything else exists, and everything else is a consumer of it.
##
## The claim that is easiest to break later is the one about the shared RNG. If
## generation ever draws from `sim.rng()`, the world becomes a function of how many
## other systems drew before it — which means adding a system somewhere else silently
## changes the map. That has a test of its own here.

const SEED: int = 20261250
const SEED_PROPERTY: int = 20261251
const PROPERTY_CASES: int = 10_000
## How many pairs of places each world in the distance property is asked about.
const PAIRS_PER_WORLD: int = 4
const M: int = 1000

var _sim: SimRoot
var _routes: RouteGraph


## The kits the shipped world is built from. The property tests build bare graphs
## rather than whole sims for speed, but a bare graph with no kits has no towns — and a
## world without towns is not the world these properties are supposed to be about.
func _kits() -> Array[Dictionary]:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	return SettlementKits.prepared(db)


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


## The spacing rule is about the world's own places: it is what makes a world edge a
## journey rather than a step. It is **not** about a town's streets, which are close
## together on purpose (claim 6) — so the second half of this asserts they are, or the
## first half would still pass on a world with no towns in it and quietly stop meaning
## anything.
func test_nodes_are_spread_out_enough_that_an_edge_is_a_journey() -> void:
	_setup()
	var ids: Array[int] = _routes.node_ids()
	var closest: int = RouteGraph.WORLD_RADIUS_MM
	var closest_street: int = RouteGraph.WORLD_RADIUS_MM
	for i: int in ids.size():
		for j: int in range(i + 1, ids.size()):
			var a: Vector2i = _routes.position_of(ids[i])
			var b: Vector2i = _routes.position_of(ids[j])
			var d: int = RouteGraph._length_mm(a.x, a.y, b.x, b.y)
			# a town's streets and the crossings where roads meet are where roads fall,
			# not where the world's places were spaced
			var in_town: bool = (_routes.node_town(ids[i]) != EntityIds.NONE
				or _routes.node_town(ids[j]) != EntityIds.NONE
				or _routes.kind_of(ids[i]) == RouteGraph.KIND_CROSSING
				or _routes.kind_of(ids[j]) == RouteGraph.KIND_CROSSING)
			if in_town:
				closest_street = mini(closest_street, d)
			else:
				closest = mini(closest, d)
	assert_true(closest >= RouteGraph.MIN_SPACING_MM, "nothing is closer than the spacing (%d mm)" % closest)
	assert_true(closest_street < RouteGraph.MIN_SPACING_MM,
		"and a town's streets are closer than that (%d mm), or this world has no towns" % closest_street)


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
func test_the_snapshot_is_the_seed_and_the_world_it_built() -> void:
	_setup()
	var saved: Dictionary = _routes.snapshot()
	assert_eq(saved["seed"], SEED, "a world is its seed")
	assert_eq(saved["world"], _routes.world_hash(), "and the world that seed built")
	var before: Array[Vector2i] = _positions(_routes)
	_routes.generate(SEED + 7)
	assert_true(_positions(_routes) != before, "somewhere else now")
	assert_eq(_routes.restore(saved), OK, "restored")
	assert_eq(_positions(_routes), before, "and it is the same world again")
	assert_eq(_routes.restore({}), ERR_INVALID_DATA, "empty")
	assert_eq(_routes.restore({"seed": "1", "world": "x"}), ERR_INVALID_DATA, "a seed that is not a number")
	assert_eq(_routes.restore({"seed": SEED}), ERR_INVALID_DATA, "a save with no world in it")
	assert_eq(_routes.restore({"seed": SEED, "world": saved["world"], "extra": 2}), ERR_INVALID_DATA, "an unknown key")
	assert_eq(_positions(_routes), before, "and the rejections left the world alone")


## The check that makes the hash worth carrying: a save whose seed no longer builds the
## world it claims is refused, rather than quietly handing the player somewhere else.
func test_a_save_from_a_different_generator_is_refused() -> void:
	_setup()
	var saved: Dictionary = _routes.snapshot()
	var before: Array[Vector2i] = _positions(_routes)
	var lying: Dictionary = saved.duplicate()
	lying["world"] = StateHash.of({"a different": "world"})
	assert_eq(_routes.restore(lying), ERR_INVALID_DATA, "the seed does not build that world")
	assert_eq(_positions(_routes), before, "and the world in hand was put back")
	assert_eq(_routes.snapshot()["world"], saved["world"], "unchanged by the refusal")


## The hash is over what was built, not over what was asked for.
func test_the_hash_is_the_world_and_not_the_seed() -> void:
	_setup()
	var canonical: Dictionary = _routes.canonical()
	assert_eq(_routes.world_hash(), StateHash.of(canonical), "it is the graph, hashed")
	var nodes: Array = canonical["nodes"]
	var edges: Array = canonical["edges"]
	assert_eq(nodes.size(), _routes.node_count(), "every place is in it")
	assert_eq(edges.size(), _routes.edge_count(), "and every corridor")
	assert_eq(_routes.world_hash().length(), 64, "a SHA-256")
	# move one corridor by a millimetre and the world is a different world
	var moved: Dictionary = _routes.canonical()
	var moved_edges: Array = moved["edges"]
	var first: Array = moved_edges[0]
	var width: int = first[3]
	first[3] = width + 1
	assert_true(StateHash.of(moved) != _routes.world_hash(), "a millimetre of road is a different world")


func _positions(graph: RouteGraph) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for node: int in graph.node_ids():
		out.append(graph.position_of(node))
	return out


## M7 spec claim 2, and one of the three things the G7 bar measures: the same seed is
## the same world, over ten thousand of them, and no two of them are the same world.
##
## The pairs are generated in two separate `RouteGraph` objects rather than two full
## sims: ten thousand assemblies would spend the whole run loading content, and what
## is being proved is that generation is a function of its seed and of nothing else.
## `test_the_seed_is_the_world` above does the same through the assembly path, and the
## replay fixtures carry it across processes.
func test_property_the_same_seed_is_the_same_world_and_no_two_are_the_same() -> void:
	var seen: Dictionary = {}
	var disagreed: int = 0
	var collided: int = 0
	var kits: Array[Dictionary] = _kits()
	var first: RouteGraph = RouteGraph.new()
	var second: RouteGraph = RouteGraph.new()
	first.set_kits(kits)
	second.set_kits(kits)
	for i: int in PROPERTY_CASES:
		var world: int = SEED_PROPERTY + i
		first.generate(world)
		second.generate(world)
		var hash: String = first.world_hash()
		if hash != second.world_hash():
			disagreed += 1
			if disagreed <= 3:
				fail("seed %d built two different worlds" % world)
		if seen.has(hash):
			collided += 1
			if collided <= 3:
				fail("seeds %d and %d built the same world" % [seen[hash], world])
		seen[hash] = world
	assert_eq(disagreed, 0, "every seed built the same world twice (%d seeds)" % PROPERTY_CASES)
	assert_eq(collided, 0, "and no two seeds built the same world")
	assert_eq(seen.size(), PROPERTY_CASES, "so there are as many worlds as seeds")


## A world is not a template with the numbers changed: over the same sample the shape
## of it moves too, or "the same seed is the same world" would be true and uninteresting.
func test_property_worlds_differ_in_shape_and_not_only_in_position() -> void:
	var sizes: Dictionary = {}
	var edges: Dictionary = {}
	var graph: RouteGraph = RouteGraph.new()
	graph.set_kits(_kits())
	for i: int in PROPERTY_CASES:
		graph.generate(SEED_PROPERTY + i)
		sizes[graph.node_count()] = true
		edges[graph.edge_count()] = true
		if graph.node_count() < RouteGraph.NODES_MIN:
			fail("seed %d built a world of %d places" % [SEED_PROPERTY + i, graph.node_count()])
			break
	assert_true(sizes.size() >= 8, "worlds vary in how many places they hold (%d sizes)" % sizes.size())
	assert_true(edges.size() >= 8, "and in how many roads (%d)" % edges.size())


## M7 spec claim 3: connectivity is true by construction. Every node is joined to one
## already joined as it is placed, so a disconnected world is not a thing that needs
## repairing — it is a bug in how the graph is built.
func test_everywhere_can_be_reached_from_the_gate() -> void:
	_setup()
	assert_true(_routes.everywhere_is_reachable(), "the whole world is one piece")
	var from_gate: Array[int] = _routes.reachable_from(1)
	assert_eq(from_gate, _routes.node_ids(), "and all of it is reachable from the gate")
	for node: int in _routes.node_ids():
		assert_eq(_routes.reachable_from(node).size(), _routes.node_count(), "and from %d" % node)
	assert_eq(_routes.reachable_from(99999), [] as Array[int], "nowhere is reachable from nowhere")
	assert_true(_routes.narrowest_edge_mm() >= RouteGraph.MIN_WIDTH_MM, "and every road can be walked")


## The property the G7 bar names. A seed that fails is a named regression case, not a
## retry: `sim/world/route_graph.gd` would be wrong, not unlucky.
func test_property_every_world_is_one_piece_with_no_bad_roads() -> void:
	var graph: RouteGraph = RouteGraph.new()
	graph.set_kits(_kits())
	var broken: int = 0
	var narrow: int = 0
	var malformed: int = 0
	var north: int = 0
	var crossed: int = 0
	var crossings: int = 0
	var widths: Dictionary = {}
	for i: int in PROPERTY_CASES:
		var world: int = SEED_PROPERTY + i
		graph.generate(world)
		if not graph.everywhere_is_reachable():
			broken += 1
			if broken <= 3:
				fail("seed %d built a world in pieces" % world)
		var narrowest: int = graph.narrowest_edge_mm()
		widths[narrowest / 1000] = true
		if narrowest < RouteGraph.MIN_WIDTH_MM:
			narrow += 1
			if narrow <= 3:
				fail("seed %d built a road %d mm wide" % [world, narrowest])
		# the city backs onto the north: every place but the gate lies south of it, the
		# world's own places at least a node's spacing south, so no road crosses the city
		for node: int in graph.node_ids():
			if node == 1:
				continue
			var z: int = graph.position_of(node).y
			var limit: int = -RouteGraph.SOUTH_OF_GATE_MM if graph.node_town(node) == EntityIds.NONE else -1
			if z > limit:
				north += 1
				if north <= 3:
					fail("seed %d put node %d at z %d, north of where the wilds are" % [world, node, z])
		# roads that cross meet: no two edges cross anywhere but at a place they share
		var ids: Array[int] = graph.edge_ids()
		for x: int in ids.size():
			for y: int in range(x + 1, ids.size()):
				if not graph._crossing(ids[x], ids[y]).is_empty():
					crossed += 1
					if crossed <= 3:
						fail("seed %d: roads %d and %d cross without meeting" % [world, ids[x], ids[y]])
		for node: int in graph.node_ids():
			if graph.kind_of(node) == RouteGraph.KIND_CROSSING:
				crossings += 1
		# no corridor joins a place to itself, and no two places are joined twice
		var pairs: Dictionary = {}
		for id: int in graph.edge_ids():
			var rec: Dictionary = graph.edge(id)
			var a: int = rec["a"]
			var b: int = rec["b"]
			var key: String = "%d-%d" % [a, b]
			if a == b or pairs.has(key) or a > b:
				malformed += 1
				if malformed <= 3:
					fail("seed %d: edge %d joins %d and %d" % [world, id, a, b])
			pairs[key] = true
	assert_eq(broken, 0, "every one of %d worlds is one piece" % PROPERTY_CASES)
	assert_eq(narrow, 0, "and has no road too narrow to walk")
	assert_eq(malformed, 0, "and no road to nowhere or road built twice")
	assert_eq(north, 0, "and nothing but the gate on the city's side of it")
	assert_eq(crossed, 0, "and no two roads cross without meeting")
	assert_true(crossings > PROPERTY_CASES, "which is not because roads never cross (%d crossings)" % crossings)
	assert_true(widths.size() > 1, "the narrowest road is not the same in every world")


## A tree would satisfy claim 3 and still be a poor world: one way to anywhere means a
## single blocked corridor cuts the map in half. The loop pass is what prevents that.
func test_a_world_is_not_a_tree() -> void:
	var graph: RouteGraph = RouteGraph.new()
	graph.set_kits(_kits())
	var trees: int = 0
	for i: int in 200:
		graph.generate(SEED_PROPERTY + i)
		if graph.edge_count() <= graph.node_count() - 1:
			trees += 1
	assert_true(trees < 40, "most worlds have more than one way to somewhere (%d of 200 were trees)" % trees)


## M7 spec claim 4: how far apart two places are is a query answered with the world
## unloaded, which is what lets a contract say "eight to fifteen kilometres out" before
## a metre of terrain exists.
func test_distance_is_answered_over_the_graph_with_nothing_loaded() -> void:
	_setup()
	assert_eq(_routes.distance_between(1, 1), 0, "nowhere is no distance from itself")
	assert_eq(_routes.distance_between(1, 99999), -1, "and a place that is not one has none")
	assert_eq(_routes.distance_between(99999, 1), -1, "either way round")
	assert_eq(_routes.path_between(1, 1), [1] as Array[int], "a place is its own path")
	assert_eq(_routes.path_between(1, 99999), [] as Array[int], "there is no way to nowhere")
	for node: int in _routes.node_ids():
		if node == 1:
			continue
		var km: int = _routes.distance_between(1, node)
		assert_true(km > 0, "node %d is somewhere (%d m)" % [node, km])
		var path: Array[int] = _routes.path_between(1, node)
		assert_eq(path[0], 1, "the way there starts at the gate")
		assert_eq(path[path.size() - 1], node, "and ends there")
		# the path is walkable: each step is an edge that exists
		for i: int in path.size() - 1:
			assert_true(_routes.edge_between(path[i], path[i + 1]) != EntityIds.NONE,
				"step %d of the way to %d is a road" % [i, node])


## A straight line is never longer than the road, and the road is never shorter than
## the straight line: the two together say the distance is a real route and not a guess.
func test_the_road_is_never_shorter_than_the_crow_flies() -> void:
	_setup()
	for node: int in _routes.node_ids():
		var by_road: int = _routes.distance_between(1, node)
		var there: Vector2i = _routes.position_of(node)
		var straight: int = RouteGraph._length_mm(0, 0, there.x, there.y) / 1000
		assert_true(by_road >= straight, "node %d: %d m by road, %d m straight" % [node, by_road, straight])


## M7 spec claim 4's property, over a sample of worlds and every pair in each: the
## distance is symmetric, obeys the triangle inequality, and is never longer than a
## path the test can find for itself.
## Ten thousand worlds with a few pairs sampled in each, rather than three hundred
## worlds and every pair in them.
##
## Exhausting the pairs inside a world is quadratic in its places, and each answer is
## its own search over those places. Once claim 6 spliced towns in and a world went from
## twenty-odd places to eighty-odd, the same test took fifty minutes to say the same
## thing. Sampling spreads the cases over thirty times as many worlds for a fraction of
## the work, which is the direction that matters: the G7 bar is stated in seeds, not in
## pairs within one seed.
func test_property_distance_is_symmetric_and_obeys_the_triangle_inequality() -> void:
	var graph: RouteGraph = RouteGraph.new()
	graph.set_kits(_kits())
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	var asymmetric: int = 0
	var triangles: int = 0
	var beaten: int = 0
	var pairs: int = 0
	for i: int in PROPERTY_CASES:
		graph.generate(SEED_PROPERTY + i)
		var ids: Array[int] = graph.node_ids()
		for sample: int in PAIRS_PER_WORLD:
			var a: int = ids[rng.randi_range(0, ids.size() - 1)]
			var b: int = ids[rng.randi_range(0, ids.size() - 1)]
			pairs += 1
			var there: int = graph.distance_between(a, b)
			if there != graph.distance_between(b, a):
				asymmetric += 1
				if asymmetric <= 3:
					fail("seed %d: %d to %d is not %d to %d" % [SEED_PROPERTY + i, a, b, b, a])
			# the path the query itself returns is a path, so the distance may not
			# be longer than walking it
			var walked: int = 0
			var path: Array[int] = graph.path_between(a, b)
			for step: int in path.size() - 1:
				var rec: Dictionary = graph.edge(graph.edge_between(path[step], path[step + 1]))
				var length: int = rec["length"]
				walked += length
			if there > walked / 1000:
				beaten += 1
				if beaten <= 3:
					fail("seed %d: %d m claimed, %d m walked" % [SEED_PROPERTY + i, there, walked / 1000])
			# one random third place a pair, rather than every triple: the cost of all
			# of them is cubic and the claim is not stronger for it
			# in millimetres, because metres truncate: two truncations on the right can
			# lose almost two metres the left never loses, and the inequality would
			# fail on rounding rather than on any path being wrong
			var c: int = ids[rng.randi_range(0, ids.size() - 1)]
			var d: int = ids[rng.randi_range(0, ids.size() - 1)]
			if graph.distance_mm_between(c, d) > graph.distance_mm_between(c, a) + graph.distance_mm_between(a, d):
				triangles += 1
				if triangles <= 3:
					fail("seed %d: going by %d beat going straight" % [SEED_PROPERTY + i, a])
	assert_eq(asymmetric, 0, "distance is the same both ways over %d pairs" % pairs)
	assert_eq(beaten, 0, "and is never longer than the path it hands back")
	assert_eq(triangles, 0, "and no detour is shorter than going straight")


## Metres are the reading unit and millimetres are the arithmetic one. This is the
## difference, stated, so nobody compares two distances in metres and wonders why a
## detour came out shorter.
func test_metres_are_the_rounded_reading_of_millimetres() -> void:
	_setup()
	for node: int in _routes.node_ids():
		var mm: int = _routes.distance_mm_between(1, node)
		assert_eq(_routes.distance_between(1, node), mm / 1000, "node %d reads as its millimetres" % node)
	assert_eq(_routes.distance_mm_between(1, 1), 0, "nowhere from itself")
	assert_eq(_routes.distance_mm_between(1, 99999), -1, "and nothing to a place that is not one")


## M7 spec claim 5: slots are emitted by generation, not chosen later. Every settlement
## and every point of interest offers exactly one candidate location; a junction offers
## none, because a junction is where roads meet and not somewhere to put a building.
func test_every_place_worth_building_at_offers_a_slot() -> void:
	_setup()
	var wanted: int = 0
	var by_node: Dictionary = {}
	for node: int in _routes.node_ids():
		var kind: StringName = _routes.kind_of(node)
		if kind == RouteGraph.KIND_POI or kind == RouteGraph.KIND_SETTLEMENT:
			wanted += 1
	assert_eq(_routes.slot_count(), wanted, "one slot for every place worth building at")
	assert_true(wanted > 0, "and a world has some (%d)" % wanted)
	for slot: int in _routes.slot_ids():
		var node: int = _routes.slot_node(slot)
		assert_true(_routes.has_node(node), "slot %d hangs off a real place" % slot)
		assert_false(by_node.has(node), "and no place offers two")
		by_node[node] = true
		var kind: StringName = _routes.kind_of(node)
		assert_true(kind == RouteGraph.KIND_POI or kind == RouteGraph.KIND_SETTLEMENT,
			"slot %d is not at a junction or the gate (%s)" % [slot, kind])
		assert_true(RouteGraph.BIOMES.has(_routes.slot_biome(slot)), "and it stands on ground the world has")
		var at: Vector2i = _routes.slot_position(slot)
		var from: Vector2i = _routes.position_of(node)
		var step: Vector2i = Vector2i((at.x - from.x) / RouteGraph.SLOT_OFFSET_MM, (at.y - from.y) / RouteGraph.SLOT_OFFSET_MM)
		assert_true(RouteGraph.SLOT_STEPS.has(step), "and it lies one step off the road (%s)" % step)
	assert_false(_routes.has_slot(99999), "and something that is not a slot is not one")
	assert_eq(_routes.slot_node(99999), EntityIds.NONE, "which hangs off nowhere")
	assert_eq(_routes.slot_biome(99999), &"", "and stands on nothing")
	assert_eq(_routes.slot_position(99999), Vector2i.ZERO, "and is not anywhere")


## The slots are inside the thing the hash is taken over, which is what makes "the same
## seed offers the same slots" a claim the world hash already carries rather than a
## second promise to keep. If a slot could move without the hash moving, a save could
## restore a world whose places had quietly changed.
func test_slots_are_part_of_the_world_and_not_an_afterthought() -> void:
	_setup()
	var canonical: Dictionary = _routes.canonical()
	assert_true(canonical.has("slots"), "the world as data includes its slots")
	var slots: Array = canonical["slots"]
	assert_eq(slots.size(), _routes.slot_count(), "all of them")
	for row: Variant in slots:
		var entry: Array = row
		var id: int = entry[0]
		var node: int = entry[1]
		var x: int = entry[2]
		var z: int = entry[3]
		var biome: String = entry[4]
		assert_eq(node, _routes.slot_node(id), "slot %d is written down as it is held" % id)
		assert_eq(Vector2i(x, z), _routes.slot_position(id), "in the same place")
		assert_eq(StringName(biome), _routes.slot_biome(id), "on the same ground")
	assert_eq(_routes.world_hash(), StateHash.of(canonical), "and the hash is taken over exactly that")


## What a contract means by "eight to fifteen kilometres from the city": the roads to
## the place, then the last stretch off the road. Asked of the graph with nothing loaded.
func test_how_far_a_slot_is_from_the_city() -> void:
	_setup()
	# a diagonal step is the long one: sixty metres each way is about eighty-five
	var furthest_off_road: int = RouteGraph.SLOT_OFFSET_MM * 1415 / 1000
	var all_at_once: Dictionary = _routes.slots_metres_from_gate()
	assert_eq(all_at_once.size(), _routes.slot_count(), "asked all at once, every slot answers")
	for slot: int in _routes.slot_ids():
		assert_eq(all_at_once[slot], _routes.slot_metres_from_gate(slot), "slot %d: the same answer as asked alone" % slot)
		var node: int = _routes.slot_node(slot)
		var by_road: int = _routes.distance_mm_between(1, node)
		var metres: int = _routes.slot_metres_from_gate(slot)
		assert_true(metres * M >= by_road - M, "slot %d is at least as far as its place (%d m)" % [slot, metres])
		assert_true(metres * M <= by_road + furthest_off_road, "and no further than one step past it")
		assert_true(metres > 0, "and somewhere out there")
	assert_eq(_routes.slot_metres_from_gate(99999), -1, "and nothing is no distance at all")


## M7 spec claim 9, the graph's half: a bound site is stitched on as a leaf. It is a
## place on the map with a road to it, and it is the save's rather than the seed's, so
## it does not move the world hash — or a save with a bound site would fail its own
## check that the seed still builds the world it names.
func test_a_bound_site_is_stitched_on_as_a_leaf() -> void:
	_setup()
	var world: String = _routes.world_hash()
	var nodes: int = _routes.node_count()
	var edges: int = _routes.edge_count()
	var before: Dictionary = {}
	for node: int in _routes.node_ids():
		before[node] = _routes.distance_mm_between(1, node)
	var slot: int = _routes.slot_ids()[0]
	assert_eq(_routes.site_node_of(slot), EntityIds.NONE, "nothing is stitched to begin with")
	var site: int = _routes.stitch_slot(slot)
	assert_eq(site, nodes + 1, "a new place, after every place the seed built")
	assert_eq(_routes.kind_of(site), RouteGraph.KIND_SITE, "of its own kind")
	assert_false(RouteGraph.KINDS.has(RouteGraph.KIND_SITE), "which generation never places")
	assert_eq(_routes.position_of(site), _routes.slot_position(slot), "where the slot is")
	assert_eq(_routes.node_town(site), EntityIds.NONE, "put there by no kit")
	assert_eq(_routes.neighbours(site), [_routes.slot_node(slot)] as Array[int], "with one road, to the place that offered it")
	assert_eq(_routes.edge_count(), edges + 1, "and that road is the only new one")
	var track: Dictionary = _routes.edge(_routes.edge_between(site, _routes.slot_node(slot)))
	assert_eq(track["width"], RouteGraph.MIN_WIDTH_MM, "as narrow as the world allows")
	assert_eq(_routes.stitch_slot(slot), site, "stitching it again is the same place")
	assert_eq(_routes.node_count(), nodes + 1, "not a second one")
	assert_eq(_routes.stitch_slot(99999), EntityIds.NONE, "and something that is not a slot stitches nothing")
	assert_eq(_routes.distance_between(1, site), _routes.slot_metres_from_gate(slot), "as far out as the slot said")
	for node: int in before:
		assert_eq(_routes.distance_mm_between(1, node), before[node], "a leaf is no shortcut: node %d is where it was" % node)
	assert_true(_routes.everywhere_is_reachable(), "the world is one piece")
	assert_eq(_routes.world_hash(), world, "and the same world")
	# a second site goes after the first, and taking them all off leaves the seed's world
	var second: int = _routes.stitch_slot(_routes.slot_ids()[1])
	assert_eq(second, site + 1, "the next site is the next id")
	_routes.unstitch_all()
	assert_eq(_routes.node_count(), nodes, "unstitched, the places are the seed's")
	assert_eq(_routes.edge_count(), edges, "and so are the roads")
	assert_eq(_routes.site_node_of(slot), EntityIds.NONE, "and nothing is bound")
	assert_eq(_routes.edges_at(_routes.slot_node(slot)).size(), _routes.neighbours(_routes.slot_node(slot)).size(),
		"with no road left dangling from where the site was")
	assert_eq(_routes.stitch_slot(slot), site, "so stitching again comes back under the same id")


## A save the graph refuses leaves the world in hand as it was, bound sites included.
func test_a_refused_restore_keeps_the_bound_sites() -> void:
	_setup()
	var site: int = _routes.stitch_slot(_routes.slot_ids()[2])
	var nodes: int = _routes.node_count()
	var lying: Dictionary = _routes.snapshot()
	lying["world"] = StateHash.of({"a different": "world"})
	assert_eq(_routes.restore(lying), ERR_INVALID_DATA, "refused")
	assert_eq(_routes.node_count(), nodes, "and the site is still there")
	assert_eq(_routes.site_node_of(_routes.slot_ids()[2]), site, "under the same id")
	assert_eq(_routes.restore(_routes.snapshot()), OK, "a good restore is the seed's world")
	assert_eq(_routes.site_node_of(_routes.slot_ids()[2]), EntityIds.NONE, "and puts the sites back to the binder, whose they are")


## The property the milestone rests on: over ten thousand worlds a slot is always at a
## real place of a kind that can hold one, one step off the road, on ground the world
## knows — and the same seed offers the same slots down to the last one.
func test_property_every_world_offers_the_same_slots_every_time() -> void:
	var kits: Array[Dictionary] = _kits()
	var first: RouteGraph = RouteGraph.new()
	var second: RouteGraph = RouteGraph.new()
	first.set_kits(kits)
	second.set_kits(kits)
	var disagreed: int = 0
	var misplaced: int = 0
	var empty: int = 0
	var counts: Dictionary = {}
	var biomes: Dictionary = {}
	for i: int in PROPERTY_CASES:
		var world: int = SEED_PROPERTY + i
		first.generate(world)
		second.generate(world)
		counts[first.slot_count()] = true
		if first.slot_count() == 0:
			empty += 1
			if empty <= 3:
				fail("seed %d built a world with nowhere to build" % world)
		if first.slot_ids() != second.slot_ids():
			disagreed += 1
			if disagreed <= 3:
				fail("seed %d offered two different sets of slots" % world)
			continue
		for slot: int in first.slot_ids():
			var node: int = first.slot_node(slot)
			var kind: StringName = first.kind_of(node)
			var at: Vector2i = first.slot_position(slot)
			var from: Vector2i = first.position_of(node)
			var step: Vector2i = Vector2i((at.x - from.x) / RouteGraph.SLOT_OFFSET_MM, (at.y - from.y) / RouteGraph.SLOT_OFFSET_MM)
			biomes[first.slot_biome(slot)] = true
			var wrong: bool = (
				not first.has_node(node)
				or (kind != RouteGraph.KIND_POI and kind != RouteGraph.KIND_SETTLEMENT)
				or not RouteGraph.SLOT_STEPS.has(step)
				or not RouteGraph.BIOMES.has(first.slot_biome(slot))
				or second.slot_position(slot) != at
				or second.slot_biome(slot) != first.slot_biome(slot))
			if wrong:
				misplaced += 1
				if misplaced <= 3:
					fail("seed %d put slot %d somewhere it should not be" % [world, slot])
				break
	assert_eq(empty, 0, "every world has somewhere to build (%d worlds)" % PROPERTY_CASES)
	assert_eq(disagreed, 0, "and offers the same slots twice running")
	assert_eq(misplaced, 0, "each one at a real place, one step off the road")
	assert_true(counts.size() >= 8, "worlds differ in how much they offer (%d counts)" % counts.size())
	assert_eq(biomes.size(), RouteGraph.BIOMES.size(), "and every kind of ground is used somewhere")
