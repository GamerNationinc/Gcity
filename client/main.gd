## The M1 range view (spec claim 17): a read-only view of the sim plus input that
## submits commands. Sets up one player, one dummy and the pistol kit through the same
## debug-class spawn commands a fixture would carry, then lets the player fire, load and
## reload. The client never writes sim state; every action is SimRoot.submit().
##
## `--demo` after `--` plays a scripted sequence through the same action path, for
## unattended playtests and screenshots; `--demo-quit=<s>` quits after that many seconds.
extends Control

const PROFILE: StringName = &"arcade"
const DUMMY_PROFILE: StringName = &"range_dummy"
const DUMMY_RANGE_M: int = 18
const ROUNDS_PER_MAG: int = 15
const LOOSE_ROUNDS: int = 30

@onready var _host: LocalHost = $LocalHost
@onready var _status: Label = $Status

var _player: int = 0
var _dummy: int = 0
var _pistol: int = 0
var _setup_stage: int = 0
var _log: Array[String] = []
var _demo: bool = false
var _demo_quit_s: float = -1.0
var _demo_t: float = 0.0
var _demo_next: int = 0
## [time in seconds, action name]
var _demo_script: Array = [
	[2.0, "fire"], [2.4, "fire"], [2.8, "fire"], [3.2, "fire"], [3.6, "fire"],
	[5.0, "reload_tactical"],
	[7.5, "fire"], [7.8, "fire"], [8.1, "fire"], [8.4, "fire"], [8.7, "fire"], [9.0, "fire"], [9.3, "fire"],
	[9.6, "fire"], [9.9, "fire"], [10.2, "fire"], [10.5, "fire"], [10.8, "fire"], [11.1, "fire"], [11.4, "fire"],
	[11.7, "fire"], [12.0, "fire"],
	[13.0, "reload_emergency"], [15.5, "fire"], [15.8, "fire"], [16.1, "fire"],
]


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--demo":
			_demo = true
		elif arg.begins_with("--demo-quit="):
			_demo_quit_s = float(arg.trim_prefix("--demo-quit="))


func _process(delta: float) -> void:
	var sim: SimRoot = _host.sim()
	_advance_setup(sim)
	if _demo:
		_demo_t += delta
		while _demo_next < _demo_script.size():
			var step: Array = _demo_script[_demo_next]
			var at: float = step[0]
			if _demo_t < at:
				break
			var action: String = step[1]
			_perform(action)
			_demo_next += 1
		if _demo_quit_s > 0.0 and _demo_t >= _demo_quit_s:
			get_tree().quit()
			return
	_render(sim)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action("range_fire"):
		_perform("fire")
	elif event.is_action("range_reload_tactical"):
		_perform("reload_tactical")
	elif event.is_action("range_reload_emergency"):
		_perform("reload_emergency")
	elif event.is_action("range_load_round"):
		_perform("load_round")
	elif event.is_action("range_wield"):
		_perform("wield")


