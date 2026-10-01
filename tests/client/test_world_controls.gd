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
