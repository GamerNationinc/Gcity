extends GcityTest

const SEED: int = 20260920


func _content() -> ContentDb:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	return db


func test_real_content_loads_and_registers_every_stat() -> void:
	var db := _content()
	var stat_files: PackedStringArray = DirAccess.get_files_at("res://content/stat")
	var expected: Array[StringName] = []
	for file: String in stat_files:
		if file.ends_with(".json"):
			expected.append(StringName(file.get_basename()))
	expected.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	assert_true(expected.size() >= 7, "M1 declares at least seven stats")
	assert_eq(db.ids(&"stat"), expected, "every stat file is an entry")
	var sim: SimRoot = SimAssembly.build(SEED, db)
	assert_true(sim != null, "assembly succeeds")
	assert_eq(sim.system_ids(), [&"content", &"entities", &"stats", &"items", &"actors", &"combat"] as Array[StringName], "fixed system order")
	var stats: StatResolver = SimAssembly.stats_of(sim)
	assert_eq(stats.stat_ids(), expected, "resolver registered every stat")
	var entry: Dictionary = db.get_entry(&"stat", &"damage")
	assert_eq(typeof(entry["default_base"]), TYPE_INT, "integral JSON numbers arrive as ints")
	assert_eq(stats.resolve(1, &"damage"), entry["default_base"], "default base comes from the file")


func test_two_builds_hash_equal_and_content_is_in_the_hash() -> void:
	var a: SimRoot = SimAssembly.build(SEED, _content())
	var b: SimRoot = SimAssembly.build(SEED, _content())
	a.step_n(5)
	b.step_n(5)
	assert_eq(a.state_hash(), b.state_hash(), "same content, same seed, same hash")
	var snap: Dictionary = a.snapshot()
	var systems: Dictionary = snap["systems"]
	var content_state: Dictionary = systems[&"content"]
	var digest: String = content_state["digest"]
	assert_eq(digest.length(), 64, "content digest is part of the state")
	var db := _content()
	assert_eq(db.add(&"stat", &"zz_extra", {"schema_version": 1, "default_base": 1, "description": "x"}), OK, "extra entry")
	var c: SimRoot = SimAssembly.build(SEED, db)
	c.step_n(5)
	assert_ne(a.state_hash(), c.state_hash(), "different content, different hash")


func test_assembly_refuses_bad_content() -> void:
	var db := ContentDb.new()
	assert_eq(db.add(&"stat", &"broken", {"schema_version": 1, "default_base": "many"}), OK, "db accepts shape; the resolver checks meaning")
	assert_true(SimAssembly.build(SEED, db) == null, "a stat without an integer default_base stops assembly")


func test_stats_of_requires_an_assembled_sim() -> void:
	assert_true(SimAssembly.stats_of(SimRoot.new(SEED)) == null, "bare sim has no resolver")
	assert_true(SimAssembly.items_of(SimRoot.new(SEED)) == null, "bare sim has no items")
	assert_true(SimAssembly.entities_of(SimRoot.new(SEED)) == null, "bare sim has no id allocator")


func test_commands_are_registered_by_the_item_system() -> void:
	var sim: SimRoot = SimAssembly.build(SEED, _content())
	assert_eq(sim.commands().kinds(), [&"actor.spawn", &"actor.wield", &"item.spawn", &"magazine.load", &"magazine.unload",
		&"weapon.attach", &"weapon.detach", &"weapon.fire", &"weapon.reload_emergency", &"weapon.reload_tactical"] as Array[StringName], "lexical kinds")


func test_assembly_refuses_content_the_item_system_cannot_use() -> void:
	var db := _content()
	assert_eq(db.add(&"weapon_part", &"zz_bad", {"schema_version": 1, "description": "x", "socket": "barrel", "fits": ["g19"],
		"modifiers": [{"stat": "recoil", "class": "pow", "value": 1}]}), OK, "db accepts shape")
	assert_true(SimAssembly.build(SEED, db) == null, "an unregistered modifier class stops assembly")
