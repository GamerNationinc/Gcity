extends GcityTest

## M4 spec claims 1–5: agents are content-profiled actors; awareness is an integer
## accumulator over sight (cone, range, a line walk on the build grid) and noise; a
## contact is remembered for a while; `perception.alerted` fires once per crossing.

const SEED: int = 20261020
const SEED_LOS: int = 20261021
const SEED_METAMORPHIC: int = 20261022
const PROPERTY_CASES: int = 10_000
const METAMORPHIC_CASES: int = 150
const M: int = 1000
## Far from every authored parcel, so rights never enter these tests.
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)
const NEVER: int = 100_000

var _sim: SimRoot
var _actors: ActorSystem
var _perception: PerceptionSystem
var _build: BuildSystem
var _events: EventBus
var _player: int = 0
var _alerts: Array[Dictionary] = []


func _setup(db: ContentDb = null) -> void:
	if db == null:
		db = ContentDb.new()
		assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_perception = SimAssembly.perception_of(_sim)
	_build = SimAssembly.build_of(_sim)
	_events = SimAssembly.combat_of(_sim).events()
	_events.subscribe(PerceptionSystem.EVENT_ALERTED, _on_alerted)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, _at(10, 0))


func _on_alerted(payload: Dictionary) -> void:
	_alerts.append(payload)


## Cell coordinates relative to FAR's cell.
func _cell(cx: int, cz: int) -> Vector3i:
	return BuildSystem.cell_of(FAR) + Vector3i(cx, 0, cz)


## The ground-level centre of a relative cell, in millimetres.
func _at(cx: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, 0, cz * M + 500)


func _guard(profile: StringName = &"guard_sim", cx: int = 0, cz: int = 0, facing: int = 0, squad: int = 1) -> int:
	var id: int = _perception.spawn(profile, _cell(cx, cz), facing, squad, "")
	assert_true(id > 0, "guard spawned")
	return id


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


func _ticks_to_alert(observer: int, contact: int, limit: int) -> int:
	for i: int in limit:
		_sim.step()
		if _perception.is_alerted(observer, contact):
			return i + 1
	return NEVER


# ---------------------------------------------------------------- claim 1: agents are content

func test_spawn_binds_the_profiles_and_places_the_agent_on_the_ground() -> void:
	_setup()
	var guard: int = _guard(&"guard_sim", 3, 4, 90, 2)
	assert_true(_perception.is_agent(guard), "registered")
	assert_false(_perception.is_agent(_player), "the player is not an agent")
	assert_eq(_actors.profile_of(guard), &"guard", "combat profile from the agent profile")
	assert_eq(_perception.profile_of(guard), &"guard_sim", "agent profile")
	assert_eq(_perception.facing_of(guard), 90, "facing")
	assert_eq(_perception.squad_of(guard), 2, "squad")
	assert_eq(_actors.position_of(guard), _at(3, 4), "cell centre at ground level")
	assert_eq(_perception.perception_of(guard)["sight_range_mm"], 40000, "perception profile resolved through the agent profile")
	assert_eq(_perception.spawn(&"nobody", _cell(0, 0), 0, 0, ""), 0, "unknown profile")
	assert_eq(_perception.spawn(&"guard_sim", _cell(0, 0), 360, 0, ""), 0, "facing out of range")
	assert_eq(_perception.spawn(&"guard_sim", _cell(0, 0), 0, 0, "nowhere"), 0, "unknown route")
	assert_true(_perception.set_profile(guard, &"guard_arcade"), "profile swap")
	assert_eq(_perception.perception_of(guard)["fov_deg"], 150, "the new perception profile applies")
	assert_false(_perception.set_profile(_player, &"guard_arcade"), "not an agent")
	assert_false(_perception.set_profile(guard, &"nobody"), "unknown profile")


