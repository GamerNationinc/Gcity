extends GcityTest

## The committed hostile corpus (standards §3.5): a payload for every command kind the
## sim registers, each one wrong in its own way, every one refused without moving the
## state hash a bit.
##
## This lives in its own file rather than beside the replay tests because it is the one
## test that covers every command handler's validation at once. Mutation testing runs
## the tests that cover the file it mutated, and while this was buried in the replay
## file it never ran against the systems whose payloads it checks: mutants that turned
## `return false` into `return true` in a handler's argument checking survived, and the
## report called them holes when the test for them was sitting right here.

const HOSTILE_COMMANDS: String = "res://tests/fuzz/commands/hostile_payloads.json"
const M1_RANGE: String = "res://tests/replay/m1-range.json"


func _content() -> ContentDb:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	return db


func _fixture(path: String) -> ReplayFixture:
	var fixture: ReplayFixture = ReplayFixture.parse(read_text(path))
	assert_true(fixture.is_valid(), "%s valid: %s" % [path, fixture.error])
	return fixture


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


## M6 spec claim 16: the corpus is extended with every new command kind. A kind that
## never appears in it has no hostile-payload coverage at all, so the corpus tracks
## the registry rather than whatever was remembered at the time.
func test_the_hostile_corpus_covers_every_registered_command_kind() -> void:
	var json := JSON.new()
	assert_eq(json.parse(read_text(HOSTILE_COMMANDS)), OK, "corpus parses")
	var corpus: Dictionary = json.data
	var cases: Array = corpus["cases"]
	var seen: Dictionary = {}
	for c: Variant in cases:
		var entry: Dictionary = c
		var kind_s: String = entry["kind"]
		seen[StringName(kind_s)] = true
	var sim: SimRoot = SimAssembly.build(1, _content())
	var registered: Array[StringName] = sim.commands().kinds()
	var missing: Array[String] = []
	for kind: StringName in registered:
		if not seen.has(kind):
			missing.append(String(kind))
	missing.sort()
	assert_eq(missing, [] as Array[String], "every registered kind has hostile payloads")
	# and a kind the sim has never heard of is itself a hostile payload worth keeping
	var unknown: int = 0
	for kind: Variant in seen:
		var named: StringName = kind
		if not registered.has(named):
			unknown += 1
	assert_true(unknown > 0, "the corpus still offers kinds the sim does not register")
