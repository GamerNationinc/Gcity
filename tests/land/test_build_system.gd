extends GcityTest

## M3 spec claims 1–4: pieces as content on the 1 m grid, canonical faces, placement
## needs build rights and support, removal collapses the unsupported.

const SEED: int = 20260930
const PROPERTY_CASES: int = 10_000
const SEED_SUPPORT: int = 20261001
const SEED_STACK: int = 20261002
const STACK_TOP: int = 7
const STACK_PIECES: int = 40
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)

var _sim: SimRoot
var _build: BuildSystem
var _land: LandSystem
var _actors: ActorSystem
var _player: int = 0
var _changes: Array[Dictionary] = []


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_build = SimAssembly.build_of(_sim)
	_land = SimAssembly.land_of(_sim)
	_actors = SimAssembly.actors_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	# the lambda captures a local array, not self: a callable holding the test would
	# make a reference cycle through the sim's event bus
	var sink: Array[Dictionary] = []
	_changes = sink
	var on_changed: Callable = func(payload: Dictionary) -> void:
		sink.append(payload)
	SimAssembly.combat_of(_sim).events().subscribe(BuildSystem.EVENT_CHANGED, on_changed)


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


func _at(cx: int, cy: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, cy * M + 500, cz * M + 500)


func _foundation(cx: int, cz: int) -> int:
	return _build.place(_player, &"foundation_block", _at(cx, 0, cz), "")


# ---------------------------------------------------------------- grid and faces

func test_cells_and_canonical_faces() -> void:
	assert_eq(BuildSystem.cell_of(Vector3i(1999, -1, 500)), Vector3i(1, -1, 0), "floor division into cells")
	assert_eq(BuildSystem.cell_centre(Vector3i(2, 0, -1)), Vector3i(2500, 500, -500), "cell centre")
	assert_eq(BuildSystem.face_key(Vector3i(3, 0, 3), "px"), "3,0,3|x", "positive face is the cell itself")
	assert_eq(BuildSystem.face_key(Vector3i(3, 0, 3), "nx"), "2,0,3|x", "negative face is the lower neighbour's positive face")
	assert_eq(BuildSystem.face_key(Vector3i(4, 0, 3), "nx"), BuildSystem.face_key(Vector3i(3, 0, 3), "px"), "the same face from either side")
	assert_eq(BuildSystem.face_key(Vector3i(0, 0, 0), "ny"), "0,-1,0|y", "floor under a cell")
	assert_eq(BuildSystem.face_key(Vector3i(0, 0, 0), "sideways"), "", "unknown facing")
	assert_eq(BuildSystem.face_cells("2,0,3|x"), [Vector3i(2, 0, 3), Vector3i(3, 0, 3)] as Array[Vector3i], "a face separates two cells")


# ---------------------------------------------------------------- placement

func test_foundation_then_wall_then_door_are_supported_in_a_chain() -> void:
	_setup()
	var f: int = _foundation(0, 0)
	assert_true(f > 0, "foundation on the ground")
	assert_eq(_build.kind_of(f), &"foundation", "kind from content")
	assert_eq(SimAssembly.stats_of(_sim).resolve(f, &"piece_hp"), 400, "hp base from the material")
	var w: int = _build.place(_player, &"wall_panel", _at(0, 1, 0), "px")
	assert_true(w > 0, "wall on the foundation")
	var d: int = _build.place(_player, &"door_frame", _at(0, 1, 0), "pz")
	assert_true(d > 0, "door on the same cell, other face")
	assert_eq(_build.piece_ids(), [f, w, d] as Array[int], "three pieces")
	assert_eq(_changes.size(), 3, "three change events")
	assert_eq(_changes[1]["added"], [w] as Array[int], "event names the added piece")
	assert_eq(_build.place(_player, &"wall_panel", _at(1, 1, 0), "nx"), EntityIds.NONE, "the same face from the other side is occupied")
	assert_eq(_build.face_piece_at(BuildSystem.face_key(BuildSystem.cell_of(_at(0, 1, 0)), "px")), w, "face lookup finds the wall")