func test_spawn_and_set_profile_command_contracts() -> void:
	_setup()
	var cell: Array[int] = [_cell(0, 0).x, 0, _cell(0, 0).z]
	assert_true(_do(PerceptionSystem.COMMAND_SPAWN, {"profile": "guard_sim", "cell": cell, "facing": 0, "squad": 1, "route": ""}), "spawn")
	assert_eq(_perception.agent_ids().size(), 1, "one agent")
	var guard: int = _perception.agent_ids()[0]
	assert_false(_do(PerceptionSystem.COMMAND_SPAWN, {"profile": "guard_sim", "cell": cell, "facing": 0, "squad": 1}), "missing route")
	assert_false(_do(PerceptionSystem.COMMAND_SPAWN, {"profile": "guard_sim", "cell": [1, 2], "facing": 0, "squad": 1, "route": ""}), "short cell")
	assert_false(_do(PerceptionSystem.COMMAND_SPAWN, {"profile": "guard_sim", "cell": [1, 2.5, 3], "facing": 0, "squad": 1, "route": ""}), "fractional cell")
	assert_false(_do(PerceptionSystem.COMMAND_SPAWN, {"profile": "guard_sim", "cell": cell, "facing": 360, "squad": 1, "route": ""}), "facing")
	assert_false(_do(PerceptionSystem.COMMAND_SPAWN, {"profile": "guard_sim", "cell": cell, "facing": 0, "squad": -1, "route": ""}), "squad")
	assert_false(_do(PerceptionSystem.COMMAND_SPAWN, {"profile": "guard_sim", "cell": cell, "facing": 0, "squad": 1, "route": "nowhere"}), "route")
	assert_false(_do(PerceptionSystem.COMMAND_SPAWN, {"profile": "guard_sim", "cell": cell, "facing": 0, "squad": 1, "route": "", "hp": 1}), "extra key")
	assert_eq(_perception.agent_ids().size(), 1, "still one agent")
	assert_true(_do(PerceptionSystem.COMMAND_SET_PROFILE, {"agent": guard, "profile": "guard_arcade"}), "set_profile")
	assert_eq(_perception.profile_of(guard), &"guard_arcade", "applied")
	assert_false(_do(PerceptionSystem.COMMAND_SET_PROFILE, {"agent": _player, "profile": "guard_arcade"}), "not an agent")
	assert_false(_do(PerceptionSystem.COMMAND_SET_PROFILE, {"agent": guard, "profile": "nobody"}), "unknown profile")
	assert_false(_do(PerceptionSystem.COMMAND_SET_PROFILE, {"agent": guard}), "missing profile")


# ---------------------------------------------------------------- claim 2: awareness accumulates

func test_time_to_alert_is_the_recorded_tick_count_for_both_profiles() -> void:
	_setup()
	var guard: int = _guard(&"guard_sim", 0, 0, 0)
	_sim.step()
	assert_eq(_perception.awareness_of(guard, _player), 31250, "one tick of full exposure at 10 m")
	assert_eq(_ticks_to_alert(guard, _player, 100), 31, "guard_sim: alerted on the 32nd tick of sight")
	assert_eq(_alerts.size(), 1, "one perception.alerted")
	assert_eq(_alerts[0]["observer"], guard, "observer")
	assert_eq(_alerts[0]["contact"], _player, "contact")
	assert_eq(_alerts[0]["tick"], 32, "on tick 32")
	_sim.step_n(10)
	assert_eq(_alerts.size(), 1, "no repeat while it stays above the threshold")
	assert_eq(_perception.awareness_of(guard, _player), PerceptionSystem.AWARENESS_MAX, "clamped")
	_alerts.clear()
	_setup()
	var arcade: int = _guard(&"guard_arcade", 0, 0, 0)
	assert_eq(_ticks_to_alert(arcade, _player, 100), 12, "guard_arcade: alerted on the 12th tick")


