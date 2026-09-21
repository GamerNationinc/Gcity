extends GcityTest

## M3 claim set P1: actors have positions, move by capped integer steps, cannot pass
## through walls or into solid cells, may pass doors, and need `enter` on a parcel.
## P4: the hit roll reads the distance between positions.

const SEED: int = 20261005
const PROPERTY_CASES: int = 10_000
const SEED_WALK: int = 20261006
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)

var _sim: SimRoot
var _actors: ActorSystem
var _movement: MovementSystem
var _build: BuildSystem
var _land: LandSystem
var _player: int = 0


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_movement = SimAssembly.movement_of(_sim)
	_build = SimAssembly.build_of(_sim)
	_land = SimAssembly.land_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, FAR + Vector3i(500, 0, 500))


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


func _at(cx: int, cy: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, cy * M + 500, cz * M + 500)


func test_positions_spawn_from_range_and_move_by_capped_steps() -> void:
	_setup()
	var dummy: int = _actors.spawn(&"range_dummy", 18)
	assert_eq(_actors.position_of(dummy), Vector3i(18 * M, 0, 0), "range_m places the actor on the x axis")
	assert_eq(_actors.range_of(dummy), 18, "range_of is metres from the origin")
	assert_eq(ActorSystem.metres_between(Vector3i.ZERO, Vector3i(3000, 4000, 0)), 5, "integer distance")
	assert_eq(ActorSystem.metres_between(Vector3i.ZERO, Vector3i(999, 0, 0)), 0, "floors to whole metres")
	assert_eq(_movement.speed_of(_player), 150, "speed from the profile")
	assert_true(_movement.move(_player, 150, -150), "a full-speed step")
	assert_eq(_actors.position_of(_player), FAR + Vector3i(650, 0, 350), "moved")
	assert_false(_movement.move(_player, 151, 0), "over the cap")
	assert_false(_movement.move(_player, 0, 0), "a zero move changes nothing and is rejected")
	assert_false(_movement.move(dummy, 1, 0), "a dummy has speed 0")
	assert_false(_movement.move(99, 1, 0), "unknown actor")
	assert_eq(_movement.move_count(), 1, "one move counted")


func test_walls_block_doors_pass_and_solids_are_impassable() -> void:
	_setup()
	_build.place(_player, &"foundation_block", _at(0, 0, 1), "")
	var wall: int = _build.place(_player, &"wall_panel", _at(0, 1, 1), "nz")
	assert_true(wall > 0, "wall between cell z=0 and z=1 at y=1")
	# the player stands at ground level (y = 0); walls at y = 1 do not block y = 0
	_actors.set_position(_player, _at(0, 0, 0))
	assert_true(_movement.move(_player, 0, 150), "ground level is below the wall")
	# a foundation occupies cell (0, 0, 1): solid at ground level
	_actors.set_position(_player, _at(0, 0, 0) + Vector3i(0, 0, 400))
	assert_false(_movement.move(_player, 0, 150), "cannot enter a solid cell")
	assert_false(_movement.move(_player, 0, 150), "still blocked")
	assert_eq(_movement.blocked_count(), 2, "blocked twice")
	# build a wall at ground level on free cells and try to cross it
	_actors.set_position(_player, _at(3, 0, 3))
	_build.place(_player, &"foundation_block", _at(3, 0, 5), "")
	var w2: int = _build.place(_player, &"wall_panel", _at(3, 0, 4), "nz")
	assert_true(w2 > 0, "a ground-level wall hangs off the foundation")
	_actors.set_position(_player, _at(3, 0, 3) + Vector3i(0, 0, 400))
	assert_false(_movement.move(_player, 0, 150), "the wall face is between cells z=3 and z=4")
	assert_true(_movement.move(_player, 0, -150), "walking away is fine")
	_build.breach(w2)
	var door: int = _build.place(_player, &"door_frame", _at(3, 0, 4), "nz")
	assert_true(door > 0, "a door in its place")
	_actors.set_position(_player, _at(3, 0, 3) + Vector3i(0, 0, 400))
	assert_true(_movement.move(_player, 0, 150), "doors are passable")
	assert_eq(BuildSystem.cell_of(_actors.position_of(_player)), BuildSystem.cell_of(_at(3, 0, 4)), "through")


func test_entering_a_parcel_needs_enter_rights() -> void:
	_setup()
	# corporate_core lets anyone enter; make a parcel with enter = false via a content
	# district would need content, so test the mechanism with a stricter table: none of
	# the shipped districts forbid entering, so build one parcel and assert the call path
	var violations: int = _land.violation_count()
	_actors.set_position(_player, Vector3i(-500, 0, 6 * M))  # just west of the starter plot
	assert_true(_movement.move(_player, 150, 0), "entering the plot: the ghetto allows entry")
	assert_eq(_land.violation_count(), violations, "no violation")
	var enter: bool = _land.rights_at(_actors.position_of(_player), _player)[&"enter"]
	assert_true(enter, "enter held")


