extends GcityTest

## The M2 replay fixture (spec claim 21) and the mid-run save: replaying the fixture
## to tick 200, saving, loading and continuing hashes equal to the uninterrupted run.

const FIXTURE: String = "res://tests/replay/m2-starter-plot.json"
const SAVE_AT: int = 200


func _db() -> ContentDb:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	return db


func _fixture() -> ReplayFixture:
	var fixture: ReplayFixture = ReplayFixture.parse(read_text(FIXTURE))
	assert_true(fixture.is_valid(), "fixture valid: %s" % fixture.error)
	return fixture


func test_starter_plot_fixture_replays_to_its_recorded_hash_and_end_state() -> void:
	var fixture: ReplayFixture = _fixture()
	var db: ContentDb = _db()
	var sim: SimRoot = SimAssembly.build(fixture.seed, db)
	var hash: String = Replay.run(fixture, sim)
	assert_eq(hash.length(), 64, "hash produced")
	assert_false(fixture.expected_hash.is_empty(), "gate fixture has its hash recorded")
	assert_eq(hash, fixture.expected_hash, "run matches the recorded hash")
	var land: LandSystem = SimAssembly.land_of(sim)
	var structures: StructureSystem = SimAssembly.structures_of(sim)
	assert_eq(land.owner_of(&"starter_plot"), &"player", "plot owned")
	assert_eq(land.owner_of(&"neighbour_east"), &"player", "neighbour bought")
	assert_eq(land.violation_count(), 1, "one violation: the first placement on the neighbour")
	assert_eq(structures.structure_ids(), [2, 8] as Array[int], "two containers")
	assert_eq(structures.module_ids(2), [3, 4, 6, 7] as Array[int], "rack, work station, sustainment, replacement sustainment")
	assert_eq(structures.module_ids(8), [9] as Array[int], "a rack on the second container")
	assert_eq(structures.power_available(2), 5500 - 800 - 1200 - 1200, "power on the first container")
	assert_eq(structures.heat_headroom(2), 3400 - 500 - 900 - 900, "heat on the first container")
	assert_eq(sim.rejected_count(), 2, "the over-occupied install and the trespassing placement")


func test_save_at_tick_200_and_resume_matches_the_uninterrupted_run() -> void:
	var fixture: ReplayFixture = _fixture()
	var db: ContentDb = _db()
	var sim: SimRoot = SimAssembly.build(fixture.seed, db)
	for command: SimCommand in fixture.commands:
		assert_eq(sim.submit(command), OK, "submit")
	sim.step_n(SAVE_AT)
	var text: String = SaveFile.serialize(sim, db.digest())
	assert_false(text.is_empty(), "save at tick %d" % SAVE_AT)
	var resumed: SimRoot = SimAssembly.load_save(SaveFile.parse(text), db)
	assert_true(resumed != null, "load")
	assert_eq(resumed.get_tick(), SAVE_AT, "resumed at the save tick")
	resumed.step_n(fixture.ticks - SAVE_AT)
	sim.step_n(fixture.ticks - SAVE_AT)
	assert_eq(resumed.state_hash(), sim.state_hash(), "resumed run equals the uninterrupted run")
	assert_eq(resumed.state_hash(), fixture.expected_hash, "and the fixture's recorded hash")
