extends GcityTest

## M3 spec claims 5–8: flood fill partitions the build cells into volumes, every wall
## is an edge with a cost, cheapest paths are deterministic and obey the metamorphic
## relations, and the raid plan goes for the most valuable reachable target.

const SEED: int = 20261002
const PROPERTY_CASES: int = 10_000
const SEED_PARTITION: int = 20261003
const SEED_METAMORPHIC: int = 20261004
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)
const CUTTER: StringName = &"cutter"
const WALL_COST: int = 400 + 700

var _sim: SimRoot
var _build: BuildSystem
var _portals: PortalGraph
var _stats: StatResolver
var _player: int = 0


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_build = SimAssembly.build_of(_sim)
	_portals = SimAssembly.portals_of(_sim)
	_stats = SimAssembly.stats_of(_sim)
	_player = SimAssembly.actors_of(_sim).spawn(&"arcade", 0)


func _at(cx: int, cy: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, cy * M + 500, cz * M + 500)


func _cell(cx: int, cy: int, cz: int) -> Vector3i:
	return BuildSystem.cell_of(_at(cx, cy, cz))


func _place(template: StringName, cx: int, cy: int, cz: int, facing: String) -> int:
	var id: int = _build.place(_player, template, _at(cx, cy, cz), facing)
	assert_true(id > 0, "place %s at (%d, %d, %d) %s" % [template, cx, cy, cz, facing])
	return id


## A 3×3 room on nine foundations, walled and roofed, with one door on the south
## side. Returns {"door": id, "walls": Array[int], "roof": Array[int]}.
func _room() -> Dictionary:
	for x: int in 3:
		for z: int in 3:
			_place(&"foundation_block", x, 0, z, "")
	var walls: Array[int] = []
	var door: int = 0
	for i: int in 3:
		walls.append(_place(&"wall_panel", 0, 1, i, "nx"))
		walls.append(_place(&"wall_panel", 2, 1, i, "px"))
		walls.append(_place(&"wall_panel", i, 1, 2, "pz"))
		if i == 1:
			door = _place(&"door_frame", i, 1, 0, "nz")
		else:
			walls.append(_place(&"wall_panel", i, 1, 0, "nz"))
	var roof: Array[int] = []
	for x: int in 3:
		for z: int in 3:
			roof.append(_place(&"floor_panel", x, 1, z, "py"))
	return {"door": door, "walls": walls, "roof": roof}


# ---------------------------------------------------------------- flood fill

func test_empty_build_has_only_the_exterior() -> void:
	_setup()
	assert_eq(_portals.node_ids(), [PortalGraph.EXTERIOR] as Array[int], "exterior only")
	assert_eq(_portals.node_at(_cell(0, 1, 0)), PortalGraph.EXTERIOR, "any air cell is exterior")
	assert_eq(_portals.node_at(_cell(0, -1, 0)), PortalGraph.SOLID, "below ground is solid")
	assert_eq(_portals.edge_count(), 0, "no edges")


func test_a_walled_room_is_one_volume_with_a_door_and_walls_as_edges() -> void:
	_setup()
	var r: Dictionary = _room()
	assert_eq(_portals.volume_count(), 1, "one enclosed volume")
	assert_eq(_portals.cells_in(1), 9, "nine cells")
	for x: int in 3:
		for z: int in 3:
			assert_eq(_portals.node_at(_cell(x, 1, z)), 1, "room cell (%d, %d) is volume 1" % [x, z])
	assert_eq(_portals.node_at(_cell(1, 2, 1)), PortalGraph.EXTERIOR, "above the roof is outside")
	assert_eq(_portals.node_at(_cell(1, 0, 1)), PortalGraph.SOLID, "a foundation cell is solid")
	assert_eq(_portals.edge_count(), 21, "11 walls + 1 door + 9 roof panels")
	assert_eq(_portals.edges_of(1).size(), 21, "all of them touch the room")
	var door: int = r["door"]
	assert_eq(_portals.edge_cost(door, CUTTER), 40, "door costs its open_cost")
	var wall: int = r["walls"][0]
	assert_eq(_portals.edge_cost(wall, CUTTER), WALL_COST, "wall costs hp × 1 + noise × 1")
	assert_eq(_portals.edge_cost(wall, &"spoon"), -1, "unknown tool")
	assert_eq(_portals.rebuild_count(), 9 + 12 + 9, "one rebuild per change")


