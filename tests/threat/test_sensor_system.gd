extends GcityTest

## M6 spec claim 10 (and claim 8's heat side): sensors are content, placed by a site.
## An edge sensor trips when an intruder crosses its face, a volume sensor when one
## enters its cells, a credential sensor when its door's check is flagged for heat.
## A trip is `sensor.tripped`, warms the intruder, and on a radio sensor reaches the
## site's squad at once. A spoofed sensor stays quiet until its spoof runs out. Agents
## do not trip their own site's sensors. The lobby camera is an agent that sees.
##
## The test site, far out in badlands at FAR_CELL = (500, 0, 500): a wall line on the
## x = 0 / x = 1 faces, a window at z 0 (power monitor), a wall at z 1, a card door at
## z 2 with a heat limit (door reader); a floor plate over cells (5, 0, 5) and
## (5, 0, 6); two guards of squad 1 far off.

const SEED: int = 20261180
const M: int = 1000
const FAR_CELL: Vector3i = Vector3i(500, 0, 500)
const TAG: StringName = &"access.test"

var _sim: SimRoot
var _actors: ActorSystem
var _movement: MovementSystem
var _perception: PerceptionSystem
var _sensors: SensorSystem
var _standing: StandingSystem
var _items: ItemSystem
var _player: int = 0
var _tripped: Array[Dictionary] = []
var _reports: Array[Dictionary] = []


func _content() -> ContentDb:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	assert_eq(db.add(&"build_piece", &"zz_front_door", {
		"schema_version": 1, "description": "A card door with a heat limit.", "kind": "door",
		"material": "scrap_steel", "open_cost": 40, "value": 0, "lock": {"requires_tag": String(TAG), "heat_max": 2000},
	}), OK, "the door")
	assert_eq(db.add(ItemSystem.KIND_TOOL, &"zz_card", {
		"schema_version": 1, "description": "Its card.", "tool_class": "cutter", "tags": [String(TAG)], "stats": [],
	}), OK, "its card")
	assert_eq(db.add(&"sensor", &"zz_plate", {"schema_version": 1, "description": "A floor plate.", "watches": "volume", "radio": false, "spoofable": false}), OK, "a plate")
	assert_eq(db.add(SiteSystem.KIND_SITE, &"zz_watched", {
		"schema_version": 1, "description": "A watched wall.", "origin": [500, 0, 500], "parcels": [],
		"pieces": [
			{"piece": "foundation_block", "cell": [0, 0, -1], "facing": ""},
			{"piece": "foundation_block", "cell": [0, 0, 3], "facing": ""},
			{"piece": "window_frame", "cell": [0, 0, 0], "facing": "px"},
			{"piece": "wall_panel", "cell": [0, 0, 1], "facing": "px"},
			{"piece": "zz_front_door", "cell": [0, 0, 2], "facing": "px"},
		],
		"points": [],
		"agents": [
			{"profile": "guard_sim", "cell": [-30, 0, 0], "facing": 180, "squad": 1, "route": ""},
			{"profile": "guard_sim", "cell": [-30, 0, 4], "facing": 180, "squad": 1, "route": ""},
		],
		"sensors": [
			{"sensor": "power_monitor", "squad": 1, "cell": [0, 0, 0], "facing": "px", "cells": []},
			{"sensor": "door_reader", "squad": 1, "cell": [0, 0, 2], "facing": "px", "cells": []},
			{"sensor": "zz_plate", "squad": 0, "cell": [0, 0, 0], "facing": "", "cells": [[5, 0, 5], [5, 0, 6]]},
		],
	}), OK, "the site")
	return db


func _setup(db: ContentDb = null) -> void:
	if db == null:
		db = _content()
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_movement = SimAssembly.movement_of(_sim)
	_perception = SimAssembly.perception_of(_sim)
	_sensors = SimAssembly.sensors_of(_sim)
	_standing = SimAssembly.standing_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, _floor_of(_c(-1, 0, 0)))
	var tripped: Array[Dictionary] = []
	var reports: Array[Dictionary] = []
	_tripped = tripped
	_reports = reports
	var events: EventBus = SimAssembly.combat_of(_sim).events()
	events.subscribe(SensorSystem.EVENT_TRIPPED, func(p: Dictionary) -> void: tripped.append(p))
	events.subscribe(SquadSystem.EVENT_REPORT, func(p: Dictionary) -> void: reports.append(p))
	_sim.submit(SimCommand.new(_sim.get_tick() + 1, SiteSystem.COMMAND_RAISE, {"site": "zz_watched"}))
	_sim.step()
	assert_eq(_sim.rejected_count(), 0, "the site is raised")


