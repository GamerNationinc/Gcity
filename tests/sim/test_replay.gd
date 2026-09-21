extends GcityTest

## Fixtures replay against the assembled sim (SimAssembly over the shipped content),
## exactly as tools/replay_hash.gd and the player run it. M0's trivial fixture
## exercises the tick loop; the M1 fixtures exercise the whole chain (spec claim 19).
const M0_FIXTURE: String = "res://tests/replay/m0-trivial.json"
const M1_RANGE: String = "res://tests/replay/m1-range.json"
const M1_PERK_OFF: String = "res://tests/replay/m1-perk-off.json"
const HOSTILE_COMMANDS: String = "res://tests/fuzz/commands/hostile_payloads.json"


func _content() -> ContentDb:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	return db


func _fixture(path: String) -> ReplayFixture:
	var fixture: ReplayFixture = ReplayFixture.parse(read_text(path))
	assert_true(fixture.is_valid(), "%s valid: %s" % [path, fixture.error])
	return fixture


func _assert_reproduces(path: String) -> SimRoot:
	var fixture: ReplayFixture = _fixture(path)
	if not fixture.is_valid():
		return null
	var first_sim: SimRoot = SimAssembly.build(fixture.seed, _content())
	var first: String = Replay.run(fixture, first_sim)
	var second: String = Replay.run(fixture, SimAssembly.build(fixture.seed, _content()))
	assert_eq(first.length(), 64, "%s: hash produced" % path)
	assert_eq(first, second, "%s: two runs are bit-identical" % path)
	assert_false(fixture.expected_hash.is_empty(), "%s: hash must be recorded" % path)
	assert_eq(first, fixture.expected_hash, "%s: run matches the recorded hash" % path)
	return first_sim


func test_m0_fixture_replays_identically_and_matches_its_recorded_hash() -> void:
	_assert_reproduces(M0_FIXTURE)


func test_m1_range_fixture_runs_the_whole_chain() -> void:
	var sim: SimRoot = _assert_reproduces(M1_RANGE)
	if sim == null:
		return
	var items: ItemSystem = SimAssembly.items_of(sim)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var combat: CombatSystem = SimAssembly.combat_of(sim)
	var progression: ProgressionSystem = SimAssembly.progression_of(sim)
	assert_eq(sim.rejected_count(), 0, "every command in the fixture applied")
	assert_eq(combat.shots(), 30, "thirty shots fired")
	assert_true(combat.hits() >= 3, "enough hits to reach level 1 (%d)" % combat.hits())
	assert_true(progression.has_perk(1, &"handgun_focus"), "the perk was unlocked mid-fixture")
	assert_eq(items.item_count(), 5 + 30 - 30, "thirty rounds consumed, five items remain")
	assert_eq(items.items_in(&"world"), [6] as Array[int], "the emergency reload dropped the first magazine")
	assert_eq(items.magazine_of(3), 7, "second magazine seated")
	assert_eq(items.chambered(3), 0, "chamber empty after the second magazine")
	assert_eq(actors.health_of(2)[&"body"], 100000000 - combat.damage_dealt(), "dummy health reconciles with the hits")


func test_m1_perk_off_fixture_differs_only_by_the_perk() -> void:
	var with_perk: ReplayFixture = _fixture(M1_RANGE)
	var without: ReplayFixture = _fixture(M1_PERK_OFF)
	assert_eq(with_perk.commands.size(), without.commands.size() + 1, "one command fewer")
	var sim_with: SimRoot = SimAssembly.build(with_perk.seed, _content())
	var sim_without: SimRoot = SimAssembly.build(without.seed, _content())
	var hash_with: String = Replay.run(with_perk, sim_with)
	var hash_without: String = Replay.run(without, sim_without)
	assert_eq(hash_without, without.expected_hash, "perk-off matches its recorded hash")
	assert_ne(hash_with, hash_without, "the perk changes the state hash")
	var combat_with: CombatSystem = SimAssembly.combat_of(sim_with)
	var combat_without: CombatSystem = SimAssembly.combat_of(sim_without)
	assert_eq(combat_with.hits(), combat_without.hits(), "the unlock consumed no randomness: same hits")
	var damage_with: int = 100000000 - SimAssembly.actors_of(sim_with).health_of(2)[&"body"]
	var damage_without: int = 100000000 - SimAssembly.actors_of(sim_without).health_of(2)[&"body"]
	assert_true(damage_with > damage_without, "more damage with the perk (%d vs %d)" % [damage_with, damage_without])


