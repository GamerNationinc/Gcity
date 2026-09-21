extends GcityTest


func test_integral_floats_become_ints_everything_else_is_untouched() -> void:
	var data: Dictionary = {"a": 1.0, "b": 1.5, "c": [2.0, 2.25, "3.0", true, null], "d": {"e": -7.0, "f": 9.0e15}, "g": 9.0e16}
	JsonNumbers.normalise(data)
	assert_eq(typeof(data["a"]), TYPE_INT, "1.0 -> int")
	assert_eq(data["a"], 1, "value kept")
	assert_eq(typeof(data["b"]), TYPE_FLOAT, "1.5 stays float")
	var arr: Array = data["c"]
	assert_eq(typeof(arr[0]), TYPE_INT, "arrays too")
	assert_eq(typeof(arr[1]), TYPE_FLOAT, "non-integral in array stays")
	assert_eq(arr[2], "3.0", "strings untouched")
	assert_eq(arr[3], true, "bools untouched")
	assert_eq(arr[4], null, "null untouched")
	var nested: Dictionary = data["d"]
	assert_eq(nested["e"], -7, "nested negative")
	assert_eq(typeof(nested["f"]), TYPE_INT, "9e15 is exactly representable")
	assert_eq(typeof(data["g"]), TYPE_FLOAT, "beyond 2^53 stays float rather than pretending to be exact")
	assert_eq(JsonNumbers.normalise(4.0), 4, "top-level scalar is returned converted")
