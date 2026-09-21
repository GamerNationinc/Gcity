extends GcityTest

## The G2 extension exercise (standards §11): a fourth module with a dependency and
## water, and a third district with a stricter rights table, exist as content only.
## This test knows no module or district by name: it walks whatever content/ holds.

const SEED: int = 20260929
const M: int = 1000


func _db() -> ContentDb:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	return db


func test_every_module_installs_on_an_empty_container_after_its_dependencies() -> void:
	var db: ContentDb = _db()
	var modules: Array[StringName] = db.ids(&"module")
	assert_true(modules.size() >= 4, "at least four modules exist (%d)" % modules.size())
	var with_water: int = 0
	var with_deps: int = 0
	for module: StringName in modules:
		var sim: SimRoot = SimAssembly.build(SEED, db)
		var actors: ActorSystem = SimAssembly.actors_of(sim)
		var structures: StructureSystem = SimAssembly.structures_of(sim)
		var player: int = actors.spawn(&"arcade", 0)
		# the badlands are free to build on; no ownership setup needed
		var s: int = structures.place(player, &"container_20ft", Vector3i(500 * M, 0, 500 * M), 0)
		assert_true(s > 0, "container for %s" % module)
		var order: Array[StringName] = _install_order(db, module)
		var row: int = 0
		var col: int = 0
		for t: StringName in order:
			var fp: Dictionary = db.get_entry(&"module", t)["footprint"]
			var cols: int = fp["cols"]
			if col + cols > 9:
				col = 0
				row += 1
			var id: int = structures.install(player, s, t, col, row)
			assert_true(id > 0, "%s: install %s at (%d, %d) with power %d heat %d" % [module, t, col, row, structures.power_available(s), structures.heat_headroom(s)])
			col += cols
		assert_true(structures.power_available(s) >= 0 and structures.heat_headroom(s) >= 0, "%s: budgets non-negative" % module)
		var t: Dictionary = db.get_entry(&"module", module)
		var water_in: int = t["water_in"]
		var deps: Array = t["depends_on"]
		if water_in > 0:
			with_water += 1
		if not deps.is_empty():
			with_deps += 1
	assert_true(with_water >= 2, "at least two modules take water")
	assert_true(with_deps >= 3, "at least three modules depend on another")


## Dependencies first (depth-first, deduplicated), then the module itself.
func _install_order(db: ContentDb, module: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	var stack: Array[StringName] = [module]
	while not stack.is_empty():
		var m: StringName = stack.pop_back()
		if out.has(m):
			continue
		var deps: Array = db.get_entry(&"module", m)["depends_on"]
		var pending: Array[StringName] = []
		for d: Variant in deps:
			var d_s: String = d
			var dep: StringName = StringName(d_s)
			if not out.has(dep):
				pending.append(dep)
		if pending.is_empty():
			out.append(m)
		else:
			stack.append(m)
			stack.append_array(pending)
	return out


func test_every_district_rights_table_is_what_rights_at_reports() -> void:
	var db: ContentDb = _db()
	var districts: Array[StringName] = db.ids(&"district")
	assert_true(districts.size() >= 3, "at least three districts exist (%d)" % districts.size())
	var sim: SimRoot = SimAssembly.build(SEED, db)
	var land: LandSystem = SimAssembly.land_of(sim)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var owner: int = actors.spawn(&"arcade", 0)
	var other: int = actors.spawn(&"arcade", 0)
	sim.submit(SimCommand.new(1, LandSystem.COMMAND_IDENTIFY, {"actor": owner, "owner": "tester"}))
	sim.step()
	var index: int = 0
	for district: StringName in districts:
		index += 1
		var x: int = (1000 + index * 100) * M
		var owned: StringName = StringName("owned_%d" % index)
		var free: StringName = StringName("free_%d" % index)
		assert_eq(land.add_parcel(owned, district, &"tester", [[x, 0], [x + 10 * M, 0], [x + 10 * M, 10 * M], [x, 10 * M]], -M, 10 * M), OK, "owned parcel in %s" % district)
		assert_eq(land.add_parcel(free, district, &"", [[x, 20 * M], [x + 10 * M, 20 * M], [x + 10 * M, 30 * M], [x, 30 * M]], -M, 10 * M), OK, "unowned parcel in %s" % district)
		var tables: Dictionary = db.get_entry(&"district", district)["rights"]
		var checks: Array = [
			["owner", Vector3i(x + 5 * M, 0, 5 * M), owner],
			["other", Vector3i(x + 5 * M, 0, 5 * M), other],
			["unowned", Vector3i(x + 5 * M, 0, 25 * M), other],
		]
		for check: Array in checks:
			var table_name: String = check[0]
			var position: Vector3i = check[1]
			var actor: int = check[2]
			var expected: Dictionary = tables[table_name]
			var actual: Dictionary = land.rights_at(position, actor)
			for right: StringName in LandSystem.RIGHTS:
				assert_eq(actual[right], expected[String(right)], "%s / %s / %s" % [district, table_name, right])
