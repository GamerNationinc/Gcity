extends GcityTest

## M7.5 spec claim 3: sight runs from the eyes to the eyes or the centre, and a shot from
## the eyes to the centre. The shipped profiles keep their eyes at the feet until claim 6;
## these tests add a two-cell body with eyes at 1 600 mm and a centre at 1 000 mm, and a
## guard that has it.

const SEED: int = 20261330
const PROPERTY_CASES: int = 10_000
const CASES_PER_ARENA: int = 100
const M: int = 1000
const FAR: Vector3i = Vector3i(300 * M, 0, 300 * M)
const TALL: StringName = &"tall_test"
const TALL_GUARD: StringName = &"tall_guard_test"
const ARENA: int = 7
const OBSTACLES: Array[StringName] = [&"wall_panel", &"wall_panel", &"concrete_wall", &"window_frame", &"door_frame", &"floor_panel", &"storage_crate"]
const SIDES: Array[String] = ["px", "nx", "pz", "nz", "py"]

var _sim: SimRoot
var _actors: ActorSystem
var _perception: PerceptionSystem
var _build: BuildSystem
var _builder: int = 0


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	for pair: Array in [[&"arcade", TALL], [&"guard", &"tall_guard_body"]]:
		var from: StringName = pair[0]
		var to: StringName = pair[1]
		var body: Dictionary = db.get_entry(ActorSystem.KIND_PROFILE, from).duplicate(true)
		body["body_cells"] = 2
		body["eye_mm"] = 1600
		body["centre_mm"] = 1000
		assert_eq(db.add(ActorSystem.KIND_PROFILE, to, body), OK, "a tall body %s" % to)
	var agent: Dictionary = db.get_entry(PerceptionSystem.KIND_AGENT, &"guard_sim").duplicate(true)
	agent["combat_profile"] = "tall_guard_body"
	assert_eq(db.add(PerceptionSystem.KIND_AGENT, TALL_GUARD, agent), OK, "a tall guard")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_perception = SimAssembly.perception_of(_sim)
	_build = SimAssembly.build_of(_sim)
	_builder = _actors.spawn(&"arcade", 0)


func _cell(cx: int, cy: int, cz: int) -> Vector3i:
	return BuildSystem.cell_of(FAR) + Vector3i(cx, cy, cz)


func _feet(c: Vector3i) -> Vector3i:
	return Vector3i(c.x * M + 500, c.y * M, c.z * M + 500)


func _place(piece: StringName, c: Vector3i, facing: String) -> int:
	return _build.place(_builder, piece, BuildSystem.cell_centre(c), facing)


## A guard at x = 0 facing +x and a contact at x = 4, a wall between x = 2 and x = 3 one
## row high, or two with `rows` = 2.
func _across_a_wall(rows: int, observer_profile: StringName, contact_profile: StringName) -> Array[int]:
	assert_true(_place(&"foundation_block", _cell(2, 0, 1), "") > 0, "foundation")
	for row: int in rows:
		assert_true(_place(&"wall_panel", _cell(2, row, 0), "px") > 0, "wall row %d" % row)
	var guard: int = _perception.spawn(observer_profile, _cell(0, 0, 0), 0, 1, "")
	assert_true(guard != EntityIds.NONE, "guard")
	_actors.set_position(guard, _feet(_cell(0, 0, 0)))
	var contact: int = _actors.spawn(contact_profile, 0)
	_actors.set_position(contact, _feet(_cell(4, 0, 0)))
	return [guard, contact] as Array[int]


func test_eyes_and_centre_come_from_the_profile() -> void:
	_setup()
	var tall: int = _actors.spawn(TALL, 0)
	var short: int = _actors.spawn(&"arcade", 0)
	assert_eq(_perception.eye_of(tall), Vector3i(0, 1600, 0), "eyes at 1.6 m")
	assert_eq(_perception.centre_of(tall), Vector3i(0, 1000, 0), "the centre at 1 m")
	assert_eq(_perception.eye_of(short), Vector3i.ZERO, "the shipped profiles look from the feet until claim 6")


func test_a_tall_guard_sees_over_a_one_metre_wall_and_not_a_two_metre_one() -> void:
	_setup()
	var pair: Array[int] = _across_a_wall(1, TALL_GUARD, TALL)
	assert_true(_perception.can_see(pair[0], pair[1]), "over a one-metre wall, eyes to eyes")
	assert_true(_perception.can_target(pair[0], pair[1]), "and a shot from the eyes reaches the centre")
	_setup()
	pair = _across_a_wall(2, TALL_GUARD, TALL)
	assert_false(_perception.can_see(pair[0], pair[1]), "not through a two-metre wall")
	assert_false(_perception.can_target(pair[0], pair[1]), "nor a shot")


func test_a_guard_looking_from_its_feet_is_stopped_by_the_one_metre_wall() -> void:
	_setup()
	var pair: Array[int] = _across_a_wall(1, &"guard_sim", &"arcade")
	assert_false(_perception.can_see(pair[0], pair[1]), "eyes at the feet: a one-metre wall hides everything, as before")


