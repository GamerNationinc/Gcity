extends GcityTest

## M5 spec claims 6–7 (ADR-006 C): `safe` is a sixth right; `sim.pause` is accepted
## only where the actor holds it and `sim.resume` only while paused; a paused sim
## advances no tick, ticks no system, dispatches only pause-safe commands and keeps
## the rest queued in order; a save taken paused restores paused. Property: the hash
## after resume equals that of the same stream with the pauses removed, save for
## `paused_steps`.

const SEED: int = 20261120
const SEED_PROPERTY: int = 20261121
const PROPERTY_CASES: int = 10_000
const M: int = 1000

var _sim: SimRoot
var _actors: ActorSystem
var _items: ItemSystem
var _land: LandSystem
var _player: int = 0


func _db() -> ContentDb:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	return db


func _setup(db: ContentDb = null) -> void:
	if db == null:
		db = _db()
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_land = SimAssembly.land_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, Vector3i(3 * M, 0, 3 * M))  # on the starter plot


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


func _own_the_plot() -> void:
	assert_true(_do(&"land.identify", {"actor": _player, "owner": "player"}), "identify")
	assert_true(_do(&"land.transfer", {"parcel": "starter_plot", "owner": "player"}), "transfer")


func test_safe_is_a_right_held_by_owners_only() -> void:
	_setup()
	var here: Vector3i = _actors.position_of(_player)
	assert_eq(_land.rights_at(here, _player).size(), 6, "six rights")
	assert_false(_safe(here, _player), "an unowned plot is not safe")
	_own_the_plot()
	assert_true(_safe(here, _player), "the owner is safe on it")
	var other: int = _actors.spawn(&"arcade", 3)
	_actors.set_position(other, here)
	assert_false(_safe(here, other), "a visitor is not")
	assert_false(_safe(Vector3i(-50 * M, 0, -50 * M), _player), "nor is anyone on unparcelled land")


func _safe(position: Vector3i, actor: int) -> bool:
	var rights: Dictionary = _land.rights_at(position, actor)
	return rights[&"safe"]


func test_pause_is_gated_by_safe_and_a_refusal_is_a_violation() -> void:
	_setup()
	var violations: int = _land.violation_count()
	assert_false(_do(&"sim.pause", {"actor": _player}), "not safe here yet")
	assert_eq(_land.violation_count(), violations + 1, "a land.violation for lack of safe")
	assert_false(_sim.is_paused(), "not paused")
	assert_false(_do(&"sim.resume", {"actor": _player}), "nothing to resume")
	_own_the_plot()
	assert_false(_do(&"sim.pause", {}), "missing actor")
	assert_false(_do(&"sim.pause", {"actor": 99}), "unknown actor")
	assert_true(_do(&"sim.pause", {"actor": _player}), "safe: paused")
	assert_true(_sim.is_paused(), "paused")
	assert_false(_do(&"sim.pause", {"actor": _player}), "not twice: refused at once, pause-safe, so it never lingers in the queue")
	assert_eq(_sim.rejected_count(), 5, "five refusals")
	assert_eq(_sim.get_tick(), 7, "the redundant pause's step was a frozen one: seven running steps before it")


