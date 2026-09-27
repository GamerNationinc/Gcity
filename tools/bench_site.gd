## The raise cost (M6 spec claim 2; G6 debt 6; G4 debt 7). For every shipped site,
## raises it in a fresh sim RUNS times and times the one tick that carries
## `site.raise`; for comparison, times the tick that carries the M4 building's
## client-side command list (one `build.place` per piece, one rebuild each), the path
## that caused G4's raise hitch. Prints percentiles in microseconds as JSON.
##   godot --headless --path . -s tools/bench_site.gd [-- --runs=50 --out=tests/out/bench_site.json]
## Deck numbers are the only numbers that count: run this from the checkout on the
## Deck, plugged and on battery.
extends SceneTree

const DEFAULT_RUNS: int = 50
const SEED: int = 20261240


func _initialize() -> void:
	var runs: int = DEFAULT_RUNS
	var out_path: String = "res://tests/out/bench_site.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--runs="):
			runs = arg.trim_prefix("--runs=").to_int()
		elif arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
	var db := ContentDb.new()
	var err: Error = ContentLoader.load_all(db)
	assert(err == OK, "content")
	var sites: Dictionary = {}
	for site: StringName in db.ids(SiteSystem.KIND_SITE):
		sites[String(site)] = _raise(db, site, runs)
	var report: Dictionary = {
		"runs": runs, "tick_hz": SimRoot.TICK_HZ, "budget_usec_per_frame": 1_000_000 / SimRoot.TICK_HZ,
		"engine": Engine.get_version_info()["string"], "os": OS.get_name(), "cpu": OS.get_processor_name(),
		"site_raise": sites, "m4_commands": _m4_commands(db, runs),
	}
	var text: String = JSON.stringify(report, "\t")
	var abs_path: String = ProjectSettings.globalize_path(out_path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var file: FileAccess = FileAccess.open(abs_path, FileAccess.WRITE)
	if file != null:
		file.store_string(text + "\n")
		file.close()
	print(text)
	quit(0)


func _raise(db: ContentDb, site: StringName, runs: int) -> Dictionary:
	var samples: Array[int] = []
	var pieces: int = 0
	var rejected: int = 0
	for i: int in runs:
		var sim: SimRoot = SimAssembly.build(SEED, db)
		sim.submit(SimCommand.new(sim.get_tick() + 1, SiteSystem.COMMAND_RAISE, {"site": String(site)}))
		var start: int = Time.get_ticks_usec()
		sim.step()
		samples.append(Time.get_ticks_usec() - start)
		pieces = SimAssembly.build_of(sim).piece_ids().size()
		rejected += sim.rejected_count()
	var out: Dictionary = _stats(samples)
	out["pieces"] = pieces
	out["rejected"] = rejected
	return out


func _m4_commands(db: ContentDb, runs: int) -> Dictionary:
	var samples: Array[int] = []
	var pieces: int = 0
	var rejected: int = 0
	for i: int in runs:
		var sim: SimRoot = SimAssembly.build(SEED, db)
		var owner: int = SimAssembly.actors_of(sim).spawn(&"arcade", 0)
		var at: int = sim.get_tick() + 1
		sim.submit(SimCommand.new(at, &"land.identify", {"actor": owner, "owner": "player"}))
		sim.submit(SimCommand.new(at, &"land.transfer", {"parcel": "starter_plot", "owner": "player"}))
		sim.submit(SimCommand.new(at, &"land.transfer", {"parcel": "neighbour_north", "owner": "player"}))
		sim.step()
		at = sim.get_tick() + 1
		for c: Dictionary in M4Building.commands(owner):
			sim.submit(SimCommand.new(at, &"build.place", c))
		var start: int = Time.get_ticks_usec()
		sim.step()
		samples.append(Time.get_ticks_usec() - start)
		pieces = SimAssembly.build_of(sim).piece_ids().size()
		rejected += sim.rejected_count()
	var out: Dictionary = _stats(samples)
	out["pieces"] = pieces
	out["rejected"] = rejected
	return out


static func _stats(samples: Array[int]) -> Dictionary:
	if samples.is_empty():
		return {"count": 0}
	var sorted: Array[int] = samples.duplicate()
	sorted.sort()
	var total: int = 0
	for v: int in sorted:
		total += v
	return {
		"count": sorted.size(), "mean": total / sorted.size(),
		"p50": sorted[sorted.size() / 2], "p99": sorted[mini(sorted.size() - 1, sorted.size() * 99 / 100)],
		"p999": sorted[mini(sorted.size() - 1, sorted.size() * 999 / 1000)], "max": sorted[sorted.size() - 1],
	}
