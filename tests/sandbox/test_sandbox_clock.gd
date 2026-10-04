extends GcityTest

## M7.6 spec claim 7, decision 4: the clock is the client's. N single steps of a held
## clock produce the same state hash as N ticks run straight; the slow and fast rates
## step a quarter, a half, two and four ticks a physics tick; the sim's tick is untouched.

const SEED: int = 20261704


func _host() -> LocalHost:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var host := LocalHost.new()
	host.seed_override = SEED
	host.use_assembly(SimAssembly.build, db)
	return host


func test_single_steps_are_the_same_ticks_run_straight() -> void:
	var held: LocalHost = _host()
	var straight: LocalHost = _host()
	assert_true(held.set_rate(0, 1), "held")
	assert_eq(held.rate_label(), "held", "says so")
	for i: int in 50:
		held._physics_process(0.0)
	assert_eq(held.sim().get_tick(), 0, "a held clock steps nothing")
	for i: int in 50:
		assert_true(held.step_once(), "one tick")
		straight._physics_process(0.0)
	assert_eq(held.sim().get_tick(), 50, "fifty single steps")
	assert_eq(held.sim().state_hash(), straight.sim().state_hash(), "the same state as fifty ticks run straight")
	assert_false(straight.step_once(), "a running clock does not single-step")
	held.free()
	straight.free()


func test_each_rate_steps_its_share() -> void:
	var host: LocalHost = _host()
	for rate: Array in [[1, 4, 10], [1, 2, 20], [1, 1, 40], [2, 1, 80], [4, 1, 160]]:
		var num: int = rate[0]
		var den: int = rate[1]
		var expected: int = rate[2]
		assert_true(host.set_rate(num, den), "rate %d/%d" % [num, den])
		var start: int = host.sim().get_tick()
		for i: int in 40:
			host._physics_process(0.0)
		assert_eq(host.sim().get_tick() - start, expected, "%d/%d steps %d ticks in 40 physics ticks" % [num, den, expected])
	assert_false(host.set_rate(3, 1), "a rate not on the list is refused")
	assert_eq(host.rate_label(), "x4", "and the last one stands")
	host.free()
