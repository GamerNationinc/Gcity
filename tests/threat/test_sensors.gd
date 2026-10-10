extends GcityTest

## M6 claim 8: a sensor watches one opening for one squad. Opening or breaching it while
## live raises security.alarm and the squad learns of the actor after the sensor's
## latency; a spoofed sensor is silent; a sensor goes with its piece.

const SEED: int = 20261028
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)

var _sim: SimRoot
var _build: BuildSystem
var _actors: ActorSystem
var _perception: PerceptionSystem
var _sensors: SensorSystem
var _player: int = 0
var _alarms: Array[Dictionary] = []


func _setup(db: ContentDb = null) -> void:
	if db == null:
		db = ContentDb.new()
		assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_build = SimAssembly.build_of(_sim)
	_actors = SimAssembly.actors_of(_sim)
	_perception = SimAssembly.perception_of(_sim)
	_sensors = SimAssembly.sensors_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, _feet(8, 8))
	var sink: Array[Dictionary] = []
	_alarms = sink
	SimAssembly.combat_of(_sim).events().subscribe(SensorSystem.EVENT_ALARM, func(p: Dictionary) -> void: sink.append(p))


func _feet(cx: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, 0, cz * M + 500)


func _at(cx: int, cy: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, cy * M + 500, cz * M + 500)


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


## A one-cell room at (0, 0, 0) with a latched window in its east wall; a guard of
## squad 1 far off, facing away. Returns the window.
func _room_and_guard() -> int:
	for c: Vector3i in [Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		assert_true(_build.place(_player, &"foundation_block", _at(c.x, c.y, c.z), "") > 0, "foundation")
	assert_true(_build.place(_player, &"floor_panel", _at(0, 0, 0), "py") > 0, "roof")
	var window: int = _build.place(_player, &"window_frame", _at(0, 0, 0), "px")
	assert_true(window > 0, "window")
	assert_true(_perception.spawn(&"guard_sim", BuildSystem.cell_of(_feet(-30, -30)), 180, 1, "") > 0, "a guard of squad 1")
	return window


func test_opening_a_watched_window_raises_the_alarm_and_the_squad_hears_after_the_latency() -> void:
	_setup()
	var window: int = _room_and_guard()
	var guard: int = _perception.agent_ids()[0]
	assert_true(_do(&"sensor.install", {"sensor": "power_monitor", "piece": window, "squad": 1}), "installed")
	_actors.set_position(_player, _feet(0, 0))
	assert_true(_do(&"opening.open", {"actor": _player, "piece": window}), "opened from inside")
	assert_eq(_alarms.size(), 1, "the alarm")
	assert_eq(_alarms[0], {"sensor": &"power_monitor", "piece": window, "squad": 1, "actor": _player}, "naming who")
	_sim.step_n(38)
	assert_false(_perception.is_alerted(guard, _player), "not before the 40-tick latency")
	_sim.step_n(3)
	assert_true(_perception.is_alerted(guard, _player), "the guard knows after it")


func test_a_spoofed_sensor_is_silent() -> void:
	_setup()
	var window: int = _room_and_guard()
	assert_true(_sensors.install(&"power_monitor", window, 1), "installed")
	assert_true(_sensors.spoof(window), "spoofed")
	assert_false(_sensors.spoof(window), "once")
	_actors.set_position(_player, _feet(0, 0))
	assert_true(_do(&"opening.open", {"actor": _player, "piece": window}), "opened")
	assert_eq(_alarms.size(), 0, "no alarm")


func test_breaching_a_watched_window_raises_the_alarm_and_the_sensor_goes_with_it() -> void:
	_setup()
	var window: int = _room_and_guard()
	assert_true(_sensors.install(&"power_monitor", window, 1), "installed")
	var cutter: int = SimAssembly.items_of(_sim).spawn(&"tool", &"plasma_cutter", ItemSystem.inventory_of(_player), 1)
	_actors.set_position(_player, _feet(1, 0))
	assert_true(_do(&"actor.wield", {"actor": _player, "weapon": cutter}), "cutter in hand")
	assert_true(_do(&"build.breach", {"actor": _player, "piece": window}), "cutting the window from outside")
	_sim.step_n(400)
	assert_false(_build.has_piece(window), "the window is out")
	assert_eq(_alarms.size(), 1, "it tripped the monitor")
	assert_false(_sensors.has_sensor(window), "and the sensor went with it")


func test_install_is_validated_and_a_sensor_survives_the_restore() -> void:
	_setup()
	var window: int = _room_and_guard()
	var wall: int = _build.cell_piece_at(BuildSystem.cell_of(_at(-1, 0, 0)))
	assert_false(_sensors.install(&"power_monitor", wall, 1), "not on a wall")
	assert_false(_sensors.install(&"zz_nothing", window, 1), "not an unknown sensor")
	assert_false(_sensors.install(&"power_monitor", window, 0), "not for squad 0")
	assert_true(_sensors.install(&"power_monitor", window, 1), "installed")
	assert_false(_sensors.install(&"power_monitor", window, 1), "not twice")
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(other, _sim.snapshot()), OK, "restores")
	assert_true(SimAssembly.sensors_of(other).has_sensor(window), "the sensor is kept")
	var bad: Dictionary = _sensors.snapshot().duplicate(true)
	var recs: Dictionary = bad["sensors"]
	var rec: Dictionary = recs[window]
	rec["squad"] = 0
	assert_eq(SimAssembly.sensors_of(other).restore(bad), ERR_INVALID_DATA, "squad 0 is rejected")


func test_a_sensor_naming_an_unknown_trigger_stops_assembly() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	assert_eq(db.add(&"sensor", &"zz_seismic", {"schema_version": 1, "description": "x", "triggers": ["stomped"], "radio_latency_ticks": 0}), OK, "a sensor")
	assert_true(SimAssembly.build(SEED, db) == null, "refused")
