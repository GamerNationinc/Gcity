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
## Where the player turns up: `actor.spawn` places on the x axis at z 0, in the city just
## east of the gate. The site is out in the wilds where the contract bound it (M7 claim
## 10), so every run begins with the walk to the gate and down the road.
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
	print("    turn in from %s, parcel %s, quest %s, progress %s" % [_actors.position_of(_player), SimAssembly.land_of(_sim).parcel_at(_actors.position_of(_player)), _quests.status_of(_player, &"cold_storage"), _quests.progress_of(_player, &"cold_storage")])
	_command(&"quest.turn_in", {"actor": _player, "quest": "cold_storage"})
	_alive_or_shout("m6-stealth")
	_report("m6-stealth")
	_write("m6-stealth")


## The front route without a token: the door is a wall, so the lobby's window goes in,
## the guards come, one of them goes down, and the data is taken anyway. A reduced
## payout and heat raised.
func _loud() -> void:
	_begin(true)
	_watch_alerts()
	if _debug:
		var combat: CombatSystem = SimAssembly.combat_of(_sim)
		var actors: ActorSystem = _actors
		var player: int = _player
		combat.events().subscribe(ActorSystem.EVENT_DIED, func(payload: Dictionary) -> void:
			var who: int = payload["actor"]
			if who != player:
				return
			var last: Dictionary = combat.last_shot()
			var shooter: int = last["shooter"]
			print("    the player died at %s, shot by %d at %s" % [BuildSystem.cell_of(actors.position_of(player)), shooter, BuildSystem.cell_of(actors.position_of(shooter))]))
	_command(&"run.begin", {"actor": _player})
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
	_walk_to(Vector3i(1, 1, -3))
	# M7 claim 10: the way home is round the building to the road now, not straight down
	# the street, so whoever is still after the player is dealt with first, from the spot
	# three cells back from the hole where they come through it one at a time
	for k: int in 8:
		_fight(1800)
		var after: bool = _anyone_after_the_player()
		var clear: bool = not after and _wait_until_clear(45, 2000)
		if _debug:
			print("    loud exit round %d at tick %d: alive %s, anyone after %s, clear %s" % [k, _sim.get_tick(), _actors.is_alive(_player), after, clear])
		if clear:
			break
	_walk_to(Vector3i(1, 1, -4))
	_command(&"run.end", {"actor": _player})
	_walk_to_the_fixer()
	print("    turn in from %s, parcel %s, quest %s, progress %s" % [_actors.position_of(_player), SimAssembly.land_of(_sim).parcel_at(_actors.position_of(_player)), _quests.status_of(_player, &"cold_storage"), _quests.progress_of(_player, &"cold_storage")])
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
	# the recovery run: back out of the city and in again. Not by the tunnel: the grate
	# is still cut, and a hole in the floor is not something you can stand on to climb
	# down. The fire stair and the maintenance window are still open to anyone.
	_travel_out()
	_walk_to_world(_street())
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
	_watch_alerts()
	_command(&"run.begin", {"actor": _player})
	_walk_to(Vector3i(5, 1, 4))
	_walk_to(Vector3i(5, 1, 7))
	# M7 claim 10: the trip out means arriving whenever the road gets you there, not at
	# the moment the upper patrol happened to be away. Two guards walk that floor in
	# opposite directions and the way across takes a hundred ticks, so the moment is
	# found by trying: the rest of the route is played from a saved state after each
	# candidate wait, and the first that nobody sees is the one this fixture records.
	var wait: int = _first_unseen_wait(_side_inside, 3000, 20)
	if wait < 0:
		push_error("no moment found to take the side route unseen")
		wait = 0
	_wait(wait)
	_side_inside()
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
	_command(&"actor.spawn", {"profile": "arcade", "range_m": SPAWN_RANGE_M})
	for id: int in _actors.actor_ids():
		if id != _operator and _actors.range_of(id) == SPAWN_RANGE_M:
			_player = id
	# M7 claim 10: the contract is taken first, which binds its place out in the wilds,
	# and the operator raises its building there
	_command(&"quest.accept", {"actor": _player, "quest": "cold_storage"})
	_command(&"site.raise", {"actor": _operator, "site": String(SITE), "quest": "cold_storage"})
	var inv: String = String(ItemSystem.inventory_of(_player))
	_command(&"item.spawn", {"kind": "device_frame", "template": "handset", "container": inv, "seed": 1, "count": 1})
	_command(&"item.spawn", {"kind": "device_module", "template": "daemon_coprocessor", "container": inv, "seed": 2, "count": 1})

	var handset: int = _find(ItemSystem.inventory_of(_player), ItemSystem.KIND_DEVICE_FRAME)
	var module: int = _find(ItemSystem.inventory_of(_player), ItemSystem.KIND_DEVICE_MODULE)
	_command(&"actor.equip_device", {"actor": _player, "device": handset})
	_command(&"item.attach", {"actor": _player, "weapon": handset, "part": module})
	if armed:
		_arm(_player, 300)
		# eight spares: four armed guards is more than one magazine of work, and since the
		# building moved out of town (M7 claim 10) the fight lasts until the walk home is
		# safe rather than until the street is quiet
		_command(&"item.spawn", {"kind": "weapon_part", "template": "g19_mag_15", "container": inv, "seed": 400, "count": 8})
		_command(&"item.spawn", {"kind": "ammo", "template": "9x19_fmj", "container": inv, "seed": 410, "count": 120})
		_load_every_loose_magazine()
		_wait(95)
	# out through the gate and down the road to wherever the contract put the building
	_travel_out()
	# in off the street and up the step onto the slab. The landing is one cell wide, so
	# the first move after the climb has to be north onto the slab itself: step off it
	# sideways and there is nothing under you.
	_walk_to_world(_street())
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
				var regions: Regions = SimAssembly.regions_of(_sim)
				var build: BuildSystem = SimAssembly.build_of(_sim)
				var next: Vector3i = BuildSystem.cell_of(here + Vector3i(signi(dx) * speed, 0, signi(dz) * speed))
				push_error("walking to %s stalled at %s (alive %s); next cell %s solid %s piece %s ground below %s parcel %s" % [target, here, _actors.is_alive(_player), next,
					regions.is_solid(next), build.cell_piece_at(next), regions.is_solid(next - Vector3i(0, 1, 0)),
					SimAssembly.land_of(_sim).parcel_at(BuildSystem.cell_centre(next))])
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


