extends GcityTest

## M7.6 spec claim 6: hold the AI. Each hold is a perception rule at its neutral value,
## proven against the same scene without it (metamorphic: no oracle for awareness, but a
## blind guard must never gain any of a player in plain sight, a deaf one must ignore a
## shot the other investigates, a frozen one must neither notice nor move nor shoot).

const SEED: int = 20261703
const M: int = 1000


func _sandbox() -> SimRoot:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	assert_eq(ContentLoader.load_all(db, "res://sandbox_content"), OK, "and the sandbox's")
	var sim: SimRoot = SandboxAssembly.build(SEED, db)
	assert_true(sim != null, "the sandbox assembles")
	return sim


func _do(sim: SimRoot, kind: StringName, payload: Dictionary) -> bool:
	var before: int = sim.dispatched_count()
	assert_eq(sim.submit(SimCommand.new(sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	sim.step()
	return sim.dispatched_count() == before + 1


func _at(rel: Vector3i) -> Vector3i:
	return Vector3i(42500, 0, 41500) + rel * M


## The player, and a guard 6 m away facing it (`facing` toward +x is 0) or away (180).
func _scene(sim: SimRoot, facing: int) -> Array[int]:
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var player: int = actors.spawn(&"arcade", 0)
	actors.set_position(player, _at(Vector3i(6, 0, 0)))
	var cell: Vector3i = BuildSystem.cell_of(_at(Vector3i.ZERO))
	var guard: int = SimAssembly.perception_of(sim).spawn(&"guard_sim", cell, facing, 0, "")
	assert_true(guard != EntityIds.NONE, "a guard")
	return [player, guard]


func _hold(sim: SimRoot, player: int, agent: Variant, effect: String, on: bool) -> bool:
	return _do(sim, SandboxSystem.COMMAND_AI, {"actor": player, "agent": agent, "effect": effect, "on": on})


func test_a_blind_guard_never_gains_awareness_of_a_player_in_plain_sight() -> void:
	for blind: bool in [false, true]:
		var sim: SimRoot = _sandbox()
		var made: Array[int] = _scene(sim, 0)
		if blind:
			assert_true(_hold(sim, made[0], made[1], "blind", true), "blind")
		var perception: PerceptionSystem = SimAssembly.perception_of(sim)
		var most: int = 0
		for i: int in 120:
			sim.step()
			most = maxi(most, perception.awareness_of(made[1], made[0]))
		if blind:
			assert_eq(most, 0, "blind: no awareness, ever")
			assert_false(perception.can_see(made[1], made[0]), "and it cannot see the player")
		else:
			assert_true(most > 0, "sighted: the same guard notices")


func test_a_deaf_guard_ignores_the_shot_the_other_investigates() -> void:
	for deaf: bool in [false, true]:
		var sim: SimRoot = _sandbox()
		var made: Array[int] = _scene(sim, 180)  # facing away: only a sound reaches it
		var player: int = made[0]
		var guard: int = made[1]
		var target: int = SimAssembly.actors_of(sim).spawn(&"range_dummy", 0)
		SimAssembly.actors_of(sim).set_position(target, _at(Vector3i(9, 0, 0)))
		var weapon: int = SimAssembly.items_of(sim).arm(player, &"g19", &"g19_mag_15", &"9x19_fmj", 15, 77)
		SimAssembly.actors_of(sim).wield(player, weapon)
		if deaf:
			assert_true(_hold(sim, player, guard, "deaf", true), "deaf")
		var perception: PerceptionSystem = SimAssembly.perception_of(sim)
		assert_eq(perception.awareness_of(guard, player), 0, "unaware before the shot")
		assert_true(_do(sim, CombatSystem.COMMAND_FIRE, {"actor": player, "target": target}), "a shot")
		if deaf:
			assert_eq(perception.awareness_of(guard, player), 0, "deaf: it heard nothing")
		else:
			assert_true(perception.awareness_of(guard, player) > 0, "hearing: the same guard heard it")


func test_a_frozen_guard_neither_notices_nor_moves_nor_shoots() -> void:
	var sim: SimRoot = _sandbox()
	var made: Array[int] = _scene(sim, 0)
	var player: int = made[0]
	var guard: int = made[1]
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var weapon: int = SimAssembly.items_of(sim).arm(guard, &"g19", &"g19_mag_15", &"9x19_fmj", 15, 78)
	actors.wield(guard, weapon)
	assert_true(_hold(sim, player, "all", "frozen", true), "everyone frozen")
	var perception: PerceptionSystem = SimAssembly.perception_of(sim)
	var where: Vector3i = actors.position_of(guard)
	var shots: int = SimAssembly.combat_of(sim).shots()
	for i: int in 400:
		sim.step()
	assert_eq(perception.awareness_of(guard, player), 0, "frozen: it noticed nothing")
	assert_eq(actors.position_of(guard), where, "moved nowhere")
	assert_eq(SimAssembly.combat_of(sim).shots(), shots, "and fired nothing")
	assert_false(_hold(sim, player, "all", "frozen", true), "frozen again: nothing to change, refused")
	assert_true(_hold(sim, player, guard, "frozen", false), "thawed")
	for i: int in 400:
		sim.step()
	assert_true(perception.awareness_of(guard, player) > 0 or SimAssembly.combat_of(sim).shots() > shots, "and it wakes to the player")


func test_a_malformed_hold_is_refused() -> void:
	var sim: SimRoot = _sandbox()
	var made: Array[int] = _scene(sim, 0)
	var player: int = made[0]
	for payload: Dictionary in [
		{"actor": player, "agent": made[1], "effect": "god", "on": true},
		{"actor": player, "agent": player, "effect": "blind", "on": true},
		{"actor": player, "agent": "some", "effect": "blind", "on": true},
		{"actor": player, "agent": 9999, "effect": "blind", "on": true},
		{"actor": player, "agent": made[1], "effect": "blind", "on": 1},
		{"actor": player, "agent": made[1], "effect": "blind"},
	]:
		assert_false(_do(sim, SandboxSystem.COMMAND_AI, payload), "refused: %s" % payload)
	assert_false(_do(sim, SandboxSystem.COMMAND_TRAINER, {"actor": made[1], "effect": "frozen", "on": true}), "holds are not trainer effects")