func test_placement_rejections() -> void:
	_setup()
	assert_eq(_build.place(_player, &"foundation_block", _at(0, 1, 0), ""), EntityIds.NONE, "foundation must be at ground level")
	assert_eq(_build.place(_player, &"foundation_block", _at(0, 0, 0), "px"), EntityIds.NONE, "cell pieces take no facing")
	assert_eq(_build.place(_player, &"wall_panel", _at(0, 0, 0), ""), EntityIds.NONE, "face pieces need a facing")
	assert_eq(_build.place(_player, &"wall_panel", _at(0, 0, 0), "py"), EntityIds.NONE, "walls are vertical")
	assert_eq(_build.place(_player, &"floor_panel", _at(0, 0, 0), "px"), EntityIds.NONE, "floors are horizontal")
	assert_eq(_build.place(_player, &"wall_panel", _at(0, 0, 0), "px"), EntityIds.NONE, "nothing supports a wall in the air")
	assert_eq(_build.place(99, &"foundation_block", _at(0, 0, 0), ""), EntityIds.NONE, "unknown actor")
	assert_eq(_build.place(_player, &"castle", _at(0, 0, 0), ""), EntityIds.NONE, "unknown template")
	var f: int = _foundation(0, 0)
	assert_eq(_build.place(_player, &"storage_crate", _at(0, 0, 0), ""), EntityIds.NONE, "cell occupied")
	assert_true(_build.place(_player, &"storage_crate", _at(0, 1, 0), "") > 0, "a crate on top is fine")
	assert_eq(_build.piece_ids().size(), 2, "two pieces")
	assert_true(f > 0, "foundation placed")


func test_building_needs_build_rights() -> void:
	_setup()
	var violations: int = _land.violation_count()
	var neighbour: Vector3i = Vector3i(13 * M, 500, 6 * M)  # inside neighbour_east, owned by an NPC
	assert_eq(_build.place(_player, &"foundation_block", neighbour, ""), EntityIds.NONE, "refused on the neighbour's land")
	assert_eq(_land.violation_count(), violations + 1, "one violation")
	assert_true(_do(LandSystem.COMMAND_IDENTIFY, {"actor": _player, "owner": "player"}), "identify")
	assert_true(_do(LandSystem.COMMAND_TRANSFER, {"parcel": "neighbour_east", "owner": "player"}), "buy it")
	var f: int = _build.place(_player, &"foundation_block", neighbour, "")
	assert_true(f > 0, "now allowed")
	var stranger: int = _actors.spawn(&"arcade", 0)
	assert_eq(_build.remove(stranger, f), [] as Array[int], "a stranger may not remove it")
	assert_eq(_land.violation_count(), violations + 2, "and that was a violation")


# ---------------------------------------------------------------- support

## M7.5 decision 4: the wall standing on the foundation is at its depth, 0, so a
## scrap-steel run reaches four hops beyond it (until M7.5 the first wall was a hop).
func test_span_limits_how_far_a_chain_reaches() -> void:
	_setup()
	_foundation(0, 0)
	var ids: Array[int] = []
	for i: int in 5:
		var w: int = _build.place(_player, &"wall_panel", _at(i, 1, 0), "pz")
		assert_true(w > 0, "wall %d within the span of four" % i)
		ids.append(w)
	assert_eq(_build.supported_set()[ids[0]], 0, "the wall on the foundation is at its depth")
	assert_eq(_build.supported_set()[ids[4]], 4, "each wall beside it a hop further")
	assert_eq(_build.place(_player, &"wall_panel", _at(5, 1, 0), "pz"), EntityIds.NONE, "the sixth is beyond scrap steel's span")
	var f2: int = _foundation(5, 0)
	assert_true(f2 > 0, "a second foundation")
	assert_true(_build.place(_player, &"wall_panel", _at(5, 1, 0), "pz") > 0, "now the sixth stands on it")


