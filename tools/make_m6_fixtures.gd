## Writes the M6 replay fixtures (spec claim 15) into tests/replay/: the mission played
## four ways, as command logs, replayed headless against the assembled sim. The site is
## raised by its operator, not by the player, so every fixture is a break-in rather than
## a tour of the player's own building.
##   godot --headless --path . -s tools/make_m6_fixtures.gd
## Then `tools/test.sh replay` prints each hash to paste into "expected_hash".
extends SceneTree

const OUT_DIR: String = "res://tests/replay"
const M: int = 1000
const SEED: int = 20261230
const SITE: StringName = &"cold_storage"
## The street step onto the slab, on public ground south of the lot.
const STEP: Vector3i = Vector3i(4, 1, -5)
## Where the player turns up: `actor.spawn` places on the x axis at z 0, and the site
## is 36 m north of it, so every run begins with the walk in.
const SPAWN_RANGE_M: int = 44
## How long a fight waits after the last shooter goes quiet before moving on.
const QUIET_TICKS: int = 120
## The middle of content/parcel/fixers_office.json.
const FIXER: Vector3i = Vector3i(6000, 0, 30000)

var _sim: SimRoot
var _commands: Array = []
var _player: int = 0
var _operator: int = 0
var _tick: int = 0
var _actors: ActorSystem
var _items: ItemSystem
var _sites: SiteSystem
var _terminals: TerminalSystem
var _score: RunScoreSystem
var _movement: MovementSystem
var _quests: QuestSystem
var _corpses: CorpseSystem
var _standing: StandingSystem


## Set by `--debug` on the command line: prints who first saw the player and where.
var _debug: bool = false


func _initialize() -> void:
	_debug = OS.get_cmdline_user_args().has("--debug")
	_stealth()
	_loud()
	_death()
	_side()
	quit(0)


# ---------------------------------------------------------------- the four runs

## The under route, clean: cut the street grate, go under the building, come up in the
## back hall, hack the server, wipe it, put the grate back on the way out, and hand the
## job in. All four counters zero, the clean bonus paid.
func _stealth() -> void:
	_begin(false)
	_watch_alerts()
	_command(&"run.begin", {"actor": _player})
	_command(&"quest.accept", {"actor": _player, "quest": "cold_storage"})
	_walk_to(Vector3i(4, 1, -2))
	var grate: int = _piece_at(Vector3i(4, 1, -2), "ny")
	_command(&"build.remove", {"actor": _player, "piece_id": grate})
	_climb(-1)
	for i: int in 10:
		_walk_to(Vector3i(4, 0, -1 + i))
	# the tunnel's head is under the back hall: wait there until the roamer has gone
	# down to the lobby, then cross to the server room before it comes back
	if not _wait_until_hall_is_clear(4, 900):
		push_error("the hall never cleared on the way in")
	_climb(1)
	_walk_to(Vector3i(3, 1, 8))
	_walk_to(Vector3i(2, 1, 8))
	_walk_to(Vector3i(2, 1, 9))
	# hack from the corner of the server room rather than the middle: the terminal is
	# within reach either way, and the doorway's sight line runs up the x = 2 column
	_walk_to(Vector3i(1, 1, 10))
	var terminal: int = _sites.terminals_of(SITE)[0]
	if _debug:
		print("    at the terminal: player cell %s, hacking from %s" % [
			BuildSystem.cell_of(_actors.position_of(_player)), _actors.position_of(_player)])
	_command(&"terminal.hack_start", {"actor": _player, "terminal": terminal})
	_wait(_terminals.hack_ticks_of(terminal) + 2)
	if _debug:
		print("    hack done at tick %d, progress %d, detected %d" % [
			_sim.get_tick(), _terminals.progress_of(terminal), _score.times_detected(_player)])
	_command(&"terminal.wipe", {"actor": _player, "terminal": terminal})
	# back out the way I came, and close the hole behind me
	# The wait happens in the corner, not in the doorway: the doorway is the one cell
	# the hall can see into, so standing in it to wait is how the last run was caught.
	if not _wait_until_hall_is_clear(4, 900):
		push_error("the hall never cleared on the way out")
	_walk_to(Vector3i(2, 1, 9))
	_walk_to(Vector3i(2, 1, 8))
	_walk_to(Vector3i(3, 1, 8))
	_walk_to(Vector3i(4, 1, 8))
	_climb(-1)
	for i: int in 10:
		_walk_to(Vector3i(4, 0, 7 - i))
	_climb(1)
	var centre: Vector3i = BuildSystem.cell_centre(_sites.cell_of(SITE, Vector3i(4, 1, -2)))
	_command(&"build.place", {"actor": _player, "piece": "floor_panel", "x": centre.x, "y": centre.y, "z": centre.z, "facing": "ny"})
	_walk_to(Vector3i(4, 1, -4))
	_command(&"run.end", {"actor": _player})
	_walk_to_the_fixer()
	_command(&"quest.turn_in", {"actor": _player, "quest": "cold_storage"})
	_alive_or_shout("m6-stealth")
	_report("m6-stealth")
	_write("m6-stealth")


