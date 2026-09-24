## The route graph (design doc §5.2; M7 spec claim 1). **This is generated first and
## everything else is a consumer of it.**
##
## Terrain, settlements and sites are all downstream: the generator carves around the
## edges this graph already declares, rather than the graph being found by searching
## terrain that already exists. Connectivity is therefore true by construction — every
## node is joined to the rest as it is placed — instead of being a property that has to
## be checked and repaired afterwards. That is the whole reason the graph comes first.
##
## Nothing here may read terrain, because when this runs there is no terrain. Nor may it
## draw from the sim's shared RNG: the graph is a function of the world seed alone, and a
## draw from `sim.rng()` would make it depend on how many other systems had drawn before
## it. It keeps its own generator, seeded from the world.
class_name RouteGraph extends SimSystem

const SYSTEM_ID: StringName = &"routes"

## What a node is. Structural, not content: content decides what stands at a place, not
## whether the graph has one.
const KIND_GATE: StringName = &"gate"
const KIND_SETTLEMENT: StringName = &"settlement"
const KIND_POI: StringName = &"poi"
const KIND_JUNCTION: StringName = &"junction"
const KINDS: Array[StringName] = [KIND_GATE, KIND_SETTLEMENT, KIND_POI, KIND_JUNCTION]
## A bound site (M7 spec claim 9). Not one of [KINDS]: generation never places one. It
## is stitched on afterwards, when a contract binds a slot, and belongs to the overlay
## rather than to the world the seed builds.
const KIND_SITE: StringName = &"site"

## What the ground at a place is. Structural like the node kinds: terrain (claim 7) is
## a consumer of this, not the author of it — the graph says what a place stands on
## before there is any terrain to ask.
const BIOME_SCRUB: StringName = &"scrub"
const BIOME_FOREST: StringName = &"forest"
const BIOME_ROCK: StringName = &"rock"
const BIOME_MARSH: StringName = &"marsh"
const BIOME_FARMLAND: StringName = &"farmland"
const BIOMES: Array[StringName] = [BIOME_SCRUB, BIOME_FOREST, BIOME_ROCK, BIOME_MARSH, BIOME_FARMLAND]

## The narrowest corridor the graph may contain, in millimetres. An edge below this is a
## corridor something cannot walk down, which is the failure the graph exists to prevent.
const MIN_WIDTH_MM: int = 3000
const MAX_WIDTH_MM: int = 12000
## How far out the world reaches, in millimetres. The city gate sits at the origin.
const WORLD_RADIUS_MM: int = 30_000_000
## Nodes never sit closer together than this, so an edge is always a journey.
const MIN_SPACING_MM: int = 400_000
## How many nodes a world has, besides the single gate.
const NODES_MIN: int = 18
const NODES_MAX: int = 34
## Extra edges added after the spanning pass, as a fraction in milli-units of the node
## count: loops, so the graph is not a tree and there is more than one way anywhere.
const LOOP_PERMILLE: int = 350
## How many times placement will try for a spot far enough from its neighbours before
## giving up on that node. Bounded so generation always terminates.
const PLACEMENT_TRIES: int = 24
## How far a site slot sits off the node that offers it, in millimetres: near enough to
## be that place, far enough that a building is beside the road rather than on it.
const SLOT_OFFSET_MM: int = 60_000
## The eight ways a slot can lie from its node. A table rather than an angle, because an
## angle means a sine and a sine means a float, and the graph is state.
const SLOT_STEPS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
]

## node id -> {"kind": StringName, "x": int, "z": int, "town": int}
## `town` is the settlement node whose kit put it there, or NONE for one of the world's
## own places. A town's streets are close together on purpose, so the spacing rule that
## makes an edge a journey is about the world's places and not a town's (claim 6).
var _nodes: Dictionary = {}
## edge id -> {"a": int, "b": int, "width": int, "length": int}
var _edges: Dictionary = {}
## node id -> Array[int] of edge ids, in the order they were made
var _at_node: Dictionary = {}
## slot id -> {"node": int, "x": int, "z": int, "biome": StringName}
var _slots: Dictionary = {}
## settlement node id -> {"kit": StringName, "turn": int, "blocks": Array}
var _towns: Dictionary = {}
## The settlement kits this world is built from, handed over once at assembly. Kept
## rather than read, so a restore rebuilds the same world it saved.
var _kits: Array[Dictionary] = []
var _seed: int = 0
## How many nodes and edges the seed built. Everything past these was stitched on by
## binding: ids are handed out in order, so the generated world is exactly the ids up to
## here, and that is what the world hash is taken over.
var _world_nodes: int = 0
var _world_edges: int = 0
## slot id -> the site node stitched onto it
var _stitched: Dictionary = {}


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


