extends GcityTest

## M2 spec claims 8–12: the container on the starter plot, modules on its socket grid,
## a shared power and heat budget through the stat resolver, and building on land you
## do not own as a rights violation rather than a special case.

const SEED: int = 20260924
const PROPERTY_CASES: int = 10_000
const SEED_BUDGET: int = 20260925
const M: int = 1000
const CONTAINER: StringName = &"container_20ft"

var _sim: SimRoot
var _land: LandSystem
var _structures: StructureSystem
var _actors: ActorSystem
var _player: int = 0


func _build() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_land = SimAssembly.land_of(_sim)
	_structures = SimAssembly.structures_of(_sim)
	_actors = SimAssembly.actors_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	assert_true(_do(LandSystem.COMMAND_IDENTIFY, {"actor": _player, "owner": "player"}), "identify")
	assert_true(_do(LandSystem.COMMAND_TRANSFER, {"parcel": "starter_plot", "owner": "player"}), "own the plot")


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


func _place_on_plot() -> int:
	var id: int = _structures.place(_player, CONTAINER, Vector3i(2 * M, 0, 4 * M), 0)
	assert_true(id > 0, "container placed on the plot")
	return id


# ---------------------------------------------------------------- placement

func test_place_on_own_plot_records_owner_and_budgets() -> void:
	_build()
	var id: int = _place_on_plot()
	var rec: Dictionary = _structures.structure(id)
	assert_eq(rec["template"], CONTAINER, "template")
	assert_eq(rec["owner_at_placement"], &"player", "owner tag at placement")
	assert_eq(_structures.footprint_of(id), [2 * M, 4 * M, 2 * M + 6058, 4 * M + 2438] as Array[int], "footprint")
	assert_eq(_structures.power_available(id), 3000, "power budget is the base")
	assert_eq(_structures.heat_headroom(id), 4000, "heat budget is the base")
	assert_eq(_structures.module_ids(id), [] as Array[int], "empty")


func test_rotation_swaps_the_footprint() -> void:
	_build()
	var id: int = _structures.place(_player, CONTAINER, Vector3i(2 * M, 0, 2 * M), 90)
	assert_true(id > 0, "placed rotated")
	assert_eq(_structures.footprint_of(id), [2 * M, 2 * M, 2 * M + 2438, 2 * M + 6058] as Array[int], "x and z swapped")
	assert_eq(_structures.place(_player, CONTAINER, Vector3i(8 * M, 0, 2 * M), 45), EntityIds.NONE, "only quarter turns")


func test_building_on_the_neighbour_is_a_violation_until_transferred() -> void:
	_build()
	var violations: int = _land.violation_count()
	var before: String = _sim.state_hash()
	assert_eq(_structures.place(_player, CONTAINER, Vector3i(14 * M, 0, 4 * M), 0), EntityIds.NONE, "refused on the neighbour")
	assert_eq(_land.violation_count(), violations + 1, "one violation emitted")
	assert_eq(_structures.structure_ids(), [] as Array[int], "nothing placed")
	assert_eq(_structures.place(_player, CONTAINER, Vector3i(8 * M, 0, 4 * M), 0), EntityIds.NONE, "straddling the boundary is refused too")
	assert_eq(_land.violation_count(), violations + 2, "the far corner was the violation")
	assert_true(_do(LandSystem.COMMAND_TRANSFER, {"parcel": "neighbour_east", "owner": "player"}), "buy the neighbour")
	assert_true(_structures.place(_player, CONTAINER, Vector3i(14 * M, 0, 4 * M), 0) > 0, "now allowed")
	assert_ne(_sim.state_hash(), before, "state moved")


func test_unparcelled_badlands_are_free_to_build_on() -> void:
	_build()
	var stranger: int = _actors.spawn(&"arcade", 0)
	assert_true(_structures.place(stranger, CONTAINER, Vector3i(500 * M, 0, 500 * M), 0) > 0, "no owner needed in the badlands")
	assert_eq(_structures.structure(_structures.structure_ids()[0])["owner_at_placement"], &"", "placed by nobody in particular")


