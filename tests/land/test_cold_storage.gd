extends GcityTest

## M6 spec claim 13: Cold Storage, authored as content/site/cold_storage.json. Three
## storeys on a docklands parcel where outsiders may not enter, with the city's service
## tunnel on its own vertical parcel under the street. Three ways in: the keycard front
## door watched by the lobby camera; the yard crate up to the storey-1 maintenance window,
## whose power monitor's junction box is in the yard; and under, by the street grate, the
## tunnel, a grate into the basement and the stairs. The under route is the only one that
## never enters the lobby camera's view. Five guards and the camera; the server-room
## terminal yields the records.

const SEED: int = 20261039
const O: Vector3i = Vector3i(600, 0, 600)

## The under route, cell by cell, from the street over the grate to the terminal.
const UNDER: Array[Vector3i] = [
	Vector3i(1, 0, -3),
	Vector3i(1, -1, -3), Vector3i(2, -1, -3), Vector3i(3, -1, -3), Vector3i(4, -1, -3), Vector3i(4, -1, -2), Vector3i(4, -1, -1),
	Vector3i(4, -1, 0), Vector3i(4, -1, 1), Vector3i(4, -1, 2), Vector3i(4, -1, 3), Vector3i(4, -1, 4), Vector3i(5, -1, 4), Vector3i(6, -1, 4), Vector3i(7, -1, 4),
	Vector3i(7, 0, 5), Vector3i(8, 0, 5), Vector3i(9, 0, 5),
	Vector3i(9, 1, 6), Vector3i(8, 1, 5), Vector3i(7, 1, 5), Vector3i(6, 1, 5), Vector3i(5, 1, 5),
	Vector3i(3, 1, 5), Vector3i(2, 1, 5), Vector3i(2, 1, 6),
]

var _sim: SimRoot


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	assert_true(SimAssembly.sites_of(_sim).spawn(&"cold_storage", O), "Cold Storage spawns")


func _feet(c: Vector3i) -> Vector3i:
	return BuildSystem.cell_centre(O + c) - Vector3i(0, BuildSystem.CELL / 2, 0)


func _camera() -> int:
	var perception: PerceptionSystem = SimAssembly.perception_of(_sim)
	for a: int in perception.agent_ids():
		if perception.profile_of(a) == &"camera":
			return a
	return EntityIds.NONE


func test_the_site_is_three_storeys_of_private_docklands_over_a_city_tunnel() -> void:
	_setup()
	var land: LandSystem = SimAssembly.land_of(_sim)
	var building: StringName = SiteSystem.parcel_id(&"cold_storage", "building")
	var utility: StringName = SiteSystem.parcel_id(&"cold_storage", "utility")
	assert_eq(land.district_of(building), &"docklands", "docklands")
	assert_eq(land.owner_of(building), &"cold_storage_corp", "owned by Cold Storage")
	assert_eq(land.owner_of(utility), &"city", "the tunnel is the city's")
	assert_eq(land.parcel_at(_feet(Vector3i(2, -1, -3))), utility, "in the tunnel you are on the city's parcel")
	assert_eq(land.parcel_at(_feet(Vector3i(2, 0, -3))), &"", "on the street above it you are on no parcel (vertical parcels, §15.2)")
	assert_eq(land.parcel_at(_feet(Vector3i(3, 1, 3))), building, "upstairs is the building")
	var stranger: int = SimAssembly.actors_of(_sim).spawn(&"arcade", 0)
	var rights: Dictionary = land.rights_at(_feet(Vector3i(5, 0, 5)), stranger)
	var may_enter: bool = rights[&"enter"]
	assert_false(may_enter, "an outsider may not enter: being seen inside is trespass")
	var build: BuildSystem = SimAssembly.build_of(_sim)
	for c: Vector3i in [Vector3i(5, -1, 3), Vector3i(5, 0, 5), Vector3i(5, 1, 5)]:
		assert_true(build.is_standable(O + c), "storey %d stands" % c.y)


func test_five_guards_and_a_camera_and_the_terminal() -> void:
	_setup()
	var perception: PerceptionSystem = SimAssembly.perception_of(_sim)
	var guards: int = 0
	var storeys: Dictionary = {}
	for a: int in perception.agent_ids():
		if perception.profile_of(a) == &"guard_sim":
			guards += 1
			storeys[BuildSystem.cell_of(SimAssembly.actors_of(_sim).position_of(a)).y] = true
	assert_eq(guards, 5, "five guards")
	assert_true(_camera() != EntityIds.NONE, "and the lobby camera")
	assert_eq(storeys.keys().size(), 3, "on all three storeys")
	var targets: Dictionary = SimAssembly.hacks_of(_sim).snapshot()["targets"]
	var names: Array[String] = []
	for k: Variant in targets:
		var rec: Dictionary = targets[k]
		var n: String = rec["target"]
		names.append(n)
	names.sort()
	assert_eq(names, ["cold_storage_terminal", "power_monitor_spoof"] as Array[String], "the terminal and the monitor's junction box")