## True while any living guard has the player as an alerted contact.
func _anyone_after_the_player() -> bool:
	var perception: PerceptionSystem = SimAssembly.perception_of(_sim)
	for id: int in _actors.actor_ids():
		if id != _player and id != _operator and _actors.is_alive(id) and perception.is_alerted(id, _player):
			return true
	return false


## The side route from the foot of the fire stair: up, in at the maintenance window,
## across the upper floor and down the inside flight.
func _side_inside() -> void:
	_climb(1)
	_walk_to(Vector3i(4, 2, 7))
	_walk_to(Vector3i(2, 2, 7))
	_walk_to(Vector3i(2, 2, 4))
	_climb(-1)
	_walk_to(Vector3i(2, 1, 7))


## The shortest wait, in steps of `step` up to `most`, after which `route` is played
## without anyone seeing the player and with the player still standing; -1 if none. Each
## try is played from a saved state and undone, commands and all, so nothing it did is
## in the fixture.
func _first_unseen_wait(route: Callable, most: int, step: int) -> int:
	var saved: Dictionary = _sim.snapshot()
	var kept: int = _commands.size()
	var seen_before: int = _score.counters(_player)[0]
	var db: ContentDb = SimAssembly.content_of(_sim)
	for wait: int in range(0, most + 1, step):
		_wait(wait)
		route.call()
		var unseen: bool = _actors.is_alive(_player) and _score.counters(_player)[0] == seen_before
		_restore(saved, db)
		_commands.resize(kept)
		if unseen:
			return wait
	return -1


## Puts the sim back to a saved state in place, so every reference the generator holds
## to its systems stays good.
func _restore(saved: Dictionary, db: ContentDb) -> void:
	var err: Error = SimAssembly.restore_systems(_sim, saved)
	assert(err == OK, "the generator's own save restores")
	err = _sim.restore_root(saved)
	assert(err == OK, "and its root")
	assert(db != null, "content")


## Steps until no living guard on a floor of the site is within `cells` of a cell on it.
func _wait_until_floor_clear(rel_y: int, near: Vector3i, cells: int, patience: int) -> bool:
	var floor_y: int = _sites.cell_of(SITE, Vector3i(0, rel_y, 0)).y
	var spot: Vector3i = _sites.cell_of(SITE, near)
	for i: int in patience:
		var clear: bool = true
		for id: int in _actors.actor_ids():
			if id == _player or id == _operator or not _actors.is_alive(id):
				continue
			var cell: Vector3i = BuildSystem.cell_of(_actors.position_of(id))
			if cell.y == floor_y and absi(cell.x - spot.x) + absi(cell.z - spot.z) <= cells:
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
			# only someone the player can see: a shot at a guard behind a wall is a round
			# thrown away, and the walk home out of town is long enough to need them all
			if perception.is_alerted(id, _player) and perception.line_of_sight(_actors.position_of(_player), _actors.position_of(id)):
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
	_travel_back()
	_walk_to_world(FIXER)


