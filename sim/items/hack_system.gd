## Hacking (M6 spec claim 12; ADR-011; design doc §15.2): timed, stationary device
## actions. A site places named terminals (its `terminals` entries: a cell, the work a
## hack takes, the device tag it requires, the noise it makes, the item it yields,
## the ticks a logout takes); each is an entity a command names.
##
## `hack.start {actor, terminal}`, `hack.spoof {actor, sensor}` and `hack.logout
## {actor, terminal}` start one action per actor, beside the target. A hack or a spoof
## needs a device equipped whose modules provide the required tag (the terminal's
## `requires`, the sensor's `spoof_requires`), and is a `loot`
## offence where that right is denied. Each tick a hack or a spoof does the device's
## resolved `memory_capacity` of work; a logout does 1 000 a tick. An action stops,
## keeping nothing, on a step, a shot, a hit, a death, or the device losing the tag.
## A hack is heard at its start and every second (`noise.made`, the terminal's noise);
## a spoof and a logout are quiet. At the end a hack yields its item into the
## hacker's inventory, emits `hack.completed {actor, terminal, name}` and leaves the
## terminal logged in by the hacker, a trace, until that hacker's logout emits
## `hack.logout {actor, terminal, name}`; a spoof keeps its sensor quiet for the
## sensor's `spoof_ticks` and emits `hack.spoofed {actor, sensor}`. A terminal is
## hacked once.
class_name HackSystem extends SimSystem

const SYSTEM_ID: StringName = &"hacks"
const COMMAND_START: StringName = &"hack.start"
const COMMAND_LOGOUT: StringName = &"hack.logout"
const COMMAND_SPOOF: StringName = &"hack.spoof"
const EVENT_COMPLETED: StringName = &"hack.completed"
const EVENT_LOGOUT: StringName = &"hack.logout"
const EVENT_SPOOFED: StringName = &"hack.spoofed"
const STAT_MEMORY: StringName = &"memory_capacity"
const KIND_HACK: String = "hack"
const KIND_LOGOUT: String = "logout"
const KIND_SPOOF: String = "spoof"
const LOGOUT_WORK_PER_TICK: int = 1000
const NOISE_EVERY_TICKS: int = SimRoot.TICK_HZ

var _content: ContentDb
var _stats: StatResolver
var _ids: EntityIds
var _items: ItemSystem
var _actors: ActorSystem
var _land: LandSystem
var _sensors: SensorSystem
var _events: EventBus
## The sim this system is registered with, held weakly: the root holds this system,
## so a strong reference back would be a cycle and neither would ever be freed.
var _sim_ref: WeakRef
## terminal id -> {"site": String, "name": String, "hacked": bool, "logged_in_by": int}
var _terminals: Dictionary = {}
## actor -> {"kind": String, "target": int, "pos": [x, y, z], "done": int, "total": int, "ticks": int}
var _actions: Dictionary = {}
var _completed: int = 0


func _init(content: ContentDb, stats: StatResolver, ids: EntityIds, items: ItemSystem, actors: ActorSystem, land: LandSystem, sensors: SensorSystem, events: EventBus) -> void:
	_content = content
	_stats = stats
	_ids = ids
	_items = items
	_actors = actors
	_land = land
	_sensors = sensors
	_events = events


## The tick the sim is on.
func _now() -> int:
	var ref: Object = _sim_ref.get_ref()
	var sim: SimRoot = ref as SimRoot
	assert(sim != null, "a system outlived its sim")
	return sim.get_tick()


func system_id() -> StringName:
	return SYSTEM_ID


func snapshot() -> Dictionary:
	return {"terminals": _terminals.duplicate(true), "actions": _actions.duplicate(true), "completed": _completed}


func attach(sim: SimRoot) -> Error:
	_sim_ref = weakref(sim)
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	for pair: Array in [[COMMAND_START, _on_start], [COMMAND_LOGOUT, _on_logout], [COMMAND_SPOOF, _on_spoof]]:
		var kind: StringName = pair[0]
		var handler: Callable = pair[1]
		err = sim.commands().register(kind, handler)
		if err != OK:
			return err
	err = _events.subscribe(CombatSystem.EVENT_FIRE, _on_fire)
	if err != OK:
		return err
	return _events.subscribe(CombatSystem.EVENT_HIT, _on_hit)