func _c(x: int, y: int, z: int) -> Vector3i:
	return FAR_CELL + Vector3i(x, y, z)


static func _floor_of(cell: Vector3i) -> Vector3i:
	return Vector3i(cell.x * M + M / 2, cell.y * M, cell.z * M + M / 2)


## Walks an actor along x by `steps` capped steps, one sim tick each.
func _walk(actor: int, dx: int, dz: int, steps: int) -> void:
	for i: int in steps:
		_sim.submit(SimCommand.new(_sim.get_tick() + 1, &"actor.move", {"actor": actor, "dx": dx, "dz": dz}))
		_sim.step()


func _sensor(profile: StringName) -> int:
	for id: int in _sensors.sensor_ids():
		if _sensors.profile_of(id) == profile:
			return id
	return EntityIds.NONE


func test_the_site_places_its_sensors() -> void:
	_setup()
	assert_eq(_sensors.sensor_ids().size(), 3, "three sensors")
	assert_true(_sensor(&"power_monitor") > 0 and _sensor(&"door_reader") > 0 and _sensor(&"zz_plate") > 0, "one of each")


func test_crossing_the_watched_window_trips_it_warms_the_intruder_and_tells_the_squad() -> void:
	_setup()
	var monitor: int = _sensor(&"power_monitor")
	_actors.set_position(_player, _floor_of(_c(0, 0, 0)))
	_walk(_player, 150, 0, 3)
	assert_eq(_tripped.size(), 0, "short of the window: nothing")
	_walk(_player, 150, 0, 1)
	assert_eq(_tripped.size(), 1, "one trip")
	var trip: Dictionary = _tripped[0]
	var sensor: int = trip["sensor"]
	var actor: int = trip["actor"]
	assert_eq(sensor, monitor, "the power monitor")
	assert_eq(actor, _player, "by the player")
	assert_true(_standing.value_of(_player, &"heat") > 1400, "who is warmer for it")
	assert_eq(_reports.size(), 1, "the squad heard over the radio")
	var informed: Array = _reports[0]["informed"]
	assert_eq(informed.size(), 2, "both guards")
	_walk(_player, 150, 0, 4)
	assert_eq(_tripped.size(), 1, "walking on inside is no second trip")


func test_a_spoofed_monitor_stays_quiet_until_the_spoof_runs_out() -> void:
	_setup()
	var monitor: int = _sensor(&"power_monitor")
	assert_true(_sensors.spoof(monitor, _sim.get_tick() + 100), "spoofed for 100 ticks")
	assert_false(_sensors.spoof(_sensor(&"door_reader"), _sim.get_tick() + 100), "a door reader cannot be spoofed")
	_actors.set_position(_player, _floor_of(_c(0, 0, 0)))
	_walk(_player, 150, 0, 4)
	assert_eq(_tripped.size(), 0, "through the window unseen")
	_walk(_player, -150, 0, 4)
	assert_eq(_tripped.size(), 0, "and back")
	_sim.step_n(100)
	_walk(_player, 150, 0, 4)
	assert_eq(_tripped.size(), 1, "the spoof ran out: tripped")


func test_the_plate_trips_on_entry_not_on_standing_and_again_on_return() -> void:
	_setup()
	_actors.set_position(_player, _floor_of(_c(5, 0, 4)))
	_walk(_player, 0, 150, 4)
	assert_eq(_tripped.size(), 1, "stepping onto the plate")
	_walk(_player, 0, 150, 6)
	assert_eq(BuildSystem.cell_of(_actors.position_of(_player)), _c(5, 0, 6), "on its second cell")
	assert_eq(_tripped.size(), 1, "crossing from one plate cell to the next is not an entry")
	_walk(_player, 0, 150, 7)
	_walk(_player, 0, -150, 7)
	assert_eq(_tripped.size(), 2, "off and back on is a second")
	assert_eq(_reports.size(), 0, "a plate with no radio tells nobody")


