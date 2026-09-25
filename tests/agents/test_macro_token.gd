extends GcityTest

## M7 spec claim 11: an off-screen agent is a token on the route graph, advanced with no
## navigation, no perception and no geometry.
##
## The property the spec names is over tick streams: a token never leaves its edge,
## its progress only grows along a leg, and at a place it either stops or carries on
## down exactly one edge. The streams here step a token to its next place and no
## further, often exactly onto it, so every crossing is seen on its own rather than
## several being folded into one step and taken on trust.

const SEED: int = 20261270
const SEED_PROPERTY: int = 20261271
const PROPERTY_STREAMS: int = 10_000
## Worlds in the property, each walked by this many streams: generating a world costs
## more than walking one, and the claim is about tokens rather than worlds.
const STREAMS_PER_WORLD: int = 20
const STEPS_PER_STREAM: int = 12
const FACTION: String = "faction.scrapline"

var _sim: SimRoot
var _routes: RouteGraph
var _tokens: MacroTokenSystem


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_routes = SimAssembly.routes_of(_sim)
	_tokens = SimAssembly.tokens_of(_sim)


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


## Two world places a few roads apart, so a token has somewhere to go that is not next
## door.
func _far_pair() -> Array[int]:
	var best: Array[int] = [1, 2]
	var most: int = 0
	for node: int in _routes.node_ids():
		var hops: int = _routes.path_between(1, node).size()
		if hops > most:
			most = hops
			best = [1, node]
	return best


func _length(edge_id: int) -> int:
	var rec: Dictionary = _routes.edge(edge_id)
	return rec["length"]


func test_a_token_is_spawned_at_a_place_bound_for_another() -> void:
	_setup()
	var pair: Array[int] = _far_pair()
	assert_true(_do(MacroTokenSystem.COMMAND_SPAWN, {"faction": FACTION, "from": pair[0], "to": pair[1], "speed": 500, "payload": {"members": 4, "profile": "guard_sim"}}),
		"a patrol sets out")
	var id: int = _tokens.token_ids()[0]
	assert_eq(_tokens.route_of(id), _routes.path_between(pair[0], pair[1]), "along the graph's own shortest way")
	assert_eq(_tokens.from_of(id), pair[0], "from where it was put")
	assert_eq(_tokens.destination_of(id), pair[1], "to where it was sent")
	assert_eq(_tokens.edge_of(id), _routes.edge_between(pair[0], _tokens.toward_of(id)), "on the first road of it")
	assert_eq(_tokens.progress_of(id), 500, "and a tick along it already: it moved on the step it was spawned")
	assert_eq(_tokens.faction_of(id), FACTION, "whose it is")
	assert_eq(_tokens.payload_of(id), {"members": 4, "profile": "guard_sim"}, "and what it carries")
	assert_false(_tokens.is_stopped(id), "still going")
	for payload: Dictionary in [
		{"faction": FACTION, "from": 1, "to": 1, "speed": 500, "payload": {}},
		{"faction": FACTION, "from": 1, "to": 99999, "speed": 500, "payload": {}},
		{"faction": FACTION, "from": 1, "to": pair[1], "speed": 0, "payload": {}},
		{"faction": FACTION, "from": 1, "to": pair[1], "speed": MacroTokenSystem.MAX_SPEED_MM_PER_TICK + 1, "payload": {}},
		{"faction": "Not A Tag", "from": 1, "to": pair[1], "speed": 500, "payload": {}},
		{"faction": FACTION, "from": 1, "to": pair[1], "speed": 500, "payload": {"members": [1]}},
		{"faction": FACTION, "from": 1, "to": pair[1], "speed": 500, "payload": {"no spaces": 1}},
		{"faction": FACTION, "from": 1, "to": pair[1], "speed": 500},
	]:
		assert_false(_do(MacroTokenSystem.COMMAND_SPAWN, payload), "refused: %s" % [payload])
	assert_eq(_tokens.token_ids().size(), 1, "and none of those made a token")


func test_a_token_walks_its_route_and_stops_at_the_end_of_it() -> void:
	_setup()
	var pair: Array[int] = _far_pair()
	var id: int = _tokens.spawn(FACTION, pair[0], pair[1], MacroTokenSystem.MAX_SPEED_MM_PER_TICK, {})
	var route: Array[int] = _tokens.route_of(id)
	var total: int = _routes.distance_mm_between(pair[0], pair[1])
	var ticks: int = (total + MacroTokenSystem.MAX_SPEED_MM_PER_TICK - 1) / MacroTokenSystem.MAX_SPEED_MM_PER_TICK
	_tokens.advance(ticks - 1)
	assert_false(_tokens.is_stopped(id), "a tick short of the whole way, it is still on the road")
	assert_eq(_tokens.toward_of(id), pair[1], "on the last road of it")
	_tokens.advance(1)
	assert_true(_tokens.is_stopped(id), "and one more tick gets it there")
	assert_eq(_tokens.progress_of(id), _length(_tokens.edge_of(id)), "at the very end of the last road")
	assert_eq(_tokens.route_of(id), route, "having kept to the route it planned")
	_tokens.advance(10_000)
	assert_true(_tokens.is_stopped(id), "a token that has arrived stays put")
	assert_eq(_tokens.toward_of(id), pair[1], "where it was sent")


