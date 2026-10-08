extends GcityTest

## M6 spec claim 2 (ADR-011 C): climb, mantle and jump are timed moves a profile must
## list in `moves`. Climb crosses a stair or a ladder between storey n and n+1; mantle
## pulls up onto a mantle-able cell piece; jump crosses a one-cell gap on the same
## storey. Nothing else moves the actor while a move runs. Property: over 10 000
## generated move commands on generated geometry, a finished move never changes the
## storey by more than one, never ends inside a cell piece, and a jump never gains height.

const SEED: int = 20261011
const PROPERTY_CASES: int = 10_000
const SEED_MOVES: int = 20261012
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)

var _sim: SimRoot
var _actors: ActorSystem
var _movement: MovementSystem
var _build: BuildSystem
var _player: int = 0


func _setup(db: ContentDb = null) -> void:
	if db == null:
		db = ContentDb.new()
		assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_movement = SimAssembly.movement_of(_sim)
	_build = SimAssembly.build_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, _feet(0, 0, 0))


func _feet(cx: int, storey: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, storey * BuildSystem.STOREY_MM, cz * M + 500)


func _at(cx: int, cy: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, cy * M + 500, cz * M + 500)


func _cell(cx: int, cy: int, cz: int) -> Vector3i:
	return BuildSystem.cell_of(_at(cx, cy, cz))


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


func _tick(n: int) -> void:
	for i: int in n:
		_sim.step()


func _where(actor: int) -> Vector3i:
	return BuildSystem.cell_of(_actors.position_of(actor))


## A stair at x 1 with its foot at x 0 (facing nx), and a storey-1 deck east of its top.
func _stairs() -> int:
	assert_true(_build.place(_player, &"foundation_block", _at(3, 0, 0), "") > 0, "foundation")
	assert_true(_build.place(_player, &"floor_panel", _at(2, 0, 0), "py") > 0, "deck")
	var stair: int = _build.place(_player, &"stair_steel", _at(1, 0, 0), "nx")
	assert_true(stair > 0, "stair")
	return stair


func test_climb_a_stair_up_and_down_at_its_ticks() -> void:
	_setup()
	var stair: int = _stairs()
	assert_true(_do(&"actor.climb", {"actor": _player, "piece": stair}), "climb from the foot")
	assert_true(_movement.is_moving(_player), "the climb takes time")
	assert_false(_movement.move(_player, 100, 0), "no walking mid-climb")
	_tick(_build.climb_ticks_of(stair) - 1)
	assert_false(_movement.is_moving(_player), "done after the stair's ticks")
	assert_eq(_where(_player), _cell(1, 1, 0), "on the stair's top, storey 1")
	for i: int in 5:
		_movement.move(_player, 150, 0)
	assert_eq(_where(_player), _cell(2, 1, 0), "walked onto the deck")
	for i: int in 5:
		_movement.move(_player, -150, 0)
	assert_eq(_where(_player), _cell(1, 1, 0), "back on the stair's top")
	assert_true(_do(&"actor.climb", {"actor": _player, "piece": stair}), "climb down")
	_tick(_build.climb_ticks_of(stair))
	assert_eq(_where(_player), _cell(0, 0, 0), "at the foot")


func test_a_climb_needs_the_move_and_the_foot() -> void:
	_setup()
	var stair: int = _stairs()
	var dummy: int = _actors.spawn(&"range_dummy", 0)
	_actors.set_position(dummy, _feet(0, 0, 0))
	assert_false(_do(&"actor.climb", {"actor": dummy, "piece": stair}), "a walk-only profile cannot climb")
	_actors.set_position(_player, _feet(1, 0, 1))
	assert_false(_do(&"actor.climb", {"actor": _player, "piece": stair}), "not from beside the stair, only its foot")
	assert_false(_do(&"actor.climb", {"actor": _player, "piece": 999}), "not an unknown piece")


func test_climb_a_ladder_through_a_floor() -> void:
	_setup()
	assert_true(_build.place(_player, &"foundation_block", _at(0, 0, 1), "") > 0, "foundation")
	var ladder: int = _build.place(_player, &"ladder_hatch", _at(0, 0, 0), "py")
	assert_true(ladder > 0, "ladder over the player")
	assert_true(_do(&"actor.climb", {"actor": _player, "piece": ladder}), "up the ladder")
	_tick(_build.climb_ticks_of(ladder))
	assert_eq(_where(_player), _cell(0, 1, 0), "standing on the ladder's top")
	assert_true(_do(&"actor.climb", {"actor": _player, "piece": ladder}), "down again")
	_tick(_build.climb_ticks_of(ladder))
	assert_eq(_where(_player), _cell(0, 0, 0), "at the bottom")


func test_mantle_onto_a_crate_but_not_a_foundation_or_through_a_wall() -> void:
	_setup()
	assert_true(_build.place(_player, &"foundation_block", _at(2, 0, 0), "") > 0, "foundation east")
	assert_true(_build.place(_player, &"storage_crate", _at(1, 0, 0), "") > 0, "crate between")
	assert_true(_do(&"actor.mantle", {"actor": _player, "dx": 1, "dz": 0}), "mantle onto the crate")
	var t: Dictionary = _actors.profile_data(_player)
	var ticks: int = t["mantle_ticks"]
	_tick(ticks)
	assert_eq(_where(_player), _cell(1, 1, 0), "on the crate")
	assert_false(_do(&"actor.mantle", {"actor": _player, "dx": 1, "dz": 0}), "a foundation's top is not a ledge (and it is level here)")
	_actors.set_position(_player, _feet(1, 0, 1))
	assert_false(_do(&"actor.mantle", {"actor": _player, "dx": 1, "dz": 0}), "nothing to mantle at storey 0 there")
	assert_true(_build.place(_player, &"wall_panel", _at(1, 0, 0), "pz") > 0, "a wall between")
	_actors.set_position(_player, _feet(1, 0, 1))
	assert_false(_do(&"actor.mantle", {"actor": _player, "dx": 0, "dz": -1}), "not through a wall")
	assert_false(_do(&"actor.mantle", {"actor": _player, "dx": 1, "dz": 1}), "one axis only")