## The front route without a token: the door is a wall, so the lobby's window goes in,
## the guards come, one of them goes down, and the data is taken anyway. A reduced
## payout and heat raised.
func _loud() -> void:
	_begin(true)
	_command(&"run.begin", {"actor": _player})
	_command(&"quest.accept", {"actor": _player, "quest": "cold_storage"})
	_walk_to(Vector3i(2, 1, -1))
	# no token: the door will not open, so the wall beside it does
	var panel: int = _piece_at(Vector3i(1, 1, 0), "nz")
	_command(&"build.remove", {"actor": _player, "piece_id": panel})
	# stay out in the street and fight through the hole: four armed guards in an open
	# lobby is a losing hand, and a breach is a door only one of them fits through
	# fight from the open street, three cells back: they have to come out through the
	# hole one at a time and cross ground with nothing on it. Standing in the doorway
	# means meeting all four at once, which is how the player died the last time this
	# was authored.
	_walk_to(Vector3i(1, 1, -3))
	_fight(1800)
	_walk_to(Vector3i(1, 1, -1))
	_fight(1800)
	_walk_to(Vector3i(1, 1, 1))
	_fight(1800)
	_walk_to(Vector3i(2, 1, 2))
	_fight(1200)
	_walk_to(Vector3i(2, 1, 7))
	_fight(1200)
	_walk_to(Vector3i(2, 1, 8))
	_walk_to(Vector3i(2, 1, 9))
	_walk_to(Vector3i(2, 1, 10))
	var terminal: int = _sites.terminals_of(SITE)[0]
	_command(&"terminal.hack_start", {"actor": _player, "terminal": terminal})
	_wait(_terminals.hack_ticks_of(terminal) + 2)
	_walk_to(Vector3i(2, 1, 9))
	_walk_to(Vector3i(2, 1, 8))
	_walk_to(Vector3i(2, 1, 1))
	_walk_to(Vector3i(1, 1, 1))
	# out through the hole, because the door still wants a token nobody has
	_walk_to(Vector3i(1, 1, 0))
	_walk_to(Vector3i(1, 1, -4))
	_command(&"run.end", {"actor": _player})
	_walk_to_the_fixer()
	_command(&"quest.turn_in", {"actor": _player, "quest": "cold_storage"})
	_alive_or_shout("m6-loud")
	_report("m6-loud")
	_write("m6-loud")