func test_paused_the_tick_freezes_and_only_pause_safe_commands_dispatch() -> void:
	_setup()
	_own_the_plot()
	var inv: StringName = ItemSystem.inventory_of(_player)
	var pistol: int = _items.spawn(&"weapon_frame", &"g19", inv, 1)
	var mag: int = _items.spawn(&"weapon_part", &"g19_mag_15", inv, 2)
	var rounds: Array[int] = []
	for i: int in 15:
		rounds.append(_items.spawn(&"ammo", &"9x19_fmj", inv, 100 + i))
	var device: int = _items.spawn(&"device_frame", &"handset", inv, 3)
	assert_true(_do(&"sim.pause", {"actor": _player}), "paused")
	var tick: int = _sim.get_tick()
	var hash_before: String = _sim.state_hash()
	# a menu's worth of commands while paused: loading rounds, wielding, equipping
	for i: int in 15:
		_sim.submit(SimCommand.new(tick + 1, &"magazine.load", {"actor": _player, "magazine": mag, "round": rounds[i]}))
	_sim.submit(SimCommand.new(tick + 1, &"actor.wield", {"actor": _player, "weapon": pistol}))
	_sim.submit(SimCommand.new(tick + 1, &"actor.equip_device", {"actor": _player, "device": device}))
	# and two that take game time, which must wait
	_sim.submit(SimCommand.new(tick + 1, &"weapon.reload_tactical", {"actor": _player, "weapon": pistol, "magazine": mag}))
	_sim.submit(SimCommand.new(tick + 1, &"actor.move", {"actor": _player, "dx": 100, "dz": 0}))
	_sim.step_n(50)
	assert_eq(_sim.get_tick(), tick, "the tick did not advance")
	assert_eq(_sim.paused_steps(), 50, "fifty frozen steps counted")
	assert_eq(_items.rounds_in(mag).size(), 15, "the magazine loaded while paused")
	assert_eq(_actors.wielded(_player), pistol, "wielded while paused")
	assert_eq(_actors.device_of(_player), device, "equipped while paused")
	assert_eq(_items.magazine_of(pistol), 0, "the reload waited")
	assert_eq(_actors.position_of(_player), Vector3i(3 * M, 0, 3 * M), "the move waited")
	assert_ne(_sim.state_hash(), hash_before, "the state moved (the menu's commands and the frozen-step count)")
	var pos_before: Vector3i = _actors.position_of(_player)
	assert_true(_do(&"sim.resume", {"actor": _player}), "resumed (pause-safe: dispatched while paused)")
	assert_eq(_sim.get_tick(), tick, "the resume step itself is still frozen")
	_sim.step()
	assert_eq(_sim.get_tick(), tick + 1, "the next step advances")
	assert_eq(_items.magazine_of(pistol), mag, "the queued reload ran on that tick")
	assert_eq(_actors.position_of(_player), pos_before + Vector3i(100, 0, 0), "and the queued move, in order")
	assert_eq(_sim.rejected_count(), 0, "nothing was rejected")
	assert_false(_sim.is_paused(), "running")
	assert_eq(_sim.paused_steps(), 51, "the resume step counted too")


func test_a_save_taken_paused_restores_paused() -> void:
	_setup()
	_own_the_plot()
	assert_true(_do(&"sim.pause", {"actor": _player}), "paused")
	_sim.submit(SimCommand.new(_sim.get_tick() + 1, &"actor.move", {"actor": _player, "dx": 50, "dz": 0}))
	_sim.step_n(3)
	var db: ContentDb = _db()
	var file: SaveFile = SaveFile.parse(SaveFile.serialize(_sim, db.digest()))
	assert_true(file.is_valid(), "save valid")
	var loaded: SimRoot = SimAssembly.load_save(file, db)
	assert_true(loaded != null, "loaded")
	assert_true(loaded.is_paused(), "still paused")
	assert_eq(loaded.paused_steps(), 3, "with its frozen steps (the pause's own step was a running one)")
	assert_eq(loaded.state_hash(), _sim.state_hash(), "hashes equal")
	loaded.step_n(2)
	_sim.step_n(2)
	assert_eq(loaded.state_hash(), _sim.state_hash(), "still equal, still frozen")
	var snap: Dictionary = _sim.snapshot()
	var bad: Dictionary = snap.duplicate(true)
	bad["paused"] = 1
	assert_eq(SimAssembly.build(SEED, db).restore_root(bad), ERR_INVALID_DATA, "paused must be a bool")
	bad = snap.duplicate(true)
	bad["paused_steps"] = -1
	assert_eq(SimAssembly.build(SEED, db).restore_root(bad), ERR_INVALID_DATA, "a negative count")
	bad = snap.duplicate(true)
	bad.erase("paused_steps")
	assert_eq(SimAssembly.build(SEED, db).restore_root(bad), ERR_INVALID_DATA, "the key is required")


