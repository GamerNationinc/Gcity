## Runs one test file, for tooling that cannot afford the whole suite.
##   godot --headless --path . -s tools/run_test_file.gd -- res://tests/.../test_x.gd
## Prints a line per test and exits non-zero if any failed. `tools/mutate.py` uses this
## to kill a mutant with the tests that cover it rather than the twenty-minute suite.
extends SceneTree


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: -s tools/run_test_file.gd -- res://tests/.../test_x.gd")
		quit(2)
		return
	var failed: int = 0
	var total: int = 0
	for path: String in args:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			print("FAIL %s: did not compile" % path)
			quit(1)
			return
		for method: Dictionary in script.get_script_method_list():
			var name_s: String = method["name"]
			if not name_s.begins_with("test_"):
				continue
			total += 1
			var probe: Variant = script.new()
			if not (probe is GcityTest):
				print("FAIL %s::%s: not a GcityTest" % [path, name_s])
				failed += 1
				continue
			var test: GcityTest = probe
			test.call(name_s)
			var failures: PackedStringArray = test.failures()
			if failures.is_empty():
				print("ok   %s::%s" % [path, name_s])
			else:
				failed += 1
				print("FAIL %s::%s" % [path, name_s])
				for failure: String in failures:
					print("     - %s" % failure)
	print("%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)