## M7.5 claim 5: a column is not an overhang. Concrete spans two, yet a wall six high
## stands on one foundation, and a wall stacked on the end of an overhang keeps the
## overhang's depth, so a three-cell wall can stand on a roof.
func test_support_by_column_limits_overhangs_not_height() -> void:
	_setup()
	var f: int = _foundation(0, 0)
	assert_true(f > 0, "foundation")
	var column: Array[int] = []
	for y: int in range(1, 7):
		var w: int = _build.place(_player, &"concrete_wall", _at(0, y, 0), "pz")
		assert_true(w > 0, "concrete wall %d high on the column" % y)
		column.append(w)
	assert_eq(_build.supported_set()[column[5]], 0, "the top of the column is at the foundation's depth")
	var out1: int = _build.place(_player, &"concrete_wall", _at(1, 1, 0), "pz")
	var out2: int = _build.place(_player, &"concrete_wall", _at(2, 1, 0), "pz")
	assert_true(out1 > 0 and out2 > 0, "two hops out is within concrete's span")
	assert_eq(_build.place(_player, &"concrete_wall", _at(3, 1, 0), "pz"), EntityIds.NONE, "the third hop out is beyond it")
	for y: int in range(2, 5):
		var w: int = _build.place(_player, &"concrete_wall", _at(2, y, 0), "pz")
		assert_true(w > 0, "a wall %d high on the end of the overhang" % y)
		assert_eq(_build.supported_set()[w], 2, "and it keeps the overhang's depth")
	var floor_on_wall: int = _build.place(_player, &"floor_panel", _at(2, 4, 0), "py")
	assert_true(floor_on_wall > 0, "a floor on the top of the wall")
	assert_eq(_build.supported_set()[floor_on_wall], 2, "rests on it at its depth")
	var crate_on_floor: int = _build.place(_player, &"storage_crate", _at(2, 5, 0), "")
	assert_true(crate_on_floor > 0, "a crate on the floor")
	assert_eq(_build.supported_set()[crate_on_floor], 2, "rests on the floor at its depth")


## A floor and a crate each rest on a wall along any of their four lower edges: on a
## wall standing on a foundation they are at depth 0, where touching the foundation or
## the wall would make them 1.
func test_a_floor_or_a_crate_rests_on_a_wall_along_any_edge() -> void:
	for facing: String in ["px", "nx", "pz", "nz"]:
		for top: StringName in [&"floor_panel", &"storage_crate"]:
			_setup()
			assert_true(_foundation(2, 2) > 0, "foundation")
			assert_true(_build.place(_player, &"wall_panel", _at(2, 1, 2), facing) > 0, "the wall along the %s edge" % facing)
			var piece: int = EntityIds.NONE
			if top == &"floor_panel":
				piece = _build.place(_player, top, _at(2, 1, 2), "py")
			else:
				piece = _build.place(_player, top, _at(2, 2, 2), "")
			assert_true(piece > 0, "a %s over that edge" % top)
			if piece > 0:
				assert_eq(_build.supported_set()[piece], 0, "rests on the wall along its %s edge (%s)" % [facing, top])


## Only resting on something is free: beside it, under it or at a corner is a hop.
func test_only_a_piece_directly_below_carries_at_no_cost() -> void:
	_setup()
	_foundation(0, 0)
	var on_top: int = _build.place(_player, &"storage_crate", _at(0, 1, 0), "")
	var beside: int = _build.place(_player, &"storage_crate", _at(1, 1, 0), "")
	var wall: int = _build.place(_player, &"wall_panel", _at(0, 2, 0), "pz")
	var hung: int = _build.place(_player, &"wall_panel", _at(1, 0, 0), "px")
	assert_true(on_top > 0 and beside > 0 and wall > 0 and hung > 0, "built")
	var depth: Dictionary = _build.supported_set()
	assert_eq(depth[on_top], 0, "a crate on the foundation rests on it")
	assert_eq(depth[beside], 1, "a crate beside that crate is a hop")
	assert_eq(depth[wall], 0, "a wall along the crate's top edge rests on it")
	assert_eq(depth[hung], 1, "a wall on bare ground beside the foundation is a hop")


