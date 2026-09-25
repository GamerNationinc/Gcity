## The portal graph over player-built structures (design doc §6.3; M3 spec claims
## 5–8). Player structures are never navmeshed: a flood fill over the build cells
## produces enclosed volumes as nodes and every face piece, and every solid block
## between two volumes, as an edge. Openings cost their `open_cost`; walls cost
## `piece_hp × hp_factor + breach_noise × noise_weight` for the tool class asked
## about, read through the stat resolver so tools and perks modify them without code.
##
## Node 0 is the exterior. Volumes are numbered from 1 in the order of their lowest
## cell, so the same structure always gets the same numbering. The graph is derived
## from the build system on every `build.changed` and is deterministic; the snapshot
## carries it so a restore can verify it rebuilds identically.
class_name PortalGraph extends SimSystem

const SYSTEM_ID: StringName = &"portals"
const EXTERIOR: int = 0
const SOLID: int = -1
const NEIGHBOURS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const MAX_REGION_CELLS: int = 200_000

var _content: ContentDb
var _stats: StatResolver
var _build: BuildSystem
## cell key -> node id (air cells inside the region); absent = exterior or outside
var _node_of_cell: Dictionary = {}
## node id -> {"cells": int, "min": [x, y, z]}
var _nodes: Dictionary = {}
## edge index -> {"piece": int, "a": int, "b": int}, sorted by piece id
var _edges: Array[Dictionary] = []
## piece id (target) -> node id it opens into
var _targets: Dictionary = {}
var _rebuilds: int = 0
## The ground (M7 claim 10): solid ground is a wall like a solid piece, so a building
## raised on the wilds' uneven ground has its rooms found just as one in the city does.
## Unset, the ground is the flat plane below the ground level it always was.
var _regions: Regions = null


func _init(content: ContentDb, stats: StatResolver, build: BuildSystem) -> void:
	_content = content
	_stats = stats
	_build = build


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


func snapshot() -> Dictionary:
	var edges: Array = []
	for e: Dictionary in _edges:
		edges.append([e["piece"], e["a"], e["b"]] as Array[int])
	return {"nodes": _nodes.duplicate(true), "edges": edges, "targets": _targets.duplicate()}


func attach(sim: SimRoot, events: EventBus) -> Error:
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	return events.subscribe(BuildSystem.EVENT_CHANGED, _on_build_changed)


func _on_build_changed(_payload: Dictionary) -> void:
	rebuild()


# ---------------------------------------------------------------- flood fill

