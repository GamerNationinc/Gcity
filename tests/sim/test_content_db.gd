extends GcityTest


func _valid() -> Dictionary:
	return {"schema_version": 1, "default_base": 5, "description": "d"}


func test_add_and_read_back() -> void:
	var db := ContentDb.new()
	assert_eq(db.add(&"stat", &"damage", _valid()), OK, "add")
	assert_true(db.has(&"stat", &"damage"), "has")
	assert_eq(db.count(), 1, "count")
	assert_eq(db.ids(&"stat"), [&"damage"] as Array[StringName], "ids")
	assert_eq(db.kinds(), [&"stat"] as Array[StringName], "kinds")
	var entry: Dictionary = db.get_entry(&"stat", &"damage")
	assert_eq(entry["default_base"], 5, "value read back")
	assert_true(entry.is_read_only(), "entries are frozen")


func test_caller_dictionary_is_copied_not_retained() -> void:
	var db := ContentDb.new()
	var data: Dictionary = _valid()
	assert_eq(db.add(&"stat", &"damage", data), OK, "add")
	data["default_base"] = 99
	var entry: Dictionary = db.get_entry(&"stat", &"damage")
	assert_eq(entry["default_base"], 5, "later edits to the caller's dictionary do not leak in")


func test_rejections() -> void:
	var db := ContentDb.new()
	assert_eq(db.add(&"Stat", &"damage", _valid()), ERR_INVALID_PARAMETER, "kind format")
	assert_eq(db.add(&"stat", &"Damage-1", _valid()), ERR_INVALID_PARAMETER, "id format")
	assert_eq(db.add(&"stat", &"", _valid()), ERR_INVALID_PARAMETER, "empty id")
	assert_eq(db.add(&"stat", &"a", {"default_base": 1}), ERR_INVALID_PARAMETER, "missing schema_version")
	assert_eq(db.add(&"stat", &"a", {"schema_version": 1.0}), ERR_INVALID_PARAMETER, "float schema_version")
	assert_eq(db.add(&"stat", &"a", {"schema_version": 0}), ERR_INVALID_PARAMETER, "zero schema_version")
	assert_eq(db.add(&"stat", &"a", {"schema_version": 1, "v": Vector2.ZERO}), ERR_INVALID_PARAMETER, "unhashable data")
	assert_eq(db.add(&"stat", &"a", _valid()), OK, "valid")
	assert_eq(db.add(&"stat", &"a", _valid()), ERR_ALREADY_EXISTS, "duplicate")
	assert_eq(db.count(), 1, "only the valid one landed")
	assert_eq(db.get_entry(&"stat", &"missing"), {}, "missing entry is empty")
	assert_eq(db.ids(&"nope"), [] as Array[StringName], "unknown kind has no ids")


func test_digest_is_order_independent_and_content_sensitive() -> void:
	var a := ContentDb.new()
	var b := ContentDb.new()
	assert_eq(a.add(&"stat", &"x", _valid()), OK, "a1")
	assert_eq(a.add(&"stat", &"y", _valid()), OK, "a2")
	assert_eq(b.add(&"stat", &"y", _valid()), OK, "b1")
	assert_eq(b.add(&"stat", &"x", _valid()), OK, "b2")
	assert_eq(a.digest(), b.digest(), "same entries, different insertion order, same digest")
	assert_eq(a.digest().length(), 64, "digest is a sha256 hex")
	var c := ContentDb.new()
	var changed: Dictionary = _valid()
	changed["default_base"] = 6
	assert_eq(c.add(&"stat", &"x", changed), OK, "c1")
	assert_eq(c.add(&"stat", &"y", _valid()), OK, "c2")
	assert_ne(a.digest(), c.digest(), "one changed number changes the digest")


func test_locks_at_first_tick_and_snapshot_carries_digest() -> void:
	var db := ContentDb.new()
	assert_eq(db.add(&"stat", &"x", _valid()), OK, "add before tick")
	var sim := SimRoot.new(1)
	assert_eq(sim.register_system(db), OK, "register")
	var before: Dictionary = db.snapshot()
	assert_eq(before["digest"], db.digest(), "snapshot digest")
	assert_eq(before["entries"], 1, "snapshot count")
	sim.step()
	assert_true(db.is_locked(), "locked after tick")
	assert_eq(db.add(&"stat", &"y", _valid()), ERR_LOCKED, "no adds after the first tick")
	assert_eq(db.snapshot(), before, "state unchanged by the rejected add")
	assert_eq(StateHash.of(db.snapshot()).length(), 64, "snapshot is hashable")