## The world is a function of its seed, so the seed is the state (design doc §5.6: a
## save is a seed plus an overlay). Restoring regenerates rather than storing a graph
## that could disagree with the seed it claims to come from.
##
## The hash rides along, and restore checks it. Without it a save carries no evidence
## of *which* generator made it, so changing generation would silently hand an old save
## a different world under the same name — and no fixture would notice, because the
## seed alone would not have moved.
func snapshot() -> Dictionary:
	return {"seed": _seed, "world": world_hash()}


func attach(sim: SimRoot) -> Error:
	# the tags are read here and never kept: a tag that names a biome the world does not
	# have is dead content and should fail assembly, but generation stays a function of
	# the seed alone, and it cannot read what nothing holds a reference to
	var kits: Array[Dictionary] = []
	var db: SimSystem = sim.get_system(ContentDb.SYSTEM_ID)
	if db != null:
		var content: ContentDb = db
		var bad: Error = SiteTags.validate(content)
		if bad != OK:
			return bad
		bad = SettlementKits.validate(content)
		if bad != OK:
			return bad
		kits = SettlementKits.prepared(content)
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	set_kits(kits)
	generate(sim.get_seed())
	return OK


# ---------------------------------------------------------------- generation

## The settlement kits every later world is built from (M7 spec claim 6). Handed over
## once, before the first generation; a graph with none simply has no towns, which is
## what the graph-only property tests want.
func set_kits(kits: Array[Dictionary]) -> void:
	_kits = kits



## Builds the graph for a world seed, discarding whatever was there.
##
## A function of the seed and of the kits this graph was given at assembly, and of
## nothing else: it reads no content, no terrain and not the sim's shared generator. The
## kits are handed over once by [set_kits] rather than read here, so generation cannot
## quietly start depending on anything more.
##
## Nodes are placed first, then joined: every node after the first is joined to one that
## is already connected, which is what makes the result connected without checking. The
## loop pass afterwards can only add edges, so it cannot break that.
func generate(world_seed: int) -> void:
	_seed = world_seed
	_nodes.clear()
	_edges.clear()
	_at_node.clear()
	_slots.clear()
	_towns.clear()
	_stitched.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	# the city gate is node 1 and sits at the origin: the world is measured from it
	_add_node(KIND_GATE, 0, 0)
	var wanted: int = rng.randi_range(NODES_MIN, NODES_MAX)
	for i: int in wanted:
		var placed: bool = false
		for attempt: int in PLACEMENT_TRIES:
			var x: int = rng.randi_range(-WORLD_RADIUS_MM, WORLD_RADIUS_MM)
			var z: int = rng.randi_range(-WORLD_RADIUS_MM, WORLD_RADIUS_MM)
			if not _far_enough(x, z):
				continue
			_add_node(_kind_for(rng), x, z)
			placed = true
			break
		if not placed:
			# the world is full enough; a node that cannot find room is simply not made,
			# which keeps generation bounded rather than looping for a space that may
			# not exist
			break
	_join_everything(rng)
	_add_loops(rng)
	_raise_towns(rng)
	_offer_slots(rng)
	_world_nodes = _nodes.size()
	_world_edges = _edges.size()


# ---------------------------------------------------------------- bound sites