# ---------------------------------------------------------------- the trip (M7 claim 10)

## The street in front of the building: the cell the step up onto the slab starts from.
func _street() -> Vector3i:
	var cell: Vector3i = _sites.cell_of(SITE, Vector3i(4, 0, -5))
	var centre: Vector3i = BuildSystem.cell_centre(cell)
	return Vector3i(centre.x, cell.y * M, centre.z)


## Where the city side of the gate's opening is, and the wild side.
const GATE_IN: Vector3i = Vector3i(500, 0, 500)


## From wherever the player is in the city, through the gate, and along the road to the
## building's street. Every step a command: the fixture is the run.
func _travel_out() -> void:
	_walk_to_world(GATE_IN, 4000)
	_command(Regions.COMMAND_ENTER, {"actor": _player, "region": "wilds"})
	_wait(Regions.LOAD_WINDOW_TICKS + 1)
	for point: Vector2i in _the_road():
		_walk_road(point)
	_round_to_the_street()


## From the building's street back along the road, through the gate into the city.
func _travel_back() -> void:
	var road: Array[Vector2i] = _the_road()
	_round_to(road[road.size() - 1])
	road.reverse()
	for point: Vector2i in road:
		_walk_road(point)
	var here: Vector3i = _actors.position_of(_player)
	_walk_road(Vector2i(GATE_IN.x, -GATE_IN.z))
	_command(Regions.COMMAND_ENTER, {"actor": _player, "region": "city"})
	_wait(Regions.LOAD_WINDOW_TICKS + 1)
	assert(here != _actors.position_of(_player), "the gate took the player through")


## The road from just outside the gate to a few metres short of the building, as
## points a couple of metres apart along the graph's own roads: the way to the place the
## contract bound, then down its track until the street is a short step off it.
func _the_road() -> Array[Vector2i]:
	var routes: RouteGraph = SimAssembly.routes_of(_sim)
	var terrain: Terrain = SimAssembly.terrain_of(_sim)
	var binder: SiteBinder = SimAssembly.binder_of(_sim)
	var site_node: int = binder.node_of(&"cold_storage")
	var path: Array[int] = routes.path_between(1, site_node)
	var out: Array[Vector2i] = [Vector2i(GATE_IN.x, -GATE_IN.z)]
	for i: int in path.size() - 1:
		var a: int = path[i]
		var b: int = path[i + 1]
		var id: int = routes.edge_between(a, b)
		var rec: Dictionary = routes.edge(id)
		var length: int = rec["length"]
		var first: int = rec["a"]
		var forward: bool = first == a
		var along: int = 2 * M
		while along < length:
			var point: Vector2i = terrain.road_at(id, along if forward else length - along)
			if b == site_node and _in_ring(point):
				# the building's own track: off it at the ring round the lot
				return out
			out.append(point)
			along += 2 * M
	return out


## The ring a few metres outside the building, inside the ground its raising levelled:
## flat, clear of every piece, and the way round to the street wherever the track came
## in. [min x, min z, max x, max z] in cells.
func _ring() -> Array[int]:
	var db: ContentDb = SimAssembly.content_of(_sim)
	var t: Dictionary = db.get_entry(SiteSystem.KIND_SITE, SITE)
	var base: Vector3i = _sites.base_of(SITE)
	var lo: Vector2i = Vector2i(1 << 30, 1 << 30)
	var hi: Vector2i = -lo
	for v: Variant in t["pieces"]:
		var piece: Dictionary = v
		var rel: Array = piece["rel"]
		var rx: int = rel[0]
		var rz: int = rel[2]
		lo = Vector2i(mini(lo.x, rx), mini(lo.y, rz))
		hi = Vector2i(maxi(hi.x, rx), maxi(hi.y, rz))
	return [base.x + lo.x - RING, base.z + lo.y - RING, base.x + hi.x + RING, base.z + hi.y + RING]


## How far outside the building the ring runs, in cells: well inside what was levelled.
const RING: int = 4


func _in_ring(point: Vector2i) -> bool:
	var r: Array[int] = _ring()
	var cx: int = Terrain._floor_div(point.x, M)
	var cz: int = Terrain._floor_div(point.y, M)
	return cx >= r[0] and cx <= r[2] and cz >= r[1] and cz <= r[3]