func test_the_front_door_is_the_keycard_door_watched_by_the_camera() -> void:
	_setup()
	var build: BuildSystem = SimAssembly.build_of(_sim)
	var door: int = build.face_piece_at(BuildSystem.face_key(O + Vector3i(2, 0, 0), "nz"))
	assert_eq(build.template_of(door), &"cold_storage_door", "the keycard door")
	assert_false(build.is_open(door), "shut")
	assert_true(SimAssembly.sensors_of(_sim).has_sensor(door), "watched")


func test_the_side_route_crate_window_and_junction_box_line_up() -> void:
	_setup()
	var build: BuildSystem = SimAssembly.build_of(_sim)
	var window: int = build.face_piece_at(BuildSystem.face_key(O + Vector3i(9, 1, 1), "px"))
	assert_eq(build.template_of(window), &"window_frame", "the maintenance window on storey 1")
	assert_true(SimAssembly.sensors_of(_sim).has_sensor(window), "with its power monitor")
	var player: int = SimAssembly.actors_of(_sim).spawn(&"arcade", 0)
	SimAssembly.actors_of(_sim).set_position(player, _feet(Vector3i(11, 0, 1)))
	assert_true(SimAssembly.movement_of(_sim).mantle(player, -1, 0), "the yard crate can be mantled")
	_sim.step_n(60)
	assert_eq(BuildSystem.cell_of(SimAssembly.actors_of(_sim).position_of(player)), O + Vector3i(10, 1, 1), "on the crate, at the window")
	assert_true(build.cells_of_piece(window).has(O + Vector3i(10, 1, 1)), "standing in the window's outer cell")
	var targets: Dictionary = SimAssembly.hacks_of(_sim).snapshot()["targets"]
	for k: Variant in targets:
		var rec: Dictionary = targets[k]
		if rec["target"] == &"power_monitor_spoof":
			assert_eq(rec["piece"], window, "the junction box is tied to the window")
			assert_eq(rec["cell"], [O.x + 11, 0, O.z + 2] as Array[int], "in the yard, on the ground")


func test_the_under_route_never_enters_the_lobby_cameras_view() -> void:
	_setup()
	var perception: PerceptionSystem = SimAssembly.perception_of(_sim)
	var actors: ActorSystem = SimAssembly.actors_of(_sim)
	var build: BuildSystem = SimAssembly.build_of(_sim)
	var camera: int = _camera()
	var dummy: int = actors.spawn(&"range_dummy", 0)
	for c: Vector3i in UNDER:
		assert_true(build.is_standable(O + c), "the under route is walkable at %s" % c)
	var content: ContentDb = _sim.get_system(ContentDb.SYSTEM_ID)
	var sweep: Dictionary = content.get_entry(&"agent_profile", &"camera")["sweep"]
	var period: int = sweep["period_ticks"]
	var seen: Array[Vector3i] = []
	var lobby_seen: bool = false
	for t: int in period:
		_sim.step()
		for c: Vector3i in UNDER:
			actors.set_position(dummy, _feet(c))
			if perception.can_see(camera, dummy) and not seen.has(c):
				seen.append(c)
		actors.set_position(dummy, _feet(Vector3i(2, 0, 1)))
		lobby_seen = lobby_seen or perception.can_see(camera, dummy)
	assert_eq(seen, [] as Array[Vector3i], "no cell of the under route is ever in the camera's view")
	assert_true(lobby_seen, "while the lobby, inside the front door, is (the check bites)")


func test_the_roamer_walks_between_storeys_and_nobody_is_stuck() -> void:
	_setup()
	var perception: PerceptionSystem = SimAssembly.perception_of(_sim)
	var actors: ActorSystem = SimAssembly.actors_of(_sim)
	var roamer: int = EntityIds.NONE
	for a: int in perception.agent_ids():
		if perception.route_of(a) == "cold_storage_stairs":
			roamer = a
	assert_true(roamer != EntityIds.NONE, "the roamer")
	var storeys: Dictionary = {}
	for i: int in 2400:
		_sim.step()
		storeys[BuildSystem.cell_of(actors.position_of(roamer)).y] = true
	assert_true(storeys.has(0) and storeys.has(1), "it climbs between the hall and storey 1 (%s)" % str(storeys.keys()))
	assert_eq(SimAssembly.movement_of(_sim).blocked_count(), 0, "no guard's step was ever blocked")


func test_the_tunnel_hatch_is_a_way_out_not_a_way_in() -> void:
	_setup()
	var build: BuildSystem = SimAssembly.build_of(_sim)
	var actors: ActorSystem = SimAssembly.actors_of(_sim)
	var hatch: int = build.face_piece_at(BuildSystem.face_key(O + Vector3i(2, -1, -3), "py"))
	assert_eq(build.template_of(hatch), &"tunnel_hatch", "the access hatch beside the street grate")
	var player: int = actors.spawn(&"arcade", 0)
	actors.set_position(player, _feet(Vector3i(2, 0, -3)))
	_sim.step_n(5)
	assert_false(SimAssembly.movement_of(_sim).climb(player, hatch), "not down it from the street")
	actors.set_position(player, _feet(Vector3i(2, -1, -3)))
	_sim.step_n(5)
	assert_true(SimAssembly.movement_of(_sim).climb(player, hatch), "up it from the tunnel")
	_sim.step_n(build.climb_ticks_of(hatch) + 2)
	assert_eq(BuildSystem.cell_of(actors.position_of(player)), O + Vector3i(2, 0, -3), "out on the street")