## Stitches a site onto a slot (M7 spec claim 9): a node where the slot is, joined to
## the node that offers it by a track as narrow as the world allows. Returns the site
## node, the same one every time for the same slot, or NONE if it is not a slot.
##
## A leaf, always: one edge, to a node already in the world. That is what keeps binding
## from disturbing anything the graph has already promised — it cannot disconnect a
## place, and it cannot be a shortcut, so no distance between two places that were
## there before changes. The way there is the road to the slot's node and then the last
## stretch off it, which is exactly what [slot_metres_from_gate] already said it was.
##
## Not part of the world hash. A seed builds a world; a save binds sites in it. The
## binder holds which slots are bound and stitches them again on restore.
func stitch_slot(slot: int) -> int:
	if not has_slot(slot):
		return EntityIds.NONE
	if _stitched.has(slot):
		return _stitched[slot]
	var at: Vector2i = slot_position(slot)
	var site: int = _add_node(KIND_SITE, at.x, at.y)
	_add_edge_wide(slot_node(slot), site, MIN_WIDTH_MM)
	_stitched[slot] = site
	return site


## The site node stitched onto a slot, or NONE if the slot is not bound.
func site_node_of(slot: int) -> int:
	if not _stitched.has(slot):
		return EntityIds.NONE
	return _stitched[slot]


func _slot_of_site(node: int) -> int:
	for key: Variant in _stitched:
		var slot: int = key
		if _stitched[slot] == node:
			return slot
	return EntityIds.NONE


## Takes every stitched site off again, leaving the world the seed built. For restore:
## the binder puts back the ones its save names, in the order they were bound, so they
## come back under the same ids.
func unstitch_all() -> void:
	for id: int in edge_ids():
		if id <= _world_edges:
			continue
		var rec: Dictionary = _edges[id]
		for end: String in ["a", "b"]:
			var node: int = rec[end]
			if node <= _world_nodes:
				var at: Array = _at_node[node]
				at.erase(id)
		_edges.erase(id)
	for node: int in node_ids():
		if node > _world_nodes:
			_nodes.erase(node)
			_at_node.erase(node)
	_stitched.clear()


## Every node after the first is joined to the nearest already-joined node, so the graph
## is connected the moment the last node is placed.
func _join_everything(rng: RandomNumberGenerator) -> void:
	var joined: Array[int] = [1]
	for node: int in node_ids():
		if node == 1:
			continue
		var nearest: int = joined[0]
		var best: int = _distance_mm(node, nearest)
		for candidate: int in joined:
			var d: int = _distance_mm(node, candidate)
			if d < best:
				best = d
				nearest = candidate
		_add_edge(nearest, node, rng)
		joined.append(node)


## A tree is a world with exactly one way to anywhere. These are the other ways.
func _add_loops(rng: RandomNumberGenerator) -> void:
	var ids: Array[int] = node_ids()
	var wanted: int = ids.size() * LOOP_PERMILLE / 1000
	for i: int in wanted:
		var a: int = ids[rng.randi_range(0, ids.size() - 1)]
		var b: int = ids[rng.randi_range(0, ids.size() - 1)]
		if a == b or _edge_between(a, b) != EntityIds.NONE:
			continue
		_add_edge(a, b, rng)


## Site slots (M7 spec claim 5): every settlement and every point of interest offers one
## candidate location, and junctions offer none — a junction is where roads meet, not
## somewhere to put a building.
##
## Emitted here, with the graph, rather than searched for later. A slot is a position,
## the ground it stands on and the place it hangs off; what it is *for* is read from
## content afterwards (see [SiteTags]), and how far it is from the city is asked of the
## graph. Nothing is stored that could later disagree with the graph that made it.
func _offer_slots(rng: RandomNumberGenerator) -> void:
	for node: int in node_ids():
		var kind: StringName = kind_of(node)
		if kind != KIND_POI and kind != KIND_SETTLEMENT:
			continue
		var step: Vector2i = SLOT_STEPS[rng.randi_range(0, SLOT_STEPS.size() - 1)]
		var biome: StringName = BIOMES[rng.randi_range(0, BIOMES.size() - 1)]
		var at: Vector2i = position_of(node)
		var id: int = _slots.size() + 1
		_slots[id] = {
			"node": node,
			"x": at.x + step.x * SLOT_OFFSET_MM,
			"z": at.y + step.y * SLOT_OFFSET_MM,
			"biome": biome,
		}