func test_structures_may_not_overlap() -> void:
	_build()
	_place_on_plot()
	assert_eq(_structures.place(_player, CONTAINER, Vector3i(5 * M, 0, 5 * M), 0), EntityIds.NONE, "overlapping footprint refused")
	assert_true(_structures.place(_player, CONTAINER, Vector3i(2 * M, 3 * M, 4 * M), 0) > 0, "stacked above is fine")
	assert_true(_structures.place(_player, CONTAINER, Vector3i(2 * M, 0, 4 * M + 2438), 0) > 0, "sharing an edge is fine")


# ---------------------------------------------------------------- modules

func test_install_three_modules_within_budget_and_refuse_the_fourth() -> void:
	_build()
	var s: int = _place_on_plot()
	assert_eq(_structures.install(_player, s, &"work_station", 0, 0), EntityIds.NONE, "work station needs power first")
	var power: int = _structures.install(_player, s, &"power_cell_rack", 0, 0)
	assert_true(power > 0, "power rack")
	assert_eq(_structures.power_available(s), 5500, "rack supplies 2500 on top of the 3000 budget")
	assert_eq(_structures.heat_headroom(s), 3400, "rack sheds 600")
	var work: int = _structures.install(_player, s, &"work_station", 2, 0)
	assert_true(work > 0, "work station")
	var sustain: int = _structures.install(_player, s, &"sustainment", 5, 0)
	assert_true(sustain > 0, "sustainment")
	assert_eq(_structures.power_available(s), 3500, "5500 - 800 - 1200")
	assert_eq(_structures.heat_headroom(s), 2000, "3400 - 500 - 900")
	assert_eq(_structures.install(_player, s, &"sustainment", 5, 2), EntityIds.NONE, "second sustainment: cells 5-7 row 2-3 are off-grid")
	assert_true(_structures.install(_player, s, &"sustainment", 0, 1) > 0, "second sustainment on free cells 0-2 x rows 1-2, within budget")
	assert_eq(_structures.power_available(s), 2300, "power after the second sustainment")
	assert_eq(_structures.heat_headroom(s), 1100, "heat after the second sustainment")


func test_budget_refuses_an_install_that_would_go_negative_and_remove_restores_exactly() -> void:
	_build()
	var s: int = _place_on_plot()
	assert_true(_structures.install(_player, s, &"power_cell_rack", 0, 0) > 0, "rack: 5500 / 3400")
	assert_true(_structures.install(_player, s, &"sustainment", 2, 0) > 0, "sustainment A: 4300 / 2500")
	assert_true(_structures.install(_player, s, &"sustainment", 5, 0) > 0, "sustainment B: 3100 / 1600")
	assert_true(_structures.install(_player, s, &"power_cell_rack", 0, 1) > 0, "rack 2: 5600 / 1000")
	var rack3: int = _structures.install(_player, s, &"power_cell_rack", 0, 2)
	assert_true(rack3 > 0, "rack 3: 8100 / 400")
	assert_eq(_structures.power_available(s), 8100, "power")
	assert_eq(_structures.heat_headroom(s), 400, "heat")
	assert_eq(_structures.install(_player, s, &"work_station", 2, 2), EntityIds.NONE, "work station needs 500 heat, 400 left: refused")
	assert_eq(_structures.module_ids(s).size(), 5, "still five")
	assert_true(_structures.remove(_player, s, rack3), "remove rack 3")
	assert_eq(_structures.power_available(s), 5600, "power restored exactly")
	assert_eq(_structures.heat_headroom(s), 1000, "heat restored exactly")
	assert_true(_structures.install(_player, s, &"work_station", 2, 2) > 0, "now it fits")
	assert_eq(_structures.heat_headroom(s), 500, "heat after the work station")


func test_sockets_never_overlap_and_stay_on_grid() -> void:
	_build()
	var s: int = _place_on_plot()
	assert_true(_structures.install(_player, s, &"power_cell_rack", 7, 2) > 0, "rack in the far corner (cols 7-8, row 2)")
	assert_eq(_structures.install(_player, s, &"power_cell_rack", 8, 0), EntityIds.NONE, "cols 8-9 off grid")
	assert_eq(_structures.install(_player, s, &"power_cell_rack", -1, 0), EntityIds.NONE, "negative col")
	assert_eq(_structures.install(_player, s, &"power_cell_rack", 0, 3), EntityIds.NONE, "row 3 off grid")
	assert_eq(_structures.install(_player, s, &"work_station", 6, 2), EntityIds.NONE, "cols 6-8 row 2 overlaps the rack")
	assert_true(_structures.install(_player, s, &"work_station", 6, 1) > 0, "row 1 is free")
	assert_eq(_structures.occupancy(s).size(), 5, "five cells occupied")