## Killed mid-hack: the corpse holds the kit, the recovery run gets it back.
func _death() -> void:
	_begin(true)
	_command(&"run.begin", {"actor": _player})
	_walk_to(Vector3i(4, 1, -2))
	var grate: int = _piece_at(Vector3i(4, 1, -2), "ny")
	_command(&"build.remove", {"actor": _player, "piece_id": grate})
	_climb(-1)
	for i: int in 10:
		_walk_to(Vector3i(4, 0, -1 + i))
	_climb(1)
	_walk_to(Vector3i(3, 1, 8))
	_walk_to(Vector3i(2, 1, 8))
	_walk_to(Vector3i(2, 1, 9))
	var terminal: int = _sites.terminals_of(SITE)[0]
	_command(&"terminal.hack_start", {"actor": _player, "terminal": terminal})
	_wait(40)
	# the guards find me at it
	_kill_the_player()
	var corpse: int = _corpses.corpse_of(_player)
	var on_the_body: int = _corpses.items_on(corpse).size()
	_command(&"actor.respawn", {"actor": _player})
	_wait(5)
	# the recovery run: back across town and in again. Not by the tunnel: the grate is
	# still cut, and a hole in the floor is not something you can stand on to climb
	# down. The fire stair and the maintenance window are still open to anyone.
	_walk_to_world(BuildSystem.cell_centre(_sites.cell_of(SITE, Vector3i(4, 0, -5))))
	_climb(1)
	_walk_to(Vector3i(4, 1, -4))
	_walk_to(Vector3i(5, 1, -4))
	_walk_to(Vector3i(5, 1, 7))
	_climb(1)
	_walk_to(Vector3i(4, 2, 7))
	_walk_to(Vector3i(2, 2, 7))
	_walk_to(Vector3i(2, 2, 4))
	_climb(-1)
	_walk_to(Vector3i(2, 1, 7))
	_walk_to(Vector3i(2, 1, 8))
	_walk_to(Vector3i(2, 1, 9))
	_command(&"corpse.loot", {"actor": _player, "corpse": corpse})
	print("    death: corpse %d held %d items, %d left on it, %d back in the pocket, alive %s" % [
		corpse, on_the_body, _corpses.items_on(corpse).size(),
		_items.items_in(ItemSystem.inventory_of(_player)).size(), _actors.is_alive(_player)])
	_report("m6-death")
	_write("m6-death")


## The side route: the fire stair outside the east wall to the maintenance window,
## proving claim 1's vertical movement in a replay.
func _side() -> void:
	_begin(false)
	_command(&"run.begin", {"actor": _player})
	_walk_to(Vector3i(5, 1, 4))
	_walk_to(Vector3i(5, 1, 7))
	_climb(1)
	_walk_to(Vector3i(4, 2, 7))
	_walk_to(Vector3i(2, 2, 7))
	_walk_to(Vector3i(2, 2, 4))
	_climb(-1)
	_walk_to(Vector3i(2, 1, 7))
	_command(&"run.end", {"actor": _player})
	_report("m6-side")
	_write("m6-side")


# ---------------------------------------------------------------- the setup

## The operator raises its own building, then the player turns up on the street with a
## handset and a daemon coprocessor, owning nothing.
func _begin(armed: bool) -> void:
	_commands = []
	_tick = 0
	var db := ContentDb.new()
	var err: Error = ContentLoader.load_all(db)
	assert(err == OK, "content")
	_sim = SimAssembly.build(SEED, db)
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_sites = SimAssembly.sites_of(_sim)
	_terminals = SimAssembly.terminals_of(_sim)
	_score = SimAssembly.score_of(_sim)
	_movement = SimAssembly.movement_of(_sim)
	_quests = SimAssembly.quests_of(_sim)
	_corpses = SimAssembly.corpses_of(_sim)
	_standing = SimAssembly.standing_of(_sim)
	_command(&"actor.spawn", {"profile": "arcade", "range_m": 0})
	_operator = _actors.actor_ids()[0]
	_command(&"land.identify", {"actor": _operator, "owner": "corp.coldchain"})
	_command(&"site.raise", {"actor": _operator, "site": String(SITE)})
	_command(&"actor.spawn", {"profile": "arcade", "range_m": SPAWN_RANGE_M})
	for id: int in _actors.actor_ids():
		if id != _operator and _actors.range_of(id) == SPAWN_RANGE_M:
			_player = id
	var inv: String = String(ItemSystem.inventory_of(_player))
	_command(&"item.spawn", {"kind": "device_frame", "template": "handset", "container": inv, "seed": 1, "count": 1})
	_command(&"item.spawn", {"kind": "device_module", "template": "daemon_coprocessor", "container": inv, "seed": 2, "count": 1})

	var handset: int = _find(ItemSystem.inventory_of(_player), ItemSystem.KIND_DEVICE_FRAME)
	var module: int = _find(ItemSystem.inventory_of(_player), ItemSystem.KIND_DEVICE_MODULE)
	_command(&"actor.equip_device", {"actor": _player, "device": handset})
	_command(&"item.attach", {"actor": _player, "weapon": handset, "part": module})
	if armed:
		_arm(_player, 300)
		# four spares, because four armed guards is more than one magazine of work
		_command(&"item.spawn", {"kind": "weapon_part", "template": "g19_mag_15", "container": inv, "seed": 400, "count": 4})
		_command(&"item.spawn", {"kind": "ammo", "template": "9x19_fmj", "container": inv, "seed": 410, "count": 60})
		_load_every_loose_magazine()
		_wait(95)
	# in off the street and up the step onto the slab. The landing is one cell wide, so
	# the first move after the climb has to be north onto the slab itself: step off it
	# sideways and there is nothing under you.
	_walk_to_world(BuildSystem.cell_centre(_sites.cell_of(SITE, Vector3i(4, 0, -5))))
	_climb(1)
	_walk_to(Vector3i(4, 1, -4))