## Towns (M7 spec claim 6). Every settlement node gets a kit spliced onto it: the kit's
## own streets become graph nodes, its roads become edges, and its sockets are joined to
## the node the outside road already arrives at. A town is therefore a subgraph of the
## world rather than a label on a node, and its navigation is in the graph from the
## moment it exists.
##
## Raised after the world is joined and looped, so a town's dense streets never take
## part in spanning the world or in the spacing rule that makes a world edge a journey.
## Nothing here can disconnect anything: every node placed is joined to the kit's
## always-built part, which is joined to the socket, which is joined to a node that is
## already part of the world. [SettlementKits.validate] is what makes that true of any
## kit, and it runs at assembly.
func _raise_towns(rng: RandomNumberGenerator) -> void:
	if _kits.is_empty():
		return
	for node: int in node_ids():
		if kind_of(node) != KIND_SETTLEMENT:
			continue
		_raise_town(node, _kits[rng.randi_range(0, _kits.size() - 1)], rng)


func _raise_town(anchor: int, kit: Dictionary, rng: RandomNumberGenerator) -> void:
	var turn: int = rng.randi_range(0, 3)
	var min_blocks: int = kit["min_blocks"]
	var max_blocks: int = kit["max_blocks"]
	var names: Array = kit["blocks"]
	var pool: Array = names.duplicate()
	var wanted: int = rng.randi_range(min_blocks, max_blocks)
	var built: Array = []
	for i: int in wanted:
		if pool.is_empty():
			break
		built.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	built.sort()
	var chosen: Dictionary = {}
	for v: Variant in built:
		var name: String = v
		chosen[name] = true
	var at: Vector2i = position_of(anchor)
	var made: Dictionary = {}
	var nodes: Array = kit["nodes"]
	for i: int in nodes.size():
		var rec: Dictionary = nodes[i]
		var block: String = rec["block"]
		if not block.is_empty() and not chosen.has(block):
			continue
		var x: int = rec["x"]
		var z: int = rec["z"]
		var rel: Vector2i = _turned(Vector2i(x, z), turn)
		var kind: StringName = rec["kind"]
		made[i] = _add_node(kind, at.x + rel.x, at.y + rel.y, anchor)
	for v: Variant in kit["edges"]:
		var rec: Dictionary = v
		var a: int = rec["a"]
		var b: int = rec["b"]
		if not made.has(a) or not made.has(b):
			# an edge into a block nobody built is not a road to nowhere, it is no road
			continue
		var width: int = rec["width"]
		var from: int = made[a]
		var to: int = made[b]
		_add_edge_wide(from, to, width)
	for v: Variant in kit["sockets"]:
		var rec: Dictionary = v
		var node: int = rec["node"]
		var width: int = rec["width"]
		var street: int = made[node]
		_add_edge_wide(anchor, street, width)
	var id: StringName = kit["id"]
	_towns[anchor] = {"kit": id, "turn": turn, "blocks": built}


## A quarter turn about the node that anchors the town, on integers: a rotation matrix
## of ones and zeroes, so a town can face four ways without a sine anywhere near the
## state.
static func _turned(rel: Vector2i, turn: int) -> Vector2i:
	match turn:
		1:
			return Vector2i(-rel.y, rel.x)
		2:
			return Vector2i(-rel.x, -rel.y)
		3:
			return Vector2i(rel.y, -rel.x)
	return rel


func _kind_for(rng: RandomNumberGenerator) -> StringName:
	var roll: int = rng.randi_range(0, 99)
	if roll < 25:
		return KIND_SETTLEMENT
	if roll < 70:
		return KIND_POI
	return KIND_JUNCTION


func _far_enough(x: int, z: int) -> bool:
	for id: int in _nodes:
		var rec: Dictionary = _nodes[id]
		var nx: int = rec["x"]
		var nz: int = rec["z"]
		if _length_mm(nx, nz, x, z) < MIN_SPACING_MM:
			return false
	return true