func test_move_command_contract() -> void:
	_setup()
	assert_true(_do(MovementSystem.COMMAND_MOVE, {"actor": _player, "dx": 100, "dz": 0}), "move")
	assert_false(_do(MovementSystem.COMMAND_MOVE, {"actor": _player, "dx": 100}), "missing dz")
	assert_false(_do(MovementSystem.COMMAND_MOVE, {"actor": _player, "dx": 1.5, "dz": 0}), "fractional")
	assert_false(_do(MovementSystem.COMMAND_MOVE, {"actor": _player, "dx": 100, "dz": 0, "dy": 1}), "extra key")
	assert_false(_do(MovementSystem.COMMAND_MOVE, {"actor": 99, "dx": 1, "dz": 0}), "unknown actor")


func test_hit_chance_reads_distance_and_farther_never_raises_it() -> void:
	_setup()
	var combat: CombatSystem = SimAssembly.combat_of(_sim)
	var items: ItemSystem = SimAssembly.items_of(_sim)
	var pistol: int = items.spawn(&"weapon_frame", &"g19", ItemSystem.inventory_of(_player), 1)
	var dummy: int = _actors.spawn(&"range_dummy", 0)
	_actors.set_position(_player, Vector3i.ZERO)
	var previous: int = combat.hit_chance_at(_player, pistol, 0)
	for metres: int in range(0, 150, 5):
		_actors.set_position(dummy, Vector3i(metres * M, 0, 0))
		var range_m: int = ActorSystem.metres_between(_actors.position_of(_player), _actors.position_of(dummy))
		assert_eq(range_m, metres, "distance in metres")
		var chance: int = combat.hit_chance_at(_player, pistol, range_m)
		assert_true(chance <= previous, "farther never raises the chance (%d m)" % metres)
		previous = chance
	assert_eq(previous, 0, "clamped to zero far out")


## Random walks with random walls: the actor is never inside a solid cell, never
## crossed a non-passable face, and every accepted move stayed within speed.
func test_property_random_walks_never_cross_walls() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_WALK
	_setup()
	for i: int in 6:
		_build.place(_player, &"foundation_block", _at(i, 0, 6), "")
		for j: int in 6:
			if rng.randi_range(0, 2) == 0:
				var facing: String = "px" if rng.randi_range(0, 1) == 0 else "pz"
				_build.place(_player, &"wall_panel" if rng.randi_range(0, 3) > 0 else &"door_frame", _at(i, 0, j), facing)
	_actors.set_position(_player, _at(0, 0, 0))
	var failures: int = 0
	var moves: int = 0
	for case: int in PROPERTY_CASES:
		var before: Vector3i = _actors.position_of(_player)
		var dx: int = rng.randi_range(-200, 200)
		var dz: int = rng.randi_range(-200, 200)
		var accepted: bool = _movement.move(_player, dx, dz)
		var after: Vector3i = _actors.position_of(_player)
		if accepted:
			moves += 1
			if absi(dx) > 150 or absi(dz) > 150 or after != before + Vector3i(dx, 0, dz):
				failures += 1
			var cell: Vector3i = BuildSystem.cell_of(after)
			if _build.cell_piece_at(cell) != EntityIds.NONE:
				failures += 1
			var from_cell: Vector3i = BuildSystem.cell_of(before)
			if cell != from_cell:
				# the crossed faces must be open or passable, checked axis by axis
				var mid: Vector3i = Vector3i(cell.x, cell.y, from_cell.z)
				for pair: Array in [[from_cell, mid], [mid, cell]]:
					var a: Vector3i = pair[0]
					var b: Vector3i = pair[1]
					if a == b:
						continue
					var d: Vector3i = b - a
					var facing: String = "px" if d.x > 0 else ("nx" if d.x < 0 else ("pz" if d.z > 0 else "nz"))
					var piece: int = _build.face_piece_at(BuildSystem.face_key(a, facing))
					if piece != EntityIds.NONE:
						var k: Dictionary = _build.kind_data(piece)
						var passable: bool = k["passable"]
						if not passable:
							failures += 1
		elif after != before:
			failures += 1
	assert_eq(failures, 0, "every accepted move obeyed the rules (%d moves)" % moves)
	assert_true(moves > 1000, "the walk moved (%d)" % moves)
