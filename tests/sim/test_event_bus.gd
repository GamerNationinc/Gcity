extends GcityTest


func test_delivery_in_subscription_order_with_frozen_payload() -> void:
	var bus := EventBus.new()
	var seen: Array[String] = []
	assert_eq(bus.subscribe(&"combat.hit", func(p: Dictionary) -> void: seen.append("a:%d" % p["damage"])), OK, "a")
	assert_eq(bus.subscribe(&"combat.hit", func(p: Dictionary) -> void: seen.append("b:%s" % str(p.is_read_only()))), OK, "b")
	assert_eq(bus.subscribe(&"Bad Name", func(_p: Dictionary) -> void: pass), ERR_INVALID_PARAMETER, "name rule")
	assert_eq(bus.subscribe(&"x", Callable()), ERR_INVALID_PARAMETER, "invalid callable")
	assert_eq(bus.emit(&"combat.hit", {"damage": 7}), 2, "two handlers ran")
	assert_eq(seen, ["a:7", "b:true"] as Array[String], "in order, payload read-only")
	assert_eq(bus.emit(&"nobody.listens", {}), 0, "no handlers is fine")
	assert_eq(bus.emitted_count(), 2, "both emits counted")
	assert_eq(bus.subscriber_count(&"combat.hit"), 2, "count")
