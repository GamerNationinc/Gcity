extends GcityTest

## The G3 extension exercise (standards §11): a second material with a different tool
## and a second wall piece using it, content only. This test names no material, tool or
## piece: it walks whatever content/ holds.

const SEED: int = 20261011
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)


func _db() -> ContentDb:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	return db


func test_every_piece_places_on_a_foundation_and_every_tool_prices_every_wall() -> void:
	var db: ContentDb = _db()
	var pieces: Array[StringName] = db.ids(&"build_piece")
	var materials: Array[StringName] = db.ids(&"material")
	var tools: Array[StringName] = db.ids(&"tool_class")
	assert_true(materials.size() >= 2, "at least two materials (%d)" % materials.size())
	assert_true(tools.size() >= 2, "at least two tool classes (%d)" % tools.size())
	var sim: SimRoot = SimAssembly.build(SEED, db)
	var build: BuildSystem = SimAssembly.build_of(sim)
	var portals: PortalGraph = SimAssembly.portals_of(sim)
	var player: int = SimAssembly.actors_of(sim).spawn(&"arcade", 0)
	var walls_priced: int = 0
	var i: int = 0
	for piece: StringName in pieces:
		var t: Dictionary = db.get_entry(&"build_piece", piece)
		var kind: Dictionary = db.get_entry(&"piece_kind", LandSystem._as_name(t["kind"]))
		var occupies: String = kind["occupies"]
		var orientation: String = kind["orientation"]
		if kind["target"] or LandSystem._as_name(t["kind"]) == &"foundation":
			continue
		# each piece gets its own foundation two cells along, and sits on that cell
		var base: Vector3i = FAR + Vector3i(500 + 2 * i * M, 500, 500)
		i += 1
		assert_true(build.place(player, &"foundation_block", base, "") > 0, "foundation %d" % i)
		var facing: String = "" if occupies == "cell" else ("py" if orientation == "horizontal" else "pz")
		var at: Vector3i = base + Vector3i(0, M, 0) if occupies == "cell" else base
		var id: int = build.place(player, piece, at, facing)
		assert_true(id > 0, "%s places against its foundation" % piece)
		var passable: bool = kind["passable"]
		if not passable:
			for tool: StringName in tools:
				var cost: int = portals.edge_cost(id, tool)
				assert_true(cost > 0, "%s priced by %s" % [piece, tool])
			walls_priced += 1
	assert_true(walls_priced >= 3, "several solid pieces were priced (%d)" % walls_priced)


func test_metamorphic_a_material_with_more_hp_costs_more_under_every_tool() -> void:
	var db: ContentDb = _db()
	var tools: Array[StringName] = db.ids(&"tool_class")
	var walls: Array[StringName] = []
	for piece: StringName in db.ids(&"build_piece"):
		var t: Dictionary = db.get_entry(&"build_piece", piece)
		if LandSystem._as_name(t["kind"]) == &"wall":
			walls.append(piece)
	assert_true(walls.size() >= 2, "at least two wall pieces (%d)" % walls.size())
	var sim: SimRoot = SimAssembly.build(SEED, db)
	var build: BuildSystem = SimAssembly.build_of(sim)
	var portals: PortalGraph = SimAssembly.portals_of(sim)
	var player: int = SimAssembly.actors_of(sim).spawn(&"arcade", 0)
	build.place(player, &"foundation_block", FAR + Vector3i(500, 500, 500), "")
	var placed: Dictionary = {}
	var i: int = 0
	for wall: StringName in walls:
		var id: int = build.place(player, wall, FAR + Vector3i(500, 500, 500 + i * M), "px")
		placed[wall] = id
		assert_true(id > 0, "%s placed" % wall)
		i += 1
	for a: StringName in walls:
		for b: StringName in walls:
			var ma: Dictionary = db.get_entry(&"material", LandSystem._as_name(db.get_entry(&"build_piece", a)["material"]))
			var mb: Dictionary = db.get_entry(&"material", LandSystem._as_name(db.get_entry(&"build_piece", b)["material"]))
			var hp_a: int = ma["hp"]
			var hp_b: int = mb["hp"]
			var noise_a: int = ma["breach_noise"]
			var noise_b: int = mb["breach_noise"]
			if hp_a >= hp_b and noise_a >= noise_b:
				for tool: StringName in tools:
					var ia: int = placed[a]
					var ib: int = placed[b]
					assert_true(portals.edge_cost(ia, tool) >= portals.edge_cost(ib, tool), "%s costs at least %s under %s" % [a, b, tool])
