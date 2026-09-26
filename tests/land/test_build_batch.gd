extends GcityTest

## M6 spec claim 2: a batch of pieces lands in one change. Placing a list with
## `place_batch` gives the same pieces, ids and portal graph as placing it one piece at
## a time, in one `build.changed` and one portal rebuild; a batch with any bad entry
## changes nothing at all.

const SEED: int = 20261101
const PROPERTY_CASES: int = 1_000
const SEED_EQUIVALENCE: int = 20261102
const SEED_ATOMIC: int = 20261103
const ATTEMPTS_PER_CASE: int = 40
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)
const FAR_CELL: Vector3i = Vector3i(500, 0, 500)

var _db: ContentDb


func _content() -> ContentDb:
	if _db == null:
		_db = ContentDb.new()
		assert_eq(ContentLoader.load_all(_db), OK, "content loads")
	return _db


## A fresh sim with one actor, as every path below has: ids line up across sims. The
## test site is far out in unparcelled badlands, where anyone may build.
func _sim() -> SimRoot:
	var sim: SimRoot = SimAssembly.build(SEED, _content())
	assert_true(sim != null, "assembly")
	assert_eq(SimAssembly.actors_of(sim).spawn(&"arcade", 0), 1, "the builder is actor 1")
	return sim


func _counter(sim: SimRoot) -> Array[Dictionary]:
	var sink: Array[Dictionary] = []
	var on_changed: Callable = func(payload: Dictionary) -> void:
		sink.append(payload)
	SimAssembly.combat_of(sim).events().subscribe(BuildSystem.EVENT_CHANGED, on_changed)
	return sink


## Places one piece the way a player does, through the rights-checked path.
func _place_one(build: BuildSystem, entry: Array) -> int:
	var template: StringName = entry[0]
	var cell: Vector3i = entry[1]
	var facing: String = entry[2]
	return build.place(1, template, BuildSystem.cell_centre(cell), facing)


func test_a_batch_equals_the_same_pieces_placed_one_by_one() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_EQUIVALENCE
	var templates: Array[StringName] = _content().ids(&"build_piece")
	var facings: Array[String] = ["", "px", "nx", "py", "ny", "pz", "nz"]
	var failures: int = 0
	var pieces_total: int = 0
	for case: int in PROPERTY_CASES:
		# grow a random structure one piece at a time and keep what was accepted
		var grow: SimRoot = _sim()
		var grow_build: BuildSystem = SimAssembly.build_of(grow)
		var accepted: Array[Array] = []
		for attempt: int in ATTEMPTS_PER_CASE:
			var t: StringName = &"foundation_block" if rng.randi_range(0, 9) < 3 else templates[rng.randi_range(0, templates.size() - 1)]
			var cy: int = [0, 0, 1, 1, 2][rng.randi_range(0, 4)]
			var cell: Vector3i = FAR_CELL + Vector3i(rng.randi_range(0, 4), cy, rng.randi_range(0, 4))
			var facing: String = facings[rng.randi_range(0, facings.size() - 1)]
			if t == &"foundation_block" or t == &"storage_crate":
				facing = ""
			var entry: Array = [t, cell, facing]
			if _place_one(grow_build, entry) > 0:
				accepted.append(entry)
		pieces_total += accepted.size()
		# the same list, one by one, in a fresh sim: every piece lands, ids 1..n in order
		var one: SimRoot = _sim()
		var one_build: BuildSystem = SimAssembly.build_of(one)
		var one_changes: Array[Dictionary] = _counter(one)
		for entry: Array in accepted:
			_place_one(one_build, entry)
		# and as one batch in another fresh sim
		var batch: SimRoot = _sim()
		var batch_build: BuildSystem = SimAssembly.build_of(batch)
		var batch_portals: PortalGraph = SimAssembly.portals_of(batch)
		var batch_changes: Array[Dictionary] = _counter(batch)
		var rebuilds_before: int = batch_portals.rebuild_count()
		var ids: Array[int] = batch_build.place_batch(accepted)
		var problem: String = ""
		if ids.size() != accepted.size():
			problem = "batch placed %d of %d" % [ids.size(), accepted.size()]
		elif StateHash.of(batch_build.snapshot()) != StateHash.of(one_build.snapshot()):
			problem = "pieces differ from the one-by-one build"
		elif StateHash.of(batch_portals.snapshot()) != StateHash.of(SimAssembly.portals_of(one).snapshot()):
			problem = "portal graph differs from the one-by-one build"
		elif StateHash.of(SimAssembly.entities_of(batch).snapshot()) != StateHash.of(SimAssembly.entities_of(one).snapshot()):
			problem = "id allocation differs"
		elif not accepted.is_empty() and (batch_changes.size() != 1 or batch_portals.rebuild_count() - rebuilds_before != 1):
			problem = "%d changes and %d rebuilds for one batch" % [batch_changes.size(), batch_portals.rebuild_count() - rebuilds_before]
		elif accepted.is_empty() and (not batch_changes.is_empty() or batch_portals.rebuild_count() != rebuilds_before):
			problem = "an empty batch changed something"
		elif one_changes.size() != accepted.size():
			problem = "one-by-one emitted %d changes for %d pieces" % [one_changes.size(), accepted.size()]
		if not problem.is_empty():
			failures += 1
			if failures <= 3:
				fail("case %d (%d pieces): %s" % [case, accepted.size(), problem])
	assert_eq(failures, 0, "batch equals one-by-one over %d cases" % PROPERTY_CASES)
	assert_true(pieces_total > PROPERTY_CASES * 5, "the cases built real structures (%d pieces)" % pieces_total)