## Spawns the range over the first ticks. Ids come from the sim, not from assumptions:
## each stage reads back what the previous stage's commands produced.
func _advance_setup(sim: SimRoot) -> void:
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var items: ItemSystem = SimAssembly.items_of(sim)
	match _setup_stage:
		0:
			_submit(sim, &"actor.spawn", {"profile": String(PROFILE), "range_m": 0})
			_submit(sim, &"actor.spawn", {"profile": String(DUMMY_PROFILE), "range_m": DUMMY_RANGE_M})
			_setup_stage = 1
		1:
			var ids: Array[int] = actors.actor_ids()
			if ids.size() < 2:
				return
			_player = ids[0]
			_dummy = ids[1]
			var inv: String = String(ItemSystem.inventory_of(_player))
			_submit(sim, &"item.spawn", {"kind": "weapon_frame", "template": "g19", "container": inv, "seed": 1, "count": 1})
			_submit(sim, &"item.spawn", {"kind": "weapon_part", "template": "g19_barrel", "container": inv, "seed": 2, "count": 1})
			_submit(sim, &"item.spawn", {"kind": "weapon_part", "template": "g19_slide", "container": inv, "seed": 3, "count": 1})
			_submit(sim, &"item.spawn", {"kind": "weapon_part", "template": "g19_mag_15", "container": inv, "seed": 4, "count": 2})
			_submit(sim, &"item.spawn", {"kind": "ammo", "template": "9x19_fmj", "container": inv, "seed": 100, "count": LOOSE_ROUNDS})
			_setup_stage = 2
		2:
			var inventory: Array[int] = items.items_in(ItemSystem.inventory_of(_player))
			if inventory.size() < 5 + LOOSE_ROUNDS:
				return
			_pistol = _first_of(items, inventory, &"weapon_frame", &"g19")
			var mags: Array[int] = _all_of(items, inventory, &"weapon_part", &"g19_mag_15")
			var rounds: Array[int] = _all_of(items, inventory, &"ammo", &"9x19_fmj")
			_submit(sim, &"actor.wield", {"actor": _player, "weapon": _pistol})
			_submit(sim, &"weapon.attach", {"actor": _player, "weapon": _pistol, "part": _first_of(items, inventory, &"weapon_part", &"g19_barrel")})
			_submit(sim, &"weapon.attach", {"actor": _player, "weapon": _pistol, "part": _first_of(items, inventory, &"weapon_part", &"g19_slide")})
			for i: int in range(ROUNDS_PER_MAG):
				_submit(sim, &"magazine.load", {"actor": _player, "magazine": mags[0], "round": rounds[i]})
			for i: int in range(ROUNDS_PER_MAG, LOOSE_ROUNDS):
				_submit(sim, &"magazine.load", {"actor": _player, "magazine": mags[1], "round": rounds[i]})
			_setup_stage = 3
		3:
			if items.rounds_in(_loose_mags(items)[0]).size() < ROUNDS_PER_MAG:
				return
			_submit(sim, &"weapon.reload_tactical", {"actor": _player, "weapon": _pistol, "magazine": _loose_mags(items)[0]})
			_setup_stage = 4
			_note("range ready: player %d, dummy %d at %d m, pistol %d" % [_player, _dummy, DUMMY_RANGE_M, _pistol])
		_:
			pass


func _perform(action: String) -> void:
	if _setup_stage < 4:
		return
	var sim: SimRoot = _host.sim()
	var items: ItemSystem = SimAssembly.items_of(sim)
	match action:
		"fire":
			_submit(sim, &"weapon.fire", {"actor": _player, "target": _dummy})
		"reload_tactical", "reload_emergency":
			var mags: Array[int] = _loose_mags(items)
			if mags.is_empty():
				_note("no loose magazine to reload with")
				return
			var best: int = mags[0]
			for m: int in mags:
				if items.rounds_in(m).size() > items.rounds_in(best).size():
					best = m
			_submit(sim, StringName("weapon." + action), {"actor": _player, "weapon": _pistol, "magazine": best})
		"load_round":
			var mags: Array[int] = _loose_mags(items)
			var rounds: Array[int] = _all_of(items, items.items_in(ItemSystem.inventory_of(_player)), &"ammo", &"9x19_fmj")
			if mags.is_empty() or rounds.is_empty():
				_note("nothing to load")
				return
			_submit(sim, &"magazine.load", {"actor": _player, "magazine": mags[0], "round": rounds[0]})
		"wield":
			var actors: ActorSystem = SimAssembly.actors_of(sim)
			var weapon: int = 0 if actors.wielded(_player) == _pistol else _pistol
			_submit(sim, &"actor.wield", {"actor": _player, "weapon": weapon})
		_:
			_note("unknown action " + action)


func _submit(sim: SimRoot, kind: StringName, payload: Dictionary) -> void:
	var err: Error = sim.submit(SimCommand.new(sim.get_tick() + 1, kind, payload))
	if err != OK:
		_note("submit %s failed: %s" % [kind, error_string(err)])


func _note(text: String) -> void:
	_log.append("t%d %s" % [_host.sim().get_tick(), text])
	if _log.size() > 6:
		_log.pop_front()


func _loose_mags(items: ItemSystem) -> Array[int]:
	return _all_of(items, items.items_in(ItemSystem.inventory_of(_player)), &"weapon_part", &"g19_mag_15")


static func _first_of(items: ItemSystem, ids: Array[int], kind: StringName, template: StringName) -> int:
	for id: int in ids:
		if items.item_kind(id) == kind and items.item_template(id) == template:
			return id
	return 0


static func _all_of(items: ItemSystem, ids: Array[int], kind: StringName, template: StringName) -> Array[int]:
	var out: Array[int] = []
	for id: int in ids:
		if items.item_kind(id) == kind and items.item_template(id) == template:
			out.append(id)
	return out