func test_property_pauses_change_nothing_but_the_frozen_step_count() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	var db: ContentDb = _db()
	var mismatches: int = 0
	var paused_total: int = 0
	for case: int in PROPERTY_CASES / 20:
		# the same generated play, once with pauses and once without: while paused,
		# only the device's own (pause-safe) commands are submitted, as the client does
		var script: Array = []
		for i: int in rng.randi_range(1, 12):
			var r: int = rng.randi_range(0, 9)
			if r < 4:
				script.append(["pause", rng.randi_range(1, 6), rng.randi_range(0, 3)])  # frozen steps, menu commands inside
			elif r < 6:
				script.append(["safe", rng.randi_range(0, 2), 0])
			else:
				script.append(["play", rng.randi_range(0, 2), 0])
		var seed: int = rng.randi()
		var results: Array[Dictionary] = []
		for with_pauses: bool in [true, false]:
			var sim: SimRoot = SimAssembly.build(seed, db)
			var actors: ActorSystem = SimAssembly.actors_of(sim)
			var items: ItemSystem = SimAssembly.items_of(sim)
			var player: int = actors.spawn(&"arcade", 0)
			actors.set_position(player, Vector3i(3 * M, 0, 3 * M))
			var inv: StringName = ItemSystem.inventory_of(player)
			var pistol: int = items.spawn(&"weapon_frame", &"g19", inv, 1)
			var mag: int = items.spawn(&"weapon_part", &"g19_mag_15", inv, 2)
			var rounds: Array[int] = []
			for i: int in 6:
				rounds.append(items.spawn(&"ammo", &"9x19_fmj", inv, 100 + i))
			sim.submit(SimCommand.new(sim.get_tick() + 1, &"land.identify", {"actor": player, "owner": "player"}))
			sim.submit(SimCommand.new(sim.get_tick() + 1, &"land.transfer", {"parcel": "starter_plot", "owner": "player"}))
			sim.step()
			var loaded: int = 0
			var wielding: bool = false
			var pause_commands: int = 0
			for step: Array in script:
				var what: String = step[0]
				var n: int = step[1]
				var k: int = step[2]
				if what == "pause":
					# the pause's own step is a running one in both runs; then the frozen
					# steps, the menu's commands dispatched while frozen, and the resume
					if with_pauses:
						sim.submit(SimCommand.new(sim.get_tick() + 1, &"sim.pause", {"actor": player}))
						pause_commands += 1
					sim.step()
					if with_pauses:
						sim.step_n(n)
				for i: int in (k if what == "pause" else (n if what == "safe" else 0)):
					if loaded < rounds.size():
						sim.submit(SimCommand.new(sim.get_tick() + 1, &"magazine.load", {"actor": player, "magazine": mag, "round": rounds[loaded]}))
						loaded += 1
					else:
						sim.submit(SimCommand.new(sim.get_tick() + 1, &"actor.wield", {"actor": player, "weapon": 0 if wielding else pistol}))
						wielding = not wielding
				if what == "pause" and with_pauses:
					sim.step()  # frozen: the menu's commands dispatch
					sim.submit(SimCommand.new(sim.get_tick() + 1, &"sim.resume", {"actor": player}))
					pause_commands += 1
					sim.step()  # frozen: the resume dispatches
				if what == "play":
					for i: int in n:
						sim.submit(SimCommand.new(sim.get_tick() + 1, &"actor.move", {"actor": player, "dx": 100, "dz": 0}))
					sim.step_n(3)
			sim.step_n(2)
			var snap: Dictionary = sim.snapshot()
			results.append({"steps": snap["paused_steps"], "dispatched": snap["dispatched"], "pause_commands": pause_commands, "hash": _hash_without_pause(snap), "snap": snap})
		var with_p: Dictionary = results[0]
		var without_p: Dictionary = results[1]
		paused_total += with_p["steps"]
		var same_dispatch: bool = with_p["dispatched"] - with_p["pause_commands"] == without_p["dispatched"]
		if with_p["hash"] != without_p["hash"] or without_p["steps"] != 0 or not same_dispatch:
			mismatches += 1
			if mismatches <= 3:
				var snap_with: Dictionary = with_p["snap"]
				var snap_without: Dictionary = without_p["snap"]
				fail("case %d: hashes differ (%d frozen steps): %s | script %s" % [case, with_p["steps"], _differing(snap_with, snap_without), script])
	assert_eq(mismatches, 0, "pausing changes nothing but the frozen-step count (%d cases)" % (PROPERTY_CASES / 20))
	assert_true(paused_total > 500, "the cases paused for real (%d frozen steps)" % paused_total)


static func _differing(a: Dictionary, b: Dictionary) -> String:
	var out: PackedStringArray = PackedStringArray()
	for key: String in a:
		if key == "systems":
			var sa: Dictionary = a["systems"]
			var sb: Dictionary = b["systems"]
			for sys: StringName in sa:
				if sa[sys] != sb[sys]:
					out.append("systems.%s: %s vs %s" % [sys, JSON.stringify(sa[sys]).left(300), JSON.stringify(sb[sys]).left(300)])
		elif a[key] != b[key]:
			out.append("%s: %s vs %s" % [key, JSON.stringify(a[key]).left(200), JSON.stringify(b[key]).left(200)])
	return "; ".join(out)


## The hash of everything but the pause bookkeeping: the frozen-step count, the flag,
## and the dispatch counter the pause and resume commands themselves add to.
static func _hash_without_pause(snap: Dictionary) -> String:
	var copy: Dictionary = snap.duplicate(true)
	copy["paused_steps"] = 0
	copy["paused"] = false
	copy["dispatched"] = 0
	return StateHash.of(copy)
