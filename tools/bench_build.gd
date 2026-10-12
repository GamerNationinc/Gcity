## The cost of the build system's support check on the Deck (G6 debt 2):
##   godot --headless --path . -s tools/bench_build.gd
## BuildSystem.supported_set() runs over every piece on each change (M3 assumption).
## Times it, and an idle sim tick for scale, with the M4 building alone and with Cold
## Storage raised too, as the client's world has them. Reports the median and the
## slow tail (99th and 99.9th percentile, the max), never an average (standards §4).
## Desktop numbers are a smoke signal; the Deck's are the ones the gate takes.
extends SceneTree

const RUNS: int = 1000
const TICKS: int = 400
const BUDGET_MS: float = 2.0  # standards §4.1: gameplay + progression + inventory


func _initialize() -> void:
	print("machine: %s, %s" % [OS.get_name(), OS.get_processor_name()])
	print("%-38s %7s %9s %9s %9s %9s" % ["case", "pieces", "p50 ms", "p99 ms", "p99.9 ms", "max ms"])
	var db := ContentDb.new()
	if ContentLoader.load_all(db) != OK:
		push_error("bench_build: content")
		quit(1)
		return
	var sim: SimRoot = SimAssembly.build(20261212, db)
	var sites: SiteSystem = SimAssembly.sites_of(sim)
	if not sites.spawn(&"m4_test_building", Vector3i.ZERO):
		push_error("bench_build: the M4 building did not spawn")
		quit(1)
		return
	_measure(sim, "M4 building")
	if not sites.spawn(&"cold_storage", sites.placement_of(&"cold_storage")):
		push_error("bench_build: Cold Storage did not spawn")
		quit(1)
		return
	_measure(sim, "M4 building + Cold Storage")
	print("budget: a change of support should fit the %.1f ms gameplay line (standards §4.1)" % BUDGET_MS)
	quit(0)


func _measure(sim: SimRoot, name: String) -> void:
	var build: BuildSystem = SimAssembly.build_of(sim)
	var pieces: int = build.piece_ids().size()
	var support: Array[int] = []
	for i: int in RUNS:
		var t0: int = Time.get_ticks_usec()
		build.supported_set()
		support.append(Time.get_ticks_usec() - t0)
	_row("support check (%s)" % name, pieces, support)
	var ticks: Array[int] = []
	for i: int in TICKS:
		var t0: int = Time.get_ticks_usec()
		sim.step()
		ticks.append(Time.get_ticks_usec() - t0)
	_row("idle sim tick (%s)" % name, pieces, ticks)


func _row(name: String, pieces: int, usec: Array[int]) -> void:
	usec.sort()
	var n: int = usec.size()
	print("%-38s %7d %9.2f %9.2f %9.2f %9.2f" % [name.left(38), pieces, usec[n / 2] / 1000.0, usec[mini(n - 1, n * 99 / 100)] / 1000.0,
		usec[mini(n - 1, n * 999 / 1000)] / 1000.0, usec[n - 1] / 1000.0])
