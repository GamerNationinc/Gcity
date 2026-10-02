## Headless test runner. Usage:
##   godot --headless --path . -s tests/run_tests.gd [-- <test> ...]
##   godot --headless --path . -s tests/run_tests.gd -- --list <file> ...
## Discovers tests/**/test_*.gd, or runs the tests named after `--`: a file
## (res://tests/.../test_x.gd) or one of its methods (res://tests/.../test_x.gd::test_y).
## tools/parallel_tests.py uses both to give each its own process, and `--list` to learn
## a file's methods from the engine rather than from its text. Runs every chosen test_*
## method on a fresh instance, prints one line per test and a summary, and exits 0 only
## if everything passed.
extends SceneTree

const TESTS_ROOT: String = "res://tests"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var listing: bool = not args.is_empty() and args[0] == "--list"
	if listing:
		args.remove_at(0)
	# path -> the methods asked for; an empty list means all of them
	var chosen: Dictionary = {}
	for arg: String in args:
		var path: String = arg.get_slice("::", 0)
		if not (path.begins_with(TESTS_ROOT + "/") and path.get_file().begins_with("test_") and path.ends_with(".gd")):
			print("FAIL %s: not a test file under %s" % [arg, TESTS_ROOT])
			quit(2)
			return
		if not chosen.has(path):
			chosen[path] = PackedStringArray()
		if arg.contains("::"):
			var methods: PackedStringArray = chosen[path]
			methods.append(arg.get_slice("::", 1))
	var paths: PackedStringArray = PackedStringArray()
	for path: String in chosen:
		paths.append(path)
	if paths.is_empty():
		_discover(TESTS_ROOT, paths)
	paths.sort()
	if listing:
		_list(paths)
		return
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
		var methods: PackedStringArray = _test_methods(script)
		var asked: PackedStringArray = chosen.get(path, PackedStringArray())
		var unknown: bool = false
		for name: String in asked:
			if not methods.has(name):
				print("FAIL %s::%s: no such test method" % [path, name])
				unknown = true
		if unknown:
			quit(2)
			return
		if not asked.is_empty():
			methods = asked
		for method: String in methods:
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


## Prints `test <path>::<method>` for every test method of every file, in source order.
func _list(paths: PackedStringArray) -> void:
	for path: String in paths:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			print("FAIL %s: script did not compile" % path)
			quit(1)
			return
		for method: String in _test_methods(script):
			print("test %s::%s" % [path, method])
	quit(0)


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
