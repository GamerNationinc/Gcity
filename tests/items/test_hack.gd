extends GcityTest

## M6 spec claim 9: the hack is a timed device task. `hack.start {actor, target}` needs
## a carried device providing `daemon_coprocessor`, free daemon slots (memory_capacity /
## 1000 minus the slots in use) covering the target's `daemons`, and the actor within
## the target's reach on its storey. It runs once per tick, making the target's noise
## every 40 ticks, and is interrupted by moving, firing, being hurt, dying, losing
## footing or `hack.cancel`. On completion it applies the target's effect (a registered
## kind), emits `hack.completed` and leaves the terminal logged in, its daemons still in
## use, until `hack.logout` (pause-safe). A paused sim does not advance a hack, and a
## device that can no longer hold what runs drops the running hack, then the newest
## logins. Property: over 10 000 generated command streams, slots are never over-committed
## after a step and every target completes at most once.

const SEED: int = 20261028
const SEED_PROPERTY: int = 20261029
const PROPERTY_CASES: int = 10_000
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)

var _sim: SimRoot
var _db: ContentDb
var _actors: ActorSystem
var _items: ItemSystem
var _hacks: HackSystem
var _player: int = 0
var _device: int = 0
var _coprocessor: int = 0
var _completed: Array[Dictionary] = []
var _noises: Array[Dictionary] = []


func _content() -> ContentDb:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	assert_eq(db.add(&"hack_target", &"zz_terminal", _target(120, 1, &"plasma_cutter")), OK, "a test terminal")
	assert_eq(db.add(&"hack_target", &"zz_vault", _target(200, 2, &"breaching_kit")), OK, "a two-daemon target")
	return db


func _target(ticks: int, daemons: int, template: StringName) -> Dictionary:
	return {"schema_version": 1, "description": "test", "ticks": ticks, "daemons": daemons, "noise": 15000, "reach_mm": 2000,
		"effect": {"kind": "spawn_item", "params": {"template": String(template)}}}


func _setup() -> void:
	_db = _content()
	_sim = SimAssembly.build(SEED, _db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_hacks = SimAssembly.hacks_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, _feet(0, 0))
	var inv: StringName = ItemSystem.inventory_of(_player)
	_device = _items.spawn(&"device_frame", &"handset", inv, 1)
	_coprocessor = _items.spawn(&"device_module", &"daemon_coprocessor", inv, 2)
	assert_true(_do(&"actor.equip_device", {"actor": _player, "device": _device}), "device carried")
	assert_true(_do(&"item.attach", {"actor": _player, "weapon": _device, "part": _coprocessor}), "coprocessor fitted")
	var completed: Array[Dictionary] = []
	_completed = completed
	var noises: Array[Dictionary] = []
	_noises = noises
	var events: EventBus = SimAssembly.combat_of(_sim).events()
	events.subscribe(HackSystem.EVENT_COMPLETED, func(payload: Dictionary) -> void: completed.append(payload))
	events.subscribe(PerceptionSystem.EVENT_NOISE, func(payload: Dictionary) -> void: noises.append(payload))


func _feet(cx: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, 0, cz * M + 500)


func _cell(cx: int, cy: int, cz: int) -> Vector3i:
	return BuildSystem.cell_of(FAR) + Vector3i(cx, cy, cz)


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


func _start(target: int) -> bool:
	return _do(&"hack.start", {"actor": _player, "target": target})


func _hack_noises() -> int:
	var n: int = 0
	for p: Dictionary in _noises:
		var source: int = p["source"]
		var loudness: int = p["loudness"]
		if source == _player and loudness == 15000:
			n += 1
	return n


