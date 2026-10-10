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
const UNVISITED: int = -2
const NEIGHBOURS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const MAX_REGION_CELLS: int = 200_000

var _content: ContentDb
var _stats: StatResolver
var _build: BuildSystem
## The region of the last rebuild and a node label per cell in it (x-major, then y,
## then z), SOLID for a solid cell; empty when there are no pieces (M6 claim 7: packed
## grids, not string-keyed dictionaries, so a rebuild stays inside its frame budget).
var _lo: Vector3i = Vector3i.ZERO
var _size: Vector3i = Vector3i.ZERO
var _labels: PackedInt32Array = PackedInt32Array()
## blocked faces of the last rebuild, one grid per axis, on the lower cell
var _blocked: Array[PackedByteArray] = []
## piece id -> its lower cell and its face axis (-1: a cell piece), as of the last change
var _piece_lower: Dictionary = {}
var _piece_axis: Dictionary = {}
## volume id -> the grid index of its first cell in x, y, z order (its numbering key)
var _node_first: Dictionary = {}
## node id -> {"cells": int, "min": [x, y, z]}
var _nodes: Dictionary = {}
## edge index -> {"piece": int, "a": int, "b": int}, sorted by piece id
var _edges: Array[Dictionary] = []
## piece id (target) -> node id it opens into
var _targets: Dictionary = {}
var _rebuilds: int = 0
## a build change since the last rebuild: the next query or snapshot rebuilds once, so a
## burst of changes (a site raised in one tick) costs one rebuild (M6 claim 7)
var _stale: bool = false


func _init(content: ContentDb, stats: StatResolver, build: BuildSystem) -> void:
	_content = content
	_stats = stats
	_build = build


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


func snapshot() -> Dictionary:
	_fresh()
	var edges: Array = []
	for e: Dictionary in _edges:
		edges.append([e["piece"], e["a"], e["b"]] as Array[int])
	return {"nodes": _nodes.duplicate(true), "edges": edges, "targets": _targets.duplicate()}


func attach(sim: SimRoot, events: EventBus) -> Error:
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	return events.subscribe(BuildSystem.EVENT_CHANGED, _on_build_changed)


## A removal-only change is applied in place (M6 claim 7: the hot path of a mission is
## breaches and cuts); anything else marks the graph stale for one batched rebuild.
func _on_build_changed(payload: Dictionary) -> void:
	if _stale:
		return
	var added: Array = payload["added"]
	var removed: Array = payload["removed"]
	if not added.is_empty() or removed.is_empty() or _size == Vector3i.ZERO or not _remove_in_place(removed):
		_stale = true


## Rebuilds once if the build changed since the last rebuild. Every query calls it: the
## graph is a function of the pieces alone, so when it is computed changes nothing.
func _fresh() -> void:
	if _stale:
		rebuild()


# ---------------------------------------------------------------- flood fill

