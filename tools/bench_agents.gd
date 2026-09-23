## The agent budget, measured (M4 spec claim 13; standards §4.1, §4.2). Runs the M4
## building headless with its four guards plus two more, a target they can all see
## and never kill (a range dummy in the lobby), and a wall placed and removed every
## REBUILD_EVERY ticks so the portal graph rebuilds; times every sim tick and prints
## the 99th and 99.9th percentiles (the 1 % and 0.1 % lows of a 40 Hz frame) as
## JSON, alongside the same run with no agents (the baseline the agent row is the
## difference from) and the ticks that carried a rebuild (the navigation row).
##   godot --headless --path . -s tools/bench_agents.gd [-- --ticks=12000 --out=tests/out/bench.json]
## Deck numbers are the only numbers that count: run this from the export's
## checkout on the Deck, plugged and on battery.
extends SceneTree

const DEFAULT_TICKS: int = 12_000
const REBUILD_EVERY: int = 400
const EXTRA_GUARDS: Array[Vector3i] = [Vector3i(1, 0, 2), Vector3i(3, 0, 2)]


func _initialize() -> void:
	var ticks: int = DEFAULT_TICKS
	var out_path: String = "res://tests/out/bench.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--ticks="):
			ticks = arg.trim_prefix("--ticks=").to_int()
		elif arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
	var with_agents: Dictionary = _run(ticks, true)
	var baseline: Dictionary = _run(ticks, false)
	var report: Dictionary = {
		"ticks": ticks, "tick_hz": SimRoot.TICK_HZ, "budget_usec_per_frame": 1_000_000 / SimRoot.TICK_HZ,
		"engine": Engine.get_version_info()["string"], "os": OS.get_name(), "cpu": OS.get_processor_name(),
		"agents": with_agents, "no_agents": baseline,
		"agent_row_usec": {
			"p50": with_agents["all"]["p50"] - baseline["all"]["p50"],
			"p99": with_agents["all"]["p99"] - baseline["all"]["p99"],
			"p999": with_agents["all"]["p999"] - baseline["all"]["p999"],
		},
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


func _run(ticks: int, agents: bool) -> Dictionary:
	var db := ContentDb.new()
	var err: Error = ContentLoader.load_all(db)
	assert(err == OK, "content")
	var sim: SimRoot = SimAssembly.build(20261200, db)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var items: ItemSystem = SimAssembly.items_of(sim)
	var owner: int = actors.spawn(&"arcade", 0)
	actors.set_position(owner, Vector3i(-20_000, 0, -20_000))
	var target: int = actors.spawn(&"range_dummy", 0)
	actors.set_position(target, BuildSystem.cell_centre(M4Building.BASE + Vector3i(1, 0, 1)) - Vector3i(0, 500, 0))
	var at: int = sim.get_tick() + 1
	sim.submit(SimCommand.new(at, &"land.identify", {"actor": owner, "owner": "player"}))
	sim.submit(SimCommand.new(at, &"land.transfer", {"parcel": "starter_plot", "owner": "player"}))
	sim.submit(SimCommand.new(at, &"land.transfer", {"parcel": "neighbour_north", "owner": "player"}))
	for c: Dictionary in M4Building.commands(owner, db):
		sim.submit(SimCommand.new(at, &"build.place", c))
	if agents:
		for g: Dictionary in M4Building.guards("guard_sim", db):
			sim.submit(SimCommand.new(at, &"agent.spawn", g))
		for rel: Vector3i in EXTRA_GUARDS:
			var cell: Vector3i = M4Building.BASE + rel
			sim.submit(SimCommand.new(at, &"agent.spawn", {"profile": "guard_sim", "cell": [cell.x, cell.y, cell.z], "facing": 270, "squad": 1, "route": ""}))
	sim.step()
	assert(sim.rejected_count() == 0, "setup applied")
	var guards: Array[int] = SimAssembly.perception_of(sim).agent_ids()
	for g: int in guards:
		_arm(sim, items, g)
	sim.step_n(100)
	var wall_cell: Vector3i = BuildSystem.cell_centre(M4Building.BASE + Vector3i(-3, 0, -3))
	var wall: int = 0
	var build: BuildSystem = SimAssembly.build_of(sim)
	var all: Array[int] = []
	var rebuilds: Array[int] = []
	for i: int in ticks:
		var rebuild: bool = i % REBUILD_EVERY == 0
		if rebuild:
			if wall == 0:
				sim.submit(SimCommand.new(sim.get_tick() + 1, &"build.place", {"actor": owner, "piece": "foundation_block", "x": wall_cell.x, "y": wall_cell.y, "z": wall_cell.z, "facing": ""}))
			else:
				sim.submit(SimCommand.new(sim.get_tick() + 1, &"build.remove", {"actor": owner, "piece_id": wall}))
		var start: int = Time.get_ticks_usec()
		sim.step()
		var spent: int = Time.get_ticks_usec() - start
		all.append(spent)
		if rebuild:
			rebuilds.append(spent)
			wall = build.cell_piece_at(BuildSystem.cell_of(wall_cell))
	var combat: CombatSystem = SimAssembly.combat_of(sim)
	return {
		"guards": guards.size(), "pieces": build.piece_ids().size(), "shots": combat.shots(), "rejected": sim.rejected_count(),
		"all": _stats(all), "rebuild_ticks": _stats(rebuilds),
	}


func _arm(sim: SimRoot, items: ItemSystem, actor: int) -> void:
	var inv: StringName = ItemSystem.inventory_of(actor)
	var pistol: int = items.spawn(&"weapon_frame", &"g19", inv, 1)
	var mag: int = items.spawn(&"weapon_part", &"g19_mag_15", inv, 2)
	for i: int in 15:
		var round: int = items.spawn(&"ammo", &"9x19_fmj", inv, 100 + i)
		sim.submit(SimCommand.new(sim.get_tick() + 1, &"magazine.load", {"actor": actor, "magazine": mag, "round": round}))
	sim.step()
	sim.submit(SimCommand.new(sim.get_tick() + 1, &"actor.wield", {"actor": actor, "weapon": pistol}))
	sim.step()
	sim.submit(SimCommand.new(sim.get_tick() + 1, &"weapon.reload_tactical", {"actor": actor, "weapon": pistol, "magazine": mag}))
	sim.step()
	# the magazine empties in a few seconds of fire; a second loaded one keeps them busy
	var spare: int = items.spawn(&"weapon_part", &"g19_mag_15", inv, 3)
	for i: int in 15:
		var round: int = items.spawn(&"ammo", &"9x19_fmj", inv, 200 + i)
		sim.submit(SimCommand.new(sim.get_tick() + 1, &"magazine.load", {"actor": actor, "magazine": spare, "round": round}))
	sim.step()


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
