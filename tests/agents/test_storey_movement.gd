extends GcityTest

## M6 spec claim 1 in movement (ADR-011 C): actors move in x/z on their storey; an
## actor with nothing under it falls a storey every `fall.ticks_per_storey` ticks and
## takes the content's landing damage; only a profile with the `drop` move steps off
## an edge; agents spawn only where they can stand. Property: over 10 000 generated
## build, move and tick operations, every living actor stands on a standable cell or
## is falling, every fall lands on time, and the landing damage equals the formula.

const SEED: int = 20261009
const PROPERTY_CASES: int = 10_000
const SEED_STREAM: int = 20261010
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


## The centre of a cell at floor level: where an actor on that storey stands.
func _feet(cx: int, storey: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, storey * BuildSystem.STOREY_MM, cz * M + 500)


func _at(cx: int, cy: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, cy * M + 500, cz * M + 500)


## A 3×1 deck on storey 1 over x 1..3, z 0: foundations at its ends, floors between.
func _deck() -> void:
	assert_true(_build.place(_player, &"foundation_block", _at(1, 0, 0), "") > 0, "west foundation")
	assert_true(_build.place(_player, &"foundation_block", _at(3, 0, 0), "") > 0, "east foundation")
	assert_true(_build.place(_player, &"floor_panel", _at(2, 0, 0), "py") > 0, "floor between")


func _tick(n: int) -> void:
	for i: int in n:
		_sim.step()


func _fall_of(actor: int) -> Dictionary:
	var t: Dictionary = _actors.profile_data(actor)
	return t["fall"]


func _body(actor: int) -> int:
	var h: Dictionary = _actors.health_of(actor)
	return h["body"]


func test_a_guard_on_a_deck_cannot_step_off_its_edge() -> void:
	_setup()
	_deck()
	var guard: int = SimAssembly.perception_of(_sim).spawn(&"guard_sim", BuildSystem.cell_of(_feet(2, 1, 0)), 0, 1, "")
	assert_true(guard > 0, "a guard on the deck")
	for i: int in 40:
		_movement.move(guard, 60, 0)
	assert_eq(BuildSystem.cell_of(_actors.position_of(guard)), BuildSystem.cell_of(_feet(3, 1, 0)), "onto the east foundation's top and no further")
	for i: int in 40:
		_movement.move(guard, 0, -60)
	assert_eq(BuildSystem.cell_of(_actors.position_of(guard)), BuildSystem.cell_of(_feet(3, 1, 0)), "nor off the side")


func test_the_player_steps_off_an_edge_and_falls_one_storey_unhurt() -> void:
	_setup()
	_deck()
	var landed: Array[Dictionary] = []
	var sink: Callable = func(payload: Dictionary) -> void:
		landed.append(payload)
	SimAssembly.combat_of(_sim).events().subscribe(MovementSystem.EVENT_LANDED, sink)
	assert_eq(_actors.set_position(_player, _feet(3, 1, 0)), OK, "on the east foundation")
	for i: int in 4:
		_movement.move(_player, 150, 0)
	assert_eq(BuildSystem.cell_of(_actors.position_of(_player)), BuildSystem.cell_of(_feet(4, 1, 0)), "stepped off into the air")
	_tick(1)
	assert_true(_movement.is_falling(_player), "falling")
	assert_false(_movement.move(_player, -150, 0), "no moving while falling")
	var fall: Dictionary = _fall_of(_player)
	var tps: int = fall["ticks_per_storey"]
	_tick(tps - 1)
	assert_false(_movement.is_falling(_player), "landed after one storey's ticks")
	assert_eq(BuildSystem.storey_of(_actors.position_of(_player)), 0, "on the ground")
	assert_eq(_body(_player), 100000, "one storey is free")
	assert_eq(landed.size(), 1, "one landing")
	assert_eq(landed[0], {"actor": _player, "storeys": 1, "damage": 0}, "the landing event")


func test_a_two_storey_fall_hurts_by_the_formula() -> void:
	_setup()
	assert_eq(_actors.set_position(_player, _feet(0, 2, 0)), OK, "two storeys up in the air")
	var fall: Dictionary = _fall_of(_player)
	var tps: int = fall["ticks_per_storey"]
	var free: int = fall["free_storeys"]
	var per: int = fall["damage_per_storey"]
	_tick(2 * tps)
	assert_false(_movement.is_falling(_player), "landed")
	assert_eq(_body(_player), 100000 - maxi(0, 2 - free) * per, "damage by the formula")
	assert_true(_actors.is_alive(_player), "alive")