func test_range_cone_and_movement_shape_the_gain() -> void:
	assert_eq(_rest_gain_at(_at(-10, 0)), 0, "behind the guard: nothing")
	assert_eq(_rest_gain_at(_at(0, 10)), 0, "90 degrees off a 120 degree cone: nothing")
	assert_eq(_rest_gain_at(_at(0, 0) + Vector3i(41 * M, 0, 0)), 0, "past 40 m: nothing")
	assert_eq(_rest_gain_at(_at(0, 0) + Vector3i(39 * M, 0, 0)), 1562, "at 39 m of 40: a twentieth of the gain")
	assert_eq(_rest_gain_at(_at(10, 0)), 31250, "10 m is inside half range: full gain")
	_setup()
	var guard: int = _guard(&"guard_sim", 0, 0, 0)
	_sim.step()
	var before: int = _perception.awareness_of(guard, _player)
	assert_true(_do(MovementSystem.COMMAND_MOVE, {"actor": _player, "dx": 0, "dz": 150}), "the player steps")
	assert_eq(_perception.awareness_of(guard, _player) - before, 31250 + 150 * 60, "a moving contact is easier to notice")
	var p: Dictionary = _perception.perception_of(guard)
	assert_eq(PerceptionSystem.exposure_gain(p, 20000, 0), 31250, "half range is still full")
	assert_eq(PerceptionSystem.exposure_gain(p, 40000, 0), 0, "zero at the range")
	assert_eq(PerceptionSystem.exposure_gain(p, 0, 100000), PerceptionSystem.AWARENESS_MAX, "clamped")


## Awareness a fresh guard at the origin (facing +x) gains from a tick with the player
## at rest at `pos`: the first tick has no previous position, the second is measured.
func _rest_gain_at(pos: Vector3i) -> int:
	_setup()
	var guard: int = _guard(&"guard_sim", 0, 0, 0)
	_actors.set_position(_player, pos)
	_sim.step()
	var before: int = _perception.awareness_of(guard, _player)
	_sim.step()
	return _perception.awareness_of(guard, _player) - before


func test_property_gain_is_monotone_in_distance_and_perception() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_METAMORPHIC
	var violations: int = 0
	for case: int in PROPERTY_CASES:
		var range_mm: int = rng.randi_range(1, 100000)
		var gain: int = rng.randi_range(0, 1000000)
		var speed_gain: int = rng.randi_range(0, 1000)
		var p: Dictionary = {"sight_range_mm": range_mm, "gain_per_tick": gain, "speed_gain_per_mm_per_tick": speed_gain}
		var near: int = rng.randi_range(0, range_mm)
		var far: int = rng.randi_range(near, range_mm)
		var moved: int = rng.randi_range(0, 500)
		var less_range: int = rng.randi_range(1, range_mm)
		var less: Dictionary = {"sight_range_mm": less_range, "gain_per_tick": rng.randi_range(0, gain), "speed_gain_per_mm_per_tick": rng.randi_range(0, speed_gain)}
		var g_near: int = PerceptionSystem.exposure_gain(p, near, moved)
		var g_far: int = PerceptionSystem.exposure_gain(p, far, moved)
		var g_less: int = PerceptionSystem.exposure_gain(less, near, moved) if near <= less_range else 0
		if g_far > g_near or g_less > g_near or g_near < 0 or g_near > PerceptionSystem.AWARENESS_MAX or PerceptionSystem.exposure_gain(p, near, moved + 1) < g_near:
			violations += 1
			if violations <= 3:
				fail("case %d: near %d far %d less %d" % [case, g_near, g_far, g_less])
	assert_eq(violations, 0, "farther never gains more; weaker perception never gains more; movement never gains less")


