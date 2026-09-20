extends GcityTest

const SEED: int = 0x5eed_0001
const PROPERTY_CASES: int = 10_000


func test_sha256_hex_shape() -> void:
	var h: String = StateHash.of({"a": 1})
	assert_eq(h.length(), 64, "hash length")
	assert_eq(h, h.to_lower(), "hash is lowercase")


func test_dictionary_order_independent() -> void:
	var a: Dictionary = {"x": 1, "y": [1, 2, {"k": "v"}], "z": null}
	var b: Dictionary = {"z": null, "y": [1, 2, {"k": "v"}], "x": 1}
	assert_eq(StateHash.of(a), StateHash.of(b), "insertion order must not matter")


func test_mixed_key_types_are_ordered_deterministically() -> void:
	var a: Dictionary = {3: "c", "b": 2, 1: "a", &"sn": 4}
	var b: Dictionary = {&"sn": 4, 1: "a", "b": 2, 3: "c"}
	assert_eq(StateHash.of(a), StateHash.of(b), "int/String/StringName keys sort canonically")


func test_value_and_type_changes_change_hash() -> void:
	var base: String = StateHash.of({"n": 1})
	assert_ne(StateHash.of({"n": 2}), base, "value change")
	assert_ne(StateHash.of({"n": 1.0}), base, "int vs float are distinct")
	assert_ne(StateHash.of({"n": "1"}), base, "int vs string are distinct")
	assert_ne(StateHash.of({"m": 1}), base, "key change")
	assert_ne(StateHash.of({"n": 1, "o": 0}), base, "extra key")
	assert_ne(StateHash.of([1]), StateHash.of({0: 1}), "array vs dictionary are distinct")
	assert_ne(StateHash.of("a"), StateHash.of(&"a"), "String vs StringName are distinct")
	assert_ne(StateHash.of(true), StateHash.of(1), "bool vs int are distinct")


func test_prefix_ambiguity_is_impossible() -> void:
	# Length-prefixed strings: ["ab", "c"] must not collide with ["a", "bc"].
	assert_ne(StateHash.of(["ab", "c"]), StateHash.of(["a", "bc"]), "length prefixes")
	assert_ne(StateHash.of(["a", ""]), StateHash.of(["a"]), "trailing empty string")


func test_unsupported_types_fail_loudly_with_empty_hash() -> void:
	assert_eq(StateHash.of(Vector2.ZERO), "", "Vector2 unsupported")
	assert_eq(StateHash.of({Vector2.ZERO: 1}), "", "Vector2 key unsupported")
	assert_eq(StateHash.of({"ok": 1, "bad": RefCounted.new()}), "", "object unsupported, even nested")
	assert_eq(StateHash.of(PackedInt64Array([1])), "", "packed int arrays unsupported")


func test_property_equal_structures_hash_equal_and_shuffled_keys_do_not_matter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var mismatches: int = 0
	var errors: int = 0
	for _case: int in PROPERTY_CASES:
		var value: Variant = _random_value(rng, 0)
		var h1: String = StateHash.of(value)
		var h2: String = StateHash.of(_reordered(value, rng))
		if h1.is_empty():
			errors += 1
		elif h1 != h2:
			mismatches += 1
	assert_eq(errors, 0, "generated values must always hash")
	assert_eq(mismatches, 0, "reordered copies must hash equal")


func _random_value(rng: RandomNumberGenerator, depth: int) -> Variant:
	var pick: int = rng.randi_range(0, 8 if depth < 3 else 6)
	match pick:
		0:
			return null
		1:
			return rng.randi() % 2 == 0
		2:
			return rng.randi() - (1 << 31)
		3:
			return rng.randf() * 1000.0
		4:
			return "s%d" % rng.randi_range(0, 50)
		5:
			return StringName("n%d" % rng.randi_range(0, 50))
		6:
			var bytes := PackedByteArray()
			for _i: int in rng.randi_range(0, 8):
				bytes.append(rng.randi_range(0, 255))
			return bytes
		7:
			var arr: Array = []
			for _i: int in rng.randi_range(0, 4):
				arr.append(_random_value(rng, depth + 1))
			return arr
		_:
			var dict: Dictionary = {}
			for _i: int in rng.randi_range(0, 4):
				var key: Variant
				match rng.randi_range(0, 2):
					0:
						key = rng.randi_range(-5, 5)
					1:
						key = "k%d" % rng.randi_range(0, 5)
					_:
						key = StringName("k%d" % rng.randi_range(0, 5))
				dict[key] = _random_value(rng, depth + 1)
			return dict


## Deep copy with every dictionary rebuilt in a shuffled key order.
func _reordered(value: Variant, rng: RandomNumberGenerator) -> Variant:
	match typeof(value):
		TYPE_ARRAY:
			var arr: Array = value
			var out: Array = []
			for element: Variant in arr:
				out.append(_reordered(element, rng))
			return out
		TYPE_DICTIONARY:
			var dict: Dictionary = value
			var keys: Array = dict.keys()
			for i: int in range(keys.size() - 1, 0, -1):
				var j: int = rng.randi_range(0, i)
				var swap: Variant = keys[i]
				keys[i] = keys[j]
				keys[j] = swap
			var out: Dictionary = {}
			for key: Variant in keys:
				out[key] = _reordered(dict[key], rng)
			return out
		_:
			return value
