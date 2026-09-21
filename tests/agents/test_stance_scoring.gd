extends GcityTest

## M4 spec claim 10: stances are content with registered scorers; an agent scores
## the stances its profile allows on its time slice, switches with hysteresis after
## a minimum duration, and executes the choice: patrols on hold, fires through the
## client's command path at an alerted target in sight, investigates a noise,
## retreats when broken, and may only retreat or surrender when routed.

const SEED: int = 20261060
const SEED_PROPERTY: int = 20261061
const PROPERTY_CASES: int = 10_000
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)

var _sim: SimRoot
var _actors: ActorSystem
var _items: ItemSystem
var _combat: CombatSystem
var _perception: PerceptionSystem
var _stress: StressSystem
var _pathing: PathingSystem
var _stances: StanceSystem
var _player: int = 0


func _db() -> ContentDb:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	return db


func _setup(db: ContentDb = null) -> void:
	if db == null:
		db = _db()
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_combat = SimAssembly.combat_of(_sim)
	_perception = SimAssembly.perception_of(_sim)
	_stress = SimAssembly.stress_of(_sim)
	_pathing = SimAssembly.pathing_of(_sim)
	_stances = SimAssembly.stances_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, FAR + Vector3i(-40 * M, 0, -40 * M))


func _cell(cx: int, cz: int) -> Vector3i:
	return BuildSystem.cell_of(FAR) + Vector3i(cx, 0, cz)


func _at(cx: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, 0, cz * M + 500)


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


## Arms `actor` with a G19, a loaded magazine and a chambered round.
func _arm(actor: int) -> int:
	var inv: StringName = ItemSystem.inventory_of(actor)
	var pistol: int = _items.spawn(&"weapon_frame", &"g19", inv, 1)
	var mag: int = _items.spawn(&"weapon_part", &"g19_mag_15", inv, 2)
	for i: int in 15:
		var round: int = _items.spawn(&"ammo", &"9x19_fmj", inv, 100 + i)
		assert_true(_do(&"magazine.load", {"actor": actor, "magazine": mag, "round": round}), "load")
	assert_true(_do(&"actor.wield", {"actor": actor, "weapon": pistol}), "wield")
	assert_true(_do(&"weapon.reload_tactical", {"actor": actor, "weapon": pistol, "magazine": mag}), "reload")
	_sim.step_n(90)
	return pistol


func _hit_event(target: int) -> void:
	_combat.events().emit(CombatSystem.EVENT_HIT, {"shooter": _player, "weapon": 0, "target": target, "node": &"body", "damage": 1, "range_m": 5, "tags": [], "killed": false})


func test_stances_are_content_with_registered_scorers() -> void:
	_setup()
	assert_eq(_stances.implemented_stances(), [&"advance", &"flank", &"hold", &"investigate", &"retreat", &"surrender"] as Array[StringName], "six built-in scorers")
	assert_eq(_stances.register_scorer(&"hold", _hit_event), ERR_ALREADY_EXISTS, "a second scorer for a name is refused")
	var db: ContentDb = _db()
	db.add(&"stance", &"dance", {"schema_version": 1, "description": "no scorer"})
	db.add(&"agent_profile", &"dancer", {"schema_version": 1, "description": "x", "combat_profile": "arcade", "perception_profile": "guard_sim",
		"aim_profile": "guard_sim", "stress_profile": "guard_sim", "stances": [{"stance": "dance", "weight": 1000}]})
	assert_true(SimAssembly.build(SEED, db) == null, "a profile naming a stance with no scorer fails assembly")
	assert_eq(_stances.allowed_stances(_perception.spawn(&"guard_arcade", _cell(0, 0), 0, 1, "")).size(), 5, "the arcade profile allows five stances: no flank")


