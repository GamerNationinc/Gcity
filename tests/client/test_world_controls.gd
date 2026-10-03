extends GcityTest

## The 2026-10-01 Deck run: the stick strafed the wrong way. The stick's right must be
## the screen's right, which is the camera's basis x, at every yaw.


func _camera_axes(yaw: float) -> Array[Vector2]:
	var basis: Basis = Basis(Vector3.UP, yaw)
	var right: Vector3 = basis.x
	var forward: Vector3 = -basis.z
	return [Vector2(right.x, right.z), Vector2(forward.x, forward.z)]


func test_the_stick_moves_the_way_the_screen_shows_at_every_yaw() -> void:
	for step: int in 16:
		var yaw: float = TAU * float(step) / 16.0
		var axes: Array[Vector2] = _camera_axes(yaw)
		var right: Vector2 = WorldView.ground_move(yaw, Vector2(1.0, 0.0))
		var up: Vector2 = WorldView.ground_move(yaw, Vector2(0.0, -1.0))
		assert_true(right.distance_to(axes[0]) < 0.001, "right is the screen's right at yaw %.2f (%s, want %s)" % [yaw, right, axes[0]])
		assert_true(up.distance_to(axes[1]) < 0.001, "up is the camera's forward at yaw %.2f (%s, want %s)" % [yaw, up, axes[1]])


func test_left_and_back_are_the_opposites_and_a_diagonal_is_not_faster() -> void:
	var yaw: float = 0.7
	assert_true(WorldView.ground_move(yaw, Vector2(-1.0, 0.0)).distance_to(-WorldView.ground_move(yaw, Vector2(1.0, 0.0))) < 0.001, "left is minus right")
	assert_true(WorldView.ground_move(yaw, Vector2(0.0, 1.0)).distance_to(-WorldView.ground_move(yaw, Vector2(0.0, -1.0))) < 0.001, "back is minus forward")
	assert_true(WorldView.ground_move(yaw, Vector2(1.0, -1.0)).length() <= 1.0001, "a diagonal is no faster than straight")


## M7.5 spec claim 11: the overlays and the camera are placed from where the sim says an
## actor stands and from its own eyes and centre, not at heights fixed for the ground
## floor, so they stay with a guard upstairs. A guard two storeys up and a player one up.
func test_overlays_and_the_eye_follow_the_actor_up_the_building() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var sim: SimRoot = SimAssembly.build(20261400, db)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var perception: PerceptionSystem = SimAssembly.perception_of(sim)
	var player: int = actors.spawn(&"arcade", 0)
	var guard: int = perception.spawn(&"guard_sim", Vector3i(3, 6, 2), 0, 0, "", "", Vector3i.ZERO)
	assert_true(guard != EntityIds.NONE, "a guard")
	actors.set_position(guard, Vector3i(3500, 6000, 2500))
	actors.set_position(player, Vector3i(9500, 3000, 2500))
	var eye_mm: int = db.get_entry(ActorSystem.KIND_PROFILE, &"guard")["eye_mm"]
	var centre_mm: int = db.get_entry(ActorSystem.KIND_PROFILE, &"arcade")["centre_mm"]
	var eye: float = eye_mm / 1000.0
	var centre: float = centre_mm / 1000.0
	assert_eq(eye, 1.6, "a guard's eyes are at 1.6 m")
	var ends: PackedVector3Array = WorldView.sight_ends(sim, guard, player)
	assert_true(ends[0].is_equal_approx(Vector3(3.5, 6.0 + eye, 2.5)), "the sight line leaves the guard's eyes: %s" % ends[0])
	assert_true(ends[1].is_equal_approx(Vector3(9.5, 3.0 + centre, 2.5)), "and reaches the player's centre: %s" % ends[1])
	assert_true(WorldView.bar_position(Vector3i(3500, 6000, 2500)).is_equal_approx(Vector3(3.5, 6.0 + WorldView.BAR_OVER_FLOOR, 2.5)), "the bar is over the guard's own floor")
	assert_true(WorldView.marker_position(Vector3i(9500, 3000, 2500)).is_equal_approx(Vector3(9.5, 3.0 + WorldView.MARKER_OVER_FLOOR, 2.5)), "the marker on the floor remembered")
	assert_true(WorldView.eye_position(sim, player).is_equal_approx(Vector3(9.5, 3.0 + 1.6, 2.5)), "and the first-person eye is the sim's eye")
