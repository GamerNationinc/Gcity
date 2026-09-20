extends GcityTest

const FUZZ_DIR: String = "res://tests/fuzz/replay_fixture"
const FUZZ_SEED: int = 0xf022
const FUZZ_MUTATIONS: int = 10_000

const VALID: String = """
{
	"schema_version": 1,
	"name": "unit",
	"seed": 42,
	"ticks": 10,
	"commands": [
		{"tick": 3, "kind": "counter.add", "payload": {"amount": 5}},
		{"tick": 10, "kind": "counter.add", "payload": {"amount": -1}}
	],
	"expected_hash": ""
}
"""


func test_valid_fixture_parses() -> void:
	var fixture: ReplayFixture = ReplayFixture.parse(VALID)
	assert_true(fixture.is_valid(), "valid: %s" % fixture.error)
	assert_eq(fixture.name, "unit", "name")
	assert_eq(fixture.seed, 42, "seed")
	assert_eq(fixture.ticks, 10, "ticks")
	assert_eq(fixture.commands.size(), 2, "two commands")
	assert_eq(fixture.commands[0].tick, 3, "command tick")
	assert_eq(fixture.commands[0].kind, &"counter.add", "command kind")
	assert_eq(fixture.commands[0].payload, {"amount": 5.0}, "payload passes through as parsed JSON")
	assert_eq(fixture.expected_hash, "", "empty hash allowed while recording")


func test_hash_field_validation() -> void:
	var good: String = "a".repeat(64)
	assert_true(ReplayFixture.parse(_with("expected_hash", '"%s"' % good)).is_valid(), "64 lowercase hex ok")
	assert_false(ReplayFixture.parse(_with("expected_hash", '"%s"' % good.to_upper())).is_valid(), "uppercase rejected")
	assert_false(ReplayFixture.parse(_with("expected_hash", '"%s"' % "a".repeat(63))).is_valid(), "wrong length rejected")
	assert_false(ReplayFixture.parse(_with("expected_hash", '"%sg"' % "a".repeat(63))).is_valid(), "non-hex rejected")
	assert_false(ReplayFixture.parse(_with("expected_hash", "1")).is_valid(), "non-string rejected")


func test_hostile_inputs_are_rejected_with_a_message() -> void:
	var cases: Dictionary[String, String] = {
		"": "empty",
		"not json": "garbage",
		"[]": "array top level",
		"null": "null top level",
		"{}": "missing keys",
		_with("schema_version", "2"): "unsupported version",
		_with("schema_version", "1.5"): "fractional version",
		_with("seed", '"42"'): "string seed",
		_with("seed", "1e300"): "huge seed",
		_with("seed", "4.5"): "fractional seed",
		_with("ticks", "0"): "zero ticks",
		_with("ticks", "-1"): "negative ticks",
		_with("ticks", "10000001"): "ticks over cap",
		_with("name", '""'): "empty name",
		_with("name", "7"): "numeric name",
		_with("commands", "{}"): "commands not array",
		_with("commands", '[{"tick": 11, "kind": "k", "payload": {}}]'): "command after last tick",
		_with("commands", '[{"tick": 0, "kind": "k", "payload": {}}]'): "command at tick 0",
		_with("commands", '[{"tick": 1, "kind": "", "payload": {}}]'): "empty kind",
		_with("commands", '[{"tick": 1, "kind": "k", "payload": []}]'): "payload not object",
		_with("commands", '[{"tick": 1, "kind": "k"}]'): "command missing payload",
		_with("commands", '[{"tick": 1, "kind": "k", "payload": {}, "x": 1}]'): "command unknown key",
		_with("commands", "[1]"): "command not object",
		VALID.replace('"name"', '"extra": 1, "name"'): "unknown top-level key",
	}
	for text: String in cases:
		var fixture: ReplayFixture = ReplayFixture.parse(text)
		assert_false(fixture.is_valid(), "%s must be rejected" % cases[text])
		assert_false(fixture.error.is_empty(), "%s must carry a message" % cases[text])
		assert_eq(fixture.commands.size(), 0, "%s leaves no partial commands" % cases[text])


func test_invalid_utf8_is_rejected() -> void:
	var bytes := PackedByteArray([0x7b, 0xff, 0xfe, 0x22, 0xc0, 0x7d])
	var fixture: ReplayFixture = ReplayFixture.parse(bytes.get_string_from_utf8())
	assert_false(fixture.is_valid(), "invalid UTF-8 rejected")
	assert_false(fixture.error.is_empty(), "invalid UTF-8 carries a message")


func test_committed_fuzz_corpus_never_validates() -> void:
	var dir: DirAccess = DirAccess.open(FUZZ_DIR)
	assert_true(dir != null, "corpus directory exists")
	if dir == null:
		return
	var files: PackedStringArray = dir.get_files()
	assert_true(files.size() > 0, "corpus is not empty")
	for file: String in files:
		if not file.ends_with(".json"):
			continue
		var fixture: ReplayFixture = ReplayFixture.parse(read_text(FUZZ_DIR.path_join(file)))
		assert_false(fixture.is_valid(), "%s must be rejected" % file)


func test_random_mutations_never_crash_and_never_validate_silently() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = FUZZ_SEED
	var base: PackedByteArray = VALID.to_utf8_buffer()
	var accepted: int = 0
	var inconsistent: int = 0
	for _i: int in FUZZ_MUTATIONS:
		var bytes: PackedByteArray = base.duplicate()
		for _m: int in rng.randi_range(1, 4):
			var at: int = rng.randi_range(0, bytes.size() - 1)
			match rng.randi_range(0, 2):
				0:
					bytes[at] = rng.randi_range(0x20, 0x7e)
				1:
					bytes.remove_at(at)
				_:
					bytes.insert(at, rng.randi_range(0x20, 0x7e))
		var fixture: ReplayFixture = ReplayFixture.parse(bytes.get_string_from_utf8())
		if fixture.is_valid():
			accepted += 1
			if fixture.ticks < 1 or fixture.name.is_empty():
				inconsistent += 1
		elif fixture.commands.size() != 0:
			inconsistent += 1
	assert_eq(inconsistent, 0, "every accepted fixture satisfies its own invariants")
	assert_true(accepted < FUZZ_MUTATIONS, "mutations were actually applied (%d accepted)" % accepted)


func _with(key: String, json_value: String) -> String:
	var regex := RegEx.new()
	regex.compile('"%s": [^,\\n]+(,?)\\n' % key)
	return regex.sub(VALID, '"%s": %s$1\n' % [key, json_value.replace("$", "$$")])