func test_starts_in_hold_and_patrols_its_route() -> void:
	var db: ContentDb = _db()
	var c0: Vector3i = _cell(0, 0)
	db.add(&"patrol_route", &"loop", {"schema_version": 1, "description": "a square", "cells": [[c0.x, 0, c0.z], [c0.x + 4, 0, c0.z], [c0.x + 4, 0, c0.z + 4], [c0.x, 0, c0.z + 4]]})
	_setup(db)
	var guard: int = _perception.spawn(&"guard_sim", _cell(0, 0), 0, 1, "loop")
	assert_eq(_stances.stance_of(guard), &"hold", "an agent starts holding")
	assert_eq(_stances.stance_of(_player), &"", "the player has no stance")
	var visited: Dictionary = {}
	for i: int in 500:
		_sim.step()
		visited[BuildSystem.cell_of(_actors.position_of(guard))] = true
	assert_eq(_stances.stance_of(guard), &"hold", "still holding")
	assert_true(visited.has(_cell(4, 0)) and visited.has(_cell(4, 4)) and visited.has(_cell(0, 4)), "stood on every corner of the route")
	assert_true(_stances.waypoint_of(guard) < 4, "the waypoint wraps around the loop (%d)" % _stances.waypoint_of(guard))
	assert_eq(_stances.fire_count(), 0, "nothing to shoot at")
	var idle: int = _perception.spawn(&"guard_sim", _cell(8, 8), 0, 1, "")
	var start: Vector3i = _actors.position_of(idle)
	_sim.step_n(50)
	assert_eq(_actors.position_of(idle), start, "without a route, hold stands still")


func test_detection_delay_then_the_first_shot_goes_through_the_command_path() -> void:
	_setup()
	var guard: int = _perception.spawn(&"guard_sim", _cell(0, 0), 180, 1, "")  # facing away while it arms
	_actors.set_position(_player, _at(7, 7))  # in place before the count starts: a teleport reads as movement
	_arm(guard)
	assert_true(_perception.set_facing(guard, 0), "the guard turns to face +x")
	var start_tick: int = _sim.get_tick()
	var dispatched: int = _sim.dispatched_count()
	var ticks: int = 0
	while _combat.shots() == 0 and ticks < 200:
		_sim.step()
		ticks += 1
	assert_eq(ticks, 33, "time_to_first_shot: alerted on the 32nd tick of sight, the shot lands on the 33rd")
	assert_eq(_stances.fire_count(), 1, "one fire command submitted by the sim")
	assert_eq(_sim.dispatched_count(), dispatched + 1, "and dispatched through the registry like the client's")
	assert_eq(_sim.rejected_count(), 0, "never a rejected command")
	assert_eq(_combat.last_shot()["shooter"], guard, "the guard fired")
	var d: Vector3i = _actors.position_of(_player) - _actors.position_of(guard)
	assert_true(absi(_perception.facing_of(guard) - StanceSystem.facing_toward(Vector2i(d.x, d.z))) <= 1, "faces the player wherever it stands now (%d)" % _perception.facing_of(guard))
	assert_true(_sim.get_tick() - start_tick == 33, "no other tick passed")
	_sim.step_n(80)
	assert_true(_combat.shots() >= 8, "keeps firing at the pistol's cycle (%d shots)" % _combat.shots())
	assert_eq(_sim.rejected_count(), 0, "readiness is checked before every submission")


func test_a_heard_shot_is_investigated_then_forgotten_back_to_hold() -> void:
	_setup()
	var guard: int = _perception.spawn(&"guard_sim", _cell(0, 0), 180, 1, "")  # facing away
	_actors.set_position(_player, _at(10, 0))
	var pistol: int = _items.spawn(&"weapon_frame", &"g19", ItemSystem.inventory_of(_player), 1)
	_sim.step_n(48)  # past the minimum stance duration of the starting hold
	_combat.events().emit(CombatSystem.EVENT_FIRE, {"shooter": _player, "weapon": pistol, "target": guard, "round": 0, "tags": []})
	_actors.set_position(_player, FAR + Vector3i(-40 * M, 0, -40 * M))  # gone before anyone looks
	_sim.step_n(StanceSystem.SCORE_EVERY)
	assert_eq(_stances.stance_of(guard), &"investigate", "a noise with nothing in sight: investigate")
	var arrived: int = -1
	for i: int in 200:
		_sim.step()
		if BuildSystem.cell_of(_actors.position_of(guard)) == _cell(10, 0):
			arrived = i
			break
	assert_true(arrived >= 0, "walked to where the shot came from")
	assert_eq(_perception.facing_of(guard), 0, "faced the way it walked")
	_sim.step_n(420)  # memory of the shot fades
	assert_eq(_stances.stance_of(guard), &"hold", "nothing found, nothing remembered: back to hold")
	assert_eq(_stances.fire_count(), 0, "never fired")