## Recomputes nodes, edges and targets from the build system's pieces. The region is
## the pieces' bounding box grown by one cell on every side (never below ground);
## air cells on the region's border belong to the exterior.
func rebuild() -> void:
	_rebuilds += 1
	_node_of_cell = {}
	_nodes = {}
	_edges = []
	_targets = {}
	var ids: Array[int] = _build.piece_ids()
	if ids.is_empty():
		return
	var lo: Vector3i = _build.cell_of_piece(ids[0])
	var hi: Vector3i = lo
	var solid: Dictionary = {}
	var faces: Dictionary = {}
	for id: int in ids:
		var rec: Dictionary = _build.piece(id)
		var face: String = rec["face"]
		for c: Vector3i in _build.cells_of_piece(id):
			lo = Vector3i(mini(lo.x, c.x), mini(lo.y, c.y), mini(lo.z, c.z))
			hi = Vector3i(maxi(hi.x, c.x), maxi(hi.y, c.y), maxi(hi.z, c.z))
		if face.is_empty():
			solid[BuildSystem.cell_key(_build.cell_of_piece(id))] = id
		else:
			faces[face] = id
	lo -= Vector3i.ONE
	hi += Vector3i.ONE
	if _regions == null:
		lo.y = maxi(lo.y, BuildSystem.GROUND_CELL_Y)
	var size: Vector3i = hi - lo + Vector3i.ONE
	assert(size.x * size.y * size.z <= MAX_REGION_CELLS, "portal region too large")
	# exterior first: everything reachable from the border
	var visited: Dictionary = {}
	var border: Array[Vector3i] = []
	for x: int in range(lo.x, hi.x + 1):
		for y: int in range(lo.y, hi.y + 1):
			for z: int in range(lo.z, hi.z + 1):
				var c: Vector3i = Vector3i(x, y, z)
				var on_border: bool = x == lo.x or x == hi.x or y == hi.y or z == lo.z or z == hi.z
				if on_border and not solid.has(BuildSystem.cell_key(c)) and not _ground(c):
					border.append(c)
	_fill(border, EXTERIOR, lo, hi, solid, faces, visited)
	# then every enclosed volume, seeded in cell order
	var next_node: int = 1
	for x: int in range(lo.x, hi.x + 1):
		for y: int in range(lo.y, hi.y + 1):
			for z: int in range(lo.z, hi.z + 1):
				var c: Vector3i = Vector3i(x, y, z)
				var key: String = BuildSystem.cell_key(c)
				if visited.has(key) or solid.has(key) or _ground(c):
					continue
				var seeds: Array[Vector3i] = [c]
				var count: int = _fill(seeds, next_node, lo, hi, solid, faces, visited)
				_nodes[next_node] = {"cells": count, "min": [c.x, c.y, c.z] as Array[int]}
				next_node += 1
	# edges: face pieces between two different nodes; solid blocks between two air cells
	for id: int in ids:
		var rec: Dictionary = _build.piece(id)
		var face: String = rec["face"]
		if not face.is_empty():
			var cells: Array[Vector3i] = BuildSystem.face_cells(face)
			var a: int = node_at(cells[0])
			var b: int = node_at(cells[1])
			if a != SOLID and b != SOLID and a != b:
				_edges.append({"piece": id, "a": mini(a, b), "b": maxi(a, b)})
		else:
			# a solid block is an edge between the air on two opposite open faces
			var c: Vector3i = _build.cell_of_piece(id)
			var pairs: Array = [[Vector3i(1, 0, 0), Vector3i(-1, 0, 0)], [Vector3i(0, 1, 0), Vector3i(0, -1, 0)], [Vector3i(0, 0, 1), Vector3i(0, 0, -1)]]
			for pair: Array in pairs:
				var d1: Vector3i = pair[0]
				var d2: Vector3i = pair[1]
				var a: int = _open_neighbour(c, d1, faces)
				var b: int = _open_neighbour(c, d2, faces)
				if a != SOLID and b != SOLID and a != b:
					_edges.append({"piece": id, "a": mini(a, b), "b": maxi(a, b)})
			var k: Dictionary = _build.kind_data(id)
			var is_target: bool = k["target"]
			if is_target:
				var best: int = SOLID
				for d: Vector3i in NEIGHBOURS:
					var n: int = _open_neighbour(c, d, faces)
					if n != SOLID and (best == SOLID or n < best):
						best = n
				_targets[id] = best
	_edges.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		var px: int = x["piece"]
		var py: int = y["piece"]
		if px != py:
			return px < py
		var ax: int = x["a"]
		var ay: int = y["a"]
		if ax != ay:
			return ax < ay
		var bx: int = x["b"]
		var by: int = y["b"]
		return bx < by)


## The node of the neighbour across an open face of `cell`, or SOLID when the face
## carries a piece or the neighbour is solid.
func _open_neighbour(cell: Vector3i, d: Vector3i, faces: Dictionary) -> int:
	if faces.has(BuildSystem.face_key(cell, _facing_of(d))):
		return SOLID
	return node_at(cell + d)


