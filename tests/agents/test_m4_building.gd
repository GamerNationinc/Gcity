extends GcityTest

## The M4 test building (spec claim 14) raises from `M4Building.commands` with no
## rejection, encloses the volumes its layout promises, and takes its four guards on
## their content routes; the lobby post sees the street through the open door.

const SEED: int = 20261070


func test_the_building_raises_and_the_guards_take_their_posts() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var sim: SimRoot = SimAssembly.build(SEED, db)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var build: BuildSystem = SimAssembly.build_of(sim)
	var portals: PortalGraph = SimAssembly.portals_of(sim)
	var perception: PerceptionSystem = SimAssembly.perception_of(sim)
	var pathing: PathingSystem = SimAssembly.pathing_of(sim)
	var player: int = actors.spawn(&"arcade", 0)
	actors.set_position(player, M4Building.PLAYER_START)
	var at: int = sim.get_tick() + 1
	sim.submit(SimCommand.new(at, &"land.identify", {"actor": player, "owner": "player"}))
	sim.submit(SimCommand.new(at, &"land.transfer", {"parcel": "starter_plot", "owner": "player"}))
	sim.submit(SimCommand.new(at, &"land.transfer", {"parcel": "neighbour_north", "owner": "player"}))
	var commands: Array[Dictionary] = M4Building.commands(player, db)
	for c: Dictionary in commands:
		sim.submit(SimCommand.new(at, &"build.place", c))
	for g: Dictionary in M4Building.guards("guard_sim", db):
		sim.submit(SimCommand.new(at, &"agent.spawn", g))
	sim.step()
	assert_eq(sim.rejected_count(), 0, "every command applied")
	assert_eq(build.piece_ids().size(), commands.size(), "%d pieces stand" % commands.size())
	for id: int in build.piece_ids():
		assert_true(build.is_supported(id), "piece %d is supported" % id)
	assert_eq(portals.volume_count(), 2, "the two roofed rooms behind their doors are volumes; the corridor opens into the roofless lobby and is exterior")
	assert_eq(perception.agent_ids().size(), 4, "four guards")
	var post: int = perception.agent_ids()[0]
	assert_eq(perception.route_of(post), "", "the post has no route")
	assert_eq(perception.route_of(perception.agent_ids()[1]), "lobby_round", "the roamer's route")
	assert_false(perception.can_see(post, player), "the post cannot see the start: it is off the door's axis")
	actors.set_position(player, Vector3i(5500, 0, 1500))
	assert_true(perception.can_see(post, player), "step in front of the door and it can")
	assert_eq(SimAssembly.movement_of(sim).speed_of(post), 60, "guards walk")
	# the roamer and the patrollers walk their routes: no step is ever blocked
	var movement: MovementSystem = SimAssembly.movement_of(sim)
	actors.set_position(player, Vector3i(-40_000, 0, -40_000))  # out of everyone's sight
	sim.step_n(600)
	assert_eq(movement.blocked_count(), 0, "no guard ever walked into a wall")
	for guard: int in perception.agent_ids():
		if not perception.route_of(guard).is_empty():
			assert_true(pathing.state_of(guard) != PathingSystem.STATE_FAILED, "guard %d's route is walkable" % guard)
			assert_true(SimAssembly.stances_of(sim).waypoint_of(guard) > 0 or pathing.state_of(guard) == PathingSystem.STATE_FOLLOWING, "guard %d is under way" % guard)
	assert_eq(sim.rejected_count(), 0, "still nothing rejected")


func test_the_street_is_watched_and_the_rooms_are_not_seen_from_it() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var sim: SimRoot = SimAssembly.build(SEED, db)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var perception: PerceptionSystem = SimAssembly.perception_of(sim)
	var player: int = actors.spawn(&"arcade", 0)
	var at: int = sim.get_tick() + 1
	sim.submit(SimCommand.new(at, &"land.identify", {"actor": player, "owner": "player"}))
	sim.submit(SimCommand.new(at, &"land.transfer", {"parcel": "starter_plot", "owner": "player"}))
	sim.submit(SimCommand.new(at, &"land.transfer", {"parcel": "neighbour_north", "owner": "player"}))
	for c: Dictionary in M4Building.commands(player, db):
		sim.submit(SimCommand.new(at, &"build.place", c))
	sim.step()
	assert_eq(sim.rejected_count(), 0, "built")
	var street: Vector3i = Vector3i(5500, 0, 1500)
	var room_a: Vector3i = BuildSystem.cell_centre(M4Building.BASE + Vector3i(0, 0, 7))
	var room_b: Vector3i = BuildSystem.cell_centre(M4Building.BASE + Vector3i(5, 0, 7))
	var door_a: Vector3i = BuildSystem.cell_centre(M4Building.BASE + Vector3i(3, 0, 8))
	var door_b: Vector3i = BuildSystem.cell_centre(M4Building.BASE + Vector3i(5, 0, 8))
	var lobby: Vector3i = BuildSystem.cell_centre(M4Building.BASE + Vector3i(2, 0, 1))
	assert_true(perception.line_of_sight(street, lobby), "the street sees into the lobby through the door")
	assert_false(perception.line_of_sight(street, room_a), "but not into room A")
	assert_false(perception.line_of_sight(street, room_b), "nor room B")
	assert_false(perception.line_of_sight(room_a, room_b), "the rooms do not see each other through their walls")
	assert_true(perception.line_of_sight(door_a, door_b), "but the two doorways see each other across the corridor: open doors pass sight")
	var outside_a: Vector3i = BuildSystem.cell_centre(M4Building.BASE + Vector3i(-3, 0, 8))
	var behind_window_a: Vector3i = BuildSystem.cell_centre(M4Building.BASE + Vector3i(1, 0, 8))
	var beside_window_a: Vector3i = BuildSystem.cell_centre(M4Building.BASE + Vector3i(0, 0, 9))
	assert_true(perception.line_of_sight(outside_a, behind_window_a), "room A's window is seen through from outside")
	assert_false(perception.line_of_sight(outside_a, beside_window_a), "the wall beside the window is not")
	var corridor_mouth: Vector3i = BuildSystem.cell_centre(M4Building.BASE + Vector3i(4, 0, 4))
	assert_false(perception.line_of_sight(corridor_mouth, street), "the corridor mouth does not see the street in front of the door")
	var far_street: Vector3i = Vector3i(20500, 0, 500)
	assert_false(perception.line_of_sight(BuildSystem.cell_centre(M4Building.BASE + Vector3i(1, 0, 1)), far_street), "the lobby does not see down the street")
