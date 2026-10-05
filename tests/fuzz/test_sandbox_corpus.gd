extends GcityTest

## M7.6 spec claim 10: every sandbox command is an untrusted boundary. A committed hostile
## corpus covers each sandbox kind (and site.raise's `at` form): every case is refused
## and leaves the systems' state untouched. Then every valid payload is broken every
## way a field can be (dropped, retyped, an unknown key added) and each is refused too.

const CORPUS: String = "res://tests/fuzz/commands/sandbox_hostile.json"
const SEED: int = 20261710


## The player (1) on the creator's lots at (42, 0, 41), a guard (2) beside it.
func _scene() -> SimRoot:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	assert_eq(ContentLoader.load_all(db, "res://sandbox_content"), OK, "and the sandbox's")
	var sim: SimRoot = SandboxAssembly.build(SEED, db)
	var setup: Array[Array] = [
		[&"actor.spawn", {"profile": "arcade", "range_m": 0}],
		[SandboxSystem.COMMAND_TELEPORT, {"actor": 1, "cell": [42, 0, 41]}],
		[&"land.identify", {"actor": 1, "owner": "player"}],
		[SandboxSystem.COMMAND_SPAWN_AGENT, {"actor": 1, "profile": "guard_sim", "cell": [40, 0, 41], "facing": 0, "kit": {}}],
	]
	for lot: String in SiteCreator.LOTS:
		setup.append([&"land.transfer", {"parcel": lot, "owner": "player"}])
	for entry: Array in setup:
		var kind: StringName = entry[0]
		var payload: Dictionary = entry[1]
		assert_eq(sim.submit(SimCommand.new(sim.get_tick() + 1, kind, payload)), OK, "setup %s" % kind)
		sim.step()
	assert_eq(sim.rejected_count(), 0, "set up cleanly")
	assert_eq(SimAssembly.perception_of(sim).agent_ids(), [2] as Array[int], "the guard is actor 2")
	# the guard frozen, so a step with nothing in it changes nothing: any change is the case's
	assert_eq(sim.submit(SimCommand.new(sim.get_tick() + 1, SandboxSystem.COMMAND_AI, {"actor": 1, "agent": 2, "effect": "frozen", "on": true})), OK, "frozen")
	sim.step_n(20)
	var still: String = StateHash.of(sim.snapshot()["systems"])
	sim.step()
	assert_eq(StateHash.of(sim.snapshot()["systems"]), still, "the scene is still")
	return sim


## Submits and steps; true when refused with the systems exactly as they were.
func _refused(sim: SimRoot, kind: StringName, payload: Dictionary) -> bool:
	var before: String = StateHash.of(sim.snapshot()["systems"])
	var rejected: int = sim.rejected_count()
	sim.submit(SimCommand.new(sim.get_tick() + 1, kind, payload))
	sim.step()
	return sim.rejected_count() == rejected + 1 and StateHash.of(sim.snapshot()["systems"]) == before


func test_the_sandbox_corpus_is_refused_without_a_state_change() -> void:
	var json := JSON.new()
	assert_eq(json.parse(read_text(CORPUS)), OK, "the corpus parses")
	var corpus: Dictionary = json.data
	var cases: Array = corpus["cases"]
	var sim: SimRoot = _scene()
	var seen: Dictionary = {}
	for i: int in cases.size():
		var entry: Dictionary = cases[i]
		var kind_s: String = entry["kind"]
		var payload: Dictionary = entry["payload"]
		JsonNumbers.normalise(payload)
		seen[kind_s] = true
		assert_true(_refused(sim, StringName(kind_s), payload), "case %d (%s %s) refused, nothing moved" % [i, kind_s, var_to_str(payload)])
	for kind: StringName in sim.commands().kinds():
		if String(kind).begins_with("sandbox."):
			assert_true(seen.has(String(kind)), "the corpus covers %s" % kind)


## Every field of every valid payload, broken each way, is refused.
func test_every_broken_field_is_refused() -> void:
	var sim: SimRoot = _scene()
	var valid: Array[Array] = [
		[SandboxSystem.COMMAND_DESPAWN, {"actor": 1, "cell": [40, 1, 41], "facing": ""}],
		[SandboxSystem.COMMAND_CLEAR, {"actor": 1}],
		[SandboxSystem.COMMAND_SPAWN_AGENT, {"actor": 1, "profile": "guard_sim", "cell": [44, 0, 44], "facing": 90,
			"kit": {"frame": "g19", "magazine": "g19_mag_15", "ammo": "9x19_fmj", "rounds": 15}}],
		[SandboxSystem.COMMAND_TRAINER, {"actor": 1, "effect": "god", "on": true}],
		[SandboxSystem.COMMAND_TELEPORT, {"actor": 1, "cell": [43, 0, 43]}],
		[SandboxSystem.COMMAND_SET_HEALTH, {"actor": 1, "node": "body", "value": 1000}],
		[SandboxSystem.COMMAND_AI, {"actor": 1, "agent": 2, "effect": "blind", "on": true}],
		[SiteSystem.COMMAND_RAISE, {"actor": 1, "site": "m4_test_building", "at": [44, 0, 44]}],
	]
	var wrong: Array = [null, "x", 1.5, [], {}, true, -1]
	var broken: int = 0
	for pair: Array in valid:
		var kind: StringName = pair[0]
		var good: Dictionary = pair[1]
		for key: Variant in good:
			# without `at`, a raise is the older valid form (the authored base): not broken
			if not (kind == SiteSystem.COMMAND_RAISE and str(key) == "at"):
				var dropped: Dictionary = good.duplicate(true)
				dropped.erase(key)
				assert_true(_refused(sim, kind, dropped), "%s without %s refused" % [kind, key])
				broken += 1
			for bad: Variant in wrong:
				if typeof(bad) == typeof(good[key]):
					continue
				# an int where an int belongs might be in range; -1 is only wrong-typed elsewhere
				var retyped: Dictionary = good.duplicate(true)
				retyped[key] = bad
				assert_true(_refused(sim, kind, retyped), "%s with %s = %s refused" % [kind, key, var_to_str(bad)])
				broken += 1
		var extra: Dictionary = good.duplicate(true)
		extra["unexpected"] = 1
		assert_true(_refused(sim, kind, extra), "%s with an unknown key refused" % kind)
		broken += 1
	assert_true(broken > 150, "%d broken payloads, each refused" % broken)