func test_removing_a_foundation_collapses_what_it_held() -> void:
	_setup()
	var f: int = _foundation(0, 0)
	var w1: int = _build.place(_player, &"wall_panel", _at(0, 1, 0), "pz")
	var w2: int = _build.place(_player, &"wall_panel", _at(1, 1, 0), "pz")
	var f2: int = _foundation(3, 0)
	var w3: int = _build.place(_player, &"wall_panel", _at(3, 1, 0), "pz")
	assert_true(f > 0 and w1 > 0 and w2 > 0 and f2 > 0 and w3 > 0, "built")
	_changes.clear()
	var removed: Array[int] = _build.remove(_player, f)
	assert_eq(removed, [f, w1, w2] as Array[int], "the foundation and both walls it held")
	assert_eq(_build.piece_ids(), [f2, w3] as Array[int], "the other chain stands")
	assert_eq(_changes.size(), 1, "one change event for the collapse")
	assert_eq(_changes[0]["removed"], [f, w1, w2] as Array[int], "event lists everything that fell")
	assert_eq(SimAssembly.stats_of(_sim).resolve(w1, &"piece_hp"), 0, "fallen pieces are forgotten by the resolver")


func test_command_payload_contracts() -> void:
	_setup()
	assert_true(_do(BuildSystem.COMMAND_PLACE, {"actor": _player, "piece": "foundation_block", "x": FAR.x + 500, "y": 500, "z": FAR.z + 500, "facing": ""}), "place")
	var f: int = _build.piece_ids()[0]
	assert_false(_do(BuildSystem.COMMAND_PLACE, {"actor": _player, "piece": "wall_panel", "x": FAR.x + 500, "y": 1500, "z": FAR.z + 500}), "missing facing")
	assert_false(_do(BuildSystem.COMMAND_PLACE, {"actor": _player, "piece": "wall_panel", "x": FAR.x + 500, "y": 1500, "z": FAR.z + 500, "facing": 1}), "facing type")
	assert_false(_do(BuildSystem.COMMAND_PLACE, {"actor": _player, "piece": "wall_panel", "x": 1e12, "y": 1500, "z": FAR.z + 500, "facing": "px"}), "out of range")
	assert_true(_do(BuildSystem.COMMAND_PLACE, {"actor": _player, "piece": "wall_panel", "x": FAR.x + 500, "y": 1500, "z": FAR.z + 500, "facing": "px"}), "wall")
	assert_false(_do(BuildSystem.COMMAND_REMOVE, {"actor": _player, "piece_id": 999}), "unknown piece")
	assert_false(_do(BuildSystem.COMMAND_REMOVE, {"actor": _player, "piece_id": f, "x": 1}), "extra key")
	assert_true(_do(BuildSystem.COMMAND_REMOVE, {"actor": _player, "piece_id": f}), "remove collapses both")
	assert_eq(_build.piece_ids(), [] as Array[int], "empty")


# ---------------------------------------------------------------- property

## Random place/remove sequences on free land: after every step, every present piece
## is supported at exactly the depth an independent oracle gives it, no two pieces
## share a cell or face, and every id is unique.
func test_property_every_present_piece_is_supported_after_any_sequence() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_SUPPORT
	_setup()
	var db: ContentDb = _sim.get_system(&"content")
	var templates: Array[StringName] = db.ids(&"build_piece")
	var failures: int = 0
	var placed: int = 0
	var removed: int = 0
	for case: int in PROPERTY_CASES:
		if rng.randi_range(0, 3) > 0 or _build.piece_ids().is_empty():
			if _random_place(rng, templates) > 0:
				placed += 1
		else:
			var ids: Array[int] = _build.piece_ids()
			if not _build.remove(_player, ids[rng.randi_range(0, ids.size() - 1)]).is_empty():
				removed += 1
		var problem: String = _check_invariants(db)
		if not problem.is_empty():
			failures += 1
			if failures <= 3:
				fail("case %d: %s" % [case, problem])
	assert_eq(failures, 0, "invariants held over %d placements and %d removals" % [placed, removed])
	assert_true(placed > 500 and removed > 200, "the sequence exercised both operations (%d, %d)" % [placed, removed])