## From the track, onto the ring and round it to its south side, then north up to the
## street in front of the building.
func _round_to_the_street() -> void:
	var r: Array[int] = _ring()
	var street: Vector3i = _street()
	_walk_ring_to(Vector2i(Terrain._floor_div(street.x, M), r[1]))
	_walk_to_world(street, 400)


## From the street, back round the ring to where the track leaves it.
func _round_to(track_end: Vector2i) -> void:
	var r: Array[int] = _ring()
	var street: Vector3i = _street()
	var here: Vector3i = _actors.position_of(_player)
	_walk_to_world(Vector3i(street.x, here.y, r[1] * M + M / 2), 400)
	var cx: int = clampi(Terrain._floor_div(track_end.x, M), r[0], r[2])
	var cz: int = clampi(Terrain._floor_div(track_end.y, M), r[1], r[3])
	_walk_ring_to(Vector2i(cx, cz))
	_walk_road(track_end)


## Walks along the ring from wherever on or near it the player is to a cell on it, by
## its corners: sides are straight and clear, the inside is the building.
func _walk_ring_to(target: Vector2i) -> void:
	var r: Array[int] = _ring()
	var here: Vector3i = _actors.position_of(_player)
	var cell: Vector2i = Vector2i(clampi(Terrain._floor_div(here.x, M), r[0], r[2]), clampi(Terrain._floor_div(here.z, M), r[1], r[3]))
	# onto the ring: to the nearest side
	var to_side: Array[int] = [cell.x - r[0], r[2] - cell.x, cell.y - r[1], r[3] - cell.y]
	var nearest: int = to_side.find(to_side.min())
	match nearest:
		0: cell.x = r[0]
		1: cell.x = r[2]
		2: cell.y = r[1]
		_: cell.y = r[3]
	_walk_cell(cell)
	# round the corners to the side the target is on
	for i: int in 4:
		if (cell.x == target.x and (cell.x == r[0] or cell.x == r[2])) or (cell.y == target.y and (cell.y == r[1] or cell.y == r[3])):
			break
		var corner: Vector2i = _next_corner(cell, r)
		_walk_cell(corner)
		cell = corner
		# an armed player going round a building that is shooting at them shoots back at
		# every corner before turning it; an unarmed one only ever comes this way unseen
		if _actors.wielded(_player) != EntityIds.NONE:
			_fight(600)
	_walk_cell(target)


## The next corner of the ring going round anticlockwise from a cell on it.
static func _next_corner(cell: Vector2i, r: Array[int]) -> Vector2i:
	if cell.y == r[1] and cell.x < r[2]:
		return Vector2i(r[2], r[1])
	if cell.x == r[2] and cell.y < r[3]:
		return Vector2i(r[2], r[3])
	if cell.y == r[3] and cell.x > r[0]:
		return Vector2i(r[0], r[3])
	return Vector2i(r[0], r[1])


## Walks to a cell on the ring. An armed player goes a few cells at a time and shoots
## back at anyone who has come out after them before each stretch: a guard out of the
## building is somebody the ring walk passes, not somebody the building's walls stop.
func _walk_cell(cell: Vector2i) -> void:
	var here: Vector3i = _actors.position_of(_player)
	var target: Vector3i = Vector3i(cell.x * M + M / 2, here.y, cell.y * M + M / 2)
	if _actors.wielded(_player) == EntityIds.NONE:
		_walk_to_world(target, 600)
		return
	for i: int in 40:
		here = _actors.position_of(_player)
		if Vector2i(here.x, here.z) == Vector2i(target.x, target.z) or not _actors.is_alive(_player):
			return
		_fight(300)
		var step: Vector3i = Vector3i(here.x + clampi(target.x - here.x, -3 * M, 3 * M), here.y, here.z + clampi(target.z - here.z, -3 * M, 3 * M))
		_walk_to_world(step, 200)


## One step of the road at a time, straight at the next point, both axes at once: the
## road is a straight line between points, and a line is what the ground is cut for.
func _walk_road(point: Vector2i) -> void:
	var speed: int = _movement.speed_of(_player)
	for i: int in 200:
		var here: Vector3i = _actors.position_of(_player)
		var dx: int = clampi(point.x - here.x, -speed, speed)
		var dz: int = clampi(point.y - here.z, -speed, speed)
		if dx == 0 and dz == 0:
			return
		_command(&"actor.move", {"actor": _player, "dx": dx, "dz": dz, "dy": 0})
		if _actors.position_of(_player) == here:
			push_error("the road to %s is blocked at %s" % [point, here])
			return
	push_error("could not reach %s along the road" % point)


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