## Recomputes nodes, edges and targets from the build system's pieces. The region is
## the pieces' bounding box (with every excavated cell) grown by one cell on every side
## and never below the lowest storey; air cells on its border belong to the exterior,
## and enclosed volumes are numbered in cell order. Solid cells and blocked faces are
## copied into packed grids once, and the flood fill runs over integer indices (M6
## claim 7); the result is exactly the string-keyed fill's (tests/nav/doubles).
func rebuild() -> void:
	_rebuilds += 1
	_stale = false
	_nodes = {}
	_edges = []
	_targets = {}
	_labels = PackedInt32Array()
	_blocked = []
	_piece_lower = {}
	_piece_axis = {}
	_node_first = {}
	_size = Vector3i.ZERO
	var ids: Array[int] = _build.piece_ids()
	if ids.is_empty():
		return
	# one read per piece: its lower cell and its face axis (-1 for a cell piece)
	var lowers: Array[Vector3i] = []
	var axes: PackedInt32Array = PackedInt32Array()
	var lo: Vector3i = _build.cell_of_piece(ids[0])
	var hi: Vector3i = lo
	for id: int in ids:
		var lower: Vector3i = _build.cell_of_piece(id)
		var face: String = _build.face_of(id)
		var axis: int = -1 if face.is_empty() else BuildSystem.AXES.find(face.substr(face.length() - 1))
		lowers.append(lower)
		axes.append(axis)
		_piece_lower[id] = lower
		_piece_axis[id] = axis
		var upper: Vector3i = lower if axis < 0 else lower + NEIGHBOURS[axis * 2]
		lo = Vector3i(mini(lo.x, lower.x), mini(lo.y, lower.y), mini(lo.z, lower.z))
		hi = Vector3i(maxi(hi.x, upper.x), maxi(hi.y, upper.y), maxi(hi.z, upper.z))
	var excavated: Array[Vector3i] = _build.excavated_cells()
	for c: Vector3i in excavated:
		lo = Vector3i(mini(lo.x, c.x), mini(lo.y, c.y), mini(lo.z, c.z))
		hi = Vector3i(maxi(hi.x, c.x), maxi(hi.y, c.y), maxi(hi.z, c.z))
	lo -= Vector3i.ONE
	hi += Vector3i.ONE
	lo.y = maxi(lo.y, BuildSystem.MIN_STOREY)
	var size: Vector3i = hi - lo + Vector3i.ONE
	var count: int = size.x * size.y * size.z
	assert(count <= MAX_REGION_CELLS, "portal region too large")
	_lo = lo
	_size = size
	var sx: int = size.y * size.z
	var sy: int = size.z
	# solid cells: earth below the ground storey unless excavated, and every cell piece
	var solid: PackedByteArray = PackedByteArray()
	solid.resize(count)
	for y: int in range(lo.y, mini(hi.y, BuildSystem.GROUND_CELL_Y - 1) + 1):
		for x: int in range(lo.x, hi.x + 1):
			var row: int = (x - lo.x) * sx + (y - lo.y) * sy
			for z: int in size.z:
				solid[row + z] = 1
	for c: Vector3i in excavated:
		solid[_index(c)] = 0
	# blocked faces, one grid per axis, on the lower cell: every face piece, and the uncut
	# ground over an excavated cell
	var blocked: Array[PackedByteArray] = []
	for axis: int in 3:
		var grid: PackedByteArray = PackedByteArray()
		grid.resize(count)
		blocked.append(grid)
	for p: int in ids.size():
		var axis: int = axes[p]
		if axis < 0:
			solid[_index(lowers[p])] = 1
		else:
			blocked[axis][_index(lowers[p])] = 1
	for c: Vector3i in excavated:
		if c.y == BuildSystem.GROUND_CELL_Y - 1 and _build.is_uncut_ground(BuildSystem.face_key(c, "py")):
			blocked[1][_index(c)] = 1
	_labels.resize(count)
	_labels.fill(UNVISITED)
	for i: int in count:
		if solid[i] == 1:
			_labels[i] = SOLID
	# exterior first: everything reachable from the border
	var border: PackedInt32Array = PackedInt32Array()
	for x: int in size.x:
		for y: int in size.y:
			for z: int in size.z:
				var on_border: bool = x == 0 or x == size.x - 1 or y == size.y - 1 or z == 0 or z == size.z - 1
				var i: int = x * sx + y * sy + z
				if on_border and _labels[i] == UNVISITED:
					border.append(i)
	_fill(border, EXTERIOR, blocked)
	# then every enclosed volume, seeded in cell order
	var next_node: int = 1
	for i: int in count:
		if _labels[i] != UNVISITED:
			continue
		var cells: int = _fill(PackedInt32Array([i]), next_node, blocked)
		_nodes[next_node] = {"cells": cells, "min": _cell_array(i)}
		_node_first[next_node] = i
		next_node += 1
	_blocked = blocked
	_derive_edges()


## Edges and targets from the labels and the piece cache: a face piece is an edge between
## two different nodes, a solid block between the air on two opposite open faces; a
## target opens into its lowest open neighbour.
func _derive_edges() -> void:
	_edges = []
	_targets = {}
	var sx: int = _size.y * _size.z
	var sy: int = _size.z
	var ids: Array[int] = _build.piece_ids()
	for id: int in ids:
		var axis: int = _piece_axis[id]
		var lower: Vector3i = _piece_lower[id]
		if axis >= 0:
			var li: int = _index(lower)
			var a: int = _labels[li]
			var b: int = _labels[li + (sx if axis == 0 else (sy if axis == 1 else 1))]
			if a != SOLID and b != SOLID and a != b:
				_edges.append({"piece": id, "a": mini(a, b), "b": maxi(a, b)})
		else:
			var c: Vector3i = lower
			for ax: int in 3:
				var d: Vector3i = NEIGHBOURS[ax * 2]
				var a: int = _open_neighbour(c, d, _blocked)
				var b: int = _open_neighbour(c, -d, _blocked)
				if a != SOLID and b != SOLID and a != b:
					_edges.append({"piece": id, "a": mini(a, b), "b": maxi(a, b)})
			var k: Dictionary = _build.kind_data(id)
			var is_target: bool = k["target"]
			if is_target:
				var best: int = SOLID
				for d: Vector3i in NEIGHBOURS:
					var n: int = _open_neighbour(c, d, _blocked)
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