## M7.5 claim 5: random sequences as above, interleaved with stacking a piece directly
## on top of a standing one. A placement never unsupports a standing piece or makes it
## deeper, a stacked piece is never deeper than the piece it stands on, and every depth
## is the oracle's (these heaps are bigger than the first property's, so more of the
## routes through a resting piece are the shortest).
func test_property_stacking_a_column_never_unsupports_what_is_under_it() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_STACK
	_setup()
	var db: ContentDb = _sim.get_system(&"content")
	var templates: Array[StringName] = db.ids(&"build_piece")
	var failures: int = 0
	var stacked: int = 0
	var placed: int = 0
	var tallest: int = 0
	for case: int in PROPERTY_CASES:
		var ids: Array[int] = _build.piece_ids()
		var roll: int = rng.randi_range(0, 9)
		# past STACK_PIECES the next step is a removal: the property is about columns,
		# and a bigger heap only makes each case slower
		if (roll >= 8 or ids.size() >= STACK_PIECES) and not ids.is_empty():
			_build.remove(_player, ids[rng.randi_range(0, ids.size() - 1)])
			continue
		var before: Dictionary = _build.supported_set()
		var under: int = EntityIds.NONE
		var added: int = EntityIds.NONE
		if roll < 4 and not ids.is_empty():
			under = ids[rng.randi_range(0, ids.size() - 1)]
			# columns stop at STACK_TOP: taller adds pieces (and time), not cases
			if _build.cell_of_piece(under).y < STACK_TOP:
				added = _stack_on(under)
			if added > 0:
				stacked += 1
				tallest = maxi(tallest, _build.cell_of_piece(added).y)
		else:
			added = _random_place(rng, templates)
			if added > 0:
				placed += 1
		if added <= 0:
			continue
		var after: Dictionary = _build.supported_set()
		var problem: String = ""
		for id: int in before:
			if not after.has(id):
				problem = "placing %d unsupported %d" % [added, id]
			elif after[id] > before[id]:
				problem = "placing %d made %d deeper (%d to %d)" % [added, id, before[id], after[id]]
		if under != EntityIds.NONE and after[added] > before[under]:
			problem = "%d stacked on %d is deeper than it (%d over %d)" % [added, under, after[added], before[under]]
		if problem.is_empty():
			problem = _check_invariants(db)
		if not problem.is_empty():
			failures += 1
			if failures <= 3:
				fail("case %d: %s" % [case, problem])
	assert_eq(failures, 0, "no placement undermined a standing piece over %d stacks and %d placements" % [stacked, placed])
	assert_true(stacked > 1000, "the sequence stacked columns (%d)" % stacked)
	assert_true(tallest > 4, "and the columns grew taller than a two-hop span reaches sideways (%d)" % tallest)


## One random placement, biased towards buildable choices so a sequence grows real
## structures, with enough noise (air cells, wrong facings) to exercise every rejection.
func _random_place(rng: RandomNumberGenerator, templates: Array[StringName]) -> int:
	var facings: Array[String] = ["", "px", "nx", "py", "ny", "pz", "nz"]
	var t: StringName = &"foundation_block" if rng.randi_range(0, 9) < 3 else templates[rng.randi_range(0, templates.size() - 1)]
	var cy: int = [0, 0, 1, 1, 1, 2, 3][rng.randi_range(0, 6)]
	var pos: Vector3i = _at(rng.randi_range(0, 5), cy, rng.randi_range(0, 5))
	var facing: String = facings[rng.randi_range(0, facings.size() - 1)]
	if t == &"foundation_block" or t == &"storage_crate":
		facing = "" if rng.randi_range(0, 9) < 9 else facing
	return _build.place(_player, t, pos, facing)