func test_cheapest_path_takes_the_door_and_is_deterministic() -> void:
	_setup()
	var r: Dictionary = _room()
	var path: Dictionary = _portals.cheapest_path(PortalGraph.EXTERIOR, 1, CUTTER)
	assert_eq(path["cost"], 40, "through the door")
	assert_eq(path["pieces"], [r["door"]] as Array[int], "one crossing")
	assert_eq(path["nodes"], [0, 1] as Array[int], "outside then in")
	assert_eq(_portals.cheapest_path(1, PortalGraph.EXTERIOR, CUTTER)["cost"], 40, "symmetric")
	assert_eq(_portals.cheapest_path(PortalGraph.EXTERIOR, 7, CUTTER)["cost"], -1, "unknown node")
	assert_eq(_portals.cheapest_path(PortalGraph.EXTERIOR, 1, &"spoon")["cost"], -1, "unknown tool")
	var a: String = StateHash.of(_portals.snapshot())
	_portals.rebuild()
	assert_eq(StateHash.of(_portals.snapshot()), a, "rebuilding gives the identical graph")


func test_sealed_bunker_is_not_unraidable_only_expensive() -> void:
	_setup()
	var r: Dictionary = _room()
	var door: int = r["door"]
	assert_eq(_build.breach(door), [door] as Array[int], "door breached")
	assert_eq(_portals.volume_count(), 0, "an open doorway makes the room part of the exterior")
	assert_eq(_portals.node_at(_cell(1, 1, 1)), PortalGraph.EXTERIOR, "the room cells are outside now")
	_place(&"wall_panel", 1, 1, 0, "nz")
	var sealed: Dictionary = _portals.cheapest_path(PortalGraph.EXTERIOR, 1, CUTTER)
	assert_eq(sealed["cost"], WALL_COST, "sealed: through the cheapest wall")
	var sealed_pieces: Array[int] = sealed["pieces"]
	assert_eq(sealed_pieces.size(), 1, "one breach")
	var lowest: int = sealed_pieces[0]
	for e: Array in _portals.edges_of(1):
		var piece: int = e[0]
		assert_true(piece >= lowest or _portals.edge_cost(piece, CUTTER) > WALL_COST, "ties resolve to the lowest piece id")


# ---------------------------------------------------------------- metamorphic

func test_metamorphic_relations_on_the_room() -> void:
	_setup()
	var r: Dictionary = _room()
	var before: int = _portals.cheapest_path(PortalGraph.EXTERIOR, 1, CUTTER)["cost"]
	var wall: int = r["walls"][3]
	_stats.add_modifier(wall, {"stat": BuildSystem.STAT_HP, "class": StatResolver.CLASS_ADD, "value": 5000, "source": &"test.reinforce"})
	var raised: int = _portals.cheapest_path(PortalGraph.EXTERIOR, 1, CUTTER)["cost"]
	assert_true(raised >= before, "raising a wall's HP never lowers the path cost")
	assert_eq(_portals.edge_cost(wall, CUTTER), WALL_COST + 5000, "the wall itself got dearer through the resolver")
	var door: int = r["door"]
	_build.breach(door)
	_place(&"wall_panel", 1, 1, 0, "nz")
	var sealed: int = _portals.cheapest_path(PortalGraph.EXTERIOR, 1, CUTTER)["cost"]
	assert_true(sealed >= before, "removing the cheapest edge never lowers the cost")
	var walls: Array[int] = r["walls"]
	_build.breach(walls[0])
	_place(&"door_frame", 0, 1, 0, "nx")
	var with_door: int = _portals.cheapest_path(PortalGraph.EXTERIOR, 1, CUTTER)["cost"]
	assert_true(with_door <= sealed, "adding a door never raises the cost")


