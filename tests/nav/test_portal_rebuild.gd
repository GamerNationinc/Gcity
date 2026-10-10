extends GcityTest

## M6 claim 7: the portal graph's rebuild is fast and exact. Property: over 10 000
## generated changes (place, remove, breach, excavate) on a small site, the
## graph the build system produces (volumes, numbering, edges, targets) equals the one
## the pre-claim-7 reference flood fill produces from the same pieces, after every one.

const SEED: int = 20261025
const CASES: int = 10_000
const SEED_STREAM: int = 20261026
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)
const ReferenceGraph: GDScript = preload("res://tests/nav/doubles/reference_portal_graph.gd")


func _at(cx: int, cy: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, cy * M + 500, cz * M + 500)


func test_property_the_graph_always_equals_the_reference_flood_fill() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	var sim: SimRoot = SimAssembly.build(SEED, db)
	assert_true(sim != null, "assembly")
	var build: BuildSystem = SimAssembly.build_of(sim)
	var portals: PortalGraph = SimAssembly.portals_of(sim)
	var player: int = SimAssembly.actors_of(sim).spawn(&"arcade", 0)
	SimAssembly.actors_of(sim).set_position(player, FAR + Vector3i(-30 * M, 0, -30 * M))
	var reference: RefCounted = ReferenceGraph.new(build)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_STREAM
	var faces: Array[StringName] = [&"wall_panel", &"door_frame", &"window_frame", &"floor_panel", &"roof_hatch", &"ladder_hatch", &"street_grate", &"concrete_wall"]
	var cells: Array[StringName] = [&"foundation_block", &"storage_crate", &"stair_steel"]
	var mismatches: int = 0
	var changes: int = 0
	var case: int = 0
	while changes < CASES and case < CASES * 10:
		case += 1
		var op: int = rng.randi_range(0, 19)
		var changed: bool = false
		if op < 12:
			var horizontal: bool = false
			var template: StringName
			var facing: String = ""
			if rng.randi_range(0, 2) == 0:
				template = cells[rng.randi_range(0, cells.size() - 1)]
				if template == &"stair_steel":
					facing = ["px", "nx", "pz", "nz"][rng.randi_range(0, 3)]
			else:
				template = faces[rng.randi_range(0, faces.size() - 1)]
				horizontal = [&"floor_panel", &"roof_hatch", &"ladder_hatch", &"street_grate"].has(template)
				facing = "py" if horizontal else ["px", "nx", "pz", "nz"][rng.randi_range(0, 3)]
			var y: int = rng.randi_range(-1, 1) if horizontal else rng.randi_range(0, 1)
			changed = build.place(player, template, _at(rng.randi_range(-3, 3), y, rng.randi_range(-3, 3)), facing) > 0
		elif op < 16:
			var ids: Array[int] = build.piece_ids()
			if not ids.is_empty():
				changed = not build.remove(player, ids[rng.randi_range(0, ids.size() - 1)]).is_empty()
		elif op < 18:
			var ids2: Array[int] = build.piece_ids()
			if not ids2.is_empty():
				changed = not build.breach(ids2[rng.randi_range(0, ids2.size() - 1)]).is_empty()
		else:
			var dig: Array[Vector3i] = [BuildSystem.cell_of(_at(rng.randi_range(-3, 3), -1, rng.randi_range(-3, 3)))]
			changed = build.excavate(dig) == OK
			portals.rebuild()  # excavation is not a build.changed event: the site spawn rebuilds after it (claim 12)
		if not changed:
			continue
		changes += 1
		var expected: Dictionary = reference.call("snapshot")
		if StateHash.of(portals.snapshot()) != StateHash.of(expected):
			mismatches += 1
			if mismatches <= 3:
				fail("case %d: graph differs from the reference (%d pieces)" % [case, build.piece_ids().size()])
	assert_eq(mismatches, 0, "the graph matches the reference after every change")
	assert_eq(changes, CASES, "10 000 changes compared (%d operations)" % case)