func test_a_hack_needs_the_coprocessor_slots_and_reach() -> void:
	_setup()
	var terminal: int = _hacks.place(&"zz_terminal", _cell(1, 0, 0), EntityIds.NONE)
	assert_true(terminal > 0, "a terminal placed beside the player")
	assert_eq(_hacks.place(&"no_such_target", _cell(2, 0, 0), EntityIds.NONE), EntityIds.NONE, "an unknown target is not placed")
	assert_eq(_hacks.place(&"zz_terminal", _cell(2, 0, 0), 999), EntityIds.NONE, "nor one on a piece that does not exist")
	assert_eq(_hacks.free_slots(_player), 2, "handset 1000 + coprocessor 1000 = two slots")
	assert_true(_do(&"item.detach", {"actor": _player, "weapon": _device, "socket": "coprocessor"}), "coprocessor out")
	assert_eq(_hacks.free_slots(_player), 0, "no slots without the coprocessor")
	assert_false(_start(terminal), "refused without the coprocessor")
	assert_true(_do(&"item.attach", {"actor": _player, "weapon": _device, "part": _coprocessor}), "coprocessor back")
	assert_false(_do(&"hack.start", {"actor": _player, "target": 999}), "refused for an unknown target")
	var far: int = _hacks.place(&"zz_terminal", _cell(4, 0, 0), EntityIds.NONE)
	assert_false(_start(far), "refused out of reach (3.5 m > 2 m)")
	var above: int = _hacks.place(&"zz_terminal", _cell(0, 1, 0), EntityIds.NONE)
	assert_false(_start(above), "refused on another storey")
	var stranger: int = _actors.spawn(&"arcade", 1)
	_actors.set_position(stranger, _feet(1, 1))
	assert_false(_do(&"hack.start", {"actor": stranger, "target": terminal}), "refused without a device")
	assert_true(_start(terminal), "accepted with the coprocessor, in reach")
	assert_true(_hacks.is_hacking(_player), "running")
	assert_eq(_hacks.free_slots(_player), 1, "one slot in use")
	var other: int = _hacks.place(&"zz_terminal", _cell(-1, 0, 0), EntityIds.NONE)
	assert_false(_start(other), "one hack at a time")
	var vault: int = _hacks.place(&"zz_vault", _cell(0, 0, 1), EntityIds.NONE)
	assert_true(_do(&"hack.cancel", {"actor": _player}), "cancelled")
	assert_false(_do(&"hack.cancel", {"actor": _player}), "nothing left to cancel")
	assert_true(_start(vault), "the two-daemon target fits two free slots")
	assert_eq(_hacks.free_slots(_player), 0, "both in use")


func test_a_hack_completes_once_and_stays_logged_in_until_logout() -> void:
	_setup()
	var terminal: int = _hacks.place(&"zz_terminal", _cell(1, 0, 0), EntityIds.NONE)
	var inv: StringName = ItemSystem.inventory_of(_player)
	var before: int = _items.items_in(inv).size()
	assert_true(_start(terminal), "started")
	_sim.step_n(118)
	assert_true(_hacks.is_hacking(_player), "still running after 119 of 120 ticks (the start tick runs one)")
	assert_eq(_completed.size(), 0, "not yet")
	_sim.step()
	assert_false(_hacks.is_hacking(_player), "done at 120")
	assert_eq(_completed.size(), 1, "hack.completed once")
	assert_eq(_completed[0], {"actor": _player, "target": terminal, "applied": true}, "naming actor and target")
	var held: Array[int] = _items.items_in(inv)
	assert_eq(held.size(), before + 1, "the effect spawned one item into the inventory")
	assert_eq(_items.item_template(held[held.size() - 1]), &"plasma_cutter", "the target's template")
	assert_eq(_hack_noises(), 3, "noise at progress 0, 40 and 80")
	assert_true(_hacks.is_done(terminal), "the terminal is done")
	assert_eq(_hacks.login_of(terminal), _player, "and logged in")
	assert_eq(_hacks.free_slots(_player), 1, "its daemon still in use")
	assert_false(_start(terminal), "a done terminal is not hacked again")
	_sim.step_n(200)
	assert_eq(_completed.size(), 1, "it completed once")
	var stranger: int = _actors.spawn(&"arcade", 1)
	assert_false(_do(&"hack.logout", {"actor": stranger, "target": terminal}), "only its own login is logged out")
	_sim.set_paused(true)
	assert_true(_do(&"hack.logout", {"actor": _player, "target": terminal}), "logout is pause-safe")
	_sim.set_paused(false)
	assert_eq(_hacks.login_of(terminal), EntityIds.NONE, "logged out")
	assert_eq(_hacks.free_slots(_player), 2, "the slot is free")
	assert_false(_do(&"hack.logout", {"actor": _player, "target": terminal}), "not twice")


