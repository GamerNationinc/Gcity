extends GcityTest

## M6 spec claim 9 and ADR-011 C: the player breaches a piece with a carried tool. The
## breach takes the piece's resolved hp × the tool class's hp_factor in ticks, is heard
## at every progress step (a second), stops if the actor moves or fires, and removes
## the piece at the end with `build.breached`. On someone else's land it proceeds and
## records one violation. `offend()` never changes an outcome.
##
## Test world, far out in unparcelled badlands (FAR_CELL = (500, 0, 500)): a foundation
## at (0, 0, 0) and a service grate over (1, 0, 0), stood on from (1, 1, 0).

const SEED: int = 20261140
const SEED_OFFEND: int = 20261141
const PROPERTY_CASES: int = 10_000
const M: int = 1000
const FAR_CELL: Vector3i = Vector3i(500, 0, 500)

var _sim: SimRoot
var _actors: ActorSystem
var _build: BuildSystem
var _items: ItemSystem
var _breaches: BreachSystem
var _land: LandSystem
var _player: int = 0
var _cutter: int = 0
var _grate: int = 0
var _noises: Array[Dictionary] = []
var _breached: Array[Dictionary] = []
var _violations: Array[Dictionary] = []


## A foundation at `base` and a service grate over the cell beside it, the player
## standing on the grate.
func _setup(base: Vector3i = FAR_CELL) -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_build = SimAssembly.build_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_breaches = SimAssembly.breaches_of(_sim)
	_land = SimAssembly.land_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_cutter = _items.spawn(ItemSystem.KIND_TOOL, &"cutter_handheld", ItemSystem.inventory_of(_player), 1)
	var ids: Array[int] = _build.place_batch([
		[&"foundation_block", base, ""],
		[&"service_grate", base + Vector3i(1, 0, 0), "py"],
	] as Array[Array])
	assert_eq(ids.size(), 2, "the grate stands")
	_grate = ids[1]
	_actors.set_position(_player, _floor_of(base + Vector3i(1, 1, 0)))
	# the lambdas capture local arrays, not self (a callable holding the test would
	# make a cycle through the sim's event bus)
	var noises: Array[Dictionary] = []
	var breached: Array[Dictionary] = []
	var violations: Array[Dictionary] = []
	_noises = noises
	_breached = breached
	_violations = violations
	var events: EventBus = SimAssembly.combat_of(_sim).events()
	events.subscribe(BreachSystem.EVENT_NOISE, func(p: Dictionary) -> void: noises.append(p))
	events.subscribe(BreachSystem.EVENT_BREACHED, func(p: Dictionary) -> void: breached.append(p))
	events.subscribe(LandSystem.EVENT_VIOLATION, func(p: Dictionary) -> void: violations.append(p))


static func _floor_of(cell: Vector3i) -> Vector3i:
	return Vector3i(cell.x * M + M / 2, cell.y * M, cell.z * M + M / 2)


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


func _start() -> bool:
	return _do(BreachSystem.COMMAND_BREACH, {"actor": _player, "piece": _grate, "tool": _cutter})


func test_the_cutter_goes_through_the_grate_in_its_time_and_is_heard_while_it_does() -> void:
	_setup()
	var stats: StatResolver = SimAssembly.stats_of(_sim)
	var total: int = stats.resolve(_grate, BuildSystem.STAT_HP) * 1  # the cutter class's hp_factor
	assert_eq(total, 200, "a grate is 200 hp of grate steel")
	var loud: int = stats.resolve(_cutter, &"noise") * stats.resolve(_grate, BuildSystem.STAT_NOISE) / 1000
	assert_true(_start(), "the breach starts")
	assert_true(_breaches.is_breaching(_player), "and runs")
	var done: Array[int] = _breaches.progress_of(_player)
	assert_eq(done, [1, total] as Array[int], "one tick in, of %d" % total)
	_sim.step_n(total - 2)
	assert_true(_build.has_piece(_grate), "a tick short, the grate still stands")
	_sim.step()
	assert_false(_build.has_piece(_grate), "then it is gone")
	assert_false(_breaches.is_breaching(_player), "and the breach is over")
	assert_eq(_breached.size(), 1, "one build.breached")
	var ev: Dictionary = _breached[0]
	var by: int = ev["actor"]
	var piece: int = ev["piece"]
	assert_eq(by, _player, "credited to the player")
	assert_eq(piece, _grate, "for the grate")
	assert_eq(_noises.size(), 5, "heard at the start and at every second of 200 ticks")
	for n: Dictionary in _noises:
		var source: int = n["source"]
		var range_mm: int = n["range_mm"]
		assert_eq(source, _player, "the noise is the player's")
		assert_eq(range_mm, loud, "carrying the cutter's noise scaled by the grate's breach noise")
	assert_eq(_violations.size(), 0, "badlands: anyone may build, so no crime")
	assert_eq(_breaches.completed_count(), 1, "counted")


func test_moving_or_firing_stops_the_breach_and_the_piece_stands() -> void:
	_setup()
	assert_true(_start(), "started")
	_sim.step_n(50)
	_actors.set_position(_player, _actors.position_of(_player) + Vector3i(100, 0, 0))
	_sim.step()
	assert_false(_breaches.is_breaching(_player), "a step stops it")
	_sim.step_n(300)
	assert_true(_build.has_piece(_grate), "the grate stands")
	assert_true(_start(), "started again from nothing")
	assert_eq(_breaches.progress_of(_player)[0], 1, "progress is not kept")
	# the shape combat emits for a shot; nothing here depends on what it hit
	SimAssembly.combat_of(_sim).events().emit(CombatSystem.EVENT_FIRE, {"shooter": _player, "weapon": 0, "target": 0, "round": 0, "tags": [] as Array})
	assert_false(_breaches.is_breaching(_player), "a shot stops it")
	_sim.step_n(300)
	assert_true(_build.has_piece(_grate), "still standing")
	assert_eq(_breached.size(), 0, "never breached")


