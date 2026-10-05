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


## Deck run 2026-10-05: the camera turned but could not look up or down.
func test_the_look_stick_up_and_down_is_bound_and_tilts_the_view() -> void:
	for pair: Array in [[&"world_look_up", -1.0], [&"world_look_down", 1.0]]:
		var on_stick: bool = false
		var action: StringName = pair[0]
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventJoypadMotion and (event as InputEventJoypadMotion).axis == JOY_AXIS_RIGHT_Y and signf((event as InputEventJoypadMotion).axis_value) == pair[1]:
				on_stick = true
		assert_true(on_stick, "%s is on the right stick's vertical axis" % action)
	for step: int in 8:
		var yaw: float = TAU * float(step) / 8.0
		var level: Vector3 = WorldView.look_direction(yaw, 0.0)
		assert_true(absf(level.y) < 0.001 and absf(level.length() - 1.0) < 0.001, "level is flat at yaw %.2f" % yaw)
		assert_true(WorldView.look_direction(yaw, 0.5).y > 0.4, "up looks up at yaw %.2f" % yaw)
		assert_true(WorldView.look_direction(yaw, -0.5).y < -0.4, "down looks down at yaw %.2f" % yaw)
		var tilted: Vector3 = WorldView.look_direction(yaw, 0.5)
		assert_true(Vector2(tilted.x, tilted.z).normalized().distance_to(Vector2(level.x, level.z)) < 0.001, "tilting keeps the heading at yaw %.2f" % yaw)


func test_the_third_person_camera_never_sinks_under_the_ground() -> void:
	var feet := Vector3(3.0, 1.0, -2.0)
	for pitch: float in [WorldView.PITCH_MIN_THIRD, 0.0, WorldView.PITCH_MAX_THIRD]:
		var at: Vector3 = WorldView.third_person_position(feet, 0.4, pitch)
		assert_true(at.y >= feet.y + 0.29, "camera above the feet at pitch %.2f (%.2f)" % [pitch, at.y])
	var rest: Vector3 = WorldView.third_person_position(feet, 0.4, 0.0)
	assert_true(rest.y - feet.y > 2.0 and rest.y - feet.y < 3.2, "at rest it sits about where it always did (%.2f up)" % (rest.y - feet.y))
	assert_true(WorldView.third_person_position(feet, 0.4, WorldView.PITCH_MIN_THIRD).y > rest.y, "looking down lifts the camera")


## A room one cell wide at the origin: walls on its four sides, a ceiling, a floor.
func _room(cell: Vector3i, facing: String) -> bool:
	return cell == Vector3i.ZERO


## CEOGG's 2026-10-05 sandbox run: walking up to a wall put the first-person eye inside it
## and the view saw through. The eye is kept a hand's width off every shut side.
func test_the_eye_never_sits_in_a_wall() -> void:
	var closed: Callable = _room
	for at: Vector3 in [Vector3(0.0, 0.5, 0.5), Vector3(0.999, 0.5, 0.5), Vector3(0.5, 0.5, 0.01), Vector3(0.5, 0.99, 0.5), Vector3(0.02, 0.98, 0.97)]:
		var eye: Vector3 = WorldView.keep_off_walls(at, closed)
		for axis: int in 3:
			assert_true(eye[axis] >= WorldView.WALL_MARGIN - 0.0001 and eye[axis] <= 1.0 - WorldView.WALL_MARGIN + 0.0001, "%s kept off the walls (%s)" % [at, eye])
	assert_true(WorldView.keep_off_walls(Vector3(0.5, 0.5, 0.5), closed).is_equal_approx(Vector3(0.5, 0.5, 0.5)), "the middle of the room is left alone")
	var open: Callable = func(_cell: Vector3i, _facing: String) -> bool: return false
	assert_true(WorldView.keep_off_walls(Vector3(0.0, 0.5, 0.01), open).is_equal_approx(Vector3(0.0, 0.5, 0.01)), "with no wall the eye goes where the body is")


## The third-person camera stops on the near side of a wall instead of sliding behind it.
func test_the_third_person_camera_stops_in_front_of_a_wall() -> void:
	# one wall: the face between x = 2 and x = 3
	var closed: Callable = func(cell: Vector3i, facing: String) -> bool:
		return (cell.x == 2 and facing == "px") or (cell.x == 3 and facing == "nx")
	var at: Vector3 = WorldView.walk_to_wall(Vector3(0.5, 1.5, 0.5), Vector3(6.0, 2.5, 0.5), closed)
	assert_true(at.x <= 3.0 - WorldView.WALL_MARGIN + 0.0001, "stopped before the wall (%s)" % at)
	assert_true(at.x > 2.0, "and no further back than it has to (%s)" % at)
	var free: Vector3 = WorldView.walk_to_wall(Vector3(0.5, 1.5, 0.5), Vector3(-4.0, 2.5, 0.5), closed)
	assert_true(free.is_equal_approx(Vector3(-4.0, 2.5, 0.5)), "away from the wall it goes all the way (%s)" % free)
	var other_side: Vector3 = WorldView.walk_to_wall(Vector3(5.5, 1.5, 0.5), Vector3(0.5, 1.5, 0.5), closed)
	assert_true(other_side.x >= 3.0 + WorldView.WALL_MARGIN - 0.0001, "from the far side it stops on that side (%s)" % other_side)


## CEOGG, 2026-10-05: "you should be able to fire whenever you want and hit any object in
## front of you". A shot at no one stops on the first wall or the ground along the view.
func test_a_shot_stops_on_the_first_wall_or_the_ground() -> void:
	var wall: Callable = func(cell: Vector3i, facing: String) -> bool:
		return (cell.x == 4 and facing == "px") or cell.y + FACING_Y.get(facing, 0) < 0
	var level: Dictionary = WorldView.shot_impact(Vector3(0.5, 1.6, 0.5), Vector3(1.0, 0.0, 0.0), 60.0, wall)
	var level_at: Vector3 = level["point"]
	var level_out: float = level["distance"]
	assert_eq(level["facing"], "px", "a level shot meets the wall")
	assert_true(absf(level_at.x - 5.0) < 0.001, "on the wall's face (%s)" % level_at)
	assert_true(absf(level_out - 4.5) < 0.001, "4.5 m out")
	var down: Dictionary = WorldView.shot_impact(Vector3(0.5, 1.6, 0.5), Vector3(-1.0, -1.0, 0.0).normalized(), 60.0, wall)
	assert_eq(down["facing"], "ny", "a shot down meets the ground")
	var down_at: Vector3 = down["point"]
	assert_true(absf(down_at.y) < 0.001, "at ground level (%s)" % down_at)
	var away: Dictionary = WorldView.shot_impact(Vector3(0.5, 1.6, 0.5), Vector3(-1.0, 0.0, 0.0), 30.0, wall)
	assert_false(away.has("facing"), "a shot at the open sky meets nothing")


const FACING_Y: Dictionary = {"ny": -1, "py": 1}


func test_every_held_thing_has_a_placeholder_shape() -> void:
	assert_eq(WorldView.weapon_shape(&"weapon_frame", &"g19"), "pistol", "a g19 is a pistol")
	assert_eq(WorldView.weapon_shape(&"weapon_frame", &"m9"), "pistol", "an m9 is a pistol")
	assert_eq(WorldView.weapon_shape(&"weapon_frame", &"ar_rifle"), "rifle", "a rifle file is a long gun")
	assert_eq(WorldView.weapon_shape(&"tool_class", &"cutter"), "tool", "a cutter is a tool")
	assert_eq(WorldView.weapon_shape(&"melee", &"bat"), "melee", "anything else is held like a blade or a bat")