## Breadth-first over air cells inside [lo, hi] through unblocked faces. Returns the
## number of cells labelled.
func _fill(seeds: Array[Vector3i], node: int, lo: Vector3i, hi: Vector3i, solid: Dictionary, faces: Dictionary, visited: Dictionary) -> int:
	var queue: Array[Vector3i] = []
	for s: Vector3i in seeds:
		var key: String = BuildSystem.cell_key(s)
		if visited.has(key) or solid.has(key) or _ground(s):
			continue
		visited[key] = true
		_node_of_cell[key] = node
		queue.append(s)
	var head: int = 0
	while head < queue.size():
		var c: Vector3i = queue[head]
		head += 1
		for d: Vector3i in NEIGHBOURS:
			var n: Vector3i = c + d
			if n.x < lo.x or n.x > hi.x or n.y < lo.y or n.y > hi.y or n.z < lo.z or n.z > hi.z:
				continue
			var key: String = BuildSystem.cell_key(n)
			if visited.has(key) or solid.has(key) or _ground(n):
				continue
			var facing: String = _facing_of(d)
			if faces.has(BuildSystem.face_key(c, facing)):
				continue
			visited[key] = true
			_node_of_cell[key] = node
			queue.append(n)
	return queue.size()


func set_regions(regions: Regions) -> void:
	_regions = regions


func _ground(cell: Vector3i) -> bool:
	return _regions != null and _regions.is_solid(cell)


static func _facing_of(d: Vector3i) -> String:
	if d.x != 0:
		return "px" if d.x > 0 else "nx"
	if d.y != 0:
		return "py" if d.y > 0 else "ny"
	return "pz" if d.z > 0 else "nz"


# ---------------------------------------------------------------- queries

## The node an air cell belongs to: EXTERIOR outside or on the border of the region,
## a volume id inside, SOLID for a cell a solid piece occupies or below ground.
func node_at(cell: Vector3i) -> int:
	if _regions == null and cell.y < BuildSystem.GROUND_CELL_Y:
		return SOLID
	if _ground(cell):
		return SOLID
	if _build.cell_piece_at(cell) != EntityIds.NONE:
		return SOLID
	var v: Variant = _node_of_cell.get(BuildSystem.cell_key(cell))
	if typeof(v) != TYPE_INT:
		return EXTERIOR
	var node: int = v
	return node


func node_ids() -> Array[int]:
	var out: Array[int] = [EXTERIOR]
	var keys: Array = _nodes.keys()
	keys.sort()
	for k: Variant in keys:
		var id: int = k
		out.append(id)
	return out


func volume_count() -> int:
	return _nodes.size()


func cells_in(node: int) -> int:
	if node == EXTERIOR:
		return -1
	if not _nodes.has(node):
		return 0
	var rec: Dictionary = _nodes[node]
	return rec["cells"]


func edge_count() -> int:
	return _edges.size()


## Edges touching a node, as [piece, other node] pairs in piece order.
func edges_of(node: int) -> Array[Array]:
	var out: Array[Array] = []
	for e: Dictionary in _edges:
		var a: int = e["a"]
		var b: int = e["b"]
		var piece: int = e["piece"]
		if a == node:
			out.append([piece, b] as Array[int])
		elif b == node:
			out.append([piece, a] as Array[int])
	return out


func targets() -> Dictionary:
	return _targets.duplicate()


func rebuild_count() -> int:
	return _rebuilds


## The cost of crossing a piece for a tool class: an opening's open_cost, else the
## breach cost from the resolver and the tool. -1 for an unknown piece or tool.
func edge_cost(piece: int, tool_class: StringName) -> int:
	if not _build.has_piece(piece) or not _content.has(BuildSystem.KIND_TOOL, tool_class):
		return -1
	var k: Dictionary = _build.kind_data(piece)
	var passable: bool = k["passable"]
	var t: Dictionary = _content.get_entry(BuildSystem.KIND_PIECE, _build.template_of(piece))
	if passable:
		return t["open_cost"]
	var tool: Dictionary = _content.get_entry(BuildSystem.KIND_TOOL, tool_class)
	var hp_factor: int = tool["hp_factor"]
	var noise_weight: int = tool["noise_weight"]
	var hp: int = maxi(0, _stats.resolve(piece, BuildSystem.STAT_HP))
	var noise: int = maxi(0, _stats.resolve(piece, BuildSystem.STAT_NOISE))
	return hp * hp_factor + noise * noise_weight