func test_metamorphic_reduced_perception_never_lowers_time_to_alert() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_METAMORPHIC
	var violations: int = 0
	var alerted_cases: int = 0
	for case: int in METAMORPHIC_CASES:
		var range_mm: int = rng.randi_range(5000, 60000)
		var fov: int = rng.randi_range(10, 360)
		var gain: int = rng.randi_range(1000, 200000)
		var speed_gain: int = rng.randi_range(0, 200)
		var threshold: int = rng.randi_range(1, 1000000)
		var base: Dictionary = {"schema_version": 1, "description": "generated", "sight_range_mm": range_mm, "fov_deg": fov,
			"gain_per_tick": gain, "speed_gain_per_mm_per_tick": speed_gain, "decay_per_tick": rng.randi_range(0, 5000),
			"alert_threshold": threshold, "memory_ticks": 10, "hearing_range_mm": 0, "hearing_gain": 0}
		var less: Dictionary = base.duplicate()
		less["sight_range_mm"] = rng.randi_range(1, range_mm)
		less["fov_deg"] = rng.randi_range(1, fov)
		less["gain_per_tick"] = rng.randi_range(0, gain)
		less["speed_gain_per_mm_per_tick"] = rng.randi_range(0, speed_gain)
		less["alert_threshold"] = rng.randi_range(threshold, 1000000)
		var db := ContentDb.new()
		assert_eq(ContentLoader.load_all(db), OK, "content loads")
		db.add(&"perception_profile", &"t_base", base)
		db.add(&"perception_profile", &"t_less", less)
		db.add(&"agent_profile", &"t_base", {"schema_version": 1, "description": "generated", "combat_profile": "arcade", "perception_profile": "t_base", "aim_profile": "guard_sim", "stress_profile": "guard_sim", "stances": [{"stance": "hold", "weight": 1000}], "radio": false, "radio_latency_ticks": 0})
		db.add(&"agent_profile", &"t_less", {"schema_version": 1, "description": "generated", "combat_profile": "arcade", "perception_profile": "t_less", "aim_profile": "guard_sim", "stress_profile": "guard_sim", "stances": [{"stance": "hold", "weight": 1000}], "radio": false, "radio_latency_ticks": 0})
		# most contacts start inside the base range and its cone, so that many cases alert
		var facing: int = rng.randi_range(0, 359)
		var bearing: int = facing + rng.randi_range(-fov / 2, fov / 2) if rng.randi_range(0, 3) > 0 else rng.randi_range(0, 359)
		var reach: int = rng.randi_range(1, range_mm / 1000 + 5)
		var dx: int = PerceptionSystem.cos_milli(bearing) * reach / 1000
		var dz: int = PerceptionSystem.sin_milli(bearing) * reach / 1000
		var ticks: Array[int] = []
		for profile: StringName in [&"t_base", &"t_less"]:
			_setup(db)
			_actors.set_position(_player, _at(dx, dz))
			var guard: int = _guard(profile, 0, 0, facing)
			ticks.append(_ticks_to_alert(guard, _player, 300))
		if ticks[0] != NEVER:
			alerted_cases += 1
		if ticks[1] < ticks[0]:
			violations += 1
			if violations <= 3:
				fail("case %d: base %d ticks, reduced %d ticks" % [case, ticks[0], ticks[1]])
	assert_eq(violations, 0, "reduced perception never alerts sooner")
	assert_true(alerted_cases > 20, "enough cases alerted at all (%d)" % alerted_cases)


# ---------------------------------------------------------------- claim 3: line of sight