## Motion is linear, so a thousand ticks in one step land exactly where a thousand
## single ticks do. The macro tier is only cheap if this holds, and hydration (claim 12)
## only agrees with itself if it does.
func test_many_ticks_at_once_is_the_same_as_one_at_a_time() -> void:
	_setup()
	var pair: Array[int] = _far_pair()
	var one_by_one := MacroTokenSystem.new(_routes)
	var all_at_once := MacroTokenSystem.new(_routes)
	for speed: int in [1, 37, 400, MacroTokenSystem.MAX_SPEED_MM_PER_TICK]:
		one_by_one.spawn(FACTION, pair[0], pair[1], speed, {})
		all_at_once.spawn(FACTION, pair[0], pair[1], speed, {})
		one_by_one.spawn(FACTION, pair[1], pair[0], speed, {})
		all_at_once.spawn(FACTION, pair[1], pair[0], speed, {})
	for block: int in [1, 7, 993, 4000, 20_000]:
		for i: int in block:
			one_by_one.advance(1)
		all_at_once.advance(block)
		assert_eq(StateHash.of(all_at_once.snapshot()), StateHash.of(one_by_one.snapshot()), "after %d more ticks they agree" % block)
	var crossed: bool = false
	for id: int in all_at_once.token_ids():
		crossed = crossed or all_at_once.from_of(id) != all_at_once.route_of(id)[0]
	assert_true(crossed, "and some of them passed through places on the way, so the carry was exercised")


## The token's world is the graph and only the graph: walking it changes nothing else
## in the sim.
func test_a_token_touches_nothing_but_the_graph() -> void:
	_setup()
	var pair: Array[int] = _far_pair()
	assert_true(_do(MacroTokenSystem.COMMAND_SPAWN, {"faction": FACTION, "from": pair[0], "to": pair[1], "speed": 300, "payload": {}}), "spawned")
	var before: Dictionary = _sim.snapshot()
	_sim.step_n(50)
	var after: Dictionary = _sim.snapshot()
	var systems_before: Dictionary = before["systems"]
	var systems_after: Dictionary = after["systems"]
	for key: Variant in systems_before:
		var id: StringName = key
		if id == MacroTokenSystem.SYSTEM_ID:
			continue
		assert_eq(StateHash.of(systems_after[id]), StateHash.of(systems_before[id]), "%s is untouched by fifty ticks of walking" % id)
	assert_eq(_tokens.progress_of(1), 300 * 51, "while the token walked every one of them")


func test_the_save_carries_every_token_and_refuses_one_off_its_road() -> void:
	_setup()
	var pair: Array[int] = _far_pair()
	_tokens.spawn(FACTION, pair[0], pair[1], 600, {"members": 3})
	_tokens.spawn(FACTION, pair[1], pair[0], 90, {})
	_tokens.advance(3000)
	var snap: Dictionary = _sim.snapshot()
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "restored")
	assert_eq(other.restore_root(snap), OK, "root restored")
	var tokens: MacroTokenSystem = SimAssembly.tokens_of(other)
	assert_eq(StateHash.of(tokens.snapshot()), StateHash.of(_tokens.snapshot()), "every token where it was")
	_sim.step_n(500)
	other.step_n(500)
	assert_eq(other.state_hash(), _sim.state_hash(), "and they walk on identically")
	var good: Dictionary = _tokens.snapshot()
	var route: Array[int] = _tokens.route_of(1)
	var leg_length: int = _length(_tokens.edge_of(1))
	var not_joined: int = EntityIds.NONE
	for node: int in _routes.node_ids():
		if node != route[0] and _routes.edge_between(route[0], node) == EntityIds.NONE:
			not_joined = node
			break
	var bad: Array[Dictionary] = []
	for change: Array in [
		["progress", leg_length + 1], ["progress", -1], ["leg", route.size() - 1], ["leg", -1],
		["speed", 0], ["speed", MacroTokenSystem.MAX_SPEED_MM_PER_TICK + 1],
		["route", [route[0]]], ["route", [route[0], not_joined]], ["route", [route[0], 99999]], ["route", ["1", "2"]],
		["faction", "Not A Tag"], ["payload", {"x": 1.5}],
	]:
		var state: Dictionary = good.duplicate(true)
		var rec: Dictionary = state["tokens"][1]
		rec[change[0]] = change[1]
		bad.append(state)
	bad.append({})
	bad.append({"tokens": {}, "next_token": 0})
	bad.append({"tokens": good["tokens"], "next_token": 2})
	bad.append({"tokens": {"1": good["tokens"][1]}, "next_token": 9})
	for state: Dictionary in bad:
		assert_eq(_tokens.restore(state), ERR_INVALID_DATA, "refused: %s" % [state])
		assert_eq(StateHash.of(_tokens.snapshot()), StateHash.of(good), "and nothing moved")
	assert_eq(_tokens.restore(good), OK, "the real thing restores")


