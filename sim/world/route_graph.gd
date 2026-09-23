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

## node id -> {"kind": StringName, "x": int, "z": int}
var _nodes: Dictionary = {}
## edge id -> {"a": int, "b": int, "width": int, "length": int}
var _edges: Dictionary = {}
## node id -> Array[int] of edge ids, in the order they were made
var _at_node: Dictionary = {}
var _seed: int = 0


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
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	generate(sim.get_seed())
	return OK


# ---------------------------------------------------------------- generation

## Builds the graph for a world seed, discarding whatever was there.
##
## Nodes are placed first, then joined: every node after the first is joined to one that
## is already connected, which is what makes the result connected without checking. The
## loop pass afterwards can only add edges, so it cannot break that.
func generate(world_seed: int) -> void:
	_seed = world_seed
	_nodes.clear()
	_edges.clear()
	_at_node.clear()
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


func _add_node(kind: StringName, x: int, z: int) -> int:
	var id: int = _nodes.size() + 1
	_nodes[id] = {"kind": kind, "x": x, "z": z}
	_at_node[id] = [] as Array[int]
	return id


func _add_edge(a: int, b: int, rng: RandomNumberGenerator) -> int:
	# an edge is stored one way round only, lower node first, so two nodes can never be
	# joined twice by the same pair written in the other order
	var lo: int = mini(a, b)
	var hi: int = maxi(a, b)
	var id: int = _edges.size() + 1
	_edges[id] = {
		"a": lo, "b": hi,
		"width": rng.randi_range(MIN_WIDTH_MM, MAX_WIDTH_MM),
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


## A SHA-256 over the whole graph: every node, every corridor, in a fixed order.
##
## Not a hash of the seed. A seed is what was asked for; this is what was built, so it
## moves when generation changes and two machines can compare worlds without shipping
## one to the other (M7 spec claim 2).
func world_hash() -> String:
	return StateHash.of(canonical())


## The graph as plain data, in the one order everyone agrees on.
func canonical() -> Dictionary:
	var nodes: Array = []
	for node: int in node_ids():
		var rec: Dictionary = _nodes[node]
		var kind: StringName = rec["kind"]
		var x: int = rec["x"]
		var z: int = rec["z"]
		nodes.append([node, String(kind), x, z])
	var edges: Array = []
	for id: int in edge_ids():
		var rec: Dictionary = _edges[id]
		var a: int = rec["a"]
		var b: int = rec["b"]
		var width: int = rec["width"]
		var length: int = rec["length"]
		edges.append([id, a, b, width, length])
	return {"nodes": nodes, "edges": edges}


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


func node_count() -> int:
	return _nodes.size()


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
	generate(world)
	if world_hash() != claimed:
		# the seed is the same and the world is not: this save was written by a
		# different generator, and loading it would quietly put the player somewhere
		# else under the same name
		push_error("RouteGraph.restore: seed %d now builds a different world (%s, save says %s)" % [
			world, world_hash().left(12), claimed.left(12)])
		generate(was_seed)
		return ERR_INVALID_DATA
	return OK
