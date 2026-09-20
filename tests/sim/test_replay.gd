extends GcityTest

## The M0 gate fixture (standards §11, G0): a trivial replay that must reproduce
## bit-identically on every run.
const M0_FIXTURE: String = "res://tests/replay/m0-trivial.json"


func test_m0_fixture_replays_identically_and_matches_its_recorded_hash() -> void:
	var fixture: ReplayFixture = ReplayFixture.parse(read_text(M0_FIXTURE))
	assert_true(fixture.is_valid(), "fixture valid: %s" % fixture.error)
	if not fixture.is_valid():
		return
	var first: String = Replay.run(fixture, SimRoot.new(fixture.seed))
	var second: String = Replay.run(fixture, SimRoot.new(fixture.seed))
	assert_eq(first.length(), 64, "hash produced")
	assert_eq(first, second, "two runs are bit-identical")
	assert_false(fixture.expected_hash.is_empty(), "gate fixture must have its hash recorded")
	assert_eq(first, fixture.expected_hash, "run matches the recorded hash")


func test_replay_refuses_mismatched_or_used_sims() -> void:
	var fixture: ReplayFixture = ReplayFixture.parse(read_text(M0_FIXTURE))
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