func test_walls_and_solids_block_sight_and_openings_pass_it() -> void:
	_setup()
	var guard: int = _guard(&"guard_sim", 3, 3, 90)
	_actors.set_position(_player, _at(3, 4))
	assert_true(_perception.can_see(guard, _player), "open ground")
	_build.place(_player, &"foundation_block", _at(3, 5), "")
	var wall: int = _build.place(_player, &"wall_panel", _at(3, 4), "nz")
	assert_true(wall > 0, "a ground-level wall between z = 3 and z = 4")
	assert_false(_perception.can_see(guard, _player), "the wall blocks")
	assert_false(_perception.line_of_sight(_at(3, 4), _at(3, 3)), "and blocks the other way")
	_sim.step()
	assert_eq(_perception.awareness_of(guard, _player), 0, "nothing gained through a wall")
	_build.breach(wall)
	var door: int = _build.place(_player, &"door_frame", _at(3, 4), "nz")
	assert_true(door > 0, "a door in its place")
	assert_true(_perception.can_see(guard, _player), "a door passes sight")
	_build.breach(door)
	var window: int = _build.place(_player, &"window_frame", _at(3, 4), "nz")
	assert_true(window > 0, "a window in its place")
	assert_true(_perception.can_see(guard, _player), "a window passes sight")
	_actors.set_position(_player, _at(3, 6))
	assert_false(_perception.can_see(guard, _player), "the foundation in between is opaque")
	assert_true(_perception.line_of_sight(_at(3, 3), _at(3, 3) + Vector3i(0, 0, 400)), "inside one cell")


func test_property_line_of_sight_is_symmetric_never_through_a_wall_and_clear_in_the_open() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_LOS
	_setup()
	# a fixed lattice of foundations for random walls to hang off; the walk never removes it
	var lattice: Dictionary = {}
	for x: int in [0, 2, 4]:
		for z: int in [0, 2, 4]:
			lattice[_build.place(_player, &"foundation_block", _at(x, z), "")] = true
	var templates: Array[StringName] = [&"foundation_block", &"storage_crate", &"wall_panel", &"door_frame", &"window_frame", &"concrete_wall"]
	var facings: Array[String] = ["px", "nx", "pz", "nz"]
	var failures: int = 0
	var blocked_seen: int = 0
	var open_seen: int = 0
	for case: int in PROPERTY_CASES:
		if rng.randi_range(0, 3) > 0 or _build.piece_ids().size() <= lattice.size():
			var t: StringName = templates[rng.randi_range(0, templates.size() - 1)]
			var facing: String = "" if t == &"foundation_block" or t == &"storage_crate" else facings[rng.randi_range(0, 3)]
			_build.place(_player, t, _at(rng.randi_range(0, 4), rng.randi_range(0, 4)), facing)
		else:
			var ids: Array[int] = _build.piece_ids()
			var victim: int = ids[rng.randi_range(0, ids.size() - 1)]
			if not lattice.has(victim):
				_build.remove(_player, victim)
		var a: Vector3i = FAR + Vector3i(rng.randi_range(-M, 6 * M - 1), 0, rng.randi_range(-M, 6 * M - 1))
		var b: Vector3i = a + Vector3i(rng.randi_range(-3 * M, 3 * M), 0, rng.randi_range(-3 * M, 3 * M))
		if _build.cell_piece_at(BuildSystem.cell_of(a)) != EntityIds.NONE or _build.cell_piece_at(BuildSystem.cell_of(b)) != EntityIds.NONE:
			continue
		var los: bool = _perception.line_of_sight(a, b)
		var problem: String = ""
		if los != _perception.line_of_sight(b, a):
			problem = "asymmetric"
		var oracle: String = _sampled_oracle(a, b)
		if oracle == "blocked":
			blocked_seen += 1
			if los:
				problem = "sight through a solid face or cell"
		elif oracle == "open":
			open_seen += 1
			if not los:
				problem = "no sight across empty cells"
		if not problem.is_empty():
			failures += 1
			if failures <= 3:
				fail("case %d: %s from %s to %s" % [case, problem, a, b])
	assert_eq(failures, 0, "line of sight invariants held (%d blocked, %d open)" % [blocked_seen, open_seen])
	assert_true(blocked_seen > 500 and open_seen > 500, "both outcomes were exercised (%d blocked, %d open)" % [blocked_seen, open_seen])