func test_remove_refuses_to_orphan_dependants() -> void:
	_build()
	var s: int = _place_on_plot()
	var rack: int = _structures.install(_player, s, &"power_cell_rack", 0, 0)
	var work: int = _structures.install(_player, s, &"work_station", 2, 0)
	assert_false(_structures.remove(_player, s, rack), "work station depends on the rack")
	var rack2: int = _structures.install(_player, s, &"power_cell_rack", 0, 1)
	assert_true(rack2 > 0, "second rack")
	assert_true(_structures.remove(_player, s, rack), "with a second rack the first may go")
	assert_false(_structures.remove(_player, s, rack2), "but not the last")
	assert_true(_structures.remove(_player, s, work), "remove the dependant")
	assert_true(_structures.remove(_player, s, rack2), "then the rack")
	assert_eq(_structures.power_available(s), 3000, "back to the bare budget")
	assert_eq(_structures.heat_headroom(s), 4000, "exactly")


func test_module_work_needs_build_rights_too() -> void:
	_build()
	var s: int = _place_on_plot()
	var rack: int = _structures.install(_player, s, &"power_cell_rack", 0, 0)
	var stranger: int = _actors.spawn(&"arcade", 0)
	var violations: int = _land.violation_count()
	assert_eq(_structures.install(stranger, s, &"work_station", 2, 0), EntityIds.NONE, "a stranger may not install")
	assert_false(_structures.remove(stranger, s, rack), "or remove")
	assert_eq(_land.violation_count(), violations + 2, "both were violations")


# ---------------------------------------------------------------- commands

func test_command_payload_contracts() -> void:
	_build()
	assert_true(_do(StructureSystem.COMMAND_PLACE, {"actor": _player, "template": "container_20ft", "x": 2 * M, "y": 0, "z": 4 * M, "rotation": 0}), "place")
	var s: int = _structures.structure_ids()[0]
	assert_false(_do(StructureSystem.COMMAND_PLACE, {"actor": _player, "template": "container_20ft", "x": 2 * M, "y": 0, "z": 4 * M}), "missing rotation")
	assert_false(_do(StructureSystem.COMMAND_PLACE, {"actor": 99, "template": "container_20ft", "x": 2 * M, "y": 0, "z": 9 * M, "rotation": 0}), "unknown actor")
	assert_false(_do(StructureSystem.COMMAND_PLACE, {"actor": _player, "template": "bunker", "x": 2 * M, "y": 0, "z": 9 * M, "rotation": 0}), "unknown template")
	assert_true(_do(StructureSystem.COMMAND_INSTALL, {"actor": _player, "structure": s, "template": "power_cell_rack", "col": 0, "row": 0}), "install")
	var rack: int = _structures.module_ids(s)[0]
	assert_false(_do(StructureSystem.COMMAND_INSTALL, {"actor": _player, "structure": s, "template": "power_cell_rack", "col": 0.5, "row": 0}), "fractional col")
	assert_false(_do(StructureSystem.COMMAND_INSTALL, {"actor": _player, "structure": s + 1, "template": "power_cell_rack", "col": 0, "row": 1}), "unknown structure")
	assert_false(_do(StructureSystem.COMMAND_REMOVE, {"actor": _player, "structure": s, "module": rack + 1}), "unknown module")
	assert_false(_do(StructureSystem.COMMAND_REMOVE, {"actor": _player, "structure": s, "module": rack, "force": true}), "extra key")
	assert_true(_do(StructureSystem.COMMAND_REMOVE, {"actor": _player, "structure": s, "module": rack}), "remove")


# ---------------------------------------------------------------- property