func test_breach_refusals() -> void:
	_setup()
	var other: int = _actors.spawn(&"arcade", 0)
	var their_cutter: int = _items.spawn(ItemSystem.KIND_TOOL, &"cutter_handheld", ItemSystem.inventory_of(other), 2)
	var pistol: int = _items.spawn(ItemSystem.KIND_FRAME, &"g19", ItemSystem.inventory_of(_player), 3)
	for payload: Dictionary in [
		{}, {"actor": _player, "piece": _grate},
		{"actor": _player, "piece": _grate, "tool": their_cutter},
		{"actor": _player, "piece": _grate, "tool": pistol},
		{"actor": _player, "piece": 9999, "tool": _cutter},
		{"actor": 9999, "piece": _grate, "tool": _cutter},
		{"actor": "1", "piece": _grate, "tool": _cutter},
		{"actor": _player, "piece": _grate, "tool": _cutter, "extra": 1},
	]:
		assert_false(_do(BreachSystem.COMMAND_BREACH, payload), "refused: %s" % [payload])
	_actors.set_position(_player, _floor_of(FAR_CELL + Vector3i(3, 0, 3)))
	assert_false(_start(), "not beside the grate")
	_actors.set_position(_player, _floor_of(FAR_CELL + Vector3i(1, 0, 0)))
	assert_true(_start(), "from below is beside it too")
	assert_false(_start(), "one breach at a time")
	_actors.damage_node(_player, &"body", 1_000_000)
	_sim.step()
	assert_false(_breaches.is_breaching(_player), "the dead stop cutting")
	assert_false(_start(), "and do not start")
	assert_eq(_violations.size(), 0, "no crime in any of it")


func test_on_someone_elses_land_the_breach_proceeds_and_is_one_violation() -> void:
	_setup(Vector3i(5, 0, 5))  # on the starter plot
	assert_true(_land.transfer(&"starter_plot", "npc.somebody"), "the plot is somebody's")
	assert_true(_start(), "the crime proceeds")
	assert_eq(_violations.size(), 1, "recorded once")
	var v: Dictionary = _violations[0]
	var right: StringName = v["right"]
	assert_eq(right, &"build", "as a build violation on their parcel")
	_sim.step_n(250)
	assert_false(_build.has_piece(_grate), "and it goes through")
	assert_eq(_violations.size(), 1, "still one: the offence is the act, not every tick of it")


## ADR-011's verification: offend never refuses, and emits exactly one violation when
## the right is denied and none when it is held, whatever the place, actor or right.
func test_property_offend_records_exactly_the_denied_rights() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_OFFEND
	_setup()
	var owners: Array[String] = ["", "player", "npc.somebody"]
	var failures: int = 0
	var denied: int = 0
	for case: int in PROPERTY_CASES:
		if rng.randi_range(0, 9) == 0:
			_land.transfer(&"starter_plot", owners[rng.randi_range(0, 2)])
			_land.transfer(&"neighbour_north", owners[rng.randi_range(0, 2)])
		var pos: Vector3i = Vector3i(rng.randi_range(-5000, 30000), rng.randi_range(-4000, 10000), rng.randi_range(-5000, 30000))
		var right: StringName = LandSystem.RIGHTS[rng.randi_range(0, LandSystem.RIGHTS.size() - 1)]
		var held: bool = _land.rights_at(pos, _player)[right]
		var before: int = _violations.size()
		var counted: int = _land.violation_count()
		var answer: bool = _land.offend(pos, _player, right)
		var emitted: int = _violations.size() - before
		var problem: String = ""
		if answer != held:
			problem = "answered %s for a right that is %s" % [answer, held]
		elif emitted != (0 if held else 1) or _land.violation_count() - counted != emitted:
			problem = "%d violations for a right that is %s" % [emitted, "held" if held else "denied"]
		if not held:
			denied += 1
		if not problem.is_empty():
			failures += 1
			if failures <= 3:
				fail("case %d: %s at %s (%s)" % [case, problem, pos, right])
	assert_eq(failures, 0, "offend recorded exactly the denied rights")
	assert_true(denied > 1000 and denied < PROPERTY_CASES - 1000, "both held and denied rights were asked (%d denied)" % denied)


func test_snapshot_restore_round_trip_mid_breach_and_rejections() -> void:
	_setup()
	assert_true(_start(), "started")
	_sim.step_n(20)
	var state: Dictionary = _breaches.snapshot()
	var db: ContentDb = _sim.get_system(&"content")
	var file: SaveFile = SaveFile.parse(SaveFile.serialize(_sim, db.digest()))
	var loaded: SimRoot = SimAssembly.load_save(file, db)
	assert_true(loaded != null, "a save taken mid-breach loads")
	assert_eq(loaded.state_hash(), _sim.state_hash(), "to the same state")
	loaded.step_n(200)
	_sim.step_n(200)
	assert_eq(loaded.state_hash(), _sim.state_hash(), "and finishes the same breach the same way")
	var fresh: BreachSystem = SimAssembly.breaches_of(SimAssembly.build(SEED, db))
	var all: Dictionary = state["breaches"]
	var mine: Dictionary = all[_player]
	for bad: Dictionary in [
		{}, {"breaches": {}, "completed": -1}, {"breaches": [], "completed": 0},
		{"breaches": {"1": mine}, "completed": 0},
		{"breaches": {_player: {"piece": _grate}}, "completed": 0},
		{"breaches": {}, "completed": 0, "extra": 1},
	]:
		assert_eq(fresh.restore(bad), ERR_INVALID_DATA, "rejects %s" % [bad])
