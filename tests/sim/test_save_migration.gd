extends GcityTest

## M6 spec claim 21: save schema version 2, with a tested migration from version 1.
## The version-1 files under tests/saves/v1 were written by the M5 gate's own code
## (b0ac3f8) after replaying the M1, M2, M4 and M5 fixtures; they are real old saves.
## M6 only added state: new systems (corpses, hacks, recovery, sensors, sites, standing,
## wallet) and new fields (build: breaching, holes, excavated, a piece's facing and open
## state; movement: falling, in_move; an agent's home facing and route origin). The
## migration fills every missing system and top-level key from a freshly built sim (so
## each is empty), gives an old piece its template's starting open state and no facing,
## and an old agent its facing as home and the world origin as its route origin.
## A version-1 save was made over older content, so its content digest cannot match;
## it is accepted on the strength of every system's own restore validation.

const SAVES_DIR: String = "res://tests/saves/v1"

var _content: ContentDb


func _db() -> ContentDb:
	if _content == null:
		_content = ContentDb.new()
		assert_eq(ContentLoader.load_all(_content), OK, "content loads")
	return _content


func _v1_paths() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for file: String in DirAccess.get_files_at(SAVES_DIR):
		if file.ends_with(".json"):
			out.append(SAVES_DIR.path_join(file))
	out.sort()
	return out


func _load(text: String) -> SimRoot:
	var file: SaveFile = SaveFile.parse(text)
	assert_true(file.is_valid(), "parse: %s" % file.error)
	return SimAssembly.load_save(file, _db())


func test_the_committed_version_1_saves_are_version_1() -> void:
	var paths: PackedStringArray = _v1_paths()
	assert_eq(paths.size(), 4, "four old saves")
	for path: String in paths:
		var file: SaveFile = SaveFile.parse(FileAccess.get_file_as_string(path))
		assert_true(file.is_valid(), "%s parses" % path)
		assert_eq(file.version, 1, "%s is version 1" % path)
		assert_true(file.content_digest != _db().digest(), "%s was made over other content" % path)
		var systems: Dictionary = file.snapshot["systems"]
		assert_false(systems.has("wallet") or systems.has("corpses"), "%s predates M6" % path)


func test_every_version_1_save_migrates_loads_and_steps() -> void:
	for path: String in _v1_paths():
		var sim: SimRoot = _load(FileAccess.get_file_as_string(path))
		assert_true(sim != null, "%s loads" % path)
		if sim == null:
			continue
		var systems: Dictionary = sim.snapshot()["systems"]
		for id: String in ["corpses", "hacks", "recovery", "sensors", "sites", "standing", "wallet"]:
			assert_true(systems.has(id), "%s: %s is there" % [path, id])
		var rejected: int = sim.rejected_count()
		sim.step_n(80)
		assert_eq(sim.rejected_count(), rejected, "%s: it steps on" % path)


func test_old_records_get_their_defaults() -> void:
	var file: SaveFile = SaveFile.parse(FileAccess.get_file_as_string(SAVES_DIR.path_join("v1-m4-radio.json")))
	var old: Dictionary = file.snapshot["systems"]
	var old_agents: Dictionary = old["perception"]["agents"]
	var sim: SimRoot = SimAssembly.load_save(file, _db())
	assert_true(sim != null, "loads")
	var perception: PerceptionSystem = SimAssembly.perception_of(sim)
	assert_true(old_agents.size() > 0, "it has guards")
	for k: Variant in old_agents:
		var agent: int = k
		var rec: Dictionary = old_agents[k]
		var facing: int = rec["facing"]
		assert_eq(perception.route_origin_of(agent), Vector3i.ZERO, "agent %d patrols from the world origin" % agent)
		var now: Dictionary = perception.snapshot()["agents"][agent]
		assert_eq(now["home"], facing, "agent %d's home facing is the one it had" % agent)
	var build: BuildSystem = SimAssembly.build_of(sim)
	var old_pieces: Dictionary = old["build"]["pieces"]
	assert_eq(build.piece_ids().size(), old_pieces.size(), "every piece kept")
	for id: int in build.piece_ids():
		var t: Dictionary = _db().get_entry(&"build_piece", build.template_of(id))
		var starts_open: bool = t["starts_open"]
		assert_eq(build.is_open(id), starts_open, "piece %d starts as its template does" % id)


func test_round_trip_over_both_versions() -> void:
	# load(v1) saves as v2; that loads to the same state and saves to the same text
	for path: String in _v1_paths():
		var from_v1: SimRoot = _load(FileAccess.get_file_as_string(path))
		if from_v1 == null:
			fail("%s did not load" % path)
			continue
		var v2: String = SaveFile.serialize(from_v1, _db().digest())
		var parsed: SaveFile = SaveFile.parse(v2)
		assert_eq(parsed.version, SaveFile.SCHEMA_VERSION, "written as version %d" % SaveFile.SCHEMA_VERSION)
		var again: SimRoot = _load(v2)
		assert_true(again != null, "the v2 save loads")
		if again == null:
			continue
		assert_eq(again.state_hash(), from_v1.state_hash(), "%s: same state" % path)
		assert_eq(SaveFile.serialize(again, _db().digest()), v2, "%s: same text" % path)
		from_v1.step_n(40)
		again.step_n(40)
		assert_eq(again.state_hash(), from_v1.state_hash(), "%s: and they step on together" % path)


func test_versions_and_digests_are_still_checked() -> void:
	var text: String = FileAccess.get_file_as_string(SAVES_DIR.path_join("v1-m1-range.json"))
	for bad_version: String in ["0", "3", "1.5"]:
		var bad: SaveFile = SaveFile.parse(text.replace('"save_schema_version": 1', '"save_schema_version": %s' % bad_version))
		assert_false(bad.is_valid(), "version %s refused" % bad_version)
	# a version-2 save over other content is still refused
	var sim: SimRoot = _load(text)
	var v2: String = SaveFile.serialize(sim, "0".repeat(64))
	var other: SaveFile = SaveFile.parse(v2)
	assert_true(other.is_valid(), "parses")
	assert_eq(SimAssembly.load_save(other, _db()), null, "a v2 save over other content is refused")
	# a version-1 save whose state the current systems cannot accept is refused
	var broken: SaveFile = SaveFile.parse(text)
	var systems: Dictionary = broken.snapshot["systems"]
	var actors: Dictionary = systems["actors"]
	actors["actors"] = {999: {"oops": true}}
	assert_eq(SimAssembly.load_save(broken, _db()), null, "a v1 save is still validated by every restore")
