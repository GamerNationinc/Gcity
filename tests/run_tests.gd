## Headless test runner. Usage:
##   godot --headless --path . -s tests/run_tests.gd
## Discovers tests/**/test_*.gd, runs every test_* method on a fresh instance, prints
## one line per test and a summary, and exits 0 only if everything passed. A runtime
## script error inside a test (an invalid call, a bad typed assignment) aborts the test
## body silently, so the runner counts them through a Logger and fails the test that
## raised one; a deliberate push_error is not a script error.
extends SceneTree


## Counts runtime script errors (ERROR_TYPE_SCRIPT), whichever thread reports them.
class ScriptErrorCounter extends Logger:
	var _mutex: Mutex = Mutex.new()
	var _count: int = 0
	var _last: String = ""

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mutex.lock()
		_count += 1
		_last = "%s (%s:%d in %s)" % [rationale if not rationale.is_empty() else code, file, line, function]
		_mutex.unlock()

	func count() -> int:
		_mutex.lock()
		var n: int = _count
		_mutex.unlock()
		return n

	func last() -> String:
		_mutex.lock()
		var text: String = _last
		_mutex.unlock()
		return text

const TESTS_ROOT: String = "res://tests"


var _errors: ScriptErrorCounter


## Quits after unregistering the logger, which would otherwise outlive the run.
func _finish(code: int) -> void:
	if _errors != null:
		OS.remove_logger(_errors)
		_errors = null
	quit(code)


func _initialize() -> void:
	# `-- --only=res://tests/items` limits the run to one directory, and `--fail-fast`
	# stops at the first failure (both for tools/mutate.py, where a mutant is killed by
	# any one failing test)
	var root: String = TESTS_ROOT
	var fail_fast: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			root = arg.trim_prefix("--only=")
		elif arg == "--fail-fast":
			fail_fast = true
	var paths: PackedStringArray = PackedStringArray()
	_discover(root, paths)
	paths.sort()
	var total: int = 0
	var failed: int = 0
	var assertions: int = 0
	_errors = ScriptErrorCounter.new()
	var errors: ScriptErrorCounter = _errors
	OS.add_logger(errors)
	for path: String in paths:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			print("FAIL %s: script did not compile" % path)
			failed += 1
			total += 1
			if fail_fast:
				_finish(1)
				return
			continue
		for method: String in _test_methods(script):
			total += 1
			var probe: Variant = script.new()
			if not (probe is GcityTest):
				print("FAIL %s::%s: test scripts must extend GcityTest" % [path, method])
				failed += 1
				continue
			var test: GcityTest = probe
			var errors_before: int = errors.count()
			test.call(method)
			assertions += test.assertion_count()
			var failures: PackedStringArray = test.failures()
			var raised: int = errors.count() - errors_before
			if raised > 0:
				failures.append("%d runtime script error(s); the last: %s" % [raised, errors.last()])
			if failures.is_empty():
				print("ok   %s::%s" % [path, method])
			else:
				failed += 1
				print("FAIL %s::%s" % [path, method])
				for failure: String in failures:
					print("     - %s" % failure)
				if fail_fast:
					print("stopped at the first failure (--fail-fast)")
					_finish(1)
					return
	print("")
	print("%d tests, %d assertions, %d failed" % [total, assertions, failed])
	if total == 0:
		print("no tests found under %s" % root)
		_finish(2)
		return
	_finish(1 if failed > 0 else 0)


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