# ---------------------------------------------------------------- driving

func _centre(rel: Vector3i) -> Vector3i:
	var cell: Vector3i = _sites.cell_of(SITE, rel)
	var centre: Vector3i = BuildSystem.cell_centre(cell)
	return Vector3i(centre.x, rel.y * M, centre.z)


func _piece_at(rel: Vector3i, facing: String) -> int:
	var build: BuildSystem = SimAssembly.build_of(_sim)
	return build.face_piece_at(BuildSystem.face_key(_sites.cell_of(SITE, rel), facing))


## One command on the next tick, then one step, so the log reads as it was played.
func _command(kind: StringName, payload: Dictionary) -> void:
	_tick = _sim.get_tick() + 1
	_commands.append({"tick": _tick, "kind": String(kind), "payload": payload})
	var err: Error = _sim.submit(SimCommand.new(_tick, kind, payload))
	assert(err == OK, "submit %s for tick %d" % [kind, _tick])
	_sim.step()


func _wait(ticks: int) -> void:
	for i: int in ticks:
		_sim.step()


## Walks to the middle of a cell, one axis at a time, at the actor's own pace. Gives up
## after a budget and says so: a route that cannot be walked is a fixture bug, and it
## should be loud rather than silently producing a shorter run.
func _walk_to(rel: Vector3i, budget: int = 200) -> void:
	_walk_to_world(_centre(rel), budget)


## Walks to a world position, finishing one axis before starting the other. A move is
## stepped axis by axis and refused outright if either half is blocked, so a diagonal
## along a wall goes nowhere at all: corridors are walked, not cut across.
func _walk_to_world(target: Vector3i, budget: int = 600) -> void:
	var speed: int = _movement.speed_of(_player)
	var stalled: int = 0
	for i: int in budget:
		var here: Vector3i = _actors.position_of(_player)
		var dx: int = clampi(target.x - here.x, -speed, speed)
		var dz: int = clampi(target.z - here.z, -speed, speed)
		if dx == 0 and dz == 0:
			return
		if dx != 0:
			dz = 0
		_command(&"actor.move", {"actor": _player, "dx": dx, "dz": dz, "dy": 0})
		if _actors.position_of(_player) == here:
			stalled += 1
			if stalled > 3:
				push_error("walking to %s stalled at %s" % [target, here])
				return
		else:
			stalled = 0
	push_error("could not walk to %s, stuck at %s" % [target, _actors.position_of(_player)])


