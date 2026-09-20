## Base class for every test file under tests/. The runner instantiates a fresh
## instance per test_* method, calls it, and collects the failures recorded here.
class_name GcityTest extends RefCounted

var _failures: PackedStringArray = PackedStringArray()
var _assertion_count: int = 0


func failures() -> PackedStringArray:
	return _failures


func assertion_count() -> int:
	return _assertion_count


func fail(message: String) -> void:
	_failures.append(message)


func assert_true(condition: bool, message: String) -> void:
	_assertion_count += 1
	if not condition:
		_failures.append(message)


func assert_false(condition: bool, message: String) -> void:
	assert_true(not condition, message)


func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	_assertion_count += 1
	if typeof(actual) != typeof(expected) or actual != expected:
		_failures.append("%s: expected %s, got %s" % [message, var_to_str(expected), var_to_str(actual)])


func assert_ne(actual: Variant, unexpected: Variant, message: String) -> void:
	_assertion_count += 1
	if typeof(actual) == typeof(unexpected) and actual == unexpected:
		_failures.append("%s: both were %s" % [message, var_to_str(actual)])


## Reads a project file as text. Fails the test (and returns "") if it cannot be read.
func read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		fail("cannot open %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return ""
	return file.get_as_text()