## Applies removed pieces to the labels in place: a face that opens merges the nodes on
## its two sides, a cell that empties joins every node it now touches (or becomes a
## volume of its own); a merge with the exterior is the exterior. Volumes are then
## renumbered by their first cell, as the full fill numbers them, and edges re-derived.
## Returns false, having changed nothing, when it cannot: a piece it never saw, or no
## pieces left.
func _remove_in_place(removed: Array) -> bool:
	for v: Variant in removed:
		var id: int = v
		if not _piece_axis.has(id):
			return false
	if _build.piece_ids().is_empty():
		return false
	var sx: int = _size.y * _size.z
	var sy: int = _size.z
	var strides: PackedInt32Array = PackedInt32Array([sx, sy, 1])
	for v: Variant in removed:
		var id: int = v
		var axis: int = _piece_axis[id]
		var lower: Vector3i = _piece_lower[id]
		var li: int = _index(lower)
		if axis >= 0:
			_blocked[axis][li] = 0
			var a: int = _labels[li]
			var b: int = _labels[li + strides[axis]]
			if a != SOLID and b != SOLID and a != b:
				_merge([a, b], PackedInt32Array())
		else:
			var touching: Array[int] = []
			for d: Vector3i in NEIGHBOURS:
				var n: int = _open_neighbour(lower, d, _blocked)
				if n != SOLID and not touching.has(n):
					touching.append(n)
			_merge(touching, PackedInt32Array([li]))
		_piece_axis.erase(id)
		_piece_lower.erase(id)
	_renumber()
	_derive_edges()
	return true


## Gives every cell labelled with one of `labels`, and every cell in `new_cells`, one
## label: the exterior if it is among them, else a fresh volume.
func _merge(labels: Array[int], new_cells: PackedInt32Array) -> void:
	var target: int = EXTERIOR
	if not labels.has(EXTERIOR):
		target = 1
		for k: Variant in _nodes:
			var node: int = k
			target = maxi(target, node + 1)
	var cells: int = new_cells.size()
	var first: int = -1
	for i: int in new_cells:
		first = i if first < 0 else mini(first, i)
	for node: int in labels:
		if node == EXTERIOR:
			continue
		var rec: Dictionary = _nodes[node]
		var c: int = rec["cells"]
		cells += c
		var f: int = _node_first[node]
		first = f if first < 0 else mini(first, f)
		_nodes.erase(node)
		_node_first.erase(node)
	if labels.size() > 1 or (labels.size() == 1 and labels[0] != target):
		for i: int in _labels.size():
			if labels.has(_labels[i]):
				_labels[i] = target
	for i: int in new_cells:
		_labels[i] = target
	if target != EXTERIOR:
		_nodes[target] = {"cells": cells, "min": _cell_array(first)}
		_node_first[target] = first


## Numbers the volumes 1.. in the order of their first cell, as the full fill does.
func _renumber() -> void:
	var order: Array[int] = []
	for k: Variant in _node_first:
		var node: int = k
		order.append(node)
	order.sort_custom(func(a: int, b: int) -> bool:
		var fa: int = _node_first[a]
		var fb: int = _node_first[b]
		return fa < fb)
	var identity: bool = true
	var map: Dictionary = {}
	for n: int in order.size():
		map[order[n]] = n + 1
		identity = identity and order[n] == n + 1
	if identity:
		return
	for i: int in _labels.size():
		var label: int = _labels[i]
		if label > EXTERIOR:
			_labels[i] = map[label]
	var nodes: Dictionary = {}
	var firsts: Dictionary = {}
	for old: int in order:
		var new_id: int = map[old]
		nodes[new_id] = _nodes[old]
		firsts[new_id] = _node_first[old]
	_nodes = nodes
	_node_first = firsts


func _cell_array(i: int) -> Array[int]:
	var sx: int = _size.y * _size.z
	var sy: int = _size.z
	return [_lo.x + i / sx, _lo.y + (i % sx) / sy, _lo.z + i % sy] as Array[int]


## The index of a cell inside the last rebuild's region, or -1 outside it.
func _index(cell: Vector3i) -> int:
	var r: Vector3i = cell - _lo
	if r.x < 0 or r.y < 0 or r.z < 0 or r.x >= _size.x or r.y >= _size.y or r.z >= _size.z:
		return -1
	return (r.x * _size.y + r.y) * _size.z + r.z


## The node across the face of `cell` in direction `d`, or SOLID when the face is
## blocked or the neighbour is solid.
func _open_neighbour(cell: Vector3i, d: Vector3i, blocked: Array[PackedByteArray]) -> int:
	var axis: int = 0 if d.x != 0 else (1 if d.y != 0 else 2)
	var lower: Vector3i = cell if (d.x + d.y + d.z) > 0 else cell + d
	var li: int = _index(lower)
	if li >= 0 and blocked[axis][li] == 1:
		return SOLID
	return node_at(cell + d)


