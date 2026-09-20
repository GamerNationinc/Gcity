## A recorded simulation run: seed, tick count, input stream and the state hash the
## run must reproduce. The primary integration test of the project (standards §3.1).
##
## Fixture text is untrusted input (standards §5.1): every field is type- and
## range-checked, unknown keys are rejected, and a bad fixture never reaches the sim.
## A failed parse returns an object whose [member error] is non-empty.
class_name ReplayFixture extends RefCounted

const SCHEMA_VERSION: int = 1
## Upper bounds on hostile input. Generous for real fixtures, small enough that a
## malicious file cannot make the test harness run for hours.
const MAX_TICKS: int = 10_000_000
const MAX_COMMANDS: int = 1_000_000
const MAX_NAME_LENGTH: int = 128
## Integers travel through JSON as doubles; beyond this they are no longer exact.
const MAX_EXACT_INT: int = 1 << 53

const _REQUIRED_KEYS: Array[String] = [
	"schema_version", "name", "seed", "ticks", "commands", "expected_hash",
]
const _COMMAND_KEYS: Array[String] = ["tick", "kind", "payload"]

var name: String = ""
var seed: int = 0
var ticks: int = 0
var commands: Array[SimCommand] = []
## 64 lowercase hex characters, or empty while a new fixture is being recorded.
var expected_hash: String = ""
## Empty when the fixture is valid; otherwise the first validation failure found.
var error: String = ""


func is_valid() -> bool:
	return error.is_empty()


static func parse(text: String) -> ReplayFixture:
	var fixture := ReplayFixture.new()
	fixture.error = fixture._load(text)
	if not fixture.error.is_empty():
		fixture.commands.clear()
	return fixture


func _load(text: String) -> String:
	var json := JSON.new()
	var parse_err: Error = json.parse(text)
	if parse_err != OK:
		return "line %d: %s" % [json.get_error_line(), json.get_error_message()]
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return "top level must be an object"
	var root: Dictionary = data
	var key_err: String = _check_keys(root, _REQUIRED_KEYS, "fixture")
	if not key_err.is_empty():
		return key_err

	var version: int = 0
	var err: String = _read_int(root, "schema_version", 1, SCHEMA_VERSION)
	if not err.is_empty():
		return err
	version = _int_of(root["schema_version"])
	if version != SCHEMA_VERSION:
		return "schema_version %d is not supported (expected %d)" % [version, SCHEMA_VERSION]

	if typeof(root["name"]) != TYPE_STRING:
		return "name must be a string"
	name = root["name"]
	if name.is_empty() or name.length() > MAX_NAME_LENGTH:
		return "name must be 1-%d characters" % MAX_NAME_LENGTH

	err = _read_int(root, "seed", -MAX_EXACT_INT, MAX_EXACT_INT)
	if not err.is_empty():
		return err
	seed = _int_of(root["seed"])

	err = _read_int(root, "ticks", 1, MAX_TICKS)
	if not err.is_empty():
		return err
	ticks = _int_of(root["ticks"])

	if typeof(root["expected_hash"]) != TYPE_STRING:
		return "expected_hash must be a string"
	expected_hash = root["expected_hash"]
	if not expected_hash.is_empty() and not _is_sha256_hex(expected_hash):
		return "expected_hash must be empty or 64 lowercase hex characters"

	if typeof(root["commands"]) != TYPE_ARRAY:
		return "commands must be an array"
	var raw_commands: Array = root["commands"]
	if raw_commands.size() > MAX_COMMANDS:
		return "commands: more than %d entries" % MAX_COMMANDS
	for index: int in raw_commands.size():
		err = _load_command(raw_commands[index], index)
		if not err.is_empty():
			return err
	return ""


func _load_command(raw: Variant, index: int) -> String:
	if typeof(raw) != TYPE_DICTIONARY:
		return "commands[%d]: must be an object" % index
	var entry: Dictionary = raw
	var key_err: String = _check_keys(entry, _COMMAND_KEYS, "commands[%d]" % index)
	if not key_err.is_empty():
		return key_err
	var err: String = _read_int(entry, "tick", 1, ticks)
	if not err.is_empty():
		return "commands[%d]: %s" % [index, err]
	if typeof(entry["kind"]) != TYPE_STRING:
		return "commands[%d]: kind must be a string" % index
	var kind: String = entry["kind"]
	if kind.is_empty():
		return "commands[%d]: kind must not be empty" % index
	if typeof(entry["payload"]) != TYPE_DICTIONARY:
		return "commands[%d]: payload must be an object" % index
	var payload: Dictionary = entry["payload"]
	commands.append(SimCommand.new(_int_of(entry["tick"]), StringName(kind), payload))
	return ""


static func _check_keys(dict: Dictionary, required: Array[String], what: String) -> String:
	for key: String in required:
		if not dict.has(key):
			return "%s: missing key '%s'" % [what, key]
	for key: Variant in dict.keys():
		var key_text: String = str(key)
		if not required.has(key_text):
			return "%s: unknown key '%s'" % [what, key_text]
	return ""


## JSON numbers arrive as floats. Accept an int, or a float that is exactly integral
## and within the exactly-representable range; reject everything else.
static func _read_int(dict: Dictionary, key: String, lo: int, hi: int) -> String:
	var raw: Variant = dict[key]
	var value: int = 0
	match typeof(raw):
		TYPE_INT:
			value = raw
		TYPE_FLOAT:
			var f: float = raw
			if is_nan(f) or is_inf(f) or f != floorf(f) or absf(f) > float(MAX_EXACT_INT):
				return "%s must be an integer" % key
			value = int(f)
		_:
			return "%s must be an integer" % key
	if value < lo or value > hi:
		return "%s must be between %d and %d" % [key, lo, hi]
	return ""


## Only valid after [method _read_int] accepted the same value.
static func _int_of(raw: Variant) -> int:
	if typeof(raw) == TYPE_INT:
		var i: int = raw
		return i
	var f: float = raw
	return int(f)


static func _is_sha256_hex(text: String) -> bool:
	if text.length() != 64:
		return false
	for i: int in text.length():
		var c: int = text.unicode_at(i)
		var is_digit: bool = c >= 0x30 and c <= 0x39
		var is_lower_hex: bool = c >= 0x61 and c <= 0x66
		if not (is_digit or is_lower_hex):
			return false
	return true