## Samples the segment every 50 mm. "blocked" when an axis-aligned cell change crosses
## an impassable face or enters a cell piece; "open" when no piece touches any cell of
## the segment's bounding box; "" when only a corner crossing decides it.
func _sampled_oracle(a: Vector3i, b: Vector3i) -> String:
	var lo: Vector3i = BuildSystem.cell_of(Vector3i(mini(a.x, b.x), 0, mini(a.z, b.z)))
	var hi: Vector3i = BuildSystem.cell_of(Vector3i(maxi(a.x, b.x), 0, maxi(a.z, b.z)))
	var touched: bool = false
	for id: int in _build.piece_ids():
		for c: Vector3i in _build.cells_of_piece(id):
			if c.x >= lo.x and c.x <= hi.x and c.z >= lo.z and c.z <= hi.z and c.y == 0:
				touched = true
	if not touched:
		return "open"
	var d: Vector3i = b - a
	var length: int = PerceptionSystem.distance_mm(a, b)
	var steps: int = maxi(length / 50, 1)
	var prev: Vector3i = BuildSystem.cell_of(a)
	for i: int in steps + 1:
		var p: Vector3i = a + Vector3i(d.x * i / steps, 0, d.z * i / steps)
		var cell: Vector3i = BuildSystem.cell_of(p)
		if cell == prev:
			continue
		var delta: Vector3i = cell - prev
		if absi(delta.x) + absi(delta.z) != 1:
			return ""
		if _near_corner(a, d, prev, delta):
			return ""
		if _build.cell_piece_at(cell) != EntityIds.NONE:
			return "blocked"
		var facing: String = "px" if delta.x > 0 else ("nx" if delta.x < 0 else ("pz" if delta.z > 0 else "nz"))
		var piece: int = _build.face_piece_at(BuildSystem.face_key(prev, facing))
		if piece != EntityIds.NONE:
			var kind: Dictionary = _build.kind_data(piece)
			var passable: bool = kind["passable"]
			if not passable:
				return "blocked"
		prev = cell
	return ""


## Whether the exact crossing of the face between `prev` and `prev + delta` lies within
## 2 mm of a cell corner, where the walk's tie-breaking (not the geometry) decides.
func _near_corner(a: Vector3i, d: Vector3i, prev: Vector3i, delta: Vector3i) -> bool:
	if delta.x != 0:
		if d.x == 0:
			return true
		var boundary: int = (prev.x + 1) * M if delta.x > 0 else prev.x * M
		var z_at: float = float(a.z) + float(d.z) * float(boundary - a.x) / float(d.x)
		var frac: float = fposmod(z_at, float(M))
		return frac < 2.0 or frac > float(M) - 2.0
	if d.z == 0:
		return true
	var boundary_z: int = (prev.z + 1) * M if delta.z > 0 else prev.z * M
	var x_at: float = float(a.x) + float(d.x) * float(boundary_z - a.z) / float(d.z)
	var frac_x: float = fposmod(x_at, float(M))
	return frac_x < 2.0 or frac_x > float(M) - 2.0


func test_cone_arithmetic() -> void:
	assert_eq(PerceptionSystem.cos_milli(0), 1000, "cos 0")
	assert_eq(PerceptionSystem.cos_milli(90), 0, "cos 90")
	assert_eq(PerceptionSystem.cos_milli(270), 0, "cos 270")
	assert_eq(PerceptionSystem.cos_milli(-60), 500, "cos -60")
	assert_eq(PerceptionSystem.sin_milli(90), 1000, "sin 90")
	assert_eq(PerceptionSystem.sin_milli(180), 0, "sin 180")
	assert_true(PerceptionSystem.in_cone(0, Vector2i(1000, 500), 120), "26 degrees off a 120 degree cone")
	assert_false(PerceptionSystem.in_cone(0, Vector2i(1000, 2000), 120), "63 degrees off: outside")
	assert_true(PerceptionSystem.in_cone(90, Vector2i(0, 1000), 10), "along +z when facing 90")
	assert_true(PerceptionSystem.in_cone(180, Vector2i(-1000, -100), 30), "facing -x")
	assert_true(PerceptionSystem.in_cone(0, Vector2i(-1000, 0), 360), "a full circle sees behind")
	assert_true(PerceptionSystem.in_cone(45, Vector2i.ZERO, 1), "a zero offset is always inside")