func _add_node(kind: StringName, x: int, z: int, town: int = EntityIds.NONE) -> int:
	var id: int = _nodes.size() + 1
	_nodes[id] = {"kind": kind, "x": x, "z": z, "town": town}
	_at_node[id] = [] as Array[int]
	return id


func _add_edge(a: int, b: int, rng: RandomNumberGenerator) -> int:
	return _add_edge_wide(a, b, rng.randi_range(MIN_WIDTH_MM, MAX_WIDTH_MM))


## A road of a width someone chose: a town's streets are as wide as its kit says, not
## as wide as the world rolled.
func _add_edge_wide(a: int, b: int, width: int) -> int:
	# an edge is stored one way round only, lower node first, so two nodes can never be
	# joined twice by the same pair written in the other order
	var lo: int = mini(a, b)
	var hi: int = maxi(a, b)
	var id: int = _edges.size() + 1
	_edges[id] = {
		"a": lo, "b": hi,
		"width": width,
		"length": _distance_mm(lo, hi),
	}
	var at_lo: Array = _at_node[lo]
	at_lo.append(id)
	var at_hi: Array = _at_node[hi]
	at_hi.append(id)
	return id


## Every node reachable from this one, lowest first. A breadth-first walk of the graph,
## which is cheap because a world is tens of nodes and the world is not loaded.
func reachable_from(start: int) -> Array[int]:
	if not has_node(start):
		return [] as Array[int]
	var seen: Dictionary = {start: true}
	var queue: Array[int] = [start]
	var at: int = 0
	while at < queue.size():
		var node: int = queue[at]
		at += 1
		for other: int in neighbours(node):
			if not seen.has(other):
				seen[other] = true
				queue.append(other)
	var out: Array[int] = []
	for key: Variant in seen:
		var id: int = key
		out.append(id)
	out.sort()
	return out


## True when every place can be reached from every other (M7 spec claim 3). Named the
## long way round because `is_connected` is Object's, and quietly overriding the signal
## API is a trap for whoever reads this next.
##
## This is not how connectivity is achieved — it is achieved by joining each node to
## one already joined as it is placed — it is how the claim is checked. A generator
## that stopped being connected would be a bug in construction, not something to repair
## afterwards, which is why nothing calls this to fix anything.
func everywhere_is_reachable() -> bool:
	if _nodes.is_empty():
		return true
	return reachable_from(node_ids()[0]).size() == _nodes.size()


## The narrowest corridor in the world, or 0 if there are none.
func narrowest_edge_mm() -> int:
	var narrowest: int = 0
	for id: int in edge_ids():
		var rec: Dictionary = _edges[id]
		var width: int = rec["width"]
		if narrowest == 0 or width < narrowest:
			narrowest = width
	return narrowest


## How far apart two places are along the roads, in whole metres, or -1 if either is
## not a place (M7 spec claim 4; design doc §6.1 macro tier).
##
## This is a query, not a journey: it answers with the world unloaded, which is what
## lets a quest say "eight to fifteen kilometres from the city" and a response time say
## how long help takes, without a metre of terrain existing. Shortest path by corridor
## length — a world is tens of nodes, so the simplest search that is actually shortest
## is the right one.
func distance_between(a: int, b: int) -> int:
	var mm: int = distance_mm_between(a, b)
	return mm if mm < 0 else mm / 1000


## The same distance in millimetres, which is the one the arithmetic is done in.
##
## Metres are for reading and for content: a contract says "eight to fifteen
## kilometres" and nobody means it to the millimetre. But truncating to metres loses
## up to a metre each time, so a detour measured in metres can come out shorter than
## the direct route by a metre or two — the triangle inequality holds here, not there.
## Anything comparing distances to each other wants this one.
func distance_mm_between(a: int, b: int) -> int:
	if not has_node(a) or not has_node(b):
		return -1
	if a == b:
		return 0
	var best: Dictionary = _shortest_from(a)
	if not best.has(b):
		return -1
	var mm: int = best[b]
	return mm


