extends GcityTest

## M6 claim 8: a camera is an agent built from content. It pans 45 degrees either side
## of where it was mounted every 6 seconds, raises awareness like a guard, reports by
## radio so its squad's guards learn of the contact after the latency, never moves or
## fires, and dies to damage like any actor.

const SEED: int = 20261027
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)

var _sim: SimRoot
var _actors: ActorSystem
var _perception: PerceptionSystem
var _player: int = 0


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_perception = SimAssembly.perception_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, FAR + Vector3i(-40 * M, 0, -40 * M))


func _cell(cx: int, cz: int) -> Vector3i:
	return BuildSystem.cell_of(FAR + Vector3i(cx * M + 500, 0, cz * M + 500))


func _feet(cx: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, 0, cz * M + 500)


func test_a_camera_pans_about_its_mount() -> void:
	_setup()
	var cam: int = _perception.spawn(&"camera", _cell(0, 0), 90, 1, "")
	assert_true(cam > 0, "a camera mounted facing +z")
	for pair: Array in [[0, 45], [60, 90], [120, 135], [180, 90], [240, 45], [30, 67]]:
		var tick: int = pair[0]
		var expected: int = pair[1]
		assert_eq(_perception.sweep_facing(cam, tick), expected, "facing at tick %d" % tick)
	var guard: int = _perception.spawn(&"guard_sim", _cell(3, 0), 0, 1, "")
	assert_eq(_perception.sweep_facing(guard, 100), -1, "a guard does not sweep")
	_sim.step_n(60)
	assert_eq(_perception.facing_of(cam), _perception.sweep_facing(cam, _sim.get_tick()), "the tick applies the sweep")


func test_a_camera_spots_the_player_and_its_squad_hears_by_radio() -> void:
	_setup()
	var cam: int = _perception.spawn(&"camera", _cell(0, 0), 0, 1, "")
	var guard: int = _perception.spawn(&"guard_sim", _cell(-20, -20), 180, 1, "")  # far off, facing away
	_actors.set_position(_player, _feet(10, 0))
	var alerted_at: int = -1
	for i: int in 200:
		_sim.step()
		if alerted_at < 0 and _perception.is_alerted(cam, _player):
			alerted_at = _sim.get_tick()
		if _perception.is_alerted(guard, _player):
			break
	assert_true(alerted_at > 0, "the camera was alerted")
	assert_true(_perception.is_alerted(guard, _player), "and the guard learned of it")
	assert_true(SimAssembly.squads_of(_sim).delivered_count() >= 1, "by a delivered radio report")
	var pos: Vector3i = _actors.position_of(cam)
	_sim.step_n(100)
	assert_eq(_actors.position_of(cam), pos, "the camera never moves")
	assert_eq(SimAssembly.stances_of(_sim).fire_count(), 0, "nor fires: it has no weapon, and the guard is out of sight")


func test_a_camera_dies_to_damage_and_then_sees_nothing() -> void:
	_setup()
	var cam: int = _perception.spawn(&"camera", _cell(0, 0), 0, 1, "")
	_actors.damage_node(cam, &"body", 20000)
	assert_false(_actors.is_alive(cam), "destroyed")
	_actors.set_position(_player, _feet(5, 0))
	_sim.step_n(60)
	assert_false(_perception.is_alerted(cam, _player), "a dead camera sees nothing")
