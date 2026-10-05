## `--sandbox` (M7.6 spec claim 1): the game's content and the sandbox's, built by
## `SandboxAssembly`. The world view loads this script by path, never by name, so a
## release export that leaves `client/sandbox/` and `sim/sandbox/` out still runs, and
## `--sandbox` there says so instead of failing to parse (decision 1).
class_name SandboxMode extends RefCounted

const CONTENT_ROOT: String = "res://sandbox_content"


## The game's content with the sandbox's added, or null (after an error).
static func content() -> ContentDb:
	var db := ContentDb.new()
	if ContentLoader.load_all(db) != OK:
		return null
	if DirAccess.dir_exists_absolute(CONTENT_ROOT) and ContentLoader.load_all(db, CONTENT_ROOT) != OK:
		return null
	return db


## Hands the host the sandbox's assembly and content. False when the content did not load.
static func install(host: LocalHost) -> bool:
	var db: ContentDb = content()
	if db == null:
		return false
	host.use_assembly(SandboxAssembly.build, db)
	return true


## Where a saved session goes (claim 9).
const FIXTURE_DIR: String = "user://fixtures"
## Where a `--demo` session saves instead, out of the player's fixtures.
const DEMO_FIXTURE_DIR: String = "user://demo_fixtures"


## A session as a replay fixture's text (the existing schema, `assembly` "sandbox"), or ""
## with the reason in `why[0]` when it cannot be one yet: a command still due after the
## current tick would replay into a different inbox than the hash was taken over.
static func fixture_text(sim: SimRoot, commands: Array[Dictionary], name: String, why: Array[String]) -> String:
	# every step the session took, the paused ones too: a replay steps as often
	var ticks: int = sim.get_tick() + sim.paused_steps()
	if ticks < 1:
		why.append("nothing has run yet")
		return ""
	for c: Dictionary in commands:
		var tick: int = c["tick"]
		if tick > sim.get_tick():
			why.append("a command is still due at tick %d: let the clock run (or step it) a moment and save again" % tick)
			return ""
	var fixture: Dictionary = {"schema_version": ReplayFixture.SCHEMA_VERSION, "name": name, "seed": sim.get_seed(), "ticks": ticks,
		"commands": commands, "expected_hash": sim.state_hash(), "assembly": "sandbox"}
	return JSON.stringify(fixture, "\t", true) + "\n"


## The inspector's node, for the world view to add and sync (claim 8).
static func inspector() -> Node3D:
	return SandboxInspector.new()


## The apps only the sandbox has, and their scenes: registered by the world view.
static func views() -> Dictionary:
	return {"sandbox": "res://client/sandbox/sandbox_app.tscn"}


