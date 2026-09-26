extends GcityTest

## M6 spec claims 8 and 9, the agents' side. A locked face lets through only an actor
## carrying an item with its tag, and every attempt is a `land.door_check`; guards plan
## around the locks they cannot open. Guards hear a breach within its range as they
## hear a shot. When a breach takes the floor from under someone, they fall (claim 5).
##
## Test world far out in unparcelled badlands (FAR_CELL = (500, 0, 500)): a wall along
## the x = 2 / x = 3 line from z = 0 to 4, held by foundations at both ends, with a
## locked door at z = 2.
## The heat side of a lock (`heat_max`) arrives with standing in group D.

const SEED: int = 20261150
const M: int = 1000
const FAR_CELL: Vector3i = Vector3i(500, 0, 500)
const TAG: StringName = &"access.test"

var _sim: SimRoot
var _actors: ActorSystem
var _build: BuildSystem
var _items: ItemSystem
var _movement: MovementSystem
var _pathing: PathingSystem
var _perception: PerceptionSystem
var _player: int = 0
var _door: int = 0
var _checks: Array[Dictionary] = []


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	assert_eq(db.add(&"build_piece", &"zz_locked_door", {
		"schema_version": 1, "description": "A door that wants a test keycard.", "kind": "door",
		"material": "scrap_steel", "open_cost": 40, "value": 0, "lock": {"requires_tag": String(TAG)},
	}), OK, "a locked door")
	assert_eq(db.add(ItemSystem.KIND_TOOL, &"zz_keycard", {
		"schema_version": 1, "description": "A keycard for the test door.", "tool_class": "cutter",
		"tags": [String(TAG)], "stats": [],
	}), OK, "its keycard")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_build = SimAssembly.build_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_movement = SimAssembly.movement_of(_sim)
	_pathing = SimAssembly.pathing_of(_sim)
	_perception = SimAssembly.perception_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	# foundations at the wall's two ends hold it up and leave both sides open
	var entries: Array[Array] = [[&"foundation_block", _c(2, 0, -1), ""], [&"foundation_block", _c(2, 0, 5), ""]]
	for z: int in 5:
		entries.append([&"zz_locked_door" if z == 2 else &"wall_panel", _c(2, 0, z), "px"])
	var ids: Array[int] = _build.place_batch(entries)
	assert_eq(ids.size(), 7, "the wall and its door stand")
	for id: int in ids:
		if _build.template_of(id) == &"zz_locked_door":
			_door = id
	var checks: Array[Dictionary] = []
	_checks = checks
	SimAssembly.combat_of(_sim).events().subscribe(MovementSystem.EVENT_DOOR_CHECK, func(p: Dictionary) -> void: checks.append(p))


func _c(x: int, y: int, z: int) -> Vector3i:
	return FAR_CELL + Vector3i(x, y, z)


static func _floor_of(cell: Vector3i) -> Vector3i:
	return Vector3i(cell.x * M + M / 2, cell.y * M, cell.z * M + M / 2)


func _cell_of(actor: int) -> Vector3i:
	return BuildSystem.cell_of(_actors.position_of(actor))


func _walk_x(actor: int, steps: int) -> void:
	for i: int in steps:
		_movement.move(actor, 150, 0)


## Whether a path steps between the two cells the door separates.
func _crosses_door(from: Vector3i, path: Array[Vector3i]) -> bool:
	var previous: Vector3i = from
	for c: Vector3i in path:
		if (previous == _c(2, 0, 2) and c == _c(3, 0, 2)) or (previous == _c(3, 0, 2) and c == _c(2, 0, 2)):
			return true
		previous = c
	return false


func test_a_locked_door_lets_through_only_the_tag_and_every_try_is_a_check() -> void:
	_setup()
	_actors.set_position(_player, _floor_of(_c(2, 0, 2)))
	_walk_x(_player, 3)
	assert_eq(_checks.size(), 0, "short of the door: no check yet")
	assert_false(_movement.move(_player, 150, 0), "no keycard: the door is shut to you")
	assert_eq(_cell_of(_player), _c(2, 0, 2), "still this side")
	assert_eq(_checks.size(), 1, "one check")
	var passed: bool = _checks[0]["passed"]
	var piece: int = _checks[0]["piece"]
	var who: int = _checks[0]["actor"]
	assert_false(passed, "failed")
	assert_eq(piece, _door, "at the door")
	assert_eq(who, _player, "by the player")
	var card: int = _items.spawn(ItemSystem.KIND_TOOL, &"zz_keycard", ItemSystem.inventory_of(_player), 1)
	assert_true(card > 0, "a keycard in the pocket")
	assert_true(_movement.move(_player, 150, 0), "now it opens")
	assert_eq(_cell_of(_player), _c(3, 0, 2), "through")
	assert_eq(_checks.size(), 2, "a second check")
	passed = _checks[1]["passed"]
	assert_true(passed, "passed")
	_walk_x(_player, 3)
	assert_eq(_checks.size(), 2, "open ground is no check")
	# a plain door checks nobody
	assert_true(_build.remove(_player, _door).size() >= 1, "the locked door out")
	assert_true(_build.place(_player, &"door_frame", BuildSystem.cell_centre(_c(2, 0, 2)), "px") > 0, "a plain door in")
	var stranger: int = _actors.spawn(&"arcade", 0)
	_actors.set_position(stranger, _floor_of(_c(2, 0, 2)))
	_walk_x(stranger, 3)
	assert_true(_movement.move(stranger, 150, 0), "a plain door opens for anyone")
	assert_eq(_checks.size(), 2, "without a check")