func test_a_batch_with_any_bad_entry_changes_nothing() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_ATOMIC
	var sim: SimRoot = _sim()
	var build: BuildSystem = SimAssembly.build_of(sim)
	var changes: Array[Dictionary] = _counter(sim)
	var room: Array[Array] = [
		[&"foundation_block", FAR_CELL, ""],
		[&"wall_panel", FAR_CELL + Vector3i(1, 0, 0), "nx"],
		[&"door_frame", FAR_CELL + Vector3i(1, 0, 0), "nz"],
	]
	var bad_entries: Array[Array] = [
		[&"no_such_piece", FAR_CELL + Vector3i(2, 0, 0), ""],                  # unknown template
		[&"wall_panel", FAR_CELL + Vector3i(1, 0, 0), "nx"],                   # a face the batch already fills
		[&"foundation_block", FAR_CELL, ""],                                   # a cell the batch already fills
		[&"wall_panel", FAR_CELL + Vector3i(30, 0, 30), "px"],                 # nothing holds it up
		[&"foundation_block", FAR_CELL + Vector3i(0, 1, 3), ""],               # a foundation off the ground
		[&"wall_panel", FAR_CELL + Vector3i(1, 0, 0), "py"],                   # a wall laid flat
		[&"floor_panel", FAR_CELL + Vector3i(1, 0, 0), "px"],                  # a floor stood up
		[&"wall_panel", FAR_CELL + Vector3i(1, 0, 0), "sideways"],             # no such facing
		[&"storage_crate", FAR_CELL + Vector3i(0, 0, 1), "px"],                # a cell piece with a facing
		[&"wall_panel", Vector3i(BuildSystem.MAX_CELL + 1, 0, 0), "px"],       # off the grid
	]
	for bad: Array in bad_entries:
		var entries: Array[Array] = room.duplicate()
		entries.insert(rng.randi_range(0, entries.size()), bad)
		var before: String = sim.state_hash()
		var ids: Array[int] = build.place_batch(entries)
		assert_eq(ids, [] as Array[int], "refused: %s" % [bad])
		assert_eq(sim.state_hash(), before, "state untouched by %s" % [bad])
		assert_true(changes.is_empty(), "no change emitted for %s" % [bad])
	# the room alone lands, and not again on top of itself
	assert_eq(build.place_batch(room).size(), 3, "the good batch lands")
	assert_eq(changes.size(), 1, "as one change")
	var added: Array = changes[0]["added"]
	assert_eq(added.size(), 3, "carrying every piece")
	var by: int = changes[0]["actor"]
	assert_eq(by, EntityIds.NONE, "placed by nobody: authored")
	var after: String = sim.state_hash()
	assert_eq(build.place_batch(room), [] as Array[int], "a second copy overlaps")
	assert_eq(sim.state_hash(), after, "and changes nothing")


func test_a_batch_is_supported_as_a_whole_not_in_list_order() -> void:
	var sim: SimRoot = _sim()
	var build: BuildSystem = SimAssembly.build_of(sim)
	# the wall is listed before the foundation that holds it
	var ids: Array[int] = build.place_batch([
		[&"wall_panel", FAR_CELL + Vector3i(1, 0, 0), "nx"],
		[&"foundation_block", FAR_CELL, ""],
	] as Array[Array])
	assert_eq(ids.size(), 2, "both land")
	assert_eq(build.template_of(ids[0]), &"wall_panel", "ids follow list order")
	for id: int in ids:
		assert_true(build.is_supported(id), "piece %d is supported" % id)
	var steel: Dictionary = _content().get_entry(&"material", &"scrap_steel")
	assert_eq(SimAssembly.stats_of(sim).resolve(ids[0], BuildSystem.STAT_HP), steel["hp"], "a batch piece gets its material's hp")
