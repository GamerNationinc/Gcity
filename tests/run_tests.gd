## Headless test runner. Usage:
##   godot --headless --path . -s tests/run_tests.gd
## Discovers tests/**/test_*.gd, runs every test_* method on a fresh instance, prints
## one line per test and a summary, and exits 0 only if everything passed.
extends SceneTree

const TESTS_ROOT: String = "res://tests"


func _initialize() -> void:
	var paths: PackedStringArray = PackedStringArray()
	_discover(TESTS_ROOT, paths)
	paths.sort()
	var total: int = 0
	var failed: int = 0
	var assertions: int = 0
	for path: String in paths:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			print("FAIL %s: script did not compile" % path)
			failed += 1
			total += 1
			continue
		for method: String in _test_methods(script):
			total += 1
			var probe: Variant = script.new()
			if not (probe is GcityTest):
				print("FAIL %s::%s: test scripts must extend GcityTest" % [path, method])
				failed += 1
				continue
			var test: GcityTest = probe
			test.call(method)
			assertions += test.assertion_count()
			var failures: PackedStringArray = test.failures()
			if failures.is_empty():
				print("ok   %s::%s" % [path, method])
			else:
				failed += 1
				print("FAIL %s::%s" % [path, method])
				for failure: String in failures:
					print("     - %s" % failure)
	print("")
	print("%d tests, %d assertions, %d failed" % [total, assertions, failed])
	if total == 0:
		print("no tests found under %s" % TESTS_ROOT)
		quit(2)
		return
	quit(1 if failed > 0 else 0)


func _discover(dir_path: String, out: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_error("cannot open %s: %s" % [dir_path, error_string(DirAccess.get_open_error())])
		return
	dir.include_hidden = false
	for sub: String in dir.get_directories():
		_discover(dir_path.path_join(sub), out)
	for file: String in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd"):
			out.append(dir_path.path_join(file))


## Names of test_* methods declared on the script itself, in source order, deduplicated
## (get_method_list also reports inherited and overridden entries).
func _test_methods(script: GDScript) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for entry: Dictionary in script.get_script_method_list():
		var name: String = entry["name"]
		if name.begins_with("test_") and not names.has(name):
			names.append(name)
	return names