func test_a_long_enough_fall_kills() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	var brittle: Dictionary = db.get_entry(&"combat_profile", &"arcade").duplicate(true)
	var fall: Dictionary = brittle["fall"]
	fall["free_storeys"] = 0
	fall["damage_per_storey"] = 60000
	assert_eq(db.add(&"combat_profile", &"zz_brittle", brittle), OK, "a brittle profile")
	_sim = SimAssembly.build(SEED, db)
	_actors = SimAssembly.actors_of(_sim)
	_movement = SimAssembly.movement_of(_sim)
	var a: int = _actors.spawn(&"zz_brittle", 0)
	assert_eq(_actors.set_position(a, _feet(0, 2, 0)), OK, "two storeys up")
	_tick(2 * 12)
	assert_false(_actors.is_alive(a), "120 000 on a 100 000 body kills")
	assert_eq(BuildSystem.storey_of(_actors.position_of(a)), 0, "the body lies on the ground")


func test_a_floor_removed_under_an_actor_drops_it() -> void:
	_setup()
	_deck()
	assert_eq(_actors.set_position(_player, _feet(2, 1, 0)), OK, "on the floor panel")
	var floor_id: int = _build.face_piece_at(BuildSystem.face_key(BuildSystem.cell_of(_feet(2, 1, 0)), "ny"))
	assert_true(floor_id > 0, "the panel")
	assert_false(_build.remove(_player, floor_id).is_empty(), "removed")
	_tick(12)
	assert_eq(BuildSystem.storey_of(_actors.position_of(_player)), 0, "fell through to the ground")


func test_dead_actors_fall_too() -> void:
	_setup()
	var dummy: int = _actors.spawn(&"range_dummy", 0)
	assert_eq(_actors.set_position(dummy, _feet(4, 1, 4)), OK, "in the air")
	_actors.damage_node(dummy, &"body", 1_000_000_000)
	assert_false(_actors.is_alive(dummy), "dead")
	_tick(12)
	assert_eq(BuildSystem.storey_of(_actors.position_of(dummy)), 0, "the body is on the ground")


func test_on_the_ground_movement_is_unchanged() -> void:
	_setup()
	for i: int in 10:
		assert_true(_movement.move(_player, 150, 0), "ground step %d" % i)
	assert_eq(_actors.position_of(_player), _feet(0, 0, 0) + Vector3i(1500, 0, 0), "1.5 m along the ground")


func test_agents_spawn_only_where_they_can_stand() -> void:
	_setup()
	_deck()
	var perception: PerceptionSystem = SimAssembly.perception_of(_sim)
	var on_deck: int = perception.spawn(&"guard_sim", BuildSystem.cell_of(_feet(2, 1, 0)), 0, 1, "")
	assert_true(on_deck > 0, "a guard on the deck")
	assert_eq(BuildSystem.storey_of(_actors.position_of(on_deck)), 1, "at storey 1")
	assert_eq(perception.spawn(&"guard_sim", BuildSystem.cell_of(_feet(5, 1, 0)), 0, 1, ""), EntityIds.NONE, "not in the air")
	assert_eq(perception.spawn(&"guard_sim", BuildSystem.cell_of(_feet(1, 0, 0)), 0, 1, ""), EntityIds.NONE, "not inside a foundation")