## Random rooms with random openings and reinforcements: after every mutation the
## three relations hold against the cost before it.
func test_property_metamorphic_relations_over_random_structures() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_METAMORPHIC
	_setup()
	_room()
	var violations: int = 0
	var checked: int = 0
	for case: int in PROPERTY_CASES:
		var before: int = _portals.cheapest_path(PortalGraph.EXTERIOR, 1, CUTTER)["cost"]
		if before < 0:
			break
		var edges: Array[Array] = _portals.edges_of(1)
		var e: Array = edges[rng.randi_range(0, edges.size() - 1)]
		var piece: int = e[0]
		var kind: Dictionary = _build.kind_data(piece)
		var passable: bool = kind["passable"]
		var op: int = rng.randi_range(0, 2)
		var after: int = -2
		var relation: String = ""
		if op == 0 and not passable:
			_stats.add_modifier(piece, {"stat": BuildSystem.STAT_HP, "class": StatResolver.CLASS_ADD, "value": rng.randi_range(1, 2000), "source": &"test.reinforce"})
			after = _portals.cheapest_path(PortalGraph.EXTERIOR, 1, CUTTER)["cost"]
			relation = "raise hp"
			if after < before:
				violations += 1
		elif op == 1 and not passable and _build.kind_of(piece) == &"wall":
			# replace a wall by a door in the same face
			var rec: Dictionary = _build.piece(piece)
			var face: String = rec["face"]
			var cells: Array[Vector3i] = BuildSystem.face_cells(face)
			var facing: String = "p" + face.split("|")[1]
			_build.breach(piece)
			var door: int = _build.place(_player, &"door_frame", BuildSystem.cell_centre(cells[0]), facing)
			if door > 0:
				after = _portals.cheapest_path(PortalGraph.EXTERIOR, 1, CUTTER)["cost"]
				relation = "add door"
				if after > before:
					violations += 1
		elif op == 2 and passable:
			# swap a door back to a wall
			var rec: Dictionary = _build.piece(piece)
			var face: String = rec["face"]
			var cells: Array[Vector3i] = BuildSystem.face_cells(face)
			var facing: String = "p" + face.split("|")[1]
			_build.breach(piece)
			var wall: int = _build.place(_player, &"wall_panel", BuildSystem.cell_centre(cells[0]), facing)
			if wall > 0:
				after = _portals.cheapest_path(PortalGraph.EXTERIOR, 1, CUTTER)["cost"]
				relation = "remove opening"
				if after < before:
					violations += 1
		if not relation.is_empty():
			checked += 1
			if violations > 0 and violations <= 3 and after != -2:
				fail("case %d (%s): cost %d -> %d" % [case, relation, before, after])
	assert_eq(violations, 0, "relations held over %d checked mutations" % checked)
	assert_true(checked > 2000, "enough mutations were applicable (%d)" % checked)


# ---------------------------------------------------------------- raid plan

func test_raid_plan_goes_for_the_most_valuable_reachable_target() -> void:
	_setup()
	var r: Dictionary = _room()
	assert_eq(_portals.raid_plan(CUTTER)["target"], EntityIds.NONE, "nothing to raid yet")
	var crate: int = _place(&"storage_crate", 1, 1, 1, "")
	assert_eq(_portals.targets(), {crate: 1}, "the crate opens into the room")
	var plan: Dictionary = _portals.raid_plan(CUTTER)
	assert_eq(plan["target"], crate, "target")
	assert_eq(plan["value"], 1000, "value from content")
	assert_eq(plan["cost"], 40, "through the door")
	assert_eq(plan["pieces"], [r["door"]] as Array[int], "the plan is the door")
	_place(&"foundation_block", 5, 0, 5, "")
	var outside_crate: int = _place(&"storage_crate", 5, 1, 5, "")
	assert_true(outside_crate > 0, "a crate on a foundation outside")
	var plan2: Dictionary = _portals.raid_plan(CUTTER)
	assert_eq(plan2["target"], outside_crate, "equal value: the cheaper (free) one wins")
	assert_eq(plan2["cost"], 0, "it is already outside")


# ---------------------------------------------------------------- partition property

## Random build sequences: the labelling is a partition consistent with the faces
## (adjacent air cells with no face piece between them share a node), every edge joins
## two distinct existing nodes, every volume has an edge or is sealed, and rebuilding
## twice gives the same graph.
func test_property_flood_fill_partitions_consistently() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PARTITION
	_setup()
	_room()  # start enclosed, then let the random walk break, seal and extend it
	var db: ContentDb = _sim.get_system(&"content")
	var templates: Array[StringName] = db.ids(&"build_piece")
	var facings: Array[String] = ["", "px", "nx", "py", "ny", "pz", "nz"]
	var failures: int = 0
	var sealed_seen: int = 0
	var volumes_seen: int = 0
	for case: int in PROPERTY_CASES:
		if rng.randi_range(0, 3) > 0 or _build.piece_ids().is_empty():
			var t: StringName = &"foundation_block" if rng.randi_range(0, 9) < 3 else templates[rng.randi_range(0, templates.size() - 1)]
			var cy: int = [0, 0, 1, 1, 1, 2][rng.randi_range(0, 5)]
			var facing: String = facings[rng.randi_range(0, facings.size() - 1)]
			if t == &"foundation_block" or t == &"storage_crate":
				facing = ""
			_build.place(_player, t, _at(rng.randi_range(0, 4), cy, rng.randi_range(0, 4)), facing)
		else:
			var ids: Array[int] = _build.piece_ids()
			_build.remove(_player, ids[rng.randi_range(0, ids.size() - 1)])
		var problem: String = _check_partition()
		volumes_seen += _portals.volume_count()
		for node: int in _portals.node_ids():
			if node != PortalGraph.EXTERIOR and _portals.edges_of(node).is_empty():
				sealed_seen += 1
		if not problem.is_empty():
			failures += 1
			if failures <= 3:
				fail("case %d: %s" % [case, problem])
	assert_eq(failures, 0, "partition invariants held (%d volumes seen, %d sealed)" % [volumes_seen, sealed_seen])
	assert_true(volumes_seen > 0, "the sequence produced enclosed volumes")