# ---------------------------------------------------------------- claims 4 and 5: noise and memory

func test_a_shot_is_heard_within_range_and_remembered_at_its_position() -> void:
	_setup()
	var items: ItemSystem = SimAssembly.items_of(_sim)
	var pistol: int = items.spawn(&"weapon_frame", &"g19", ItemSystem.inventory_of(_player), 1)
	var near: int = _guard(&"guard_sim", 20, 0, 0)  # 10 m ahead of the player, facing away from it
	var far: int = _guard(&"guard_sim", 80, 0, 180)  # 70 m: beyond both ranges
	_actors.set_position(_player, _at(10, 0))
	assert_false(_perception.can_see(near, _player), "the near guard faces away")
	_events.emit(CombatSystem.EVENT_FIRE, {"shooter": _player, "weapon": pistol, "target": near, "round": 0, "tags": []})
	assert_eq(_perception.awareness_of(near, _player), 500000, "heard: the hearing gain")
	assert_eq(_perception.last_known(near, _player), _at(10, 0), "the shot's position")
	assert_eq(_perception.memory_of(near, _player), 400, "memory set")
	assert_eq(_perception.awareness_of(far, _player), 0, "beyond 60 m: nothing")
	assert_false(_perception.has_last_known(far, _player), "and nothing remembered")
	_sim.step()
	assert_eq(_perception.awareness_of(near, _player), 500000, "no decay on the tick the shot was heard")
	_sim.step()
	assert_eq(_perception.awareness_of(near, _player), 490000, "decays afterwards")
	assert_eq(_perception.memory_of(near, _player), 399, "memory counts down while unseen")
	_events.emit(CombatSystem.EVENT_FIRE, {"shooter": _player, "weapon": pistol, "target": near, "round": 0, "tags": []})
	assert_eq(_perception.awareness_of(near, _player), 990000, "a second shot adds the gain again")
	_events.emit(CombatSystem.EVENT_FIRE, {"shooter": _player, "weapon": pistol, "target": near, "round": 0, "tags": []})
	_sim.step()
	assert_true(_perception.is_alerted(near, _player), "a third shot crosses the threshold")
	assert_eq(_alerts.size(), 1, "alerted by ear")


func test_memory_decays_and_alert_re_fires_after_dropping_below_the_threshold() -> void:
	_setup()
	var guard: int = _guard(&"guard_sim", 0, 0, 0)
	assert_eq(_ticks_to_alert(guard, _player, 100), 32, "alerted")
	_actors.set_position(_player, _at(-10, 0))
	_sim.step()
	assert_eq(_perception.awareness_of(guard, _player), 990000, "decays once out of sight")
	assert_false(_perception.is_alerted(guard, _player), "below the threshold again")
	assert_eq(_perception.last_known(guard, _player), _at(10, 0), "last seen where it was")
	assert_eq(_perception.memory_of(guard, _player), 399, "memory counts down")
	_actors.set_position(_player, _at(10, 0))
	_sim.step()
	assert_true(_perception.is_alerted(guard, _player), "back in sight: over the threshold")
	assert_eq(_alerts.size(), 2, "a second perception.alerted")
	_actors.set_position(_player, _at(-10, 0))
	_sim.step_n(100)
	assert_eq(_perception.awareness_of(guard, _player), 0, "forgotten")
	assert_eq(_perception.memory_of(guard, _player), 300, "memory outlives awareness")
	_sim.step_n(300)
	assert_false(_perception.has_last_known(guard, _player), "then the position goes too")
	assert_eq(_perception.awareness_of(guard, _player), 0, "and the record is gone")


