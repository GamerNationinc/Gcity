extends GcityTest

## M3 spec claim 9: a dumb token follows the raid plan, spends edge cost in ticks,
## breaches walls, replans after each crossing and arrives at the target's volume.

const SEED: int = 20261007
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)
const CUTTER: StringName = &"cutter"

var _sim: SimRoot
var _build: BuildSystem
var _portals: PortalGraph
var _raids: RaidTokenSystem
var _player: int = 0
var _events: Array[Dictionary] = []


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	_build = SimAssembly.build_of(_sim)
	_portals = SimAssembly.portals_of(_sim)
	_raids = SimAssembly.raids_of(_sim)
	_player = SimAssembly.actors_of(_sim).spawn(&"arcade", 0)
	var sink: Array[Dictionary] = []
	_events = sink
	var bus: EventBus = SimAssembly.combat_of(_sim).events()
	bus.subscribe(RaidTokenSystem.EVENT_BREACHED, func(p: Dictionary) -> void: sink.append(p))
	bus.subscribe(RaidTokenSystem.EVENT_ARRIVED, func(p: Dictionary) -> void: sink.append(p))


func _at(cx: int, cy: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, cy * M + 500, cz * M + 500)


func _place(template: StringName, cx: int, cy: int, cz: int, facing: String) -> int:
	var id: int = _build.place(_player, template, _at(cx, cy, cz), facing)
	assert_true(id > 0, "place %s at (%d, %d, %d) %s" % [template, cx, cy, cz, facing])
	return id


func _room(with_door: bool) -> Dictionary:
	for x: int in 3:
		for z: int in 3:
			_place(&"foundation_block", x, 0, z, "")
	var door: int = 0
	for i: int in 3:
		_place(&"wall_panel", 0, 1, i, "nx")
		_place(&"wall_panel", 2, 1, i, "px")
		_place(&"wall_panel", i, 1, 2, "pz")
		if i == 1 and with_door:
			door = _place(&"door_frame", i, 1, 0, "nz")
		else:
			_place(&"wall_panel", i, 1, 0, "nz")
	for x: int in 3:
		for z: int in 3:
			_place(&"floor_panel", x, 1, z, "py")
	var crate: int = _place(&"storage_crate", 1, 1, 1, "")
	return {"door": door, "crate": crate}


func test_no_target_no_token() -> void:
	_setup()
	assert_eq(_raids.spawn(CUTTER), 0, "nothing to raid")
	assert_eq(_raids.spawn(&"spoon"), 0, "unknown tool")


func test_token_walks_through_the_door_in_four_ticks_and_arrives() -> void:
	_setup()
	var r: Dictionary = _room(true)
	var token: int = _raids.spawn(CUTTER)
	assert_true(token > 0, "token spawned")
	assert_eq(_raids.state_of(token), "moving", "moving")
	assert_eq(_raids.cell_of(token), BuildSystem.cell_of(_at(1, 1, -1)), "starts outside the door")
	_sim.step_n(3)
	assert_eq(_raids.state_of(token), "moving", "door costs 40: not through after 3 ticks (30)")
	_sim.step_n(2)
	assert_eq(_raids.state_of(token), "arrived", "through the door and in the crate's volume")
	assert_eq(_raids.cell_of(token), BuildSystem.cell_of(_at(1, 1, 0)), "inside")
	var door: int = r["door"]
	assert_true(_build.has_piece(door), "the door was passed, not breached")
	assert_eq(_events.size(), 1, "one arrival event, no breach")
	assert_eq(_events[0]["target"], r["crate"], "arrived at the crate")


func test_token_breaches_a_sealed_room_at_the_cheapest_wall() -> void:
	_setup()
	var r: Dictionary = _room(false)
	var plan: Dictionary = _portals.raid_plan(CUTTER)
	assert_eq(plan["cost"], 1100, "one wall to cut")
	var token: int = _raids.spawn(CUTTER)
	var pieces_before: int = _build.piece_ids().size()
	_sim.step_n(109)
	assert_eq(_raids.state_of(token), "moving", "1100 / 10 = 110 ticks: not yet")
	assert_true(_build.piece_ids().size() == pieces_before, "nothing breached yet")
	_sim.step_n(2)
	assert_eq(_raids.state_of(token), "arrived", "breached and in")
	assert_eq(_build.piece_ids().size(), pieces_before - 1, "exactly one wall gone")
	assert_eq(_events.size(), 2, "breach then arrival")
	assert_eq(_events[0]["piece"], plan["pieces"][0], "the planned wall was the one breached")
	assert_eq(_raids.token(token)["breached"], 1, "counted")
	var crate: int = r["crate"]
	assert_true(_build.has_piece(crate), "the crate itself is untouched")


func test_token_replans_when_the_player_seals_the_door_mid_raid() -> void:
	_setup()
	var r: Dictionary = _room(true)
	var token: int = _raids.spawn(CUTTER)
	_sim.step_n(2)
	var door: int = r["door"]
	_build.breach(door)
	_place(&"wall_panel", 1, 1, 0, "nz")
	_sim.step_n(1)
	assert_eq(_raids.state_of(token), "moving", "still coming")
	var crossing: int = _raids.token(token)["crossing"]
	assert_true(crossing != door, "no longer crossing the vanished door")
	_sim.step_n(120)
	assert_eq(_raids.state_of(token), "arrived", "cut through instead")
	assert_eq(_raids.token(token)["breached"], 1, "one breach")


func test_command_and_restore() -> void:
	_setup()
	_room(true)
	assert_false(_do(RaidTokenSystem.COMMAND_SPAWN, {}), "missing tool")
	assert_false(_do(RaidTokenSystem.COMMAND_SPAWN, {"tool": "spoon"}), "unknown tool")
	assert_true(_do(RaidTokenSystem.COMMAND_SPAWN, {"tool": "cutter"}), "spawn")
	_sim.step_n(2)
	var full: Dictionary = _sim.snapshot()
	var db := ContentDb.new()
	ContentLoader.load_all(db)
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(other, full), OK, "restore")
	assert_eq(StateHash.of(SimAssembly.raids_of(other).snapshot()), StateHash.of(_raids.snapshot()), "identical tokens")
	var bad: Dictionary = _raids.snapshot().duplicate(true)
	var tokens: Dictionary = bad["tokens"]
	var rec: Dictionary = tokens[1]
	rec["state"] = "flying"
	assert_eq(SimAssembly.raids_of(other).restore(bad), ERR_INVALID_DATA, "unknown state rejected")


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1