func _check_partition() -> String:
	var ids: Array[int] = _build.piece_ids()
	if ids.is_empty():
		return "" if _portals.volume_count() == 0 else "volumes without pieces"
	var faces: Dictionary = {}
	var lo: Vector3i = _build.cell_of_piece(ids[0])
	var hi: Vector3i = lo
	for id: int in ids:
		var rec: Dictionary = _build.piece(id)
		var face: String = rec["face"]
		if not face.is_empty():
			faces[face] = id
		for c: Vector3i in _build.cells_of_piece(id):
			lo = Vector3i(mini(lo.x, c.x), mini(lo.y, c.y), mini(lo.z, c.z))
			hi = Vector3i(maxi(hi.x, c.x), maxi(hi.y, c.y), maxi(hi.z, c.z))
	lo -= Vector3i.ONE
	hi += Vector3i.ONE
	lo.y = maxi(lo.y, 0)
	var counts: Dictionary = {}
	for x: int in range(lo.x, hi.x + 1):
		for y: int in range(lo.y, hi.y + 1):
			for z: int in range(lo.z, hi.z + 1):
				var c: Vector3i = Vector3i(x, y, z)
				var n: int = _portals.node_at(c)
				if n == PortalGraph.SOLID:
					if _build.cell_piece_at(c) == EntityIds.NONE:
						return "air cell %s labelled solid" % c
					continue
				if n != PortalGraph.EXTERIOR and not _portals.node_ids().has(n):
					return "cell %s labelled with unknown node %d" % [c, n]
				var seen: int = counts.get(n, 0)
				counts[n] = seen + 1
				for d: Vector3i in [Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1)]:
					var m: Vector3i = c + d
					if m.x > hi.x or m.y > hi.y or m.z > hi.z:
						continue
					var nm: int = _portals.node_at(m)
					if nm == PortalGraph.SOLID:
						continue
					var facing: String = "px" if d.x == 1 else ("py" if d.y == 1 else "pz")
					if not faces.has(BuildSystem.face_key(c, facing)) and nm != n:
						return "open face between %s (node %d) and %s (node %d)" % [c, n, m, nm]
	for node: int in _portals.node_ids():
		if node == PortalGraph.EXTERIOR:
			continue
		var labelled: int = counts.get(node, 0)
		if labelled != _portals.cells_in(node):
			return "node %d claims %d cells, %d labelled" % [node, _portals.cells_in(node), labelled]
		for e: Array in _portals.edges_of(node):
			var other: int = e[1]
			if other == node or (other != PortalGraph.EXTERIOR and not _portals.node_ids().has(other)):
				return "edge from %d to bad node %d" % [node, other]
			var through: int = e[0]
			if not _build.has_piece(through):
				return "edge through a missing piece"
	var a: String = StateHash.of(_portals.snapshot())
	_portals.rebuild()
	var b: String = StateHash.of(_portals.snapshot())
	if a != b:
		return "rebuild is not deterministic"
	return ""


# ---------------------------------------------------------------- restore

func test_restore_rebuilds_and_verifies() -> void:
	_setup()
	_room()
	_place(&"storage_crate", 1, 1, 1, "")
	var full: Dictionary = _sim.snapshot()
	var db := ContentDb.new()
	ContentLoader.load_all(db)
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(other, full), OK, "restore")
	var restored: PortalGraph = SimAssembly.portals_of(other)
	assert_eq(StateHash.of(restored.snapshot()), StateHash.of(_portals.snapshot()), "identical graph")
	assert_eq(restored.raid_plan(CUTTER)["cost"], 40, "plan works on the restored graph")
	var bad: Dictionary = _portals.snapshot().duplicate(true)
	var edges: Array = bad["edges"]
	edges.pop_back()
	assert_eq(restored.restore(bad), ERR_INVALID_DATA, "a saved graph that the pieces do not produce is rejected")