func test_property_every_living_actor_stands_or_falls_and_falls_land_on_time() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_STREAM
	# light fall damage, so the stream's actors survive thousands of falls and keep moving;
	# the formula is checked on every landing all the same
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	for profile: StringName in [&"arcade", &"guard"]:
		var t: Dictionary = db.get_entry(&"combat_profile", profile).duplicate(true)
		var fall: Dictionary = t["fall"]
		fall["damage_per_storey"] = 5
		assert_eq(db.add(&"combat_profile", StringName("zz_light_%s" % profile), t), OK, "light falls for %s" % profile)
	var agent: Dictionary = db.get_entry(&"agent_profile", &"guard_sim").duplicate(true)
	agent["combat_profile"] = "zz_light_guard"
	assert_eq(db.add(&"agent_profile", &"zz_light_guard", agent), OK, "a guard on the light profile")
	_setup(db)
	_deck()
	var player: int = _actors.spawn(&"zz_light_arcade", 0)
	assert_eq(_actors.set_position(player, _feet(0, 0, 2)), OK, "the light player on the ground")
	var landed: Array[Dictionary] = []
	var sink: Callable = func(payload: Dictionary) -> void:
		landed.append(payload)
	SimAssembly.combat_of(_sim).events().subscribe(MovementSystem.EVENT_LANDED, sink)
	var guard: int = SimAssembly.perception_of(_sim).spawn(&"zz_light_guard", BuildSystem.cell_of(_feet(2, 1, 0)), 0, 1, "")
	assert_true(guard > 0, "a guard on the deck")
	var movers: Array[int] = [player, guard]
	var templates: Array[StringName] = [&"foundation_block", &"storage_crate", &"floor_panel", &"wall_panel"]
	var failures: int = 0
	var accepted_moves: int = 0
	var falls: int = 0
	## actor -> ticks spent falling in the current fall
	var airborne: Dictionary = {}
	for case: int in PROPERTY_CASES:
		var op: int = rng.randi_range(0, 19)
		if op < 8:
			var who: int = movers[rng.randi_range(0, 1)]
			var cap: int = _movement.speed_of(who)
			if _movement.move(who, rng.randi_range(-cap, cap), rng.randi_range(-cap, cap)):
				accepted_moves += 1
		elif op < 11:
			var template: StringName = templates[rng.randi_range(0, templates.size() - 1)]
			var cell: Vector3i = Vector3i(rng.randi_range(-2, 6), rng.randi_range(0, 2), rng.randi_range(-3, 3))
			var facing: String = ""
			if template == &"floor_panel":
				facing = "py"
			elif template == &"wall_panel":
				facing = ["px", "nx", "pz", "nz"][rng.randi_range(0, 3)]
			_build.place(_player, template, _at(cell.x, cell.y, cell.z), facing)
		elif op < 12:
			var ids: Array[int] = _build.piece_ids()
			if not ids.is_empty():
				_build.remove(_player, ids[rng.randi_range(0, ids.size() - 1)])
		elif op == 19:
			# arrive somewhere, possibly in the air: the next ticks must bring it down
			var who: int = movers[rng.randi_range(0, 1)]
			var spot: Vector3i = _feet(rng.randi_range(-2, 6), rng.randi_range(0, 2), rng.randi_range(-3, 3))
			if not _movement.is_falling(who) and _build.cell_piece_at(BuildSystem.cell_of(spot)) == EntityIds.NONE:
				_actors.set_position(who, spot)
		else:
			landed.clear()
			var storey_before: Dictionary = {}
			for a: int in movers:
				storey_before[a] = BuildSystem.storey_of(_actors.position_of(a))
			_sim.step()
			for a: int in movers:
				if _movement.is_falling(a):
					var so_far: int = airborne.get(a, 0)
					airborne[a] = so_far + 1
			for ev: Dictionary in landed:
				var a: int = ev["actor"]
				falls += 1
				var fall: Dictionary = _fall_of(a)
				var tps: int = fall["ticks_per_storey"]
				var storeys: int = ev["storeys"]
				# a fall that lands on this tick spent `storeys` drops; it began on the
				# first tick its cell was found with nothing under it
				var in_air: int = airborne.get(a, 0)
				if in_air + 1 > storeys * tps:
					failures += 1
				var free: int = fall["free_storeys"]
				var per: int = fall["damage_per_storey"]
				var expected: int = maxi(0, storeys - free) * per
				var dealt: int = ev["damage"]
				if dealt > expected:
					failures += 1
				airborne.erase(a)
			for a: int in movers:
				if not _movement.is_falling(a):
					airborne.erase(a)
		for a: int in movers:
			if _actors.is_alive(a) and not _movement.is_falling(a) \
					and not _build.is_standable(BuildSystem.cell_of(_actors.position_of(a))) and op >= 12 and op < 19:
				failures += 1
	assert_eq(failures, 0, "standing or falling after every tick; falls land on time with the formula's damage")
	assert_true(accepted_moves > PROPERTY_CASES / 10, "the stream moved actors (%d moves)" % accepted_moves)
	assert_true(falls > 10, "the stream made actors fall (%d falls)" % falls)