func test_squadmates_are_not_contacts() -> void:
	_setup()
	var a: int = _guard(&"guard_sim", 0, 0, 0, 1)
	var b: int = _guard(&"guard_sim", 5, 0, 180, 1)
	var c: int = _guard(&"guard_sim", 20, 0, 180, 2)
	_actors.set_position(_player, _at(-10, 0))
	_sim.step()
	assert_eq(_perception.awareness_of(a, b), 0, "same squad, facing each other: not a contact")
	assert_eq(_perception.awareness_of(b, a), 0, "either way")
	assert_true(_perception.awareness_of(a, c) > 0, "another squad is a contact")
	assert_true(_perception.awareness_of(c, a) > 0, "and sees back")


# ---------------------------------------------------------------- restore

func test_restore_round_trip_and_rejections() -> void:
	_setup()
	var guard: int = _guard(&"guard_sim", 0, 0, 0)
	_sim.step_n(5)
	var snap: Dictionary = _sim.snapshot()
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "restored")
	assert_eq(other.restore_root(snap), OK, "root restored")
	var perception: PerceptionSystem = SimAssembly.perception_of(other)
	assert_eq(perception.snapshot(), _perception.snapshot(), "equal state")
	assert_eq(perception.awareness_of(guard, _player), 5 * 31250, "awareness carried over")
	_sim.step()
	other.step()
	assert_eq(other.state_hash(), _sim.state_hash(), "steps on together")
	var state: Dictionary = _perception.snapshot()
	assert_eq(perception.restore({}), ERR_INVALID_DATA, "empty")
	var bad: Dictionary = state.duplicate(true)
	var contacts: Dictionary = bad["contacts"]
	var table: Dictionary = contacts[guard]
	table[99] = table[_player]
	assert_eq(perception.restore(bad), ERR_INVALID_DATA, "a contact that is not an actor")
	bad = state.duplicate(true)
	var agents: Dictionary = bad["agents"]
	agents[_player] = agents[guard]
	var rec: Dictionary = agents[_player]
	rec["facing"] = 400
	assert_eq(perception.restore(bad), ERR_INVALID_DATA, "a facing out of range")
	bad = state.duplicate(true)
	bad["alerts"] = -1
	assert_eq(perception.restore(bad), ERR_INVALID_DATA, "a negative counter")
	assert_eq(perception.snapshot(), state, "rejections leave the state untouched")


## M7 spec claim 13: out in the wilds the ground blocks sight like a wall does. A
## contact on the far side of a rise is not seen; with nothing between, it is.
func test_the_ground_hides_what_is_behind_it() -> void:
	_setup()
	var regions: Regions = SimAssembly.regions_of(_sim)
	var perception: PerceptionSystem = SimAssembly.perception_of(_sim)
	# a rise between two people, higher than both of them by two levels, inside a
	# guard's sight range
	var found: bool = false
	var a: Vector3i = Vector3i.ZERO
	var b: Vector3i = Vector3i.ZERO
	# along rows, so neighbouring probes share the ground chunks they read
	for i: int in 12000:
		var cx: int = 300 + (i % 4000) * 5
		var cz: int = -2000 - (i / 4000) * 997
		var y0: int = regions.standing_cell_y(cx * 1000, cz * 1000)
		var ridge: int = regions.standing_cell_y((cx + 15) * 1000, cz * 1000)
		var y1: int = regions.standing_cell_y((cx + 30) * 1000, cz * 1000)
		if ridge >= maxi(y0, y1) + 2:
			a = Vector3i(cx * 1000 + 500, y0 * 1000, cz * 1000 + 500)
			b = Vector3i((cx + 30) * 1000 + 500, y1 * 1000, cz * 1000 + 500)
			found = true
			break
	assert_true(found, "the wilds have a rise to hide behind")
	assert_false(perception.line_of_sight(a, b), "a rise between two people hides them from each other")
	var open_a: Vector3i = Vector3i(500, 0, -40_000)
	var open_b: Vector3i = Vector3i(10_500, 0, -40_000)
	assert_true(perception.line_of_sight(open_a, open_b), "on the level apron outside the gate they see each other")

