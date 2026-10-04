## `--sandbox` (M7.6 spec claim 1): the game's content and the sandbox's, built by
## `SandboxAssembly`. The world view loads this script by path, never by name, so a
## release export that leaves `client/sandbox/` and `sim/sandbox/` out still runs, and
## `--sandbox` there says so instead of failing to parse (decision 1).
extends RefCounted

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
			return "%s not spawned at %s: no room for a body there (two cells, nothing built in them)" % [profile, cell]
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
	return "the spawn menu sent something it cannot spawn"