## Steps until every living guard on the ground floor is south of `rel_z`, which is
## how a stealth run is authored: the back hall is crossed while the roamer is down in
## the lobby, not hopefully. Returns false if patience runs out.
func _wait_until_hall_is_clear(rel_z: int, patience: int) -> bool:
	var floor_y: int = _sites.cell_of(SITE, Vector3i(0, 1, 0)).y
	var line: int = _sites.cell_of(SITE, Vector3i(0, 0, rel_z)).z
	for i: int in patience:
		var clear: bool = true
		for id: int in _actors.actor_ids():
			if id == _player or id == _operator or not _actors.is_alive(id):
				continue
			var cell: Vector3i = BuildSystem.cell_of(_actors.position_of(id))
			if cell.y == floor_y and cell.z >= line:
				clear = false
				break
		if clear:
			return true
		_wait(1)
	return false


## Steps until no living guard has the player as an alerted contact and none is within
## `metres`, or the patience runs out.
func _wait_until_clear(metres: int, patience: int) -> bool:
	var perception: PerceptionSystem = SimAssembly.perception_of(_sim)
	for i: int in patience:
		var clear: bool = true
		for id: int in _actors.actor_ids():
			if id == _player or id == _operator or not _actors.is_alive(id):
				continue
			if perception.is_alerted(id, _player):
				clear = false
				break
			if ActorSystem.metres_between(_actors.position_of(id), _actors.position_of(_player)) <= metres:
				clear = false
				break
		if clear:
			return true
		_wait(1)
	return false


## A level change, which is refused rather than fudged if there is nothing to climb.
## A fixture that silently failed to go upstairs would still replay; it just would not
## be the run its name claims.
func _climb(dy: int) -> void:
	var before: Vector3i = _actors.position_of(_player)
	_command(&"actor.move", {"actor": _player, "dx": 0, "dz": 0, "dy": dy})
	var after: Vector3i = _actors.position_of(_player)
	if after.y == before.y:
		push_error("could not climb %d from %s (cell %s)" % [dy, before, BuildSystem.cell_of(before)])


## Shoots back for a budget of ticks: fires at whoever has seen the player, reloads
## from a spare magazine when the weapon runs dry, and waits a few beats after the last
## of them goes quiet in case another is still on its way. A loud run is a fight.
func _fight(budget: int) -> void:
	var perception: PerceptionSystem = SimAssembly.perception_of(_sim)
	var pistol: int = _actors.wielded(_player)
	var quiet: int = 0
	for i: int in budget:
		if not _actors.is_alive(_player):
			return
		var target: int = 0
		for id: int in _actors.actor_ids():
			if id == _player or id == _operator or not _actors.is_alive(id):
				continue
			if perception.is_alerted(id, _player):
				target = id
				break
		if target == 0:
			quiet += 1
			if quiet > QUIET_TICKS:
				return
			_wait(1)
			continue
		quiet = 0
		if _items.chambered(pistol) == EntityIds.NONE:
			var spare: int = _full_magazine()
			if spare == EntityIds.NONE:
				return
			_command(&"weapon.reload_emergency", {"actor": _player, "weapon": pistol, "magazine": spare})
			_wait(60)
			continue
		_command(&"weapon.fire", {"actor": _player, "target": target})


## A loose magazine of the player's with rounds still in it.
func _full_magazine() -> int:
	for id: int in _items.items_in(ItemSystem.inventory_of(_player)):
		if _items.item_kind(id) == ItemSystem.KIND_PART and not _items.rounds_in(id).is_empty():
			return id
	return EntityIds.NONE


## Stands still under fire until the guards finish the job.
func _kill_the_player() -> void:
	for i: int in 1500:
		if not _actors.is_alive(_player):
			return
		_wait(1)
	push_error("the guards never killed the player")


## Down off the slab and across town to the fixer. Every step is a command, because a
## fixture that moved an actor any other way would not replay as the run it claims.
func _walk_to_the_fixer() -> void:
	_walk_to(Vector3i(4, 1, -4))
	_walk_to(STEP)
	_climb(-1)
	_walk_to_world(FIXER)


# ---------------------------------------------------------------- writing

