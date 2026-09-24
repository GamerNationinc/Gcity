## Settlement kits (M7 spec claim 6): a town is a prefab subgraph, not noise.
##
## A `content/settlement/` entry is a small graph of streets and yards, positioned
## relative to the settlement node that anchors it, with sockets where the outside road
## arrives and a district so its rights tables already exist (design doc §7.2). The
## world picks a kit, a quarter turn and which optional blocks got built; the town then
## snaps onto the route graph as a subgraph, with its own navigation already in it.
##
## This is the point where the world stops being a function of the seed alone and
## becomes a function of the seed *and* the kits. That is stated rather than hidden:
## [RouteGraph.generate] takes the kits as an argument, so it still reads nothing and
## the same pair always builds the same world. Adding a kit changes worlds, and the
## fixture hashes are re-recorded, which is what any content change already costs
## (`docs/extending-missions.md`).
##
## Nothing here places anything. It turns content into plain data the graph can splice,
## and it refuses content that would build a town the graph could not keep its promises
## about — a block joined to nothing, a road too narrow to walk, a kit so wide two towns
## would interleave.
class_name SettlementKits extends RefCounted

const KIND: StringName = &"settlement"
## How far a kit may reach from the node that anchors it. Half the spacing between
## world nodes, so two towns can abut but their streets can never interleave.
const MAX_REACH_MM: int = RouteGraph.MIN_SPACING_MM / 2


## Every kit as plain data, in id order: what the graph splices.
##
## Plain data rather than the content entries themselves, because the graph is handed
## its kits and holds them across a restore; it may not keep a reference to something
## that could be reloaded underneath it.
static func prepared(content: ContentDb) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in content.ids(KIND):
		out.append(_prepare(id, content.get_entry(KIND, id)))
	return out


static func _prepare(id: StringName, entry: Dictionary) -> Dictionary:
	var district: String = entry["district"]
	var min_blocks: int = entry["min_blocks"]
	var max_blocks: int = entry["max_blocks"]
	var nodes: Array = []
	var blocks: Dictionary = {}
	for v: Variant in entry["nodes"]:
		var rec: Dictionary = v
		var rel: Array = rec["rel"]
		var x: int = rel[0]
		var z: int = rel[1]
		var kind: String = rec["kind"]
		var block: String = rec["block"]
		if not block.is_empty():
			blocks[block] = true
		nodes.append({"x": x, "z": z, "kind": StringName(kind), "block": block})
	var edges: Array = []
	for v: Variant in entry["edges"]:
		var rec: Dictionary = v
		var a: int = rec["a"]
		var b: int = rec["b"]
		var width: int = rec["width"]
		edges.append({"a": a, "b": b, "width": width})
	var sockets: Array = []
	for v: Variant in entry["sockets"]:
		var rec: Dictionary = v
		var node: int = rec["node"]
		var width: int = rec["width"]
		sockets.append({"node": node, "width": width})
	var names: Array = blocks.keys()
	names.sort()
	return {
		"id": id,
		"district": StringName(district),
		"min_blocks": min_blocks,
		"max_blocks": max_blocks,
		"nodes": nodes,
		"edges": edges,
		"sockets": sockets,
		"blocks": names,
	}


## Every kit builds a town the graph can keep its promises about. Checked at assembly,
## because a kit that fails any of these produces a world that is wrong rather than
## ugly, and "connectivity is true by construction" has to survive splicing.
static func validate(content: ContentDb) -> Error:
	for kit: Dictionary in prepared(content):
		var err: Error = _check(kit)
		if err != OK:
			return err
	return OK


static func _check(kit: Dictionary) -> Error:
	var id: StringName = kit["id"]
	var nodes: Array = kit["nodes"]
	var blocks: Array = kit["blocks"]
	var min_blocks: int = kit["min_blocks"]
	var max_blocks: int = kit["max_blocks"]
	if min_blocks > max_blocks:
		return _fail("settlement/%s wants between %d and %d blocks" % [id, min_blocks, max_blocks])
	if max_blocks > blocks.size():
		return _fail("settlement/%s wants up to %d blocks and has %d" % [id, max_blocks, blocks.size()])
	for i: int in nodes.size():
		var rec: Dictionary = nodes[i]
		var kind: StringName = rec["kind"]
		if kind == RouteGraph.KIND_GATE or kind == RouteGraph.KIND_SETTLEMENT:
			# a town inside a town would raise a town inside that one
			return _fail("settlement/%s puts a %s in a town" % [id, kind])
		var x: int = rec["x"]
		var z: int = rec["z"]
		if RouteGraph._length_mm(0, 0, x, z) > MAX_REACH_MM:
			return _fail("settlement/%s reaches %d mm from its road, past %d" % [
				id, RouteGraph._length_mm(0, 0, x, z), MAX_REACH_MM])
	for v: Variant in kit["edges"]:
		var rec: Dictionary = v
		var a: int = rec["a"]
		var b: int = rec["b"]
		if a >= nodes.size() or b >= nodes.size():
			return _fail("settlement/%s joins %d to %d and has %d places" % [id, a, b, nodes.size()])
		if a == b:
			return _fail("settlement/%s joins place %d to itself" % [id, a])
	var sockets: Array = kit["sockets"]
	for v: Variant in sockets:
		var rec: Dictionary = v
		var node: int = rec["node"]
		if node >= nodes.size():
			return _fail("settlement/%s takes its road at %d and has %d places" % [id, node, nodes.size()])
		var at: Dictionary = nodes[node]
		var block: String = at["block"]
		if not block.is_empty():
			# the road has to arrive somewhere that is always built
			return _fail("settlement/%s takes its road at a place in block '%s'" % [id, block])
	# the part that is always built has to hold together on its own, and every optional
	# block has to reach it: a block joined only to another optional block would be cut
	# off whenever that one was not built, and the world would come apart
	if not _joined_up(kit, "", true):
		return _fail("settlement/%s does not hold together without its blocks" % id)
	for v: Variant in blocks:
		var block: String = v
		if not _joined_up(kit, block, false):
			return _fail("settlement/%s builds '%s' with no way in" % [id, block])
	return OK


## True when the always-built part plus `block` is one piece. With `core_only` the
## block is ignored and only the always-built part is walked.
static func _joined_up(kit: Dictionary, block: String, core_only: bool) -> bool:
	var nodes: Array = kit["nodes"]
	var present: Dictionary = {}
	for i: int in nodes.size():
		var rec: Dictionary = nodes[i]
		var at: String = rec["block"]
		if at.is_empty() or (not core_only and at == block):
			present[i] = true
	if present.is_empty():
		return false
	var at_node: Dictionary = {}
	for v: Variant in kit["edges"]:
		var rec: Dictionary = v
		var a: int = rec["a"]
		var b: int = rec["b"]
		if not present.has(a) or not present.has(b):
			continue
		var from_a: Array = at_node.get(a, [])
		from_a.append(b)
		at_node[a] = from_a
		var from_b: Array = at_node.get(b, [])
		from_b.append(a)
		at_node[b] = from_b
	var start: int = present.keys()[0]
	var seen: Dictionary = {start: true}
	var queue: Array[int] = [start]
	var walked: int = 0
	while walked < queue.size():
		var node: int = queue[walked]
		walked += 1
		var next: Array = at_node.get(node, [])
		for v: Variant in next:
			var other: int = v
			if not seen.has(other):
				seen[other] = true
				queue.append(other)
	return seen.size() == present.size()


static func _fail(message: String) -> Error:
	push_error(message)
	return ERR_INVALID_DATA