## Cheapest path between two nodes for a tool class: {"cost": int, "pieces": Array[int]
## in crossing order, "nodes": Array[int]}. cost -1 when unreachable. Uniform-cost
## search (A* with a zero heuristic: nodes have no metric); ties resolve to the lower
## piece id, so the result is deterministic.
func cheapest_path(from: int, to: int, tool_class: StringName) -> Dictionary:
	var none: Dictionary = {"cost": -1, "pieces": [] as Array[int], "nodes": [] as Array[int]}
	if not _content.has(BuildSystem.KIND_TOOL, tool_class):
		return none
	if from != EXTERIOR and not _nodes.has(from):
		return none
	if to != EXTERIOR and not _nodes.has(to):
		return none
	var best: Dictionary = {from: 0}
	var via: Dictionary = {}
	var done: Dictionary = {}
	while true:
		var current: int = -2
		var current_cost: int = 0
		for n: Variant in best:
			if done.has(n):
				continue
			var c: int = best[n]
			var node: int = n
			if current == -2 or c < current_cost or (c == current_cost and node < current):
				current = node
				current_cost = c
		if current == -2:
			break
		done[current] = true
		if current == to:
			break
		for e: Array in edges_of(current):
			var piece: int = e[0]
			var other: int = e[1]
			var cost: int = edge_cost(piece, tool_class)
			if cost < 0:
				continue
			var total: int = current_cost + cost
			var known: Variant = best.get(other)
			var improves: bool = typeof(known) != TYPE_INT or total < known
			if not improves and typeof(known) == TYPE_INT and total == known:
				var prev: Array = via[other]
				var prev_piece: int = prev[1]
				improves = piece < prev_piece
			if improves:
				best[other] = total
				via[other] = [current, piece] as Array[int]
	if not done.has(to):
		return none
	var pieces: Array[int] = []
	var nodes: Array[int] = [to]
	var at: int = to
	while at != from:
		var step: Array = via[at]
		var prev_node: int = step[0]
		var piece: int = step[1]
		pieces.push_front(piece)
		nodes.push_front(prev_node)
		at = prev_node
	return {"cost": best[to], "pieces": pieces, "nodes": nodes}


## The raid plan from the exterior: the highest-value reachable target (ties: lower
## cost, then lower id) and its cheapest path to the volume it sits in.
## {"target": piece id or 0, "value": int, "cost": int, "pieces": Array[int]}.
func raid_plan(tool_class: StringName) -> Dictionary:
	var plan: Dictionary = {"target": EntityIds.NONE, "value": 0, "cost": -1, "pieces": [] as Array[int]}
	var ids: Array = _targets.keys()
	ids.sort()
	for t: Variant in ids:
		var target: int = t
		var node: int = _targets[target]
		if node == SOLID:
			continue
		var path: Dictionary = cheapest_path(EXTERIOR, node, tool_class)
		var cost: int = path["cost"]
		if cost < 0:
			continue
		var template: Dictionary = _content.get_entry(BuildSystem.KIND_PIECE, _build.template_of(target))
		var value: int = template["value"]
		var current_value: int = plan["value"]
		var current_cost: int = plan["cost"]
		var better: bool = plan["target"] == EntityIds.NONE or value > current_value or (value == current_value and cost < current_cost)
		if better:
			plan = {"target": target, "value": value, "cost": cost, "pieces": path["pieces"]}
	return plan


# ---------------------------------------------------------------- restore

## The graph is derived state: restore rebuilds it from the (already restored) build
## system and refuses if the result differs from what was saved.
func restore(state: Dictionary) -> Error:
	if state.size() != 3:
		return _restore_fail("shape")
	rebuild()
	if StateHash.of(snapshot()) != StateHash.of(state):
		return _restore_fail("saved graph differs from the one the pieces produce")
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("PortalGraph.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