func test_replay_refuses_mismatched_or_used_sims() -> void:
	var fixture: ReplayFixture = _fixture(M0_FIXTURE)
	assert_eq(Replay.run(fixture, SimRoot.new(fixture.seed + 1)), "", "wrong seed")
	var used := SimRoot.new(fixture.seed)
	used.step()
	assert_eq(Replay.run(fixture, used), "", "sim already ticked")
	var bad: ReplayFixture = ReplayFixture.parse("{}")
	assert_eq(Replay.run(bad, SimRoot.new(0)), "", "invalid fixture")


func test_replay_with_commands_and_a_system() -> void:
	var text: String = '{"schema_version": 1, "name": "cmds", "seed": 9, "ticks": 8, "commands": [{"tick": 2, "kind": "counter.add", "payload": {"amount": 4}}, {"tick": 8, "kind": "counter.add", "payload": {"amount": 6}}], "expected_hash": ""}'
	var fixture: ReplayFixture = ReplayFixture.parse(text)
	assert_true(fixture.is_valid(), "valid: %s" % fixture.error)
	var sim := SimRoot.new(fixture.seed)
	var counter := CounterSystemDouble.new()
	counter.attach(sim)
	var hash: String = Replay.run(fixture, sim)
	assert_eq(hash.length(), 64, "hash produced")
	assert_eq(counter.total, 10, "both commands applied")
	assert_eq(sim.get_tick(), 8, "ran to the fixture's tick count")
	var without: String = Replay.run(fixture, SimRoot.new(fixture.seed))
	assert_ne(hash, without, "a sim without the system rejects the commands and hashes differently")


## The committed hostile corpus: every payload is rejected on the standard range and
## leaves the systems' state hash exactly where it was.
func test_hostile_command_corpus_is_rejected_without_state_change() -> void:
	var json := JSON.new()
	assert_eq(json.parse(read_text(HOSTILE_COMMANDS)), OK, "corpus parses")
	var corpus: Dictionary = json.data
	var cases: Array = corpus["cases"]
	assert_true(cases.size() >= 40, "corpus has at least 40 cases (%d)" % cases.size())
	var fixture: ReplayFixture = _fixture(M1_RANGE)
	var sim: SimRoot = SimAssembly.build(fixture.seed, _content())
	# set up the range with the fixture's first four ticks of commands, then stop
	for command: SimCommand in fixture.commands:
		if command.tick <= 4:
			assert_eq(sim.submit(command), OK, "setup submit")
	sim.step_n(90)
	assert_eq(sim.rejected_count(), 0, "setup applied cleanly")
	var i: int = 0
	for c: Variant in cases:
		var entry: Dictionary = c
		var kind_s: String = entry["kind"]
		var payload: Dictionary = entry["payload"]
		var before: String = StateHash.of(sim.snapshot()["systems"])
		var rejected_before: int = sim.rejected_count()
		assert_eq(sim.submit(SimCommand.new(sim.get_tick() + 1, StringName(kind_s), payload)), OK, "submit case %d" % i)
		sim.step()
		assert_eq(sim.rejected_count(), rejected_before + 1, "case %d (%s %s) rejected" % [i, kind_s, var_to_str(payload)])
		assert_eq(StateHash.of(sim.snapshot()["systems"]), before, "case %d left system state untouched" % i)
		i += 1