## M6 claim 19's hacking pane reads, never writes: the targets in reach (exactly those
## a start would accept by place), each one's name and length, the running target and
## the actor's logins, oldest first.
func test_the_queries_a_client_reads() -> void:
	_setup()
	var terminal: int = _hacks.place(&"zz_terminal", _cell(1, 0, 0), EntityIds.NONE)
	var vault: int = _hacks.place(&"zz_vault", _cell(0, 0, 1), EntityIds.NONE)
	var far: int = _hacks.place(&"zz_terminal", _cell(4, 0, 0), EntityIds.NONE)
	var above: int = _hacks.place(&"zz_terminal", _cell(0, 1, 0), EntityIds.NONE)
	assert_eq(_hacks.targets_in_reach(_player), [terminal, vault] as Array[int], "in reach on the storey, by id")
	assert_eq(_hacks.target_name(terminal), &"zz_terminal", "its content id")
	assert_eq(_hacks.target_name(far + above), &"", "an unknown id has none")
	assert_eq(_hacks.target_ticks(vault), 200, "its length")
	assert_eq(_hacks.target_ticks(far + above), -1, "an unknown id has none")
	assert_eq(_hacks.running_target(_player), EntityIds.NONE, "nothing running")
	assert_false(_start(far), "a start agrees: out of reach")
	assert_false(_start(above), "and off the storey")
	assert_true(_start(terminal), "started")
	assert_eq(_hacks.running_target(_player), terminal, "running")
	_sim.step_n(119)
	assert_eq(_hacks.running_target(_player), EntityIds.NONE, "done")
	assert_eq(_hacks.logins_of(_player), [terminal] as Array[int], "logged in")
	_actors.set_position(_player, _feet(4, 0))
	assert_eq(_hacks.targets_in_reach(_player), [far] as Array[int], "reach follows the actor")
	assert_eq(_hacks.logins_of(_player + 100), [] as Array[int], "an actor with none")


func test_a_paused_sim_does_not_advance_or_start_a_hack() -> void:
	_setup()
	var terminal: int = _hacks.place(&"zz_terminal", _cell(1, 0, 0), EntityIds.NONE)
	assert_true(_start(terminal), "started")
	var left: int = _hacks.ticks_left(_player)
	_sim.set_paused(true)
	_sim.step_n(500)
	assert_eq(_hacks.ticks_left(_player), left, "frozen while paused")
	var other: int = _hacks.place(&"zz_terminal", _cell(-1, 0, 0), EntityIds.NONE)
	var dispatched: int = _sim.dispatched_count()
	_sim.submit(SimCommand.new(_sim.get_tick() + 1, &"hack.start", {"actor": _player, "target": other}))
	_sim.submit(SimCommand.new(_sim.get_tick() + 1, &"hack.cancel", {"actor": _player}))
	_sim.step_n(10)
	assert_eq(_sim.dispatched_count(), dispatched, "neither cancel nor start dispatches while paused")
	_sim.set_paused(false)
	_sim.step()
	assert_false(_hacks.is_hacking(_player), "both ran on resume, in order: the start refused (one at a time), the cancel")
	assert_eq(_completed.size(), 0, "nothing completed")


func test_a_hack_is_interrupted_by_every_listed_cause() -> void:
	for cause: String in ["move", "fire", "hurt", "die", "cancel", "fall"]:
		_setup()
		var pistol: int = _arm()
		var dummy: int = _actors.spawn(&"range_dummy", 1)
		_actors.set_position(dummy, _feet(0, 3))
		var terminal: int = _hacks.place(&"zz_terminal", _cell(1, 0, 0), EntityIds.NONE)
		assert_true(_start(terminal), "%s: started" % cause)
		_sim.step_n(50)
		match cause:
			"move":
				_actors.set_position(_player, _feet(0, 0) + Vector3i(0, 0, 100))
				_sim.step()
			"fire":
				assert_true(_do(&"weapon.fire", {"actor": _player, "target": dummy}), "fire: the shot is accepted")
			"hurt":
				_actors.damage_node(_player, &"body", 1)
				_sim.step()
			"die":
				_actors.damage_node(_player, &"body", 100000)
				_sim.step()
			"cancel":
				assert_true(_do(&"hack.cancel", {"actor": _player}), "cancel accepted")
			"fall":
				_actors.set_position(_player, _feet(0, 0) + Vector3i(0, 2 * M, 0))
				_sim.step()
		assert_false(_hacks.is_hacking(_player), "%s interrupts the hack" % cause)
		assert_eq(_hacks.slots_in_use(_player), 0, "%s: its slot is free again" % cause)
		_sim.step_n(200)
		assert_eq(_completed.size(), 0, "%s: it never completes" % cause)
		assert_false(_hacks.is_done(terminal), "%s: the terminal is untouched" % cause)
		assert_true(pistol > 0, "armed")