func test_the_door_reader_trips_only_on_a_hot_card() -> void:
	_setup()
	_items.spawn(ItemSystem.KIND_TOOL, &"zz_card", ItemSystem.inventory_of(_player), 1)
	_actors.set_position(_player, _floor_of(_c(0, 0, 2)))
	_walk(_player, 150, 0, 4)
	assert_eq(_tripped.size(), 0, "a cold card: silence")
	_standing.raise(_player, &"heat", 5000)
	_walk(_player, -150, 0, 4)
	assert_eq(_tripped.size(), 1, "a hot card: the reader trips")
	var sensor: int = _tripped[0]["sensor"]
	assert_eq(sensor, _sensor(&"door_reader"), "the door reader")
	assert_eq(_reports.size(), 1, "and radios it")


func test_guards_do_not_trip_their_own_sensors() -> void:
	_setup()
	var guard: int = _perception.agent_ids()[0]
	_actors.set_position(guard, _floor_of(_c(0, 0, 0)))
	for i: int in 3:
		_movement.move(guard, 60, 0)
	for i: int in 20:
		_movement.move(guard, 60, 0)
	assert_eq(_tripped.size(), 0, "a guard through the window trips nothing")


func test_the_lobby_camera_sees_and_radios() -> void:
	_setup()
	var camera: int = _perception.spawn(&"lobby_camera", _c(-10, 0, 20), 0, 1, "")
	assert_true(camera > 0, "a camera agent")
	_actors.set_position(_player, _floor_of(_c(-6, 0, 20)))
	var ticks: int = 0
	while not _perception.is_alerted(camera, _player) and ticks < 200:
		_sim.step()
		ticks += 1
		_actors.set_position(_player, _floor_of(_c(-6, 0, 20)))
	assert_true(_perception.is_alerted(camera, _player), "the camera sees the player (%d ticks)" % ticks)
	_sim.step_n(3)
	assert_true(_reports.size() >= 1, "and radios it")
	assert_eq(SimAssembly.actors_of(_sim).wielded(camera), EntityIds.NONE, "a camera holds no weapon")


func test_assembly_refuses_a_site_sensor_that_cannot_watch_what_it_names() -> void:
	for bad: Dictionary in [
		{"sensor": "nowhere", "squad": 1, "cell": [0, 0, 0], "facing": "px", "cells": []},
		{"sensor": "power_monitor", "squad": 1, "cell": [0, 0, 0], "facing": "py", "cells": []},
		{"sensor": "power_monitor", "squad": 1, "cell": [0, 0, 0], "facing": "", "cells": []},
		{"sensor": "zz_plate", "squad": 0, "cell": [0, 0, 0], "facing": "", "cells": []},
		{"sensor": "door_reader", "squad": -1, "cell": [0, 0, 2], "facing": "px", "cells": []},
	]:
		var db: ContentDb = _content()
		var site: Dictionary = db.get_entry(SiteSystem.KIND_SITE, &"zz_watched").duplicate(true)
		site["sensors"] = [bad]
		assert_eq(db.add(SiteSystem.KIND_SITE, &"zz_bad", site), OK, "the db takes the shape")
		assert_true(SimAssembly.build(SEED, db) == null, "assembly refuses %s" % [bad])


func test_sensors_survive_the_save_round_trip_and_bad_state_is_refused() -> void:
	_setup()
	var monitor: int = _sensor(&"power_monitor")
	_sensors.spoof(monitor, _sim.get_tick() + 50)
	var db: ContentDb = _sim.get_system(&"content")
	var loaded: SimRoot = SimAssembly.load_save(SaveFile.parse(SaveFile.serialize(_sim, db.digest())), db)
	assert_true(loaded != null, "loads")
	assert_eq(loaded.state_hash(), _sim.state_hash(), "the same state")
	var state: Dictionary = _sensors.snapshot()
	var all: Dictionary = state["sensors"]
	var rec: Dictionary = all[monitor]
	var fresh: SensorSystem = SimAssembly.sensors_of(SimAssembly.build(SEED, db))
	for bad: Dictionary in [
		{}, {"sensors": [], "tripped": 0}, {"sensors": {}, "tripped": -1},
		{"sensors": {"1": rec}, "tripped": 0},
		{"sensors": {monitor: {"profile": "nowhere"}}, "tripped": 0},
		{"sensors": {}, "tripped": 0, "x": 1},
	]:
		assert_eq(fresh.restore(bad), ERR_INVALID_DATA, "rejects %s" % [bad])
