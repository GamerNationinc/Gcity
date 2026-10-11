extends GcityTest

## M6 spec claim 10: the Cold Storage front door is locked by the cold_storage_keycard
## and declares `check: {standing: heat, max}`. An opener with the card always gets the
## door open; when its heat is above `max` the opening also emits
## `build.check_failed {actor, piece, standing, value}`, which the door's watching camera
## turns into an alarm (sim/threat). A piece's check names a real standing, and only an
## opening may carry one.

const SEED: int = 20261033
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)

var _sim: SimRoot
var _build: BuildSystem
var _actors: ActorSystem
var _player: int = 0
var _failed: Array[Dictionary] = []


func _setup(db: ContentDb = null) -> void:
	if db == null:
		db = ContentDb.new()
		assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_build = SimAssembly.build_of(_sim)
	_actors = SimAssembly.actors_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, _feet(6, 6))
	var sink: Array[Dictionary] = []
	_failed = sink
	SimAssembly.combat_of(_sim).events().subscribe(BuildSystem.EVENT_CHECK_FAILED, func(p: Dictionary) -> void: sink.append(p))


func _feet(cx: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, 0, cz * M + 500)


func _at(cx: int, cy: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, cy * M + 500, cz * M + 500)


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


## A one-cell lobby at (0, 0, 0) with the Cold Storage door in its east wall.
func _lobby() -> int:
	for c: Vector3i in [Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		assert_true(_build.place(_player, &"foundation_block", _at(c.x, c.y, c.z), "") > 0, "foundation")
	assert_true(_build.place(_player, &"floor_panel", _at(0, 0, 0), "py") > 0, "roof")
	var door: int = _build.place(_player, &"cold_storage_door", _at(0, 0, 0), "px")
	assert_true(door > 0, "the front door")
	return door


func _card() -> void:
	SimAssembly.items_of(_sim).spawn(&"key_item", &"cold_storage_keycard", ItemSystem.inventory_of(_player), 1)


func _heat(alarms: int) -> void:
	for i: int in alarms:
		SimAssembly.combat_of(_sim).events().emit(SensorSystem.EVENT_ALARM, {"sensor": &"power_monitor", "piece": 0, "squad": 1, "actor": _player})


func test_the_door_needs_the_keycard() -> void:
	_setup()
	var door: int = _lobby()
	assert_false(_build.is_open(door), "it starts shut")
	_actors.set_position(_player, _feet(1, 0))
	assert_false(_do(&"opening.open", {"actor": _player, "piece": door}), "refused without the card")
	_card()
	assert_true(_do(&"opening.open", {"actor": _player, "piece": door}), "opens with it")
	assert_eq(_failed.size(), 0, "cool: the check passes quietly")


func test_a_hot_opener_still_gets_in_but_the_check_fails_loudly() -> void:
	_setup()
	var door: int = _lobby()
	_card()
	_heat(2)
	assert_eq(SimAssembly.standing_of(_sim).standing_of(_player, &"heat"), 400, "heat 400, over the door's 300")
	_actors.set_position(_player, _feet(1, 0))
	assert_true(_do(&"opening.open", {"actor": _player, "piece": door}), "the door still opens")
	assert_true(_build.is_open(door), "open")
	assert_eq(_failed, [{"actor": _player, "piece": door, "standing": &"heat", "value": 400}], "and the check failed, naming who and how hot")
	assert_true(_do(&"opening.close", {"actor": _player, "piece": door}), "closed again")
	assert_eq(_failed.size(), 1, "closing checks nothing")


func test_heat_at_the_limit_passes() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	var door_t: Dictionary = db.get_entry(&"build_piece", &"cold_storage_door").duplicate(true)
	door_t["check"] = {"standing": "heat", "max": 200}
	assert_eq(db.add(&"build_piece", &"zz_door_200", door_t), OK, "a door checking heat above 200")
	_setup(db)
	for c: Vector3i in [Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		_build.place(_player, &"foundation_block", _at(c.x, c.y, c.z), "")
	_build.place(_player, &"floor_panel", _at(0, 0, 0), "py")
	var door: int = _build.place(_player, &"zz_door_200", _at(0, 0, 0), "px")
	assert_true(door > 0, "placed")
	_card()
	_heat(1)
	_actors.set_position(_player, _feet(1, 0))
	assert_true(_do(&"opening.open", {"actor": _player, "piece": door}), "opens")
	assert_eq(_failed.size(), 0, "heat equal to max is not above it")


func test_a_check_names_a_real_standing_on_an_opening() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	var bad: Dictionary = db.get_entry(&"build_piece", &"cold_storage_door").duplicate(true)
	bad["check"] = {"standing": "zz_nothing", "max": 0}
	assert_eq(db.add(&"build_piece", &"zz_bad", bad), OK, "an unknown standing")
	assert_eq(SimAssembly.build(SEED, db), null, "rejected")
	db = ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	var wall: Dictionary = db.get_entry(&"build_piece", &"wall_panel").duplicate(true)
	wall["check"] = {"standing": "heat", "max": 0}
	assert_eq(db.add(&"build_piece", &"zz_bad", wall), OK, "a check on a wall")
	assert_eq(SimAssembly.build(SEED, db), null, "rejected")