## A G19 in hand with a chambered round, for the firing cause.
func _arm() -> int:
	var inv: StringName = ItemSystem.inventory_of(_player)
	var pistol: int = _items.spawn(&"weapon_frame", &"g19", inv, 11)
	var mag: int = _items.spawn(&"weapon_part", &"g19_mag_15", inv, 12)
	for i: int in 3:
		var round: int = _items.spawn(&"ammo", &"9x19_fmj", inv, 100 + i)
		assert_true(_do(&"magazine.load", {"actor": _player, "magazine": mag, "round": round}), "load")
	assert_true(_do(&"actor.wield", {"actor": _player, "weapon": pistol}), "wield")
	assert_true(_do(&"weapon.reload_tactical", {"actor": _player, "weapon": pistol, "magazine": mag}), "reload")
	_sim.step_n(90)
	return pistol


func test_a_device_that_shrinks_drops_the_running_hack_then_the_newest_logins() -> void:
	_setup()
	var a: int = _hacks.place(&"zz_terminal", _cell(1, 0, 0), EntityIds.NONE)
	var b: int = _hacks.place(&"zz_terminal", _cell(-1, 0, 0), EntityIds.NONE)
	assert_true(_start(a), "first")
	_sim.step_n(120)
	assert_true(_start(b), "second")
	_sim.step_n(120)
	assert_eq(_hacks.free_slots(_player), 0, "two logins hold both slots")
	assert_true(_do(&"item.detach", {"actor": _player, "weapon": _device, "socket": "coprocessor"}), "the coprocessor comes out")
	assert_eq(_hacks.login_of(a), EntityIds.NONE, "without the coprocessor no login holds")
	assert_eq(_hacks.login_of(b), EntityIds.NONE, "either of them")
	assert_true(_do(&"item.attach", {"actor": _player, "weapon": _device, "part": _coprocessor}), "back in")
	var c: int = _hacks.place(&"zz_vault", _cell(0, 0, 1), EntityIds.NONE)
	var d: int = _hacks.place(&"zz_terminal", _cell(0, 0, -1), EntityIds.NONE)
	assert_true(_start(d), "a one-daemon hack")
	_sim.step_n(120)
	assert_eq(_hacks.login_of(d), _player, "logged in")
	assert_false(_start(c), "a two-daemon hack does not fit beside it")
	assert_true(_do(&"hack.logout", {"actor": _player, "target": d}), "logout")
	assert_true(_start(c), "now it fits")
	var stats: StatResolver = SimAssembly.stats_of(_sim)
	var memory: int = stats.resolve(_device, &"memory_capacity")
	assert_eq(memory, 2000, "two slots")
	stats.set_base(_device, &"memory_capacity", 0)  # a 1000-point device: the hack no longer fits
	_sim.step()
	assert_false(_hacks.is_hacking(_player), "the running hack is dropped")


func test_an_effect_kind_is_a_registration() -> void:
	var db: ContentDb = _content()
	assert_eq(db.add(&"hack_target", &"zz_bad", {"schema_version": 1, "description": "test", "ticks": 10, "daemons": 1, "noise": 0, "reach_mm": 1000,
		"effect": {"kind": "summon_dragon", "params": {}}}), OK, "an unknown effect kind")
	assert_eq(SimAssembly.build(SEED, db), null, "is rejected at assembly")
	db = _content()
	assert_eq(db.add(&"hack_target", &"zz_bad", _target(10, 1, &"no_such_item")), OK, "an unknown template")
	assert_eq(SimAssembly.build(SEED, db), null, "is rejected at assembly")
	db = _content()
	assert_eq(db.add(&"hack_target", &"zz_bad", _target(0, 1, &"plasma_cutter")), OK, "zero ticks")
	assert_eq(SimAssembly.build(SEED, db), null, "is rejected at assembly")
	_setup()
	var noop: Callable = _hacks.free_slots
	assert_eq(_hacks.register_effect(HackSystem.EFFECT_SPAWN_ITEM, noop, noop), ERR_ALREADY_EXISTS, "a kind registers once")
	assert_true(_hacks.has_effect(HackSystem.EFFECT_SPAWN_ITEM), "spawn_item is registered")


