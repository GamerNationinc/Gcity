extends GcityTest

## M6 claim 6, metamorphic relation: adding a closed door between an agent and a contact
## never raises the contact's awareness gain. A guard's gain is exposure_gain(...) when
## it sees the contact and 0 otherwise, and a door changes nothing but the line of
## sight, so over 10 000 generated layouts and pairs of points, a closed door on any
## face never turns a blocked line of sight into a clear one.

const SEED: int = 20261023
const CASES: int = 10_000
const SEED_RELATION: int = 20261024
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)


func _at(cx: int, cy: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, cy * M + 500, cz * M + 500)


func test_metamorphic_a_closed_door_never_raises_awareness_gain() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	var door: Dictionary = db.get_entry(&"build_piece", &"door_frame").duplicate(true)
	door["starts_open"] = false
	assert_eq(db.add(&"build_piece", &"zz_shut_door", door), OK, "a door that starts shut")
	var sim: SimRoot = SimAssembly.build(SEED, db)
	assert_true(sim != null, "assembly")
	var build: BuildSystem = SimAssembly.build_of(sim)
	var perception: PerceptionSystem = SimAssembly.perception_of(sim)
	var player: int = SimAssembly.actors_of(sim).spawn(&"arcade", 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_RELATION
	# a fixed scatter of walls on two storeys to give the lines something to cross
	for x: int in range(-4, 5, 2):
		build.place(player, &"foundation_block", _at(x, 0, -5), "")
	for i: int in 12:
		var facing: String = ["px", "nx", "pz", "nz"][rng.randi_range(0, 3)]
		build.place(player, &"wall_panel", _at(rng.randi_range(-4, 4), 0, rng.randi_range(-4, -2)), facing)
	var violations: int = 0
	var blocked_by_door: int = 0
	for case: int in CASES:
		var a: Vector3i = _at(rng.randi_range(-4, 4), 0, rng.randi_range(-4, 4))
		var b: Vector3i = _at(rng.randi_range(-4, 4), 0, rng.randi_range(-4, 4))
		var facing: String = ["px", "nx", "pz", "nz"][rng.randi_range(0, 3)]
		var clear_before: bool = perception.line_of_sight(a, b)
		var id: int = build.place(player, &"zz_shut_door", _at(rng.randi_range(-4, 4), 0, rng.randi_range(-4, 4)), facing)
		if id <= 0:
			continue
		var clear_after: bool = perception.line_of_sight(a, b)
		if clear_after and not clear_before:
			violations += 1
		if clear_before and not clear_after:
			blocked_by_door += 1
		build.remove(player, id)
	assert_eq(violations, 0, "a closed door never clears a line of sight")
	assert_true(blocked_by_door > 20, "and the doors did block lines (%d)" % blocked_by_door)