## The places passed through on the shortest way from `a` to `b`, `a` first and `b`
## last, or empty if either is not a place. A single node is its own path.
func path_between(a: int, b: int) -> Array[int]:
	if not has_node(a) or not has_node(b):
		return [] as Array[int]
	if a == b:
		return [a] as Array[int]
	var came: Dictionary = {}
	var best: Dictionary = _shortest_from(a, came)
	if not best.has(b):
		return [] as Array[int]
	var out: Array[int] = [b]
	var at: int = b
	while at != a:
		var previous: int = came[at]
		out.push_front(previous)
		at = previous
	return out


## Shortest distance in millimetres from one node to every node it can reach. Fills
## `came_from` with the step before each node when one is given.
func _shortest_from(start: int, came_from: Dictionary = {}) -> Dictionary:
	var best: Dictionary = {start: 0}
	var settled: Dictionary = {}
	while true:
		# the world is tens of nodes: scanning for the nearest unsettled one is cheaper
		# than keeping a heap, and it cannot get the answer wrong
		var node: int = EntityIds.NONE
		var node_cost: int = 0
		for key: Variant in best:
			var id: int = key
			if settled.has(id):
				continue
			var cost: int = best[id]
			if node == EntityIds.NONE or cost < node_cost:
				node = id
				node_cost = cost
		if node == EntityIds.NONE:
			break
		settled[node] = true
		for edge_id: int in edges_at(node):
			var rec: Dictionary = _edges[edge_id]
			var x: int = rec["a"]
			var y: int = rec["b"]
			var length: int = rec["length"]
			var other: int = y if x == node else x
			var through: int = node_cost + length
			var known: int = best[other] if best.has(other) else 0
			if not best.has(other) or through < known:
				best[other] = through
				came_from[other] = node
	return best


## A SHA-256 over the whole graph: every node, every corridor, in a fixed order.
##
## Not a hash of the seed. A seed is what was asked for; this is what was built, so it
## moves when generation changes and two machines can compare worlds without shipping
## one to the other (M7 spec claim 2).
func world_hash() -> String:
	return StateHash.of(canonical())


## The graph the seed built as plain data, in the one order everyone agrees on. Bound
## sites are left out: they are the save's overlay, not the world (see [stitch_slot]).
func canonical() -> Dictionary:
	var nodes: Array = []
	for node: int in node_ids():
		if node > _world_nodes:
			# a bound site: the save's, not the seed's
			continue
		var rec: Dictionary = _nodes[node]
		var kind: StringName = rec["kind"]
		var x: int = rec["x"]
		var z: int = rec["z"]
		var town: int = rec["town"]
		nodes.append([node, String(kind), x, z, town])
	var edges: Array = []
	for id: int in edge_ids():
		if id > _world_edges:
			continue
		var rec: Dictionary = _edges[id]
		var a: int = rec["a"]
		var b: int = rec["b"]
		var width: int = rec["width"]
		var length: int = rec["length"]
		edges.append([id, a, b, width, length])
	var slots: Array = []
	for id: int in slot_ids():
		var rec: Dictionary = _slots[id]
		var node: int = rec["node"]
		var x: int = rec["x"]
		var z: int = rec["z"]
		var biome: StringName = rec["biome"]
		slots.append([id, node, x, z, String(biome)])
	var towns: Array = []
	for node: int in town_ids():
		var rec: Dictionary = _towns[node]
		var kit: StringName = rec["kit"]
		var turn: int = rec["turn"]
		var blocks: Array = rec["blocks"]
		towns.append([node, String(kit), turn, blocks.duplicate()])
	return {"nodes": nodes, "edges": edges, "slots": slots, "towns": towns}


# ---------------------------------------------------------------- queries

## Node ids, lowest first. Ids are handed out in placement order and never reused.
func node_ids() -> Array[int]:
	var out: Array[int] = []
	for key: Variant in _nodes:
		var id: int = key
		out.append(id)
	out.sort()
	return out


func edge_ids() -> Array[int]:
	var out: Array[int] = []
	for key: Variant in _edges:
		var id: int = key
		out.append(id)
	out.sort()
	return out


## Slot ids, lowest first. Handed out in node order, so the same seed offers the same
## slots under the same names (M7 spec claim 5).
func slot_ids() -> Array[int]:
	var out: Array[int] = []
	for key: Variant in _slots:
		var id: int = key
		out.append(id)
	out.sort()
	return out