# ---------------------------------------------------------------- placing

## Whether a site's terminal entry can be honoured: work and logout ticks positive, a
## required tag, and an item it yields that can be spawned.
func entry_is_valid(entry: Dictionary) -> bool:
	var work: int = entry["hack_work"]
	var logout: int = entry["logout_ticks"]
	var requires: String = entry["requires"]
	var yields: Dictionary = entry["yields"]
	var kind_s: String = yields["kind"]
	var template_s: String = yields["template"]
	return work > 0 and logout > 0 and not requires.is_empty() and ItemSystem.SPAWNABLE.has(StringName(kind_s)) \
		and _content.has(StringName(kind_s), StringName(template_s))


## Places a site's terminal. Returns its id.
func install(site: StringName, name: StringName) -> int:
	var id: int = _ids.allocate()
	_terminals[id] = {"site": String(site), "name": String(name), "hacked": false, "logged_in_by": EntityIds.NONE}
	return id


## The site entry behind a terminal (validated at assembly), or {}.
func _entry(terminal: int) -> Dictionary:
	if not _terminals.has(terminal):
		return {}
	var rec: Dictionary = _terminals[terminal]
	var site_s: String = rec["site"]
	var name_s: String = rec["name"]
	if not _content.has(SiteSystem.KIND_SITE, StringName(site_s)):
		return {}
	var t: Dictionary = _content.get_entry(SiteSystem.KIND_SITE, StringName(site_s))
	var terminals: Array = t.get("terminals", [])
	for e: Variant in terminals:
		var ed: Dictionary = e
		if ed["name"] == name_s:
			return ed
	return {}


func _terminal_cell(terminal: int) -> Vector3i:
	var rec: Dictionary = _terminals[terminal]
	var site_s: String = rec["site"]
	var t: Dictionary = _content.get_entry(SiteSystem.KIND_SITE, StringName(site_s))
	return SiteSystem._cell(t["origin"]) + SiteSystem._cell(_entry(terminal)["cell"])


# ---------------------------------------------------------------- queries

func terminal_ids() -> Array[int]:
	var out: Array[int] = []
	for key: Variant in _terminals:
		var id: int = key
		out.append(id)
	out.sort()
	return out


func terminal_name(terminal: int) -> StringName:
	if not _terminals.has(terminal):
		return &""
	var rec: Dictionary = _terminals[terminal]
	var name_s: String = rec["name"]
	return StringName(name_s)


func terminal_position(terminal: int) -> Vector3i:
	var c: Vector3i = _terminal_cell(terminal)
	return Vector3i(c.x * BuildSystem.CELL + BuildSystem.CELL / 2, c.y * BuildSystem.CELL, c.z * BuildSystem.CELL + BuildSystem.CELL / 2)


## How far a hack at this terminal is heard, in millimetres.
func terminal_noise_mm(terminal: int) -> int:
	var entry: Dictionary = _entry(terminal)
	if entry.is_empty():
		return 0
	return entry["noise_mm"]


func is_hacked(terminal: int) -> bool:
	if not _terminals.has(terminal):
		return false
	var rec: Dictionary = _terminals[terminal]
	return rec["hacked"]


func is_logged_in(terminal: int) -> bool:
	return logged_in_by(terminal) != EntityIds.NONE


func logged_in_by(terminal: int) -> int:
	if not _terminals.has(terminal):
		return EntityIds.NONE
	var rec: Dictionary = _terminals[terminal]
	return rec["logged_in_by"]


func is_hacking(actor: int) -> bool:
	return _actions.has(actor)


## "hack", "logout", "spoof" or "" for an actor's action.
func action_kind(actor: int) -> String:
	if not _actions.has(actor):
		return ""
	var rec: Dictionary = _actions[actor]
	return rec["kind"]


