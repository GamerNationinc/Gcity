extends GcityTest


func _accept(_sim: SimRoot, _payload: Dictionary) -> bool:
	return true


func _reject(_sim: SimRoot, _payload: Dictionary) -> bool:
	return false


func _broken(_sim: SimRoot, _payload: Dictionary) -> int:
	return 42


func test_register_rejects_empty_kind_invalid_handler_and_duplicates() -> void:
	var registry := CommandRegistry.new()
	assert_eq(registry.register(&"", _accept), ERR_INVALID_PARAMETER, "empty kind")
	assert_eq(registry.register(&"x", Callable()), ERR_INVALID_PARAMETER, "invalid handler")
	assert_eq(registry.register(&"x", _accept), OK, "first registration")
	assert_eq(registry.register(&"x", _reject), ERR_ALREADY_EXISTS, "duplicate")
	assert_true(registry.has(&"x"), "has after register")
	assert_false(registry.has(&"y"), "has for unknown")


func test_kinds_are_sorted() -> void:
	var registry := CommandRegistry.new()
	registry.register(&"b", _accept)
	registry.register(&"a", _accept)
	registry.register(&"c", _accept)
	var kinds: Array[StringName] = registry.kinds()
	assert_eq(kinds, [&"a", &"b", &"c"] as Array[StringName], "sorted kinds")


func test_dispatch_outcomes() -> void:
	var registry := CommandRegistry.new()
	registry.register(&"ok", _accept)
	registry.register(&"no", _reject)
	registry.register(&"bug", _broken)
	var sim := SimRoot.new(1)
	assert_eq(registry.dispatch(sim, SimCommand.new(1, &"ok", {})), OK, "accepted")
	assert_eq(registry.dispatch(sim, SimCommand.new(1, &"no", {})), ERR_INVALID_PARAMETER, "rejected by handler")
	assert_eq(registry.dispatch(sim, SimCommand.new(1, &"missing", {})), ERR_DOES_NOT_EXIST, "unknown kind")
	assert_eq(registry.dispatch(sim, SimCommand.new(1, &"bug", {})), ERR_BUG, "handler contract violation")