## Places the same piece one cell above `under` (a crate above a foundation or a
## floor, which cannot take their own kind above). Returns the new id or NONE.
func _stack_on(under: int) -> int:
	var rec: Dictionary = _build.piece(under)
	var face: String = rec["face"]
	var above: Vector3i = BuildSystem.cell_centre(_build.cell_of_piece(under) + Vector3i(0, 1, 0))
	if face.is_empty() or face.ends_with("|y"):
		var t: StringName = _build.template_of(under)
		if face.ends_with("|y") or _build.kind_of(under) == &"foundation":
			t = &"storage_crate"
		return _build.place(_player, t, above, "")
	return _build.place(_player, _build.template_of(under), above, "p" + face.get_slice("|", 1))


func _check_invariants(db: ContentDb) -> String:
	var ids: Array[int] = _build.piece_ids()
	var occupied: Dictionary = {}
	var by_cell: Dictionary = {}
	for id: int in ids:
		var rec: Dictionary = _build.piece(id)
		var face: String = rec["face"]
		var key: String = face if not face.is_empty() else BuildSystem.cell_key(_build.cell_of_piece(id))
		if occupied.has(key):
			return "%s occupied twice" % key
		occupied[key] = id
		for c: Vector3i in _build.cells_of_piece(id):
			var ck: String = BuildSystem.cell_key(c)
			if not by_cell.has(ck):
				by_cell[ck] = [] as Array[int]
			var list: Array[int] = by_cell[ck]
			list.append(id)
	# oracle: label-correcting search from ground foundations over touching pieces,
	# bounded by span; a hop costs nothing where the piece rests on the one it came from,
	# judged by geometry (`_rests_on`), not by the system's slot list
	var boxes: Dictionary = {}
	for id: int in ids:
		boxes[id] = _box(id)
	var depth: Dictionary = {}
	var queue: Array[int] = []
	for id: int in ids:
		if _build.kind_of(id) == &"foundation" and _build.cell_of_piece(id).y == 0:
			depth[id] = 0
			queue.append(id)
	var head: int = 0
	while head < queue.size():
		var id: int = queue[head]
		head += 1
		var d: int = depth[id]
		var under: Array[int] = boxes[id]
		for c: Vector3i in _build.cells_of_piece(id):
			for offset: Vector3i in [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				var ck: String = BuildSystem.cell_key(c + offset)
				if not by_cell.has(ck):
					continue
				var list: Array[int] = by_cell[ck]
				for other: int in list:
					var over: Array[int] = boxes[other]
					var to: int = d + (0 if _rests_on(over, under) else 1)
					var m: Dictionary = db.get_entry(&"material", _build.material_of(other))
					var span: int = m["max_span"]
					if to > span:
						continue
					if depth.has(other):
						var known: int = depth[other]
						if known <= to:
							continue
					depth[other] = to
					queue.append(other)
	var sim_depth: Dictionary = _build.supported_set()
	for id: int in ids:
		if not depth.has(id):
			return "piece %d (%s) is present but unsupported" % [id, _build.template_of(id)]
		if not sim_depth.has(id) or sim_depth[id] != depth[id]:
			return "piece %d (%s): the system says depth %s, the oracle %d" % [id, _build.template_of(id), str(sim_depth.get(id)), depth[id]]
	if sim_depth.size() != ids.size():
		return "the supported set names %d pieces, %d are present" % [sim_depth.size(), ids.size()]
	return ""


## A piece's extent in cells, [x0, x1, y0, y1, z0, z1]; a face is flat along its axis.
func _box(id: int) -> Array[int]:
	var c: Vector3i = _build.cell_of_piece(id)
	var rec: Dictionary = _build.piece(id)
	var face: String = rec["face"]
	var box: Array[int] = [c.x, c.x + 1, c.y, c.y + 1, c.z, c.z + 1]
	if face.ends_with("|x"):
		box[0] = c.x + 1
	elif face.ends_with("|y"):
		box[2] = c.y + 1
	elif face.ends_with("|z"):
		box[4] = c.z + 1
	return box


## M7.5 decision 4 by geometry: `top` rests on `bottom` when its underside is at the
## other's top and, seen from above, they overlap as fully as the thinner of the two
## allows (a line under a wall, an area under a cell or floor). Cells side by side
## share only an edge, perpendicular walls only a point: neither rests.
static func _rests_on(top: Array[int], bottom: Array[int]) -> bool:
	if top[2] != bottom[3]:
		return false
	var lx: int = maxi(top[0], bottom[0])
	var hx: int = mini(top[1], bottom[1])
	var lz: int = maxi(top[4], bottom[4])
	var hz: int = mini(top[5], bottom[5])
	if lx > hx or lz > hz:
		return false
	var overlap: int = int(hx > lx) + int(hz > lz)
	var thinner: int = mini(int(top[1] > top[0]) + int(top[5] > top[4]), int(bottom[1] > bottom[0]) + int(bottom[5] > bottom[4]))
	return overlap == thinner


# ---------------------------------------------------------------- restore

func test_snapshot_restore_round_trip_and_rejections() -> void:
	_setup()
	_foundation(0, 0)
	_build.place(_player, &"wall_panel", _at(0, 1, 0), "px")
	_build.place(_player, &"door_frame", _at(0, 1, 0), "nz")
	var full: Dictionary = _sim.snapshot()
	var db := ContentDb.new()
	ContentLoader.load_all(db)
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(other, full), OK, "restore")
	var restored: BuildSystem = SimAssembly.build_of(other)
	assert_eq(StateHash.of(restored.snapshot()), StateHash.of(_build.snapshot()), "identical")
	assert_eq(restored.face_piece_at(BuildSystem.face_key(BuildSystem.cell_of(_at(0, 1, 0)), "px")), _build.piece_ids()[1], "occupancy rebuilt")
	var bad: Dictionary = _build.snapshot().duplicate(true)
	var pieces: Dictionary = bad["pieces"]
	var rec: Dictionary = pieces[_build.piece_ids()[1]]
	rec["face"] = "0,0,0|w"
	var fresh: BuildSystem = SimAssembly.build_of(SimAssembly.build(SEED, db))
	assert_eq(fresh.restore(bad), ERR_INVALID_DATA, "bad face axis rejected")
	assert_eq(fresh.piece_ids(), [] as Array[int], "nothing restored")