## A request from a sandbox app, turned into sim commands (claim 2). Returns what to tell
## the player: what was sent, or why nothing was (never a silent press).
static func request(view: WorldView, kind: StringName, payload: Dictionary) -> String:
	if kind != SandboxApp.KIND_SPAWN:
		return "the sandbox does not know %s" % kind
	var sim: SimRoot = view.host_sim()
	var cell: Vector3i = view.creator_cursor()
	var spawn: String = payload.get("spawn", "")
	if spawn == "agent":
		var profile: String = payload["profile"]
		var kit: Dictionary = payload["kit"]
		if not SimAssembly.movement_of(sim).body_fits(cell, 2):
			# the 18:18 run: the cursor sat in the foundation just built; say where it would fit
			var up: String = "; one level up fits: R1 raises the cursor" if SimAssembly.movement_of(sim).body_fits(cell + Vector3i(0, 1, 0), 2) else "; move the cursor (D-pad) to open floor"
			return "%s not spawned at %s: no room for a body there (two cells, nothing built in them)%s" % [profile, cell, up]
		view.submit_command(SandboxSystem.COMMAND_SPAWN_AGENT, {"actor": view.player_id(), "profile": profile,
			"cell": [cell.x, cell.y, cell.z], "facing": view.spawn_facing(), "kit": kit})
		return "spawning %s at %s%s" % [profile, cell, ", unarmed" if kit.is_empty() else ", with %s" % kit["frame"]]
	if spawn == "item":
		var template: String = payload["template"]
		var count: int = payload["count"]
		view.submit_command(&"item.spawn", {"kind": payload["kind"], "template": template,
			"container": String(ItemSystem.inventory_of(view.player_id())), "seed": sim.get_tick(), "count": count})
		return "%s x%d into your pockets" % [template, count]
	if spawn == "site":
		var site: String = payload["site"]
		if SimAssembly.sites_of(sim).is_raised(StringName(site)):
			return "%s not raised: it already stands (clear the lot, or restart, to raise it again)" % site
		view.submit_command(SiteSystem.COMMAND_RAISE, {"actor": view.player_id(), "site": site, "at": [cell.x, cell.y, cell.z]})
		return "raising %s with its base at %s" % [site, cell]
	var player: int = view.player_id()
	if spawn == "trainer":
		var effect: String = payload["effect"]
		var on: bool = payload["on"]
		view.submit_command(SandboxSystem.COMMAND_TRAINER, {"actor": player, "effect": effect, "on": on})
		return "%s %s" % [SandboxApp.EFFECT_NAMES[effect], "on" if on else "off"]
	if spawn == "heal":
		var actors: ActorSystem = SimAssembly.actors_of(sim)
		if not actors.is_alive(player):
			return "not healed: you are dead (the death screen brings you back)"
		var health: Dictionary = actors.health_of(player)
		for node: StringName in health:
			view.submit_command(SandboxSystem.COMMAND_SET_HEALTH, {"actor": player, "node": String(node), "value": actors.max_health(player, node)})
		return "full health"
	if spawn == "teleport":
		if not SimAssembly.movement_of(sim).actor_fits(player, cell):
			return "not teleported to %s: your body does not fit there" % cell
		view.submit_command(SandboxSystem.COMMAND_TELEPORT, {"actor": player, "cell": [cell.x, cell.y, cell.z]})
		return "teleported to %s" % cell
	if spawn == "ai":
		var held: String = payload["effect"]
		var hold: bool = payload["on"]
		var changes: int = 0
		for agent: int in SimAssembly.perception_of(sim).agent_ids():
			if SimAssembly.actors_of(sim).is_alive(agent) and SandboxAssembly.sandbox_of(sim).trainer_on(agent, held) != hold:
				changes += 1
		if changes == 0:
			return "nothing to change: every guard is already %s%s" % ["" if hold else "not ", held]
		view.submit_command(SandboxSystem.COMMAND_AI, {"actor": player, "agent": "all", "effect": held, "on": hold})
		return "every guard %s%s" % ["" if hold else "no longer ", held]
	if spawn == "time":
		var host: LocalHost = view.host()
		var step: bool = payload["step"]
		if step:
			if not host.step_once():
				return "not stepped: hold the clock first"
			return "stepped to tick %d" % host.sim().get_tick()
		var num: int = payload["num"]
		var den: int = payload["den"]
		host.set_rate(num, den)
		return "time %s" % host.rate_label()
	if spawn == "inspect":
		var inspector: Node3D = view.inspector()
		var overlay: String = payload["overlay"]
		if overlay == "all" or overlay == "none":
			inspector.call(&"set_all", overlay == "all")
			return "every overlay %s" % ("on" if overlay == "all" else "off")
		var known: bool = inspector.call(&"toggle", overlay)
		if not known:
			return "no overlay called %s" % overlay
		var on: bool = inspector.call(&"is_on", overlay)
		return "%s %s" % [SandboxInspector.NAMES[overlay], "on" if on else "off"]
	if spawn == "record":
		var now: Dictionary = Time.get_datetime_dict_from_system()
		var name: String = "sandbox-%04d%02d%02d-%02d%02d%02d" % [now["year"], now["month"], now["day"], now["hour"], now["minute"], now["second"]]
		var why: Array[String] = []
		var text: String = fixture_text(sim, view.session(), name, why)
		if text.is_empty():
			return "not saved: %s" % why[0]
		var path: String = write_fixture(text, name, DEMO_FIXTURE_DIR if view.is_demo() else FIXTURE_DIR)
		if path.is_empty():
			return "not saved: could not write %s" % FIXTURE_DIR
		return "saved %s: %d ticks, %d commands" % [path, sim.get_tick(), view.session().size()]
	return "the spawn menu sent something it cannot spawn"


## Writes a fixture's text to `<dir>/<name>.json`. The path, or "" after an error.
static func write_fixture(text: String, name: String, dir: String = FIXTURE_DIR) -> String:
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return ""
	var path: String = dir.path_join(name + ".json")
	var handle: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if handle == null:
		return ""
	handle.store_string(text)
	handle.close()
	return path