func action_target(actor: int) -> int:
	if not _actions.has(actor):
		return EntityIds.NONE
	var rec: Dictionary = _actions[actor]
	return rec["target"]


## [work done, work in all] of an actor's action, or [].
func progress_of(actor: int) -> Array[int]:
	var out: Array[int] = []
	if not _actions.has(actor):
		return out
	var rec: Dictionary = _actions[actor]
	var done: int = rec["done"]
	var total: int = rec["total"]
	out.append(done)
	out.append(total)
	return out


func completed_count() -> int:
	return _completed


## Whether an actor's device provides a tag: its equipped device's modules' `provides`.
func device_provides(actor: int, tag: StringName) -> bool:
	var device: int = _actors.device_of(actor)
	return device != EntityIds.NONE and _items.provides_of(device).has(tag)


## A hack or spoof's work a tick: the device's resolved memory, at least 1.
func work_rate(actor: int) -> int:
	var device: int = _actors.device_of(actor)
	if device == EntityIds.NONE:
		return 0
	return maxi(1, _stats.resolve(device, STAT_MEMORY))


static func _beside(a: Vector3i, b: Vector3i) -> bool:
	var d: Vector3i = a - b
	return absi(d.x) + absi(d.y) + absi(d.z) <= 1


# ---------------------------------------------------------------- starting

func start_hack(actor: int, terminal: int) -> bool:
	if not _can_act(actor) or not _terminals.has(terminal) or is_hacked(terminal):
		return false
	var entry: Dictionary = _entry(terminal)
	var requires: String = entry["requires"]
	var cell: Vector3i = _terminal_cell(terminal)
	if not device_provides(actor, StringName(requires)) or not _beside(BuildSystem.cell_of(_actors.position_of(actor)), cell):
		return false
	_land.offend(BuildSystem.cell_centre(cell), actor, &"loot")
	var work: int = entry["hack_work"]
	_begin(actor, KIND_HACK, terminal, work)
	return true


func start_logout(actor: int, terminal: int) -> bool:
	if not _can_act(actor) or logged_in_by(terminal) != actor:
		return false
	if not _beside(BuildSystem.cell_of(_actors.position_of(actor)), _terminal_cell(terminal)):
		return false
	var logout: int = _entry(terminal)["logout_ticks"]
	_begin(actor, KIND_LOGOUT, terminal, logout * LOGOUT_WORK_PER_TICK)
	return true


func start_spoof(actor: int, sensor: int) -> bool:
	if not _can_act(actor) or not _sensors.is_spoofable(sensor):
		return false
	var t: Dictionary = _content.get_entry(SensorSystem.KIND_SENSOR, _sensors.profile_of(sensor))
	var here: Vector3i = BuildSystem.cell_of(_actors.position_of(actor))
	var near: bool = false
	for c: Vector3i in _sensors.cells_of(sensor):
		near = near or _beside(here, c)
	var requires: String = t["spoof_requires"]
	if not near or not device_provides(actor, StringName(requires)):
		return false
	_land.offend(BuildSystem.cell_centre(_sensors.cells_of(sensor)[0]), actor, &"loot")
	var work: int = t["spoof_work"]
	_begin(actor, KIND_SPOOF, sensor, work)
	return true


func _can_act(actor: int) -> bool:
	return _actors.is_alive(actor) and not _actions.has(actor)


func _begin(actor: int, kind: String, target: int, total: int) -> void:
	var pos: Vector3i = _actors.position_of(actor)
	_actions[actor] = {"kind": kind, "target": target, "pos": [pos.x, pos.y, pos.z] as Array[int], "done": 0, "total": total, "ticks": 0}


## {"actor": int, "terminal": int}
func _on_start(_sim_root: SimRoot, payload: Dictionary) -> bool:
	if not _ints(payload, ["actor", "terminal"]):
		return false
	var actor: int = payload["actor"]
	var terminal: int = payload["terminal"]
	return start_hack(actor, terminal)


