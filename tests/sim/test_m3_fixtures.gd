extends GcityTest

## The M3 replay fixtures (spec claim 12, P3): the bunker raided through its door,
## the killbox where the player's new door beats the wall the token was cutting, and
## the walk through the door with a refused step into a wall.

const M: int = 1000


func _db() -> ContentDb:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	return db


func _run(path: String) -> SimRoot:
	var fixture: ReplayFixture = ReplayFixture.parse(read_text(path))
	assert_true(fixture.is_valid(), "%s valid: %s" % [path, fixture.error])
	var sim: SimRoot = SimAssembly.build(fixture.seed, _db())
	var hash: String = Replay.run(fixture, sim)
	assert_eq(hash.length(), 64, "hash produced")
	assert_false(fixture.expected_hash.is_empty(), "%s has its hash recorded" % path)
	assert_eq(hash, fixture.expected_hash, "%s matches the recorded hash" % path)
	return sim


func test_bunker_is_raided_through_its_door_without_a_breach() -> void:
	var sim: SimRoot = _run("res://tests/replay/m3-bunker.json")
	var raids: RaidTokenSystem = SimAssembly.raids_of(sim)
	var build: BuildSystem = SimAssembly.build_of(sim)
	var portals: PortalGraph = SimAssembly.portals_of(sim)
	assert_eq(build.piece_ids().size(), 26, "four foundations, twelve walls incl. the door, nine roof panels, a crate")
	assert_eq(portals.volume_count(), 1, "one enclosed volume")
	assert_eq(raids.token_ids(), [1] as Array[int], "one token")
	assert_eq(raids.state_of(1), "arrived", "arrived")
	assert_eq(raids.token(1)["breached"], 0, "through the door, nothing breached")
	assert_eq(sim.rejected_count(), 0, "every command applied")


func test_killbox_the_new_door_beats_the_wall_being_cut() -> void:
	var sim: SimRoot = _run("res://tests/replay/m3-killbox.json")
	var raids: RaidTokenSystem = SimAssembly.raids_of(sim)
	var build: BuildSystem = SimAssembly.build_of(sim)
	assert_eq(raids.state_of(1), "arrived", "arrived")
	assert_eq(raids.token(1)["breached"], 0, "the token took the door instead of finishing the cut")
	assert_eq(build.piece_ids().size(), 26, "wall swapped for a door: same count")
	assert_eq(sim.rejected_count(), 0, "every command applied")


func test_walk_through_the_door_and_a_refused_step_into_a_wall() -> void:
	var sim: SimRoot = _run("res://tests/replay/m3-walk.json")
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var movement: MovementSystem = SimAssembly.movement_of(sim)
	var pos: Vector3i = actors.position_of(1)
	assert_eq(BuildSystem.cell_of(pos), Vector3i(5, 0, 4), "inside the room, just past the door")
	assert_true(movement.blocked_count() >= 1, "at least one step into the wall was refused")
	assert_eq(sim.rejected_count(), movement.blocked_count(), "the only rejections were the refused steps")
	assert_true(movement.move_count() > 80, "the rest of the walk happened (%d moves)" % movement.move_count())