func test_broken_retreats_and_routed_surrenders_under_the_gun() -> void:
	_setup()
	var guard: int = _perception.spawn(&"guard_sim", _cell(0, 0), 0, 1, "")
	_actors.set_position(_player, _at(6, 0))
	_sim.step_n(48)
	assert_eq(_stances.stance_of(guard), &"advance", "alerted to the player at 6 m: advance")
	_sim.step_n(48)  # let advance run its minimum
	_hit_event(guard)
	_hit_event(guard)
	_combat.events().emit(CombatSystem.EVENT_FIRE, {"shooter": _player, "weapon": 0, "target": guard, "round": 0, "tags": []})
	assert_eq(_stress.stress_of(guard), 750000, "two hits and a shot at it")
	assert_true(_stress.is_broken(guard), "broken, with margin over the threshold for the decay before its slot")
	_sim.step_n(StanceSystem.SCORE_EVERY)
	assert_eq(_stances.stance_of(guard), &"retreat", "broken: retreat")
	var x_before: int = _actors.position_of(guard).x
	_sim.step_n(40)
	assert_true(_actors.position_of(guard).x < x_before, "moved away from the player, -x")
	_sim.step_n(48)  # let retreat run its minimum
	assert_eq(_perception.facing_of(guard), 0, "keeps its eyes on the contact while backing off")
	_hit_event(guard)
	_hit_event(guard)
	assert_true(_stress.is_routed(guard), "routed")
	_actors.set_position(_player, _actors.position_of(guard) + Vector3i(3 * M, 0, 0))  # right in front of it
	_sim.step_n(StanceSystem.SCORE_EVERY + 1)
	assert_eq(_stances.stance_of(guard), &"surrender", "routed, the player 3 m away in sight: surrender")
	var pos: Vector3i = _actors.position_of(guard)
	_sim.step_n(20)
	assert_eq(_actors.position_of(guard), pos, "and stands still")
	assert_eq(_stances.fire_count(), 0, "no shot from a surrendered agent")


func test_hysteresis_keeps_a_stance_for_its_minimum_duration() -> void:
	_setup()
	var guard: int = _perception.spawn(&"guard_sim", _cell(0, 0), 180, 1, "")
	_actors.set_position(_player, _at(10, 0))
	var pistol: int = _items.spawn(&"weapon_frame", &"g19", ItemSystem.inventory_of(_player), 1)
	_sim.step_n(10)
	_combat.events().emit(CombatSystem.EVENT_FIRE, {"shooter": _player, "weapon": pistol, "target": guard, "round": 0, "tags": []})
	_sim.step_n(StanceSystem.SCORE_EVERY)
	assert_eq(_stances.stance_of(guard), &"hold", "investigate would win, but hold has not run its minimum")
	_sim.step_n(StanceSystem.MIN_STANCE_TICKS)
	assert_eq(_stances.stance_of(guard), &"investigate", "after the minimum it switches")