## {"actor": int, "terminal": int}
func _on_logout(_sim_root: SimRoot, payload: Dictionary) -> bool:
	if not _ints(payload, ["actor", "terminal"]):
		return false
	var actor: int = payload["actor"]
	var terminal: int = payload["terminal"]
	return start_logout(actor, terminal)


## {"actor": int, "sensor": int}
func _on_spoof(_sim_root: SimRoot, payload: Dictionary) -> bool:
	if not _ints(payload, ["actor", "sensor"]):
		return false
	var actor: int = payload["actor"]
	var sensor: int = payload["sensor"]
	return start_spoof(actor, sensor)


static func _ints(payload: Dictionary, keys: Array[String]) -> bool:
	if payload.size() != keys.size():
		return false
	for k: String in keys:
		if typeof(payload.get(k)) != TYPE_INT:
			return false
	return true


# ---------------------------------------------------------------- the tick

func tick(_sim_root: SimRoot) -> void:
	var actors: Array[int] = []
	for key: Variant in _actions:
		var id: int = key
		actors.append(id)
	actors.sort()
	for actor: int in actors:
		if _actions.has(actor):
			_advance(actor)


func _advance(actor: int) -> void:
	var rec: Dictionary = _actions[actor]
	var kind: String = rec["kind"]
	var target: int = rec["target"]
	var pos: Array = rec["pos"]
	var x: int = pos[0]
	var y: int = pos[1]
	var z: int = pos[2]
	if not _actors.is_alive(actor) or _actors.position_of(actor) != Vector3i(x, y, z):
		_actions.erase(actor)
		return
	if kind != KIND_LOGOUT and not device_provides(actor, _required_tag(kind, target)):
		_actions.erase(actor)
		return
	var ticks: int = rec["ticks"]
	if kind == KIND_HACK and ticks % NOISE_EVERY_TICKS == 0:
		var here: Vector3i = _actors.position_of(actor)
		var noise: int = _entry(target)["noise_mm"]
		_events.emit(BreachSystem.EVENT_NOISE, {"source": actor, "x": here.x, "y": here.y, "z": here.z, "range_mm": noise})
	rec["ticks"] = ticks + 1
	var done: int = rec["done"]
	var total: int = rec["total"]
	done = mini(total, done + (LOGOUT_WORK_PER_TICK if kind == KIND_LOGOUT else work_rate(actor)))
	rec["done"] = done
	if done < total:
		return
	_actions.erase(actor)
	_completed += 1
	match kind:
		KIND_HACK:
			var term: Dictionary = _terminals[target]
			term["hacked"] = true
			term["logged_in_by"] = actor
			var yields: Dictionary = _entry(target)["yields"]
			var kind_s: String = yields["kind"]
			var template_s: String = yields["template"]
			var item: int = _items.spawn(StringName(kind_s), StringName(template_s), ItemSystem.inventory_of(actor), target)
			assert(item != EntityIds.NONE, "terminal yields were validated at assembly")
			_events.emit(EVENT_COMPLETED, {"actor": actor, "terminal": target, "name": terminal_name(target)})
		KIND_LOGOUT:
			var term: Dictionary = _terminals[target]
			term["logged_in_by"] = EntityIds.NONE
			_events.emit(EVENT_LOGOUT, {"actor": actor, "terminal": target, "name": terminal_name(target)})
		_:
			var t: Dictionary = _content.get_entry(SensorSystem.KIND_SENSOR, _sensors.profile_of(target))
			var quiet: int = t["spoof_ticks"]
			_sensors.spoof(target, _now() + quiet)
			_events.emit(EVENT_SPOOFED, {"actor": actor, "sensor": target})


func _required_tag(kind: String, target: int) -> StringName:
	if kind == KIND_SPOOF:
		var t: Dictionary = _content.get_entry(SensorSystem.KIND_SENSOR, _sensors.profile_of(target))
		var spoof_requires: String = t["spoof_requires"]
		return StringName(spoof_requires)
	var requires: String = _entry(target)["requires"]
	return StringName(requires)