func test_jump_a_one_cell_gap_on_the_same_storey() -> void:
	_setup()
	_actors.set_position(_player, _feet(0, 0, 5))
	# two decks on storey 1: x 0..1 and x 3..4, a gap at x 2
	for x: int in [0, 4]:
		assert_true(_build.place(_player, &"foundation_block", _at(x, 0, 0), "") > 0, "foundation %d" % x)
	assert_true(_build.place(_player, &"floor_panel", _at(1, 0, 0), "py") > 0, "west deck")
	assert_true(_build.place(_player, &"floor_panel", _at(3, 0, 0), "py") > 0, "east deck")
	_actors.set_position(_player, _feet(1, 1, 0))
	assert_false(_do(&"actor.jump", {"actor": _player, "dx": -1, "dz": 0}), "not onto the foundation two cells away: the middle holds you up, no gap")
	assert_true(_do(&"actor.jump", {"actor": _player, "dx": 1, "dz": 0}), "across the gap")
	var t: Dictionary = _actors.profile_data(_player)
	var ticks: int = t["jump_ticks"]
	_tick(ticks)
	assert_eq(_where(_player), _cell(3, 1, 0), "landed on the east deck")
	assert_false(_movement.is_falling(_player), "and stands there")
	assert_false(_do(&"actor.jump", {"actor": _player, "dx": 1, "dz": 0}), "no landing past the east end")


func test_a_profile_naming_a_move_the_sim_lacks_stops_assembly() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	assert_eq(db.add(&"move", &"zz_wallrun", {"schema_version": 1, "description": "not implemented"}), OK, "a new move")
	var p: Dictionary = db.get_entry(&"combat_profile", &"arcade").duplicate(true)
	var moves: Array = p["moves"]
	moves.append("zz_wallrun")
	assert_eq(db.add(&"combat_profile", &"zz_runner", p), OK, "a profile using it")
	assert_true(SimAssembly.build(SEED, db) == null, "refused: no implementation")


func test_property_moves_change_storey_by_at_most_one_and_never_end_inside_a_piece() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_MOVES
	_setup()
	var templates: Array[StringName] = [&"foundation_block", &"storage_crate", &"floor_panel", &"wall_panel", &"stair_steel", &"ladder_hatch"]
	_actors.set_position(_player, _feet(0, 0, 9))
	# a lattice of foundations so most pieces placed near them are supported
	for x: int in range(-3, 4, 3):
		for z: int in range(-3, 4, 3):
			_build.place(_player, &"foundation_block", _at(x, 0, z), "")
	for i: int in 120:
		var template: StringName = templates[rng.randi_range(0, templates.size() - 1)]
		var c: Vector3i = Vector3i(rng.randi_range(-3, 3), rng.randi_range(0, 1), rng.randi_range(-3, 3))
		var facing: String = ""
		if template == &"floor_panel" or template == &"ladder_hatch":
			facing = "py"
		elif template == &"wall_panel" or template == &"stair_steel":
			facing = ["px", "nx", "pz", "nz"][rng.randi_range(0, 3)]
		_build.place(_player, template, _at(c.x, c.y, c.z), facing)
	var failures: int = 0
	var finished: int = 0
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for case: int in PROPERTY_CASES:
		if not _actors.is_alive(_player):
			break
		var from: Vector3i = _where(_player)
		var started: bool = false
		var kind: int = rng.randi_range(0, 3)
		var d: Vector2i = dirs[rng.randi_range(0, 3)]
		if kind == 0:
			var ids: Array[int] = _build.piece_ids()
			started = _movement.climb(_player, ids[rng.randi_range(0, ids.size() - 1)])
		elif kind == 1:
			started = _movement.mantle(_player, d.x, d.y)
		elif kind == 2:
			started = _movement.jump(_player, d.x, d.y)
		else:
			_movement.move(_player, rng.randi_range(-150, 150), rng.randi_range(-150, 150))
		if started:
			while _movement.is_moving(_player):
				_sim.step()
			finished += 1
			var to: Vector3i = _where(_player)
			if absi(to.y - from.y) > 1 or _build.cell_piece_at(to) != EntityIds.NONE:
				failures += 1
			if kind == 2 and to.y != from.y:
				failures += 1
		while _movement.is_falling(_player):
			_sim.step()
		if rng.randi_range(0, 3) == 0:
			# start somewhere new that can be stood on, among the pieces
			var spot: Vector3i = _feet(rng.randi_range(-4, 4), rng.randi_range(0, 2), rng.randi_range(-4, 4))
			if _build.is_standable(BuildSystem.cell_of(spot)):
				_actors.set_position(_player, spot)
	assert_eq(failures, 0, "every finished move within one storey, outside every piece; jumps level")
	assert_true(finished > 100, "the stream finished moves (%d)" % finished)