## The settlement nodes that have a town on them, lowest first.
func town_ids() -> Array[int]:
	var out: Array[int] = []
	for key: Variant in _towns:
		var id: int = key
		out.append(id)
	out.sort()
	return out


func node_count() -> int:
	return _nodes.size()


func town_count() -> int:
	return _towns.size()


func has_town(node: int) -> bool:
	return _towns.has(node)


## The town a node belongs to, or NONE if it is one of the world's own places. A town's
## anchor is a world node, so it belongs to no town itself — it is where the road arrives.
func node_town(node: int) -> int:
	var stored: Variant = _nodes.get(node)
	if typeof(stored) != TYPE_DICTIONARY:
		return EntityIds.NONE
	var rec: Dictionary = stored
	return rec["town"]


func town_kit(node: int) -> StringName:
	var stored: Variant = _towns.get(node)
	if typeof(stored) != TYPE_DICTIONARY:
		return &""
	var rec: Dictionary = stored
	return rec["kit"]


## Which way the town faces, as a quarter turn.
func town_turn(node: int) -> int:
	var stored: Variant = _towns.get(node)
	if typeof(stored) != TYPE_DICTIONARY:
		return 0
	var rec: Dictionary = stored
	return rec["turn"]


## The optional blocks this town actually got built with, in a fixed order.
func town_blocks(node: int) -> Array:
	var stored: Variant = _towns.get(node)
	if typeof(stored) != TYPE_DICTIONARY:
		return []
	var rec: Dictionary = stored
	var blocks: Array = rec["blocks"]
	return blocks.duplicate()


## The district whose rights tables a town already has (design doc §7.2), or empty if
## the node is not a town or the kit it used is no longer in the world's kits.
func town_district(node: int) -> StringName:
	var kit: StringName = town_kit(node)
	for entry: Dictionary in _kits:
		var id: StringName = entry["id"]
		if id == kit:
			return entry["district"]
	return &""


func slot_count() -> int:
	return _slots.size()


func has_slot(slot: int) -> bool:
	return _slots.has(slot)


## The node that offers a slot, or NONE.
func slot_node(slot: int) -> int:
	var stored: Variant = _slots.get(slot)
	if typeof(stored) != TYPE_DICTIONARY:
		return EntityIds.NONE
	var rec: Dictionary = stored
	return rec["node"]


## Where a slot is, in millimetres on the ground plane.
func slot_position(slot: int) -> Vector2i:
	var stored: Variant = _slots.get(slot)
	if typeof(stored) != TYPE_DICTIONARY:
		return Vector2i.ZERO
	var rec: Dictionary = stored
	var x: int = rec["x"]
	var z: int = rec["z"]
	return Vector2i(x, z)


## The ground a slot stands on.
func slot_biome(slot: int) -> StringName:
	var stored: Variant = _slots.get(slot)
	if typeof(stored) != TYPE_DICTIONARY:
		return &""
	var rec: Dictionary = stored
	return rec["biome"]


## How far a slot is from the city gate in whole metres, by road to its node and then
## the last stretch off the road, or -1 if it is not a slot.
##
## Asked rather than stored: a contract says "eight to fifteen kilometres from the city"
## and this is the number it means. Storing it would be a second copy of something the
## graph already knows, free to drift from it.
func slot_metres_from_gate(slot: int) -> int:
	if not has_slot(slot):
		return -1
	var node: int = slot_node(slot)
	return _slot_metres(slot, distance_mm_between(1, node))


## Every slot's distance from the city gate, slot id -> whole metres: the same answer as
## [slot_metres_from_gate] for each, from one search rather than one per slot.
func slots_metres_from_gate() -> Dictionary:
	var out: Dictionary = {}
	var best: Dictionary = _shortest_from(1) if has_node(1) else {}
	for slot: int in slot_ids():
		var node: int = slot_node(slot)
		var by_road: int = best[node] if best.has(node) else -1
		out[slot] = _slot_metres(slot, by_road)
	return out


