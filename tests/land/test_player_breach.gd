extends GcityTest

## M6 spec claim 4: `build.breach {actor, piece}` takes a piece out with the tool in
## hand. The actor stands at the piece (in one of a face's two cells, or beside a cell
## piece) and wields a tool of the material's breach class; the breach takes the
## material's breach_ticks and is called off if the actor moves, is hurt, dies, loses
## its footing or the piece goes first. A breach on a parcel where the actor lacks
## `build` is a recorded violation, never a refusal. On completion the piece comes out
## through BuildSystem.breach and `build.breached {actor, piece, removed}` is emitted.

const SEED: int = 20261018
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)

var _sim: SimRoot
var _build: BuildSystem
var _actors: ActorSystem
var _items: ItemSystem
var _land: LandSystem
var _player: int = 0
var _cutter: int = 0
var _breached: Array[Dictionary] = []
var _db: ContentDb


func _setup() -> void:
	_db = ContentDb.new()
	assert_eq(ContentLoader.load_all(_db), OK, "content loads")
	_sim = SimAssembly.build(SEED, _db)
	assert_true(_sim != null, "assembly")
	_build = SimAssembly.build_of(_sim)
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_land = SimAssembly.land_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, _feet(FAR, 0, 0))
	_cutter = _items.spawn(&"tool", &"plasma_cutter", ItemSystem.inventory_of(_player), 1)
	assert_true(_do(&"actor.wield", {"actor": _player, "weapon": _cutter}), "cutter in hand")
	var sink: Array[Dictionary] = []
	_breached = sink
	var on_breached: Callable = func(payload: Dictionary) -> void:
		sink.append(payload)
	SimAssembly.combat_of(_sim).events().subscribe(BuildSystem.EVENT_BREACHED, on_breached)


func _feet(origin: Vector3i, cx: int, cz: int) -> Vector3i:
	return origin + Vector3i(cx * M + 500, 0, cz * M + 500)


func _at(origin: Vector3i, cx: int, cy: int, cz: int) -> Vector3i:
	return origin + Vector3i(cx * M + 500, cy * M + 500, cz * M + 500)


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


## A steel wall on the east face of (0, 0, 0), held up by a foundation north of it.
func _wall(origin: Vector3i) -> int:
	assert_true(_build.place(_player, &"foundation_block", _at(origin, 0, 0, 1), "") > 0, "foundation")
	var wall: int = _build.place(_player, &"wall_panel", _at(origin, 0, 0, 0), "px")
	assert_true(wall > 0, "wall")
	return wall


func _ticks_of(piece: int) -> int:
	var m: Dictionary = _db.get_entry(&"material", _build.material_of(piece))
	return m["breach_ticks"]


func test_a_cutter_takes_a_steel_wall_out_in_its_breach_ticks() -> void:
	_setup()
	var wall: int = _wall(FAR)
	var ticks: int = _ticks_of(wall)
	assert_true(_do(&"build.breach", {"actor": _player, "piece": wall}), "breach started (tick 1 of %d)" % ticks)
	assert_true(_build.is_breaching(_player), "under way")
	_sim.step_n(ticks - 2)
	assert_true(_build.has_piece(wall), "still standing one tick short")
	_sim.step()
	assert_false(_build.has_piece(wall), "out on its last tick")
	assert_false(_build.is_breaching(_player), "done")
	assert_eq(_breached.size(), 1, "one event")
	assert_eq(_breached[0], {"actor": _player, "piece": wall, "removed": [wall] as Array[int]}, "naming the actor")


func test_the_wrong_tool_no_tool_or_no_reach_is_refused() -> void:
	_setup()
	var wall: int = _wall(FAR)
	var kit: int = _items.spawn(&"tool", &"breaching_kit", ItemSystem.inventory_of(_player), 2)
	assert_true(_do(&"actor.wield", {"actor": _player, "weapon": kit}), "breacher in hand")
	assert_false(_do(&"build.breach", {"actor": _player, "piece": wall}), "steel wants a cutter")
	assert_true(_do(&"actor.wield", {"actor": _player, "weapon": 0}), "empty hands")
	assert_false(_do(&"build.breach", {"actor": _player, "piece": wall}), "no tool")
	assert_true(_do(&"actor.wield", {"actor": _player, "weapon": _cutter}), "cutter again")
	_actors.set_position(_player, _feet(FAR, 3, 3))
	assert_false(_do(&"build.breach", {"actor": _player, "piece": wall}), "out of reach")
	_actors.set_position(_player, _feet(FAR, 1, 0))
	assert_true(_do(&"build.breach", {"actor": _player, "piece": wall}), "from the other side of the wall")
	assert_false(_do(&"build.breach", {"actor": _player, "piece": wall}), "not twice at once")