func test_cover_asks_the_same_lines() -> void:
	_setup()
	var pair: Array[int] = _across_a_wall(1, TALL_GUARD, TALL)
	var at: Vector3i = _actors.position_of(pair[0])
	var there: Vector3i = _actors.position_of(pair[1])
	assert_true(_perception.sight_line(pair[0], at, pair[1], there), "a one-metre wall is no cover to a standing person")
	_setup()
	pair = _across_a_wall(2, TALL_GUARD, TALL)
	assert_false(_perception.sight_line(pair[0], _actors.position_of(pair[0]), pair[1], _actors.position_of(pair[1])), "a two-metre wall is")


## The metamorphic relations: adding a piece never makes a hidden contact visible, and
## removing one (with whatever falls with it) never hides a visible one.
func test_more_wall_never_shows_and_less_wall_never_hides() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var failures: Array[String] = []
	var visible_cases: int = 0
	var changes: int = 0
	for arena: int in PROPERTY_CASES / CASES_PER_ARENA:
		_setup()
		for x: int in ARENA + 1:
			for z: int in ARENA + 1:
				if rng.randi_range(0, 3) == 0:
					_place(&"foundation_block", _cell(x, 0, z), "")
		for i: int in 40:
			var c: Vector3i = _cell(rng.randi_range(0, ARENA), rng.randi_range(0, 2), rng.randi_range(0, ARENA))
			var piece: StringName = OBSTACLES[rng.randi_range(0, OBSTACLES.size() - 1)]
			_place(piece, c, "" if piece == &"storage_crate" else SIDES[rng.randi_range(0, SIDES.size() - 1)])
		var observer: int = _actors.spawn(TALL, 0)
		var contact: int = _actors.spawn(TALL, 0)
		for case: int in CASES_PER_ARENA:
			var a: Vector3i = _feet(_cell(rng.randi_range(0, ARENA), rng.randi_range(0, 1), rng.randi_range(0, ARENA)))
			var b: Vector3i = _feet(_cell(rng.randi_range(0, ARENA), rng.randi_range(0, 1), rng.randi_range(0, ARENA)))
			var before: bool = _perception.sight_line(observer, a, contact, b)
			if before:
				visible_cases += 1
			var c: Vector3i = _cell(rng.randi_range(0, ARENA), rng.randi_range(0, 2), rng.randi_range(0, ARENA))
			var piece: StringName = OBSTACLES[rng.randi_range(0, OBSTACLES.size() - 1)]
			var added: int = _place(piece, c, "" if piece == &"storage_crate" else SIDES[rng.randi_range(0, SIDES.size() - 1)])
			if added == EntityIds.NONE:
				continue
			changes += 1
			var with_more: bool = _perception.sight_line(observer, a, contact, b)
			if with_more and not before:
				failures.append("arena %d case %d: adding %s at %s showed %s -> %s" % [arena, case, piece, c, a, b])
			var ids: Array[int] = _build.piece_ids()
			var gone: Array[int] = _build.remove(_builder, ids[rng.randi_range(0, ids.size() - 1)])
			if gone.is_empty():
				continue
			if with_more and not _perception.sight_line(observer, a, contact, b):
				failures.append("arena %d case %d: removing %s hid %s -> %s" % [arena, case, gone, a, b])
			if failures.size() > 5:
				break
		if failures.size() > 5:
			break
	assert_eq(failures, [] as Array[String], "more wall never shows, less wall never hides")
	assert_true(changes > 1000 and visible_cases > 500 and visible_cases < PROPERTY_CASES - 500, "the property saw changes and both answers (%d changes, %d visible)" % [changes, visible_cases])


## M7.5 spec claim 4: reach is measured from the body's centre, with the content's
## reach numbers unchanged. An air cell 2.5 m up and a metre along is 2.69 m from the
## feet, beyond the 2.5 m a hand reaches, and 1.80 m from a centre a metre up.
func test_reach_is_measured_from_the_body_centre() -> void:
	_setup()
	var tall: int = _actors.spawn(TALL, 0)
	var short: int = _actors.spawn(&"arcade", 0)
	assert_eq(_actors.centre_of(_builder), _actors.position_of(_builder), "a shipped body's centre is its feet, until claim 6")
	var regions: Regions = SimAssembly.regions_of(_sim)
	for pair: Array in [[short, 0, false], [tall, 4, true]]:
		var actor: int = pair[0]
		var x: int = pair[1]
		var reaches: bool = pair[2]
		# on the level apron outside the gate, air from y 0 up
		_actors.set_position(actor, Vector3i(x * M + 500, 0, -40_500))
		if actor == tall:
			assert_eq(_actors.centre_of(tall), Vector3i(x * M + 500, 1000, -40_500), "a tall body's centre is a metre up")
		var cell: Vector3i = Vector3i(x + 1, 2, -41)
		assert_false(regions.is_solid(cell), "air there")
		var before: int = _sim.dispatched_count()
		_sim.submit(SimCommand.new(_sim.get_tick() + 1, Regions.COMMAND_FILL, {"actor": actor, "cell": [cell.x, cell.y, cell.z]}))
		_sim.step()
		assert_eq(_sim.dispatched_count() == before + 1, reaches, "%s body fills the cell: %s" % ["a tall" if actor == tall else "a short", reaches])