## Random install/remove sequences: headroom always equals budget minus the installed
## modules' draw (oracle), never goes negative, occupancy never overlaps, and every
## refusal has one of the spec's reasons.
func test_property_budget_and_occupancy_hold_across_random_sequences() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_BUDGET
	_build()
	var s: int = _place_on_plot()
	var db: ContentDb = _content_db()
	var templates: Array[StringName] = db.ids(&"module")
	var failures: int = 0
	var installs: int = 0
	var removes: int = 0
	for case: int in PROPERTY_CASES:
		if rng.randi_range(0, 2) > 0 or _structures.module_ids(s).is_empty():
			var t: StringName = templates[rng.randi_range(0, templates.size() - 1)]
			if _structures.install(_player, s, t, rng.randi_range(-1, 9), rng.randi_range(-1, 3)) > 0:
				installs += 1
		else:
			var ids: Array[int] = _structures.module_ids(s)
			if _structures.remove(_player, s, ids[rng.randi_range(0, ids.size() - 1)]):
				removes += 1
		var problem: String = _check_invariants(s, db)
		if not problem.is_empty():
			failures += 1
			if failures <= 3:
				fail("case %d: %s" % [case, problem])
	assert_eq(failures, 0, "invariants held over %d installs and %d removes" % [installs, removes])
	assert_true(installs > 100 and removes > 100, "the sequence exercised both operations")


func _content_db() -> ContentDb:
	var db := ContentDb.new()
	ContentLoader.load_all(db)
	return db


func _check_invariants(s: int, db: ContentDb) -> String:
	var st: Dictionary = db.get_entry(&"structure", CONTAINER)
	var power: int = st["power_budget"]
	var heat: int = st["heat_budget"]
	var cells: Dictionary = {}
	var rec: Dictionary = _structures.structure(s)
	var modules: Dictionary = rec["modules"]
	var installed: Array[StringName] = []
	for module_id: int in modules:
		var m: Dictionary = modules[module_id]
		var mt: StringName = m["template"]
		var t: Dictionary = db.get_entry(&"module", mt)
		installed.append(mt)
		var draw: int = t["power_draw"]
		var output: int = t["heat_output"]
		power -= draw
		heat -= output
		var fp: Dictionary = t["footprint"]
		var col0: int = m["col"]
		var row0: int = m["row"]
		var cols: int = fp["cols"]
		var rows: int = fp["rows"]
		for c: int in range(col0, col0 + cols):
			for r: int in range(row0, row0 + rows):
				if c < 0 or c >= 9 or r < 0 or r >= 3:
					return "module %d off grid" % module_id
				var key: String = "%d,%d" % [c, r]
				if cells.has(key):
					return "cell %s double-booked" % key
				cells[key] = module_id
	for module_id: int in modules:
		var m: Dictionary = modules[module_id]
		var mt: StringName = m["template"]
		var t: Dictionary = db.get_entry(&"module", mt)
		for dep: Variant in t["depends_on"]:
			var dep_s: String = dep
			if not installed.has(StringName(dep_s)):
				return "module %d lacks dependency %s" % [module_id, dep]
	if power < 0 or heat < 0:
		return "budget negative (%d, %d)" % [power, heat]
	if _structures.power_available(s) != power:
		return "power %d != oracle %d" % [_structures.power_available(s), power]
	if _structures.heat_headroom(s) != heat:
		return "heat %d != oracle %d" % [_structures.heat_headroom(s), heat]
	return ""


# ---------------------------------------------------------------- restore

func test_snapshot_restore_round_trip_and_rejections() -> void:
	_build()
	var s: int = _place_on_plot()
	_structures.install(_player, s, &"power_cell_rack", 0, 0)
	_structures.install(_player, s, &"work_station", 2, 0)
	var full: Dictionary = _sim.snapshot()
	var other: SimRoot = SimAssembly.build(SEED, _content_db())
	assert_eq(SimAssembly.restore_systems(other, full), OK, "restore every system")
	var restored: StructureSystem = SimAssembly.structures_of(other)
	assert_eq(StateHash.of(restored.snapshot()), StateHash.of(_structures.snapshot()), "identical records")
	assert_eq(restored.power_available(s), _structures.power_available(s), "budget restored through the resolver")
	assert_eq(restored.occupancy(s), _structures.occupancy(s), "occupancy rebuilt")
	var bad: Dictionary = _structures.snapshot().duplicate(true)
	var structures: Dictionary = bad["structures"]
	var rec: Dictionary = structures[s]
	rec["rotation"] = 45
	var fresh: StructureSystem = SimAssembly.structures_of(SimAssembly.build(SEED, _content_db()))
	assert_eq(fresh.restore(bad), ERR_INVALID_DATA, "bad rotation rejected")
	assert_eq(fresh.structure_ids(), [] as Array[int], "nothing restored")