func test_moving_being_hurt_or_losing_the_piece_calls_it_off() -> void:
	_setup()
	var wall: int = _wall(FAR)
	assert_true(_do(&"build.breach", {"actor": _player, "piece": wall}), "started")
	_sim.step_n(10)
	assert_true(SimAssembly.movement_of(_sim).move(_player, 0, 100), "a step")
	_sim.step()
	assert_false(_build.is_breaching(_player), "moving calls it off")
	_actors.set_position(_player, _feet(FAR, 0, 0))
	assert_true(_do(&"build.breach", {"actor": _player, "piece": wall}), "started again")
	_actors.damage_node(_player, &"body", 1)
	_sim.step()
	assert_false(_build.is_breaching(_player), "being hurt calls it off")
	assert_true(_do(&"build.breach", {"actor": _player, "piece": wall}), "and again")
	assert_false(_build.breach(wall).is_empty(), "a raid takes the wall first")
	_sim.step()
	assert_false(_build.is_breaching(_player), "nothing left to cut")
	assert_true(_build.has_piece(_build.cell_piece_at(BuildSystem.cell_of(_at(FAR, 0, 0, 1)))), "the foundation is untouched")


func test_a_breach_without_the_build_right_is_a_violation_not_a_refusal() -> void:
	_setup()
	assert_true(_do(&"land.identify", {"actor": _player, "owner": "player.one"}), "the player is player.one")
	assert_true(_do(&"land.transfer", {"parcel": "starter_plot", "owner": "player.one"}), "owns the plot")
	_actors.set_position(_player, _feet(Vector3i.ZERO, 2, 2))
	var wall: int = _wall(Vector3i(2 * M, 0, 2 * M))
	assert_true(_do(&"land.transfer", {"parcel": "starter_plot", "owner": "npc.someone"}), "sold")
	var before: int = _land.violation_count()
	assert_true(_do(&"build.breach", {"actor": _player, "piece": wall}), "breach goes ahead")
	assert_eq(_land.violation_count(), before + 1, "recorded as a violation")
	_sim.step_n(_ticks_of(wall))
	assert_false(_build.has_piece(wall), "and the wall comes out")


func test_a_breach_in_progress_survives_the_restore() -> void:
	_setup()
	var wall: int = _wall(FAR)
	assert_true(_do(&"build.breach", {"actor": _player, "piece": wall}), "started")
	_sim.step_n(50)
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(other, _sim.snapshot()), OK, "restores")
	assert_true(SimAssembly.build_of(other).is_breaching(_player), "still breaching")
	var bad: Dictionary = _build.snapshot().duplicate(true)
	var breaching: Dictionary = bad["breaching"]
	var rec: Dictionary = breaching[_player]
	rec["ticks"] = -3
	assert_eq(SimAssembly.build_of(SimAssembly.build(SEED, db)).restore(bad), ERR_INVALID_DATA, "a negative countdown is rejected")


func test_whoever_stands_on_a_breached_floor_falls_through() -> void:
	# claims 1 and 4 together: the breach is never refused, the guard on top drops
	_setup()
	assert_true(_build.place(_player, &"foundation_block", _at(FAR, 0, 0, 1), "") > 0, "foundation")
	var floor_id: int = _build.place(_player, &"floor_panel", _at(FAR, 0, 0, 0), "py")
	assert_true(floor_id > 0, "a floor over the player's cell")
	var guard: int = SimAssembly.perception_of(_sim).spawn(&"guard_sim", BuildSystem.cell_of(_at(FAR, 0, 1, 0)), 0, 1, "")
	assert_true(guard > 0, "a guard on it")
	assert_true(_do(&"build.breach", {"actor": _player, "piece": floor_id}), "cut from below")
	_sim.step_n(_ticks_of(floor_id) + 12)
	assert_false(_build.has_piece(floor_id), "the floor is out")
	assert_eq(BuildSystem.storey_of(_actors.position_of(guard)), 0, "the guard dropped to the ground")