func _render(sim: SimRoot) -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Gcity M1 range    seed %d   tick %d   state %s" % [sim.get_seed(), sim.get_tick(), sim.state_hash().left(16)])
	lines.append("content %d entries %s    dispatched %d   rejected %d" % [
		_host.content().count(), _host.content().digest().left(12), sim.dispatched_count(), sim.rejected_count()])
	lines.append("")
	if _setup_stage < 4:
		lines.append("setting up the range (stage %d)..." % _setup_stage)
		_status.text = "\n".join(lines)
		return
	var stats: StatResolver = SimAssembly.stats_of(sim)
	var items: ItemSystem = SimAssembly.items_of(sim)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var combat: CombatSystem = SimAssembly.combat_of(sim)
	var mag: int = items.magazine_of(_pistol)
	var chambered: int = items.chambered(_pistol)
	var wielded: bool = actors.wielded(_player) == _pistol
	lines.append("PLAYER %d   health %s   wielding %s" % [_player, _hp(actors, _player), "g19 #%d" % _pistol if wielded else "nothing"])
	lines.append("DUMMY  %d   health %s   %s   at %d m" % [_dummy, _hp(actors, _dummy), "alive" if actors.is_alive(_dummy) else "DOWN", DUMMY_RANGE_M])
	lines.append("")
	lines.append("g19 #%d   chamber: %s   magazine: %s   %s" % [
		_pistol, "round #%d" % chambered if chambered != 0 else "EMPTY",
		"#%d %d/%d" % [mag, items.rounds_in(mag).size(), items.capacity_of(ItemSystem.magazine_container(mag))] if mag != 0 else "none",
		"busy until t%d" % items.busy_until(_pistol) if items.is_busy(_pistol, sim.get_tick()) else "ready"])
	lines.append("  hit chance %s at %d m (base %s)   damage/round %s   recoil %s   ergonomics %s   sway %s" % [
		_pct(combat.hit_chance_at(_player, _pistol, DUMMY_RANGE_M)), DUMMY_RANGE_M, _pct(stats.resolve(_pistol, &"hit_chance")),
		_milli(stats.resolve(chambered, &"damage")) if chambered != 0 else "-",
		_milli(stats.resolve(_pistol, &"recoil")), _milli(stats.resolve(_pistol, &"ergonomics")), _milli(stats.resolve(_pistol, &"sway"))])
	lines.append("  reload %d ticks   cycle %d ticks   aim-in %d ticks" % [
		stats.resolve(_pistol, &"reload_ticks") / 1000, stats.resolve(_pistol, &"cycle_ticks") / 1000, stats.resolve(_pistol, &"aim_in_ticks") / 1000])
	var loose: Array[int] = _loose_mags(items)
	var loose_text: PackedStringArray = PackedStringArray()
	for m: int in loose:
		loose_text.append("#%d %d/%d" % [m, items.rounds_in(m).size(), ROUNDS_PER_MAG])
	lines.append("  loose magazines: %s   loose rounds: %d   dropped in world: %d items" % [
		", ".join(loose_text) if not loose_text.is_empty() else "none",
		_all_of(items, items.items_in(ItemSystem.inventory_of(_player)), &"ammo", &"9x19_fmj").size(), items.items_in(&"world").size()])
	lines.append("")
	var last: Dictionary = combat.last_shot()
	lines.append("SHOTS %d   hits %d   kills %d" % [combat.shots(), combat.hits(), combat.kills()])
	if not last.is_empty():
		var hit: bool = last["hit"]
		var chance: int = last["chance"]
		var damage: int = last["damage"]
		lines.append("  last shot t%d: rolled against %s -> %s%s" % [last["tick"], _pct(chance),
			"HIT %s for %s" % [last["node"], _milli(damage)] if hit else "miss", "  (kill)" if last["killed"] else ""])
	lines.append("")
	lines.append("[Space / A] fire   [R / X] tactical reload   [E / Y] emergency reload   [L / B] load a round   [W / LB] wield")
	if _demo:
		lines.append("DEMO %.1fs  step %d/%d" % [_demo_t, _demo_next, _demo_script.size()])
	for entry: String in _log:
		lines.append(entry)
	_status.text = "\n".join(lines)


static func _hp(actors: ActorSystem, actor: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var health: Dictionary = actors.health_of(actor)
	var keys: Array = health.keys()
	keys.sort()
	for k: Variant in keys:
		var node: StringName = k
		var hp: int = health[node]
		parts.append("%s %s/%s" % [node, _milli(hp), _milli(actors.max_health(actor, node))])
	return ", ".join(parts)


static func _pct(basis: int) -> String:
	return "%.1f%%" % (basis / 10000.0)


static func _milli(value: int) -> String:
	return "%.1f" % (value / 1000.0)