## Breadth-first over unvisited cells through unblocked faces, labelling them `node`.
## Returns the number of cells labelled.
func _fill(seeds: PackedInt32Array, node: int, blocked: Array[PackedByteArray]) -> int:
	var sx: int = _size.y * _size.z
	var sy: int = _size.z
	var queue: PackedInt32Array = PackedInt32Array()
	for i: int in seeds:
		if _labels[i] != UNVISITED:
			continue
		_labels[i] = node
		queue.append(i)
	var bx: PackedByteArray = blocked[0]
	var by: PackedByteArray = blocked[1]
	var bz: PackedByteArray = blocked[2]
	var head: int = 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		var x: int = i / sx
		var y: int = (i % sx) / sy
		var z: int = i % sy
		if x + 1 < _size.x and bx[i] == 0 and _labels[i + sx] == UNVISITED:
			_labels[i + sx] = node
			queue.append(i + sx)
		if x > 0 and bx[i - sx] == 0 and _labels[i - sx] == UNVISITED:
			_labels[i - sx] = node
			queue.append(i - sx)
		if y + 1 < _size.y and by[i] == 0 and _labels[i + sy] == UNVISITED:
			_labels[i + sy] = node
			queue.append(i + sy)
		if y > 0 and by[i - sy] == 0 and _labels[i - sy] == UNVISITED:
			_labels[i - sy] = node
			queue.append(i - sy)
		if z + 1 < _size.z and bz[i] == 0 and _labels[i + 1] == UNVISITED:
			_labels[i + 1] = node
			queue.append(i + 1)
		if z > 0 and bz[i - 1] == 0 and _labels[i - 1] == UNVISITED:
			_labels[i - 1] = node
			queue.append(i - 1)
	return queue.size()


# ---------------------------------------------------------------- queries

## The node an air cell belongs to: EXTERIOR outside or on the border of the region,
## a volume id inside, SOLID for a cell a solid piece occupies or earth (M6 claim 6).
func node_at(cell: Vector3i) -> int:
	_fresh()
	var i: int = _index(cell)
	if i < 0:
		return SOLID if _build.is_solid(cell) else EXTERIOR
	return _labels[i]


## Whether an air cell lies inside an enclosed volume: the latch side of an opening (M6
## claim 3).
func is_inside(cell: Vector3i) -> bool:
	return node_at(cell) > EXTERIOR


func node_ids() -> Array[int]:
	_fresh()
	var out: Array[int] = [EXTERIOR]
	var keys: Array = _nodes.keys()
	keys.sort()
	for k: Variant in keys:
		var id: int = k
		out.append(id)
	return out


func volume_count() -> int:
	_fresh()
	return _nodes.size()


func cells_in(node: int) -> int:
	_fresh()
	if node == EXTERIOR:
		return -1
	if not _nodes.has(node):
		return 0
	var rec: Dictionary = _nodes[node]
	return rec["cells"]


func edge_count() -> int:
	_fresh()
	return _edges.size()


## Edges touching a node, as [piece, other node] pairs in piece order.
func edges_of(node: int) -> Array[Array]:
	_fresh()
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
	_fresh()
	return _targets.duplicate()


func rebuild_count() -> int:
	return _rebuilds


## The cost of crossing a piece for a tool class: a stair's or a ladder's climb ticks
## (it is climbed, not breached: M6 claim 2), an opening's open_cost, else the breach
## cost from the resolver and the tool. -1 for an unknown piece or tool.
func edge_cost(piece: int, tool_class: StringName) -> int:
	if not _build.has_piece(piece) or not _content.has(BuildSystem.KIND_TOOL, tool_class):
		return -1
	var climb: int = _build.climb_ticks_of(piece)
	if climb > 0:
		return climb
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


## The move an edge's piece asks of whoever crosses it (the design doc §6.4 capability
## tags, M6 claim 2): `climb` for a stair or a ladder, "" for an opening or a breach.
## Mantles and jumps cross open air inside one volume, so no edge asks for them.
func edge_move(piece: int) -> StringName:
	if _build.climb_ticks_of(piece) > 0:
		return MovementSystem.MOVE_CLIMB
	return &""


## Cheapest path between two nodes for a tool class: {"cost": int, "pieces": Array[int]
## in crossing order, "nodes": Array[int]}. cost -1 when unreachable. Uniform-cost
## search (A* with a zero heuristic: nodes have no metric); ties resolve to the lower
## piece id, so the result is deterministic.
func cheapest_path(from: int, to: int, tool_class: StringName) -> Dictionary:
	_fresh()
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
	_fresh()
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