func _slot_metres(slot: int, by_road: int) -> int:
	if by_road < 0:
		return -1
	var at: Vector2i = slot_position(slot)
	var from: Vector2i = position_of(slot_node(slot))
	return (by_road + _length_mm(from.x, from.y, at.x, at.y)) / 1000


func edge_count() -> int:
	return _edges.size()


func has_node(node: int) -> bool:
	return _nodes.has(node)


func kind_of(node: int) -> StringName:
	var stored: Variant = _nodes.get(node)
	if typeof(stored) != TYPE_DICTIONARY:
		return &""
	var rec: Dictionary = stored
	return rec["kind"]


## Where a node is, in millimetres on the ground plane. The y is terrain's business and
## terrain does not exist yet.
func position_of(node: int) -> Vector2i:
	var stored: Variant = _nodes.get(node)
	if typeof(stored) != TYPE_DICTIONARY:
		return Vector2i.ZERO
	var rec: Dictionary = stored
	var x: int = rec["x"]
	var z: int = rec["z"]
	return Vector2i(x, z)


## The edge record: which two nodes, how wide the corridor, how long.
func edge(id: int) -> Dictionary:
	var stored: Variant = _edges.get(id)
	if typeof(stored) != TYPE_DICTIONARY:
		return {}
	var rec: Dictionary = stored
	return rec.duplicate()


## The edges meeting at a node, lowest id first.
func edges_at(node: int) -> Array[int]:
	var stored: Variant = _at_node.get(node)
	if typeof(stored) != TYPE_ARRAY:
		return [] as Array[int]
	var out: Array[int] = []
	for v: Variant in stored:
		var id: int = v
		out.append(id)
	out.sort()
	return out


## The nodes one edge away, lowest first.
func neighbours(node: int) -> Array[int]:
	var out: Array[int] = []
	for id: int in edges_at(node):
		var rec: Dictionary = _edges[id]
		var a: int = rec["a"]
		var b: int = rec["b"]
		out.append(b if a == node else a)
	out.sort()
	return out


## The edge joining two nodes, or NONE. Order does not matter.
func _edge_between(a: int, b: int) -> int:
	for id: int in edges_at(a):
		var rec: Dictionary = _edges[id]
		var x: int = rec["a"]
		var y: int = rec["b"]
		if (x == a and y == b) or (x == b and y == a):
			return id
	return EntityIds.NONE


func edge_between(a: int, b: int) -> int:
	return _edge_between(a, b)


func world_seed() -> int:
	return _seed


func _distance_mm(a: int, b: int) -> int:
	var pa: Vector2i = position_of(a)
	var pb: Vector2i = position_of(b)
	return _length_mm(pa.x, pa.y, pb.x, pb.y)


## Integer millimetres between two points, without floats: the graph is state and state
## does not hold anything whose last bit depends on the machine.
static func _length_mm(ax: int, az: int, bx: int, bz: int) -> int:
	var dx: int = ax - bx
	var dz: int = az - bz
	return _isqrt(dx * dx + dz * dz)


static func _isqrt(value: int) -> int:
	if value <= 0:
		return 0
	var x: int = value
	var y: int = (x + 1) / 2
	while y < x:
		x = y
		y = (x + value / x) / 2
	return x


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 2 or typeof(state.get("seed")) != TYPE_INT or typeof(state.get("world")) != TYPE_STRING:
		push_error("RouteGraph.restore: snapshot must be {\"seed\": int, \"world\": String}")
		return ERR_INVALID_DATA
	var world: int = state["seed"]
	var claimed: String = state["world"]
	var was_seed: int = _seed
	var was_bound: Array[int] = []
	for node: int in node_ids():
		if node > _world_nodes:
			was_bound.append(_slot_of_site(node))
	generate(world)
	if world_hash() != claimed:
		# the seed is the same and the world is not: this save was written by a
		# different generator, and loading it would quietly put the player somewhere
		# else under the same name
		push_error("RouteGraph.restore: seed %d now builds a different world (%s, save says %s)" % [
			world, world_hash().left(12), claimed.left(12)])
		generate(was_seed)
		for slot: int in was_bound:
			stitch_slot(slot)
		return ERR_INVALID_DATA
	return OK