func test_the_snapshot_restores_exactly_and_rejects_hostile_state() -> void:
	_setup()
	var a: int = _hacks.place(&"zz_terminal", _cell(1, 0, 0), EntityIds.NONE)
	_hacks.place(&"zz_vault", _cell(-1, 0, 0), EntityIds.NONE)
	assert_true(_start(a), "started")
	_sim.step_n(130)
	var b: int = _hacks.place(&"zz_terminal", _cell(0, 0, 1), EntityIds.NONE)
	assert_true(_start(b), "a second, running")
	_sim.step_n(7)
	var snap: Dictionary = _hacks.snapshot()
	assert_eq(_hacks.restore(snap.duplicate(true)), OK, "its own snapshot restores")
	assert_eq(StateHash.of(_hacks.snapshot()), StateHash.of(snap), "exactly")
	var hostile: Array[Dictionary] = []
	var bad: Dictionary = snap.duplicate(true)
	bad["next"] = -1
	hostile.append(bad)
	# ids start at 1: a counter of 0 is refused even with no targets to contradict it
	# (a mutation survivor)
	bad = {"targets": {}, "running": {}, "logins": {}, "next": 0, "completed": 0}
	hostile.append(bad)
	bad = snap.duplicate(true)
	var targets: Dictionary = bad["targets"]
	var rec: Dictionary = targets[a]
	rec["target"] = "no_such_target"
	hostile.append(bad)
	bad = snap.duplicate(true)
	var running: Dictionary = bad["running"]
	var run: Dictionary = running[_player]
	run["ticks"] = 0
	hostile.append(bad)
	bad = snap.duplicate(true)
	running = bad["running"]
	run = running[_player]
	run["target"] = a  # already done
	hostile.append(bad)
	bad = snap.duplicate(true)
	bad.erase("completed")
	hostile.append(bad)
	for h: Dictionary in hostile:
		assert_eq(_hacks.restore(h), ERR_INVALID_DATA, "a hostile snapshot is rejected")
	assert_eq(StateHash.of(_hacks.snapshot()), StateHash.of(snap), "and changes nothing")


func test_property_slots_are_never_over_committed_and_targets_complete_once() -> void:
	_setup()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	var targets: Array[int] = []
	for i: int in 6:
		var kind: StringName = &"zz_vault" if i % 3 == 0 else &"zz_terminal"
		targets.append(_hacks.place(kind, _cell(i % 3 - 1, 0, i / 3), EntityIds.NONE))
	var stats: StatResolver = SimAssembly.stats_of(_sim)
	var over: int = 0
	var reused: int = 0
	var cases: int = 0
	while cases < PROPERTY_CASES:
		cases += 1
		var op: int = rng.randi_range(0, 19)
		var at: int = _sim.get_tick() + 1
		var target: int = targets[rng.randi_range(0, targets.size() - 1)]
		match op:
			0, 1, 2, 3, 4, 5, 6, 7:
				_sim.submit(SimCommand.new(at, &"hack.start", {"actor": _player, "target": target}))
			8:
				_sim.submit(SimCommand.new(at, &"hack.cancel", {"actor": _player}))
			9, 10, 11:
				_sim.submit(SimCommand.new(at, &"hack.logout", {"actor": _player, "target": target}))
			12:
				_sim.submit(SimCommand.new(at, &"item.detach", {"actor": _player, "weapon": _device, "socket": "coprocessor"}))
			13, 14:
				_sim.submit(SimCommand.new(at, &"item.attach", {"actor": _player, "weapon": _device, "part": _coprocessor}))
			15:
				stats.set_base(_device, &"memory_capacity", rng.randi_range(0, 3) * 1000)
			16:
				_actors.set_position(_player, _feet(rng.randi_range(-1, 1), rng.randi_range(-1, 1)))
			_:
				for k: int in targets.size():  # done terminals are replaced, so completions keep coming
					if _hacks.is_done(targets[k]):
						targets[k] = _hacks.place(&"zz_vault" if k % 3 == 0 else &"zz_terminal", _cell(k % 3 - 1, 0, k / 3), EntityIds.NONE)
		_sim.step_n(rng.randi_range(1, 80))
		if _hacks.slots_in_use(_player) > _hacks.capacity(_player):
			over += 1
	var seen: Dictionary = {}
	for p: Dictionary in _completed:
		var t: int = p["target"]
		if seen.has(t):
			reused += 1
		seen[t] = true
	assert_eq(over, 0, "slots never over-committed after a step")
	assert_eq(reused, 0, "no target completed twice")
	assert_true(_completed.size() > 100, "and hacks did complete (%d)" % _completed.size())
