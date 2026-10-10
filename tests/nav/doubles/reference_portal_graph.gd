## Test double: the portal graph's flood fill as it was before claim 7 (string-keyed,
## one call per cell into the build system), kept as the oracle the packed-grid rebuild
## must match exactly: same volumes, numbering, edges and targets for any build state.
class_name ReferencePortalGraphDouble extends RefCounted

const EXTERIOR: int = 0
const SOLID: int = -1
const NEIGHBOURS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

var _build: BuildSystem
var _node_of_cell: Dictionary = {}


func _init(build: BuildSystem) -> void:
	_build = build


## {"nodes", "edges", "targets"} exactly as PortalGraph.snapshot() shapes them.
func snapshot() -> Dictionary:
	_node_of_cell = {}
	var nodes: Dictionary = {}
	var edges: Array[Dictionary] = []
	var targets: Dictionary = {}
	var ids: Array[int] = _build.piece_ids()
	if ids.is_empty():
		return {"nodes": nodes, "edges": [], "targets": targets}
	var lo: Vector3i = _build.cell_of_piece(ids[0])
	var hi: Vector3i = lo
	var faces: Dictionary = {}
	for id: int in ids:
		var rec: Dictionary = _build.piece(id)
		var face: String = rec["face"]
		for c: Vector3i in _build.cells_of_piece(id):
			lo = Vector3i(mini(lo.x, c.x), mini(lo.y, c.y), mini(lo.z, c.z))
			hi = Vector3i(maxi(hi.x, c.x), maxi(hi.y, c.y), maxi(hi.z, c.z))
		if not face.is_empty():
			faces[face] = id
	for c: Vector3i in _build.excavated_cells():
		lo = Vector3i(mini(lo.x, c.x), mini(lo.y, c.y), mini(lo.z, c.z))
		hi = Vector3i(maxi(hi.x, c.x), maxi(hi.y, c.y), maxi(hi.z, c.z))
	lo -= Vector3i.ONE
	hi += Vector3i.ONE
	lo.y = maxi(lo.y, BuildSystem.MIN_STOREY)
	var visited: Dictionary = {}
	var border: Array[Vector3i] = []
	for x: int in range(lo.x, hi.x + 1):
		for y: int in range(lo.y, hi.y + 1):
			for z: int in range(lo.z, hi.z + 1):
				var c: Vector3i = Vector3i(x, y, z)
				var on_border: bool = x == lo.x or x == hi.x or y == hi.y or z == lo.z or z == hi.z
				if on_border and not _build.is_solid(c):
					border.append(c)
	_fill(border, EXTERIOR, lo, hi, faces, visited)
	var next_node: int = 1
	for x: int in range(lo.x, hi.x + 1):
		for y: int in range(lo.y, hi.y + 1):
			for z: int in range(lo.z, hi.z + 1):
				var c: Vector3i = Vector3i(x, y, z)
				if visited.has(BuildSystem.cell_key(c)) or _build.is_solid(c):
					continue
				var count: int = _fill([c] as Array[Vector3i], next_node, lo, hi, faces, visited)
				nodes[next_node] = {"cells": count, "min": [c.x, c.y, c.z] as Array[int]}
				next_node += 1
	for id: int in ids:
		var rec: Dictionary = _build.piece(id)
		var face: String = rec["face"]
		if not face.is_empty():
			var cells: Array[Vector3i] = BuildSystem.face_cells(face)
			var a: int = _node_at(cells[0])
			var b: int = _node_at(cells[1])
			if a != SOLID and b != SOLID and a != b:
				edges.append({"piece": id, "a": mini(a, b), "b": maxi(a, b)})
		else:
			var c: Vector3i = _build.cell_of_piece(id)
			for pair: Array in [[Vector3i(1, 0, 0), Vector3i(-1, 0, 0)], [Vector3i(0, 1, 0), Vector3i(0, -1, 0)], [Vector3i(0, 0, 1), Vector3i(0, 0, -1)]]:
				var d1: Vector3i = pair[0]
				var d2: Vector3i = pair[1]
				var a: int = _open_neighbour(c, d1, faces)
				var b: int = _open_neighbour(c, d2, faces)
				if a != SOLID and b != SOLID and a != b:
					edges.append({"piece": id, "a": mini(a, b), "b": maxi(a, b)})
			var k: Dictionary = _build.kind_data(id)
			var is_target: bool = k["target"]
			if is_target:
				var best: int = SOLID
				for d: Vector3i in NEIGHBOURS:
					var n: int = _open_neighbour(c, d, faces)
					if n != SOLID and (best == SOLID or n < best):
						best = n
				targets[id] = best
	edges.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
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
	var out_edges: Array = []
	for e: Dictionary in edges:
		out_edges.append([e["piece"], e["a"], e["b"]] as Array[int])
	return {"nodes": nodes, "edges": out_edges, "targets": targets}


func _node_at(cell: Vector3i) -> int:
	if _build.is_solid(cell):
		return SOLID
	var v: Variant = _node_of_cell.get(BuildSystem.cell_key(cell))
	if typeof(v) != TYPE_INT:
		return EXTERIOR
	var node: int = v
	return node


func _open_neighbour(cell: Vector3i, d: Vector3i, faces: Dictionary) -> int:
	var face: String = BuildSystem.face_key(cell, _facing_of(d))
	if faces.has(face) or _build.is_uncut_ground(face):
		return SOLID
	return _node_at(cell + d)


func _fill(seeds: Array[Vector3i], node: int, lo: Vector3i, hi: Vector3i, faces: Dictionary, visited: Dictionary) -> int:
	var queue: Array[Vector3i] = []
	for s: Vector3i in seeds:
		var key: String = BuildSystem.cell_key(s)
		if visited.has(key) or _build.is_solid(s):
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
			if visited.has(key) or _build.is_solid(n):
				continue
			var face: String = BuildSystem.face_key(c, _facing_of(d))
			if faces.has(face) or _build.is_uncut_ground(face):
				continue
			visited[key] = true
			_node_of_cell[key] = node
			queue.append(n)
	return queue.size()


static func _facing_of(d: Vector3i) -> String:
	if d.x != 0:
		return "px" if d.x > 0 else "nx"
	if d.y != 0:
		return "py" if d.y > 0 else "ny"
	return "pz" if d.z > 0 else "nz"
