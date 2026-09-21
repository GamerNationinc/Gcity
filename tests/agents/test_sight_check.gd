extends GcityTest

## M4 spec claim 7: a shot at a target the shooter cannot see runs no stage and is
## recorded as a miss with reason `no_los`, for players and agents alike. The round
## still leaves and the shot is still heard. This replaces the client-side aim of
## the G3 debt log with the sim's own answer.

const SEED: int = 20261040
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)

var _sim: SimRoot
var _actors: ActorSystem
var _items: ItemSystem
var _combat: CombatSystem
var _perception: PerceptionSystem
var _build: BuildSystem
var _player: int = 0
var _pistol: int = 0


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


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	# a guard that never fires of its own accord: the test's fire commands are the only shots
	db.add(&"agent_profile", &"guard_passive", {"schema_version": 1, "description": "test", "combat_profile": "arcade", "perception_profile": "guard_sim",
		"aim_profile": "guard_sim", "stress_profile": "guard_sim", "stances": [{"stance": "surrender", "weight": 1000}]})
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_combat = SimAssembly.combat_of(_sim)
	_perception = SimAssembly.perception_of(_sim)
	_build = SimAssembly.build_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, _at(3, 3))
	_pistol = _arm(_player)


func test_a_player_shot_through_a_wall_is_a_no_los_miss_that_still_makes_noise() -> void:
	_setup()
	var dummy: int = _actors.spawn(&"range_dummy", 0)
	_actors.set_position(dummy, _at(3, 4))
	var guard: int = _perception.spawn(&"guard_sim", _cell(20, 3), 0, 1, "")  # 17 m off, facing away
	_build.place(_player, &"foundation_block", _at(3, 5), "")
	var wall: int = _build.place(_player, &"wall_panel", _at(3, 4), "nz")
	assert_true(wall > 0, "a wall between the player and the dummy")
	assert_false(_perception.can_target(_player, dummy), "the player cannot see through it")
	var rounds_before: int = _items.item_count()
	assert_true(_do(&"weapon.fire", {"actor": _player, "target": dummy}), "the shot is accepted")
	var last: Dictionary = _combat.last_shot()
	assert_eq(last["reason"], CombatSystem.REASON_NO_LOS, "recorded as a no-line-of-sight miss")
	var hit: bool = last["hit"]
	assert_false(hit, "a miss")
	assert_eq(last["chance"], 0, "no stage ran")
	assert_eq(_combat.shots(), 1, "the shot counted")
	assert_eq(_items.item_count(), rounds_before - 1, "the round is gone")
	assert_eq(_actors.health_of(dummy)["body"], _actors.max_health(dummy, &"body"), "the dummy is untouched")
	assert_eq(_perception.awareness_of(guard, _player), 500000, "the shot was heard all the same")
	_build.breach(wall)
	var door: int = _build.place(_player, &"door_frame", _at(3, 4), "nz")
	assert_true(door > 0, "a door in its place")
	_sim.step_n(10)
	assert_true(_do(&"weapon.fire", {"actor": _player, "target": dummy}), "fires again")
	last = _combat.last_shot()
	assert_eq(last["reason"], "", "through the door the stages run")
	var chance: int = last["chance"]
	assert_true(chance > 0, "with a real hit chance")


func test_an_agent_must_see_its_target_not_merely_have_a_line() -> void:
	_setup()
	var guard: int = _perception.spawn(&"guard_passive", _cell(10, 3), 180, 1, "")  # facing -x, toward the player
	var pistol: int = _arm(guard)
	_sim.step_n(60)
	assert_true(_perception.can_target(guard, _player), "the player is in the guard's cone at 7 m")
	assert_true(_do(&"weapon.fire", {"actor": guard, "target": _player}), "the guard fires")
	assert_eq(_combat.last_shot()["reason"], "", "a real shot")
	var health_after_real_shot: int = _actors.health_of(_player)["body"]
	_actors.set_position(_player, _at(17, 3))  # behind the guard: clear line, outside the cone
	_sim.step_n(10)
	assert_true(_perception.line_of_sight(_actors.position_of(guard), _actors.position_of(_player)), "the line is clear")
	assert_false(_perception.can_target(guard, _player), "but an agent cannot shoot what it does not see")
	assert_true(_do(&"weapon.fire", {"actor": guard, "target": _player}), "the command is still accepted")
	assert_eq(_combat.last_shot()["reason"], CombatSystem.REASON_NO_LOS, "and misses for lack of sight")
	assert_eq(_actors.health_of(_player)["body"], health_after_real_shot, "the blind shot touched nothing")
	assert_eq(pistol, _actors.wielded(guard), "the guard still holds its pistol")


func test_the_reason_survives_the_save_round_trip_and_is_validated() -> void:
	_setup()
	var dummy: int = _actors.spawn(&"range_dummy", 0)
	_actors.set_position(dummy, _at(3, 6))
	_build.place(_player, &"foundation_block", _at(3, 5), "")
	assert_true(_do(&"weapon.fire", {"actor": _player, "target": dummy}), "a shot into the foundation")
	assert_eq(_combat.last_shot()["reason"], CombatSystem.REASON_NO_LOS, "no line through a solid cell")
	var snap: Dictionary = _sim.snapshot()
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "restored")
	var combat: CombatSystem = SimAssembly.combat_of(other)
	assert_eq(combat.last_shot()["reason"], CombatSystem.REASON_NO_LOS, "the reason came across")
	var state: Dictionary = _combat.snapshot()
	var bad: Dictionary = state.duplicate(true)
	var last: Dictionary = bad["last"]
	last["reason"] = "wind"
	assert_eq(combat.restore(bad), ERR_INVALID_DATA, "an unknown reason is rejected")
	bad = state.duplicate(true)
	last = bad["last"]
	last.erase("reason")
	assert_eq(combat.restore(bad), ERR_INVALID_DATA, "a missing reason is rejected")