## The property the G7 bar names, over ten thousand tick streams.
func test_property_a_token_keeps_to_its_edge_and_takes_one_road_at_a_time() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var routes := RouteGraph.new()
	routes.set_kits(SettlementKits.prepared(db))
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	var off_edge: int = 0
	var backwards: int = 0
	var bad_turn: int = 0
	var restless: int = 0
	var crossings: int = 0
	var arrivals: int = 0
	var streams: int = 0
	while streams < PROPERTY_STREAMS:
		routes.generate(SEED_PROPERTY + streams / STREAMS_PER_WORLD)
		var nodes: Array[int] = routes.node_ids()
		for s: int in STREAMS_PER_WORLD:
			streams += 1
			var tokens := MacroTokenSystem.new(routes)
			var from: int = nodes[rng.randi_range(0, nodes.size() - 1)]
			var to: int = nodes[rng.randi_range(0, nodes.size() - 1)]
			if from == to:
				to = nodes[(nodes.find(from) + 1) % nodes.size()]
			var id: int = tokens.spawn(FACTION, from, to, rng.randi_range(1, MacroTokenSystem.MAX_SPEED_MM_PER_TICK), {})
			var speed: int = tokens.speed_of(id)
			for step: int in STEPS_PER_STREAM:
				var edge: int = tokens.edge_of(id)
				var was_from: int = tokens.from_of(id)
				var was_toward: int = tokens.toward_of(id)
				var was_progress: int = tokens.progress_of(id)
				var was_stopped: bool = tokens.is_stopped(id)
				var was_leg: int = tokens.leg_of(id)
				# ticks to the next place, and often exactly that many, so the stream lands
				# on places as well as between them
				var was_rec: Dictionary = routes.edge(edge)
				var was_length: int = was_rec["length"]
				var left: int = was_length - was_progress
				var to_next: int = maxi(1, (left + speed - 1) / speed)
				tokens.advance(to_next if rng.randi_range(0, 1) == 0 else rng.randi_range(1, to_next))
				var now: int = tokens.edge_of(id)
				var rec: Dictionary = routes.edge(now)
				var length: int = -1
				var a: int = EntityIds.NONE
				var b: int = EntityIds.NONE
				if not rec.is_empty():
					length = rec["length"]
					a = rec["a"]
					b = rec["b"]
				var progress: int = tokens.progress_of(id)
				var from_now: int = tokens.from_of(id)
				if rec.is_empty() or progress < 0 or progress > length or (from_now != a and from_now != b):
					off_edge += 1
					if off_edge <= 3:
						fail("world %d stream %d: the token left its edge" % [SEED_PROPERTY + streams / STREAMS_PER_WORLD, s])
					break
				if was_stopped:
					if now != edge or progress != was_progress:
						restless += 1
						if restless <= 3:
							fail("a stopped token moved on")
					continue
				if now == edge and from_now == was_from:
					if progress < was_progress:
						backwards += 1
						if backwards <= 3:
							fail("progress went from %d back to %d on one leg" % [was_progress, progress])
					if tokens.is_stopped(id):
						arrivals += 1
					continue
				# it reached a place: it carries on from there down the next road of its
				# route. A road can be shorter than a tick of a fast token — roads that
				# cross are split where they meet — so one step can pass more than one
				# place; each is still the next on the route, and the token is on the
				# road between the two places its route says it is between
				crossings += 1
				var route: Array[int] = tokens.route_of(id)
				var leg: int = tokens.leg_of(id)
				var on_route: bool = leg > was_leg and route[leg] == from_now and routes.edge_between(route[leg], route[leg + 1]) == now
				if not on_route or now == edge or route[was_leg + 1] != was_toward:
					bad_turn += 1
					if bad_turn <= 3:
						fail("at node %d the token turned onto edge %d from edge %d" % [was_toward, now, edge])
	assert_eq(off_edge, 0, "no token ever left its edge (%d streams)" % streams)
	assert_eq(backwards, 0, "progress never went backwards along a leg")
	assert_eq(bad_turn, 0, "every place was left down exactly one road, the next on the route")
	assert_eq(restless, 0, "and a token that stopped stayed stopped")
	assert_true(crossings > PROPERTY_STREAMS, "the streams crossed plenty of places (%d)" % crossings)
	assert_true(arrivals > 100, "and plenty of tokens got where they were going (%d)" % arrivals)
