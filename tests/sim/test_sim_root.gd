extends GcityTest

const SEED_A: int = 20260920
const SEED_B: int = 20260921
const PROPERTY_CASES: int = 10_000


func test_tick_length_is_an_exact_integer() -> void:
	assert_eq(SimRoot.TICK_USEC * SimRoot.TICK_HZ, 1_000_000, "TICK_HZ must divide one second exactly")


func test_fresh_sim_state() -> void:
	var sim := SimRoot.new(SEED_A)
	assert_eq(sim.get_seed(), SEED_A, "seed")
	assert_eq(sim.get_tick(), 0, "tick starts at 0")
	assert_eq(sim.dispatched_count(), 0, "nothing dispatched")
	assert_eq(sim.rejected_count(), 0, "nothing rejected")
	assert_eq(sim.system_ids(), [] as Array[StringName], "no systems")
	assert_eq(sim.state_hash().length(), 64, "hash is well formed")


func test_step_advances_tick_and_ticks_systems_in_registration_order() -> void:
	var sim := SimRoot.new(SEED_A)
	var first := CounterSystemDouble.new(&"first")
	var second := CounterSystemDouble.new(&"second")
	assert_eq(sim.register_system(first), OK, "register first")
	assert_eq(sim.register_system(second), OK, "register second")
	assert_eq(sim.system_ids(), [&"first", &"second"] as Array[StringName], "registration order kept")
	sim.step_n(3)
	assert_eq(sim.get_tick(), 3, "three ticks")
	assert_eq(first.ticks_seen, 3, "first ticked thrice")
	assert_eq(second.ticks_seen, 3, "second ticked thrice")
	assert_eq(first.ticks_of_sim_seen, [1, 2, 3] as Array[int], "system sees the tick already advanced")
	assert_ne(first.last_draw, second.last_draw, "each system drew its own value from the shared RNG")


func test_registration_rules() -> void:
	var sim := SimRoot.new(SEED_A)
	assert_eq(sim.register_system(CounterSystemDouble.new(&"")), ERR_INVALID_PARAMETER, "empty id")
	assert_eq(sim.register_system(CounterSystemDouble.new(&"a")), OK, "first")
	assert_eq(sim.register_system(CounterSystemDouble.new(&"a")), ERR_ALREADY_EXISTS, "duplicate id")
	sim.step()
	assert_eq(sim.register_system(CounterSystemDouble.new(&"b")), ERR_LOCKED, "no registration after tick 0")
	assert_eq(sim.system_ids(), [&"a"] as Array[StringName], "rejected systems are not kept")


func test_late_commands_are_rejected_at_submit() -> void:
	var sim := SimRoot.new(SEED_A)
	assert_eq(sim.submit(SimCommand.new(0, &"x", {})), ERR_INVALID_PARAMETER, "tick 0 is the past")
	assert_eq(sim.submit(SimCommand.new(1, &"x", {})), OK, "tick 1 is the future")
	sim.step()
	assert_eq(sim.submit(SimCommand.new(1, &"x", {})), ERR_INVALID_PARAMETER, "tick 1 is now the present")


func test_commands_dispatch_on_their_tick_in_submission_order() -> void:
	var sim := SimRoot.new(SEED_A)
	var counter := CounterSystemDouble.new()
	assert_eq(counter.attach(sim), OK, "attach")
	sim.submit(SimCommand.new(2, CounterSystemDouble.COMMAND_ADD, {"amount": 5}))
	sim.submit(SimCommand.new(2, CounterSystemDouble.COMMAND_ADD, {"amount": -2}))
	sim.submit(SimCommand.new(4, CounterSystemDouble.COMMAND_ADD, {"amount": 10}))
	sim.step()
	assert_eq(counter.total, 0, "nothing due on tick 1")
	sim.step()
	assert_eq(counter.total, 3, "both tick-2 commands applied in order")
	assert_eq(sim.dispatched_count(), 2, "two dispatched")
	sim.step_n(2)
	assert_eq(counter.total, 13, "tick-4 command applied")
	assert_eq(sim.dispatched_count(), 3, "three dispatched")
	assert_eq(sim.rejected_count(), 0, "none rejected")


func test_unknown_and_invalid_commands_are_counted_not_fatal() -> void:
	var sim := SimRoot.new(SEED_A)
	var counter := CounterSystemDouble.new()
	counter.attach(sim)
	sim.submit(SimCommand.new(1, &"nope", {}))
	sim.submit(SimCommand.new(1, CounterSystemDouble.COMMAND_ADD, {"amount": "five"}))
	sim.submit(SimCommand.new(1, CounterSystemDouble.COMMAND_ADD, {"amount": 1, "extra": 1}))
	sim.step()
	assert_eq(sim.rejected_count(), 3, "three rejected")
	assert_eq(sim.dispatched_count(), 0, "none applied")
	assert_eq(counter.total, 0, "state untouched by rejected commands")


func test_pending_commands_are_part_of_state() -> void:
	var a := SimRoot.new(SEED_A)
	var b := SimRoot.new(SEED_A)
	assert_eq(a.state_hash(), b.state_hash(), "fresh sims match")
	a.submit(SimCommand.new(5, &"x", {"v": 1}))
	assert_ne(a.state_hash(), b.state_hash(), "a pending command changes the hash")
	b.submit(SimCommand.new(5, &"x", {"v": 1}))
	assert_eq(a.state_hash(), b.state_hash(), "same pending command restores equality")


func test_same_seed_and_inputs_hash_equal_different_seed_differs() -> void:
	var a: String = _run(SEED_A)
	var b: String = _run(SEED_A)
	var c: String = _run(SEED_B)
	assert_eq(a, b, "deterministic")
	assert_ne(a, c, "seed matters")
	assert_eq(a.length(), 64, "well formed")


func test_property_replays_are_bit_identical_across_random_seeds_and_inputs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_A
	var mismatches: int = 0
	for _case: int in PROPERTY_CASES:
		var seed: int = rng.randi()
		var ticks: int = rng.randi_range(1, 20)
		var script: Array[Array] = []
		for _i: int in rng.randi_range(0, 5):
			script.append([rng.randi_range(1, ticks), rng.randi_range(-100, 100)])
		if _run_script(seed, ticks, script) != _run_script(seed, ticks, script):
			mismatches += 1
	assert_eq(mismatches, 0, "every generated run must replay identically")


func _run(seed: int) -> String:
	return _run_script(seed, 50, [[3, 7], [3, -1], [10, 100]])


func _run_script(seed: int, ticks: int, script: Array[Array]) -> String:
	var sim := SimRoot.new(seed)
	CounterSystemDouble.new().attach(sim)
	for entry: Array in script:
		var tick: int = entry[0]
		var amount: int = entry[1]
		sim.submit(SimCommand.new(tick, CounterSystemDouble.COMMAND_ADD, {"amount": amount}))
	sim.step_n(ticks)
	return sim.state_hash()