## M6 spec claim 15: `build.changed` says where a removed piece stood, because the
## piece record is gone by the time anyone hears about it and "is that gap still
## open?" is a question the scoring asks at the end of a run.
func test_the_change_event_names_the_slot_a_removed_piece_left() -> void:
	_setup()
	_changes.clear()
	assert_true(_foundation(0, 0) > 0, "a foundation")
	var wall: int = _build.place(_player, &"wall_panel", _at(0, 1, 0), "nz")
	assert_true(wall > 0, "a wall on it")
	var placed: Array = _changes[_changes.size() - 1]["removed_at"]
	assert_eq(placed, [] as Array[String], "a placement removes nothing")
	var slot: String = _build.key_of_piece(wall)
	assert_false(slot.is_empty(), "the wall stands somewhere")
	assert_false(_build.slot_is_empty(slot), "and that slot is taken")
	assert_false(_build.remove(_player, wall).is_empty(), "cut it out")
	assert_true(_build.slot_is_empty(slot), "the slot is open now")
	var removed_at: Array = _changes[_changes.size() - 1]["removed_at"]
	assert_eq(removed_at, [slot] as Array[String], "and the event said which slot")
	# a collapse names every slot it emptied, not just the one that was cut
	var rebuilt: int = _build.place(_player, &"wall_panel", _at(0, 1, 0), "nz")
	assert_true(rebuilt > 0, "put it back")
	assert_false(_build.slot_is_empty(slot), "the gap is closed again")
	var foundation: int = _build.cell_piece_at(BuildSystem.cell_of(_at(0, 0, 0)))
	assert_false(_build.remove(_player, foundation).is_empty(), "pull the foundation out from under it")
	var collapse: Array = _changes[_changes.size() - 1]["removed_at"]
	assert_eq(collapse.size(), 2, "the foundation and what it was holding up")
	assert_true(collapse.has(slot), "including the wall's slot")
	assert_true(_build.slot_is_empty(slot), "which is open once more")
	assert_eq(_build.key_of_piece(9999), "", "and a piece that never stood has no slot")