## Fills every loose magazine the player has from their loose rounds.
func _load_every_loose_magazine() -> void:
	for mag: int in _items.items_in(ItemSystem.inventory_of(_player)):
		if _items.item_kind(mag) != ItemSystem.KIND_PART:
			continue
		for round: int in _items.items_in(ItemSystem.inventory_of(_player)):
			if _items.item_kind(round) != ItemSystem.KIND_AMMO:
				continue
			if _items.rounds_in(mag).size() >= 15:
				break
			_command(&"magazine.load", {"actor": _player, "magazine": mag, "round": round})


## One actor, one pistol, fifteen rounds in the magazine, wielded and loaded.
func _arm(actor: int, seed: int) -> void:
	var inv: String = String(ItemSystem.inventory_of(actor))
	_command(&"item.spawn", {"kind": "weapon_frame", "template": "g19", "container": inv, "seed": seed, "count": 1})
	_command(&"item.spawn", {"kind": "weapon_part", "template": "g19_mag_15", "container": inv, "seed": seed + 1, "count": 1})
	_command(&"item.spawn", {"kind": "ammo", "template": "9x19_fmj", "container": inv, "seed": seed + 10, "count": 15})
	var pistol: int = _find(ItemSystem.inventory_of(actor), ItemSystem.KIND_FRAME)
	var mag: int = _find(ItemSystem.inventory_of(actor), ItemSystem.KIND_PART)
	for round: int in _items.items_in(ItemSystem.inventory_of(actor)):
		if _items.item_kind(round) == ItemSystem.KIND_AMMO and _items.rounds_in(mag).size() < 15:
			_command(&"magazine.load", {"actor": actor, "magazine": mag, "round": round})
	_command(&"actor.wield", {"actor": actor, "weapon": pistol})
	_command(&"weapon.reload_tactical", {"actor": actor, "weapon": pistol, "magazine": mag})


func _find(container: StringName, kind: StringName) -> int:
	for id: int in _items.items_in(container):
		if _items.item_kind(id) == kind:
			return id
	return EntityIds.NONE


## Prints the first handful of sightings: tick, who saw, from where, and where the
## player was standing. Authoring a stealth route without this is guesswork.
func _watch_alerts() -> void:
	if not _debug:
		return
	var seen: Array[int] = [0]
	var actors: ActorSystem = _actors
	var sim: SimRoot = _sim
	var player: int = _player
	SimAssembly.combat_of(_sim).events().subscribe(PerceptionSystem.EVENT_ALERTED, func(payload: Dictionary) -> void:
		var contact: int = payload["contact"]
		if contact != player or seen[0] >= 8:
			return
		seen[0] += 1
		var observer: int = payload["observer"]
		print("    alert %d: tick %d, agent %d at cell %s saw the player at cell %s" % [
			seen[0], sim.get_tick(), observer,
			BuildSystem.cell_of(actors.position_of(observer)), BuildSystem.cell_of(actors.position_of(player))]))


## A run that was supposed to be survived and was not writes a fixture in which the
## player lies where they fell and every later step quietly does nothing. Say so.
func _alive_or_shout(name: String) -> void:
	if not _actors.is_alive(_player):
		push_error("%s: the player died; the rest of this fixture is a corpse not moving" % name)


func _report(name: String) -> void:
	var counters: Array[int] = _score.counters(_player)
	print("%s: detected %d, alarms %d, bodies %d, traces %d; multiplier %d; heat %d; quest %s; credits %d" % [
		name, counters[0], counters[1], counters[2], counters[3],
		_score.multiplier(_player, &"fixer_standard"), _standing.heat_of(_player),
		_quests.status_of(_player, SITE), _items.credits_in(ItemSystem.inventory_of(_player))])


func _write(name: String) -> void:
	var ticks: int = _sim.get_tick() + 5
	var fixture: Dictionary = {"schema_version": 1, "name": name, "seed": SEED, "ticks": ticks, "commands": _commands, "expected_hash": ""}
	var file: FileAccess = FileAccess.open("%s/%s.json" % [OUT_DIR, name], FileAccess.WRITE)
	assert(file != null, "open %s" % name)
	file.store_string(JSON.stringify(fixture, "\t") + "\n")
	file.close()
	print("wrote %s: %d commands, %d ticks" % [name, _commands.size(), ticks])
