extends GcityTest

## M3 spec claim 9: a dumb token follows the raid plan, spends edge cost in ticks,
## breaches walls, replans after each crossing and arrives at the target's volume.
## Since M7.5 (gate item 2) a token crosses as a person: where one fits and can stand on
## both sides, through both faces of a person's height, so the rooms here are a storey
## tall on the ground and a door is two door faces.

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


## A 3 × 3 room on the ground, a storey tall: foundations at its outer corners, walls of
## three faces, a 2 m door (two door faces under a wall face) in the middle of the south
## side when `with_door`, the roof on top, and a crate inside. "door" is the bottom face.
func _room(with_door: bool) -> Dictionary:
	for corner: Vector3i in [Vector3i(-1, 0, -1), Vector3i(3, 0, -1), Vector3i(-1, 0, 3), Vector3i(3, 0, 3)]:
		_place(&"foundation_block", corner.x, corner.y, corner.z, "")
	var doors: Array[int] = []
	for i: int in 3:
		for row: int in 3:
			_place(&"wall_panel", 0, row, i, "nx")
			_place(&"wall_panel", 2, row, i, "px")
			_place(&"wall_panel", i, row, 2, "pz")
			if i == 1 and with_door and row < 2:
				doors.append(_place(&"door_frame", i, row, 0, "nz"))
			else:
				_place(&"wall_panel", i, row, 0, "nz")
	for x: int in 3:
		for z: int in 3:
			_place(&"floor_panel", x, 2, z, "py")
	var crate: int = _place(&"storage_crate", 1, 0, 1, "")
	return {"door": doors[0] if not doors.is_empty() else 0, "doors": doors, "crate": crate}


## Takes out the two lowest faces of the south side's middle column and puts `piece` in
## their place: a person's height of it.
func _swap_south_middle(piece: StringName) -> void:
	for row: int in 2:
		var at: int = _build.face_piece_at(BuildSystem.face_key(BuildSystem.cell_of(_at(1, row, 0)), "nz"))
		if at != EntityIds.NONE:
			_build.breach(at)
		_place(piece, 1, row, 0, "nz")


func test_no_target_no_token() -> void:
	_setup()
	assert_eq(_raids.spawn(CUTTER), 0, "nothing to raid")
	assert_eq(_raids.spawn(&"spoon"), 0, "unknown tool")


func test_token_walks_through_the_door_in_eight_ticks_and_arrives() -> void:
	_setup()
	var r: Dictionary = _room(true)
	var token: int = _raids.spawn(CUTTER)
	assert_true(token > 0, "token spawned")
	assert_eq(_raids.state_of(token), "moving", "moving")
	assert_eq(_raids.cell_of(token), BuildSystem.cell_of(_at(1, 0, -1)), "starts outside the door")
	assert_eq(_raids.plan(CUTTER)["cost"], 80, "a 2 m door: two door faces at 40")
	_sim.step_n(7)
	assert_eq(_raids.state_of(token), "moving", "not through after 7 ticks (70)")
	_sim.step_n(2)
	assert_eq(_raids.state_of(token), "arrived", "through the door and in the crate's volume")
	assert_eq(_raids.cell_of(token), BuildSystem.cell_of(_at(1, 0, 0)), "inside")
	for door: int in r["doors"]:
		assert_true(_build.has_piece(door), "the door was passed, not breached")
	assert_eq(_events.size(), 1, "one arrival event, no breach")
	assert_eq(_events[0]["target"], r["crate"], "arrived at the crate")


func test_token_breaches_a_sealed_room_at_the_cheapest_wall() -> void:
	_setup()
	var r: Dictionary = _room(false)
	var plan: Dictionary = _raids.plan(CUTTER)
	assert_eq(plan["cost"], 2200, "a person's height of wall to cut: two panels")
	assert_eq(_portals.raid_plan(CUTTER)["cost"], 1100, "where the face-by-face graph would cut one, a gap nobody fits")
	var token: int = _raids.spawn(CUTTER)
	var pieces_before: int = _build.piece_ids().size()
	_sim.step_n(219)
	assert_eq(_raids.state_of(token), "moving", "2200 / 10 = 220 ticks: not yet")
	assert_true(_build.piece_ids().size() == pieces_before, "nothing breached yet")
	_sim.step_n(2)
	assert_eq(_raids.state_of(token), "arrived", "breached and in")
	assert_eq(_build.piece_ids().size(), pieces_before - 2, "exactly two panels gone")
	assert_eq(_events.size(), 3, "two breaches then arrival")
	assert_eq(_events[0]["piece"], plan["pieces"][0], "the planned wall was the one breached, bottom first")
	assert_eq(_raids.token(token)["breached"], 2, "counted")
	var crate: int = r["crate"]
	assert_true(_build.has_piece(crate), "the crate itself is untouched")


func test_token_replans_when_the_player_seals_the_door_mid_raid() -> void:
	_setup()
	var r: Dictionary = _room(true)
	var token: int = _raids.spawn(CUTTER)
	_sim.step_n(2)
	var door: int = r["door"]
	_swap_south_middle(&"wall_panel")
	_sim.step_n(1)
	assert_eq(_raids.state_of(token), "moving", "still coming")
	var crossing: int = _raids.token(token)["crossing"]
	assert_true(crossing != door, "no longer crossing the vanished door")
	_sim.step_n(230)
	assert_eq(_raids.state_of(token), "arrived", "cut through instead")
	assert_eq(_raids.token(token)["breached"], 2, "a person's height breached: two panels")


