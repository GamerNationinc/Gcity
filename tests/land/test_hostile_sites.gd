extends GcityTest

## M6 spec claim 22: hostile site files are refused, by content validation at assembly
## or by the spawn, which then changes nothing. The corpus is tests/fuzz/content_sites.

const SEED: int = 20261190
const DIR: String = "res://tests/fuzz/content_sites"
const IDS: Dictionary = {"site": "zz_hostile", "patrol_route": "zz_off_the_floor", "hack_target": "zz_unknown_effect"}


func test_every_hostile_site_is_refused() -> void:
	var files: PackedStringArray = PackedStringArray()
	for f: String in DirAccess.get_files_at(DIR):
		if f.ends_with(".json"):
			files.append(f)
	files.sort()
	assert_eq(files.size(), 5, "five hostile sites")
	for f: String in files:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join(f)))
		if typeof(parsed) != TYPE_DICTIONARY:
			fail("%s is not an object" % f)
			continue
		var case: Dictionary = parsed
		JsonNumbers.normalise(case)  # as the content loader does: whole numbers are ints
		var expect: String = case["expect"]
		var entries: Dictionary = case["entries"]
		var db := ContentDb.new()
		assert_eq(ContentLoader.load_all(db), OK, "content")
		for kind_v: Variant in entries:
			var kind: String = kind_v
			var entry: Dictionary = entries[kind_v]
			var id: String = IDS[kind]
			assert_eq(db.add(StringName(kind), StringName(id), entry), OK, "%s: add %s/%s" % [f, kind, id])
		var sim: SimRoot = SimAssembly.build(SEED, db)
		if expect == "refused_at_assembly":
			assert_true(sim == null, "%s: refused at assembly" % f)
			continue
		assert_eq(expect, "refused_at_spawn", "%s: a known expectation" % f)
		assert_true(sim != null, "%s: assembles" % f)
		if sim == null:
			continue
		var before: String = sim.state_hash()
		var rejected: int = sim.rejected_count()
		sim.submit(SimCommand.new(sim.get_tick() + 1, &"site.spawn", {"site": "zz_hostile", "origin": [300, 0, 300]}))
		sim.step()
		assert_eq(sim.rejected_count(), rejected + 1, "%s: the spawn is rejected" % f)
		assert_false(SimAssembly.sites_of(sim).is_spawned(&"zz_hostile"), "%s: nothing spawned" % f)
		var after: SimRoot = SimAssembly.build(SEED, db)
		after.submit(SimCommand.new(after.get_tick() + 1, &"site.spawn", {"site": "nowhere", "origin": [300, 0, 300]}))
		after.step()
		assert_eq(sim.state_hash(), after.state_hash(), "%s: the state is as if an unknown site had been asked for" % f)
		assert_true(before != "", "hashed")