func test_property_choice_is_allowed_and_routed_never_advances() -> void:
	_setup()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	var names: Array[StringName] = _stances.implemented_stances()
	var violations: int = 0
	var switches: int = 0
	for case: int in PROPERTY_CASES:
		var allowed: Array[Dictionary] = []
		for name: StringName in names:
			if rng.randi_range(0, 2) > 0:
				allowed.append({"stance": name, "weight": rng.randi_range(0, 3000)})
		if allowed.is_empty():
			allowed.append({"stance": names[rng.randi_range(0, names.size() - 1)], "weight": 1000})
		var current_entry: Dictionary = allowed[rng.randi_range(0, allowed.size() - 1)]
		var current: StringName = current_entry["stance"]
		var routed: bool = rng.randi_range(0, 3) == 0
		var ctx: Dictionary = {"known": rng.randi_range(0, 1) == 1, "visible": rng.randi_range(0, 1) == 1, "alerted": rng.randi_range(0, 1) == 1,
			"awareness": rng.randi_range(0, 1000000), "distance_mm": rng.randi_range(0, 40000), "stress": rng.randi_range(0, 1000000),
			"broken": rng.randi_range(0, 1) == 1, "routed": routed, "in_cover": rng.randi_range(0, 1) == 1, "route": rng.randi_range(0, 1) == 1}
		var ran: int = rng.randi_range(0, 80)
		var choice: Dictionary = _stances.choose(allowed, ctx, current, ran)
		var chosen: StringName = choice["stance"]
		var switched: bool = choice["switched"]
		var in_allowed: bool = false
		var escape: bool = false
		for e: Dictionary in allowed:
			if e["stance"] == chosen:
				in_allowed = true
			if e["stance"] == &"retreat" or e["stance"] == &"surrender":
				escape = true
		var problem: String = ""
		if not in_allowed:
			problem = "chose a stance outside the profile"
		elif routed and escape and chosen != &"retreat" and chosen != &"surrender":
			problem = "routed but chose %s" % chosen
		elif not switched and chosen != current:
			problem = "did not switch yet changed"
		elif switched and chosen == current:
			problem = "switched to itself"
		elif switched and ran < StanceSystem.MIN_STANCE_TICKS and not (routed and escape and current != &"retreat" and current != &"surrender"):
			problem = "switched before the minimum without being forced"
		if switched:
			switches += 1
		if not problem.is_empty():
			violations += 1
			if violations <= 3:
				fail("case %d: %s" % [case, problem])
	assert_eq(violations, 0, "choices always allowed; routed agents only retreat or surrender; hysteresis holds")
	assert_true(switches > 500, "switches happened (%d)" % switches)


func test_scoring_is_time_sliced_by_agent_id() -> void:
	_setup()
	var ids: Array[int] = []
	for i: int in 3:
		ids.append(_perception.spawn(&"guard_sim", _cell(i * 3, 0), 0, 1, ""))
	var before: int = _stances.score_count()
	_sim.step_n(StanceSystem.SCORE_EVERY)
	assert_eq(_stances.score_count() - before, 3, "each agent scored exactly once in a full cycle")
	before = _stances.score_count()
	_sim.step()
	assert_true(_stances.score_count() - before <= 1, "at most one of three scores on a given tick")
	assert_eq(StanceSystem.facing_toward(Vector2i(1000, 0)), 0, "facing +x")
	assert_true(absi(StanceSystem.facing_toward(Vector2i(0, -1000)) - 270) <= 1, "facing -z")
	assert_true(absi(StanceSystem.facing_toward(Vector2i(-1000, 1000)) - 135) <= 1, "facing between -x and +z")


func test_restore_round_trip_and_rejections() -> void:
	_setup()
	var guard: int = _perception.spawn(&"guard_sim", _cell(0, 0), 0, 1, "")
	_actors.set_position(_player, _at(12, 0))
	_sim.step_n(60)
	assert_eq(_stances.stance_of(guard), &"advance", "alerted at 12 m: advancing")
	var snap: Dictionary = _sim.snapshot()
	var other: SimRoot = SimAssembly.build(SEED, _db())
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "restored")
	assert_eq(other.restore_root(snap), OK, "root restored")
	var stances: StanceSystem = SimAssembly.stances_of(other)
	assert_eq(stances.snapshot(), _stances.snapshot(), "equal state")
	_sim.step_n(10)
	other.step_n(10)
	assert_eq(other.state_hash(), _sim.state_hash(), "steps on together")
	var state: Dictionary = _stances.snapshot()
	assert_eq(stances.restore({}), ERR_INVALID_DATA, "empty")
	var bad: Dictionary = state.duplicate(true)
	var records: Dictionary = bad["stances"]
	var rec: Dictionary = records[guard]
	rec["stance"] = &"dance"
	assert_eq(stances.restore(bad), ERR_INVALID_DATA, "an unknown stance")
	bad = state.duplicate(true)
	records = bad["stances"]
	records[_player] = records[guard]
	assert_eq(stances.restore(bad), ERR_INVALID_DATA, "a record for a non-agent")
	assert_eq(stances.snapshot(), state, "rejections leave the state untouched")