func test_token_switches_to_a_door_the_player_opens_mid_cut() -> void:
	_setup()
	_room(false)
	var token: int = _raids.spawn(CUTTER)
	_sim.step_n(20)
	var rec: Dictionary = _raids.token(token)
	var crossing: int = rec["crossing"]
	assert_true(crossing > 0, "cutting a wall")
	assert_eq(rec["progress"], 200, "twenty ticks in")
	# the player opens a door on the far side
	_swap_south_middle(&"door_frame")
	_sim.step_n(1)
	assert_eq(_raids.token(token)["progress"], 10, "progress reset: the plan changed")
	_sim.step_n(10)
	assert_eq(_raids.state_of(token), "arrived", "through the new door")
	assert_eq(_raids.token(token)["breached"], 0, "nothing breached")


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


## Found by the G7 mutation run: every restored token had already made progress, so a
## restore refusing one that had not started went unnoticed.
func test_a_token_that_has_not_started_restores() -> void:
	_setup()
	_room(true)
	var token: int = _raids.spawn(CUTTER)
	assert_eq(_raids.token(token)["progress"], 0, "nothing done yet")
	assert_eq(_raids.token(token)["breached"], 0, "nothing breached yet")
	var db := ContentDb.new()
	ContentLoader.load_all(db)
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(other, _sim.snapshot()), OK, "restore")
	assert_eq(StateHash.of(SimAssembly.raids_of(other).snapshot()), StateHash.of(_raids.snapshot()), "identical tokens")


## Found by the G7 mutation run: no test left a token with no way to its target.
## A crate set down on the cell it stands in does.
func test_a_token_built_over_where_it_stands_fails() -> void:
	_setup()
	_room(true)
	var token: int = _raids.spawn(CUTTER)
	_sim.step()
	_place(&"foundation_block", 1, 0, -1, "")
	assert_eq(_portals.node_at(_raids.cell_of(token)), PortalGraph.SOLID, "the token stands in solid ground")
	_sim.step()
	assert_eq(_raids.state_of(token), "failed", "it has nowhere to go")


## Found by the G7 mutation run: every way in cost something, so a raid plan costing
## nothing was never walked. A stair flight set in a wall is an opening that costs
## nothing to pass; a token finds that plan and walks it.
func test_a_token_walks_a_plan_that_costs_nothing() -> void:
	_setup()
	_room(true)
	# a flight at the foot of the doorway and nothing over it: a person's height open
	_swap_south_middle(&"stair_flight")
	var top: int = _build.face_piece_at(BuildSystem.face_key(BuildSystem.cell_of(_at(1, 1, 0)), "nz"))
	_build.breach(top)
	var plan: Dictionary = _raids.plan(CUTTER)
	assert_eq(plan["cost"], 0, "in through the stair for nothing")
	var token: int = _raids.spawn(CUTTER)
	assert_true(token > 0, "token spawned")
	_sim.step_n(3)
	assert_eq(_raids.state_of(token), "arrived", "and in")
	assert_eq(_raids.token(token)["breached"], 0, "nothing breached")


## M7.5 gate item 2: a door a metre high under a wall is no person's way in. The token
## goes through it, and through the wall panel over it, which it cuts.
func test_a_one_metre_door_costs_the_panel_over_it() -> void:
	_setup()
	_room(false)
	var bottom: int = _build.face_piece_at(BuildSystem.face_key(BuildSystem.cell_of(_at(1, 0, 0)), "nz"))
	_build.breach(bottom)
	var low_door: int = _place(&"door_frame", 1, 0, 0, "nz")
	var above: int = _build.face_piece_at(BuildSystem.face_key(BuildSystem.cell_of(_at(1, 1, 0)), "nz"))
	assert_true(above > 0, "a wall panel over the door")
	var plan: Dictionary = _raids.plan(CUTTER)
	assert_eq(plan["cost"], 40 + 1100, "the door and the panel over it")
	var token: int = _raids.spawn(CUTTER)
	_sim.step_n(116)
	assert_eq(_raids.state_of(token), "arrived", "in, through a person-high gap")
	assert_true(_build.has_piece(low_door), "the door passed, not cut")
	assert_false(_build.has_piece(above), "the panel over it cut")
	assert_eq(_raids.token(token)["breached"], 1, "one breach")


## M7.5 gate item 2: a token crosses only where a person can stand on both sides. A door
## a metre up a slab, with nothing to stand on outside it, is no way in at all.
func test_a_door_over_a_drop_is_no_way_in() -> void:
	_setup()
	for x: int in 3:
		for z: int in 3:
			_place(&"foundation_block", x, 0, z, "")
	for i: int in 3:
		for row: int in range(1, 4):
			_place(&"wall_panel", 0, row, i, "nx")
			_place(&"wall_panel", 2, row, i, "px")
			_place(&"wall_panel", i, row, 2, "pz")
			_place(&"door_frame" if i == 1 and row < 3 else &"wall_panel", i, row, 0, "nz")
	for x: int in 3:
		for z: int in 3:
			_place(&"floor_panel", x, 3, z, "py")
	_place(&"storage_crate", 1, 1, 1, "")
	assert_eq(_raids.plan(CUTTER)["cost"], -1, "nowhere outside to stand at any wall")
	assert_eq(_raids.spawn(CUTTER), 0, "so no token comes")