func test_a_guard_plans_around_a_lock_it_cannot_open_and_through_one_it_can() -> void:
	_setup()
	_actors.set_position(_player, _floor_of(_c(-80, 0, -80)))  # out of every sight
	var guard: int = _perception.spawn(&"guard_sim", _c(0, 0, 2), 0, 1, "")
	var goal: Vector3i = _c(5, 0, 2)
	assert_true(_pathing.request(guard, goal), "a goal beyond the door")
	var ticks: int = 0
	while _pathing.state_of(guard) == PathingSystem.STATE_PLANNING and ticks < 40:
		_pathing.tick(_sim)
		ticks += 1
		_actors.set_position(guard, _floor_of(_c(0, 0, 2)))
	assert_eq(_pathing.state_of(guard), PathingSystem.STATE_FOLLOWING, "a way exists")
	assert_false(_crosses_door(_c(0, 0, 2), _pathing.path_of(guard)), "but not through the locked door: round the wall's end")
	var around: int = _pathing.path_of(guard).size()
	_pathing.cancel(guard)
	_items.spawn(ItemSystem.KIND_TOOL, &"zz_keycard", ItemSystem.inventory_of(guard), 3)
	assert_true(_pathing.request(guard, goal), "again, with the keycard")
	ticks = 0
	while _pathing.state_of(guard) == PathingSystem.STATE_PLANNING and ticks < 40:
		_pathing.tick(_sim)
		ticks += 1
		_actors.set_position(guard, _floor_of(_c(0, 0, 2)))
	assert_true(_crosses_door(_c(0, 0, 2), _pathing.path_of(guard)), "straight through the door it can open")
	assert_true(_pathing.path_of(guard).size() < around, "which is shorter")
	ticks = 0
	while _pathing.state_of(guard) != PathingSystem.STATE_ARRIVED and ticks < 600:
		_sim.step()
		ticks += 1
	assert_eq(_cell_of(guard), goal, "and walked (%d ticks)" % ticks)


func test_guards_hear_a_breach_within_its_range() -> void:
	_setup()
	var near: int = _perception.spawn(&"guard_sim", _c(-4, 0, 2), 0, 1, "")
	var far: int = _perception.spawn(&"guard_sim", _c(-40, 0, 2), 0, 2, "")
	var noise: Dictionary = {"source": _player, "x": _floor_of(_c(0, 0, 2)).x, "y": 0, "z": _floor_of(_c(0, 0, 2)).z, "range_mm": 7500}
	_actors.set_position(_player, _floor_of(_c(0, 0, 2)))
	SimAssembly.combat_of(_sim).events().emit(BreachSystem.EVENT_NOISE, noise)
	assert_true(_perception.awareness_of(near, _player) > 0, "the guard 4 m off heard it")
	assert_true(_perception.has_last_known(near, _player), "and knows where")
	assert_eq(_perception.last_known(near, _player), _floor_of(_c(0, 0, 2)), "at the noise")
	assert_eq(_perception.awareness_of(far, _player), 0, "the guard 40 m off did not")
	var quiet: Dictionary = noise.duplicate()
	quiet["range_mm"] = 1000
	var near2: int = _perception.spawn(&"guard_sim", _c(-4, 0, 6), 0, 3, "")
	SimAssembly.combat_of(_sim).events().emit(BreachSystem.EVENT_NOISE, quiet)
	assert_eq(_perception.awareness_of(near2, _player), 0, "a quiet noise carries a metre, not four")


func test_cutting_out_the_grate_you_stand_on_drops_you() -> void:
	_setup()
	var ids: Array[int] = _build.place_batch([
		[&"foundation_block", _c(10, 0, 10), ""],
		[&"service_grate", _c(11, 0, 10), "py"],
	] as Array[Array])
	assert_eq(ids.size(), 2, "a grate")
	_actors.set_position(_player, _floor_of(_c(11, 1, 10)))
	var cutter: int = _items.spawn(ItemSystem.KIND_TOOL, &"cutter_handheld", ItemSystem.inventory_of(_player), 4)
	_sim.submit(SimCommand.new(_sim.get_tick() + 1, BreachSystem.COMMAND_BREACH, {"actor": _player, "piece": ids[1], "tool": cutter}))
	_sim.step_n(210)
	assert_false(_build.has_piece(ids[1]), "the grate is cut out")
	assert_eq(_cell_of(_player), _c(11, 0, 10), "and the player is down in the shaft")
	assert_eq(_actors.position_of(_player).y, 0, "on its floor")


func test_assembly_refuses_a_lock_that_is_not_on_a_door() -> void:
	for bad: Dictionary in [
		{"schema_version": 1, "description": "x", "kind": "wall", "material": "scrap_steel", "open_cost": 0, "value": 0, "lock": {"requires_tag": "a.b"}},
		{"schema_version": 1, "description": "x", "kind": "hatch", "material": "scrap_steel", "open_cost": 0, "value": 0, "lock": {"requires_tag": "a.b"}},
		{"schema_version": 1, "description": "x", "kind": "door", "material": "scrap_steel", "open_cost": 0, "value": 0, "lock": {"requires_tag": "a.b", "heat": 1}},
		{"schema_version": 1, "description": "x", "kind": "door", "material": "scrap_steel", "open_cost": 0, "value": 0, "lock": {"requires_tag": 3}},
	]:
		var db := ContentDb.new()
		assert_eq(ContentLoader.load_all(db), OK, "content loads")
		assert_eq(db.add(&"build_piece", &"zz_bad_lock", bad), OK, "the db takes the shape")
		assert_true(SimAssembly.build(SEED, db) == null, "assembly refuses %s" % [bad])