func _on_fire(payload: Dictionary) -> void:
	var v: Variant = payload.get("shooter")
	if typeof(v) == TYPE_INT:
		var shooter: int = v
		_actions.erase(shooter)


func _on_hit(payload: Dictionary) -> void:
	var v: Variant = payload.get("target")
	if typeof(v) == TYPE_INT:
		var target: int = v
		_actions.erase(target)


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 3 or typeof(state.get("terminals")) != TYPE_DICTIONARY or typeof(state.get("actions")) != TYPE_DICTIONARY \
			or typeof(state.get("completed")) != TYPE_INT:
		return _restore_fail("shape")
	var completed: int = state["completed"]
	if completed < 0:
		return _restore_fail("negative count")
	var terms_in: Dictionary = state["terminals"]
	var terminals: Dictionary = {}
	for key: Variant in terms_in:
		if typeof(key) != TYPE_INT or typeof(terms_in[key]) != TYPE_DICTIONARY:
			return _restore_fail("terminal key")
		var id: int = key
		var rec: Dictionary = terms_in[key]
		if rec.size() != 4 or typeof(rec.get("site")) != TYPE_STRING or typeof(rec.get("name")) != TYPE_STRING \
				or typeof(rec.get("hacked")) != TYPE_BOOL or typeof(rec.get("logged_in_by")) != TYPE_INT:
			return _restore_fail("terminal %d fields" % id)
		var site_s: String = rec["site"]
		var name_s: String = rec["name"]
		var hacked: bool = rec["hacked"]
		var by: int = rec["logged_in_by"]
		terminals[id] = {"site": site_s, "name": name_s, "hacked": hacked, "logged_in_by": by}
	var saved: Dictionary = _terminals
	_terminals = terminals
	for id: int in terminal_ids():
		var rec: Dictionary = _terminals[id]
		var by: int = rec["logged_in_by"]
		var hacked: bool = rec["hacked"]
		if _entry(id).is_empty() or (by != EntityIds.NONE and (not hacked or not _actors.has_actor(by))):
			_terminals = saved
			return _restore_fail("terminal %d" % id)
	var acts_in: Dictionary = state["actions"]
	var actions: Dictionary = {}
	for key: Variant in acts_in:
		if typeof(key) != TYPE_INT or typeof(acts_in[key]) != TYPE_DICTIONARY:
			_terminals = saved
			return _restore_fail("action key")
		var actor: int = key
		var rec: Dictionary = acts_in[key]
		if rec.size() != 6 or typeof(rec.get("kind")) != TYPE_STRING or typeof(rec.get("target")) != TYPE_INT or typeof(rec.get("pos")) != TYPE_ARRAY \
				or typeof(rec.get("done")) != TYPE_INT or typeof(rec.get("total")) != TYPE_INT or typeof(rec.get("ticks")) != TYPE_INT:
			_terminals = saved
			return _restore_fail("action %d fields" % actor)
		var kind: String = rec["kind"]
		var target: int = rec["target"]
		var done: int = rec["done"]
		var total: int = rec["total"]
		var ticks: int = rec["ticks"]
		var pos: Array = rec["pos"]
		var target_ok: bool = _sensors.is_spoofable(target) if kind == KIND_SPOOF else _terminals.has(target)
		if not [KIND_HACK, KIND_LOGOUT, KIND_SPOOF].has(kind) or not target_ok or not _actors.has_actor(actor) \
				or done < 0 or total < 1 or done >= total or ticks < 0 or pos.size() != 3:
			_terminals = saved
			return _restore_fail("action %d values" % actor)
		for v: Variant in pos:
			if typeof(v) != TYPE_INT:
				_terminals = saved
				return _restore_fail("action %d position" % actor)
		var px: int = pos[0]
		var py: int = pos[1]
		var pz: int = pos[2]
		actions[actor] = {"kind": kind, "target": target, "pos": [px, py, pz] as Array[int], "done": done, "total": total, "ticks": ticks}
	_actions = actions
	_completed = completed
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("HackSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
