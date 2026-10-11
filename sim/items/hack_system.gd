## The hack (design doc §12.2, §15.2; M6 spec claim 9): a timed task on the carried
## device. A hack target is content (`hack_target`: ticks, daemons, noise, reach_mm and
## an effect of a registered kind); a placed target is an instance at a cell, optionally
## tied to a piece its effect acts on. `hack.start` needs a device providing
## `daemon_coprocessor` with free daemon slots for the target's cost, and the actor
## within reach on the target's storey. The hack runs one tick per tick, makes the
## target's noise every NOISE_EVERY ticks, and is called off when the actor moves, fires,
## is hurt, dies or loses its footing, or by `hack.cancel`. On completion the effect is
## applied, `hack.completed {actor, target, applied}` is emitted, and the terminal stays
## logged in, its daemons in use, until `hack.logout` (pause-safe). A device that can no
## longer hold what runs on it drops the running hack, then the newest logins.
class_name HackSystem extends SimSystem

const SYSTEM_ID: StringName = &"hacks"
const KIND_TARGET: StringName = &"hack_target"
const COMMAND_START: StringName = &"hack.start"
const COMMAND_CANCEL: StringName = &"hack.cancel"
const COMMAND_LOGOUT: StringName = &"hack.logout"
const EVENT_COMPLETED: StringName = &"hack.completed"
const PROVIDES: StringName = &"daemon_coprocessor"
const STAT_MEMORY: StringName = &"memory_capacity"
const MEMORY_PER_SLOT: int = 1000
const NOISE_EVERY: int = 40
const EFFECT_SPAWN_ITEM: StringName = &"spawn_item"

var _content: ContentDb
var _stats: StatResolver
var _items: ItemSystem
var _actors: ActorSystem
var _build: BuildSystem
var _events: EventBus
## actor -> bool: may it work a device this tick (the movement system); unset, nobody can
var _footing: Callable = Callable()
## effect kind -> {"check": Callable(params) -> bool, "apply": Callable(actor, params, piece) -> bool}
var _effects: Dictionary = {}
## instance id -> {"target": StringName, "cell": [x, y, z], "piece": int, "done": bool}
var _targets: Dictionary = {}
## actor -> {"target": int, "ticks": int left, "pos": [x, y, z] mm, "health": int}
var _running: Dictionary = {}
## actor -> [instance ids logged in, oldest first]
var _logins: Dictionary = {}
var _next: int = 1
var _completed: int = 0


func _init(content: ContentDb, stats: StatResolver, items: ItemSystem, actors: ActorSystem, build: BuildSystem, events: EventBus) -> void:
	_content = content
	_stats = stats
	_items = items
	_actors = actors
	_build = build
	_events = events
	register_effect(EFFECT_SPAWN_ITEM, _check_spawn_item, _apply_spawn_item)


func system_id() -> StringName:
	return SYSTEM_ID


func set_footing_check(check: Callable) -> void:
	_footing = check


## Registers an effect kind (invariant 3): `check(params) -> bool` vets a target's
## params at content validation, `apply(actor, params, piece) -> bool` runs on completion.
## Effects are registered before attach, which validates the content against them.
func register_effect(kind: StringName, check: Callable, apply: Callable) -> Error:
	if _effects.has(kind):
		push_error("HackSystem: effect '%s' is already registered" % kind)
		return ERR_ALREADY_EXISTS
	_effects[kind] = {"check": check, "apply": apply}
	return OK


func has_effect(kind: StringName) -> bool:
	return _effects.has(kind)


func attach(sim: SimRoot) -> Error:
	var err: Error = validate_content()
	if err != OK:
		return err
	err = sim.register_system(self)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_START, _on_start)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_CANCEL, _on_cancel)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_LOGOUT, _on_logout, true)
	if err != OK:
		return err
	return _events.subscribe(CombatSystem.EVENT_FIRE, _on_fire)


## Every target has a positive duration and cost, non-negative noise and reach, and an
## effect of a registered kind whose params that kind accepts.
func validate_content() -> Error:
	for id: StringName in _content.ids(KIND_TARGET):
		var t: Dictionary = _content.get_entry(KIND_TARGET, id)
		for key: String in ["ticks", "daemons", "noise", "reach_mm"]:
			if typeof(t.get(key)) != TYPE_INT:
				return _content_fail("hack_target/%s needs an integer %s" % [id, key])
		var ticks: int = t["ticks"]
		var daemons: int = t["daemons"]
		var noise: int = t["noise"]
		var reach: int = t["reach_mm"]
		if ticks < 1 or daemons < 1 or noise < 0 or reach < 0:
			return _content_fail("hack_target/%s has an out-of-range number" % id)
		var effect_v: Variant = t.get("effect")
		if typeof(effect_v) != TYPE_DICTIONARY:
			return _content_fail("hack_target/%s needs an effect" % id)
		var effect: Dictionary = effect_v
		var kind_v: Variant = effect.get("kind")
		var params_v: Variant = effect.get("params")
		if typeof(kind_v) != TYPE_STRING or typeof(params_v) != TYPE_DICTIONARY:
			return _content_fail("hack_target/%s effect needs a kind and params" % id)
		var kind_s: String = kind_v
		var kind: StringName = StringName(kind_s)
		if not _effects.has(kind):
			return _content_fail("hack_target/%s uses unregistered effect '%s'" % [id, kind_s])
		var rec: Dictionary = _effects[kind]
		var check: Callable = rec["check"]
		var params: Dictionary = params_v
		var ok: bool = check.call(params)
		if not ok:
			return _content_fail("hack_target/%s effect '%s' rejects its params" % [id, kind_s])
	return OK


func _content_fail(reason: String) -> Error:
	push_error("HackSystem: content rejected: %s" % reason)
	return ERR_INVALID_DATA


# ---------------------------------------------------------------- tick

func tick(_sim: SimRoot) -> void:
	var actors: Array = _running.keys()
	actors.sort()
	for a: Variant in actors:
		var actor: int = a
		var rec: Dictionary = _running[actor]
		var pos: Array = rec["pos"]
		var px: int = pos[0]
		var py: int = pos[1]
		var pz: int = pos[2]
		var health: int = rec["health"]
		if not _actors.is_alive(actor) or not _footing.is_valid() or not _footing.call(actor) \
				or _actors.position_of(actor) != Vector3i(px, py, pz) or _health_total(actor) < health \
				or slots_in_use(actor) > capacity(actor):
			_running.erase(actor)
			continue
		var target: int = rec["target"]
		var t: Dictionary = _template(target)
		var total: int = t["ticks"]
		var ticks: int = rec["ticks"]
		if (total - ticks) % NOISE_EVERY == 0:
			var noise: int = t["noise"]
			_events.emit(PerceptionSystem.EVENT_NOISE, {"source": actor, "x": px, "y": py, "z": pz, "loudness": noise})
		ticks -= 1
		if ticks > 0:
			rec["ticks"] = ticks
			continue
		_running.erase(actor)
		_complete(actor, target)
	var holders: Array = _logins.keys()
	holders.sort()
	for a: Variant in holders:
		var actor: int = a
		var list: Array = _logins[actor]
		while not list.is_empty() and slots_in_use(actor) > capacity(actor):
			list.pop_back()
		if list.is_empty():
			_logins.erase(actor)


func _complete(actor: int, target: int) -> void:
	var rec: Dictionary = _targets[target]
	rec["done"] = true
	_completed += 1
	if not _logins.has(actor):
		_logins[actor] = [] as Array
	var list: Array = _logins[actor]
	list.append(target)
	var effect: Dictionary = _template(target)["effect"]
	var kind_s: String = effect["kind"]
	var params: Dictionary = effect["params"]
	var handler: Dictionary = _effects[StringName(kind_s)]
	var apply: Callable = handler["apply"]
	var piece: int = rec["piece"]
	var applied: bool = apply.call(actor, params, piece)
	_events.emit(EVENT_COMPLETED, {"actor": actor, "target": target, "applied": applied})


func _on_fire(payload: Dictionary) -> void:
	var shooter: int = payload["shooter"]
	_running.erase(shooter)


# ---------------------------------------------------------------- queries

## Places a target instance at a cell (sites at claim 12), tied to `piece` (NONE for
## none) for an effect that acts on one. Returns its id, or NONE for an unknown target
## or a piece that does not exist.
func place(target: StringName, cell: Vector3i, piece: int) -> int:
	if not _content.has(KIND_TARGET, target) or (piece != EntityIds.NONE and not _build.has_piece(piece)):
		return EntityIds.NONE
	var id: int = _next
	_next += 1
	_targets[id] = {"target": target, "cell": [cell.x, cell.y, cell.z] as Array[int], "piece": piece, "done": false}
	return id


func is_hacking(actor: int) -> bool:
	return _running.has(actor)


## Ticks left on the actor's running hack, or -1.
func ticks_left(actor: int) -> int:
	if not _running.has(actor):
		return -1
	var rec: Dictionary = _running[actor]
	return rec["ticks"]


func is_done(target: int) -> bool:
	if not _targets.has(target):
		return false
	var rec: Dictionary = _targets[target]
	return rec["done"]


## The actor logged in to a target, or NONE.
func login_of(target: int) -> int:
	var holders: Array = _logins.keys()
	holders.sort()
	for a: Variant in holders:
		var list: Array = _logins[a]
		if list.has(target):
			var actor: int = a
			return actor
	return EntityIds.NONE


## The targets within the actor's reach on its storey, by id: those a start would
## accept by place.
func targets_in_reach(actor: int) -> Array[int]:
	var out: Array[int] = []
	if not _actors.has_actor(actor):
		return out
	var ids: Array = _targets.keys()
	ids.sort()
	for v: Variant in ids:
		var id: int = v
		if _in_reach(actor, id):
			out.append(id)
	return out


## The target's content id, or &"" for an unknown id.
func target_name(target: int) -> StringName:
	if not _targets.has(target):
		return &""
	var rec: Dictionary = _targets[target]
	return rec["target"]


## The target's length in ticks, or -1 for an unknown id.
func target_ticks(target: int) -> int:
	if not _targets.has(target):
		return -1
	var ticks: int = _template(target)["ticks"]
	return ticks


## The target the actor's running hack works, or NONE.
func running_target(actor: int) -> int:
	if not _running.has(actor):
		return EntityIds.NONE
	var rec: Dictionary = _running[actor]
	return rec["target"]


## The targets the actor is logged in to, oldest first.
func logins_of(actor: int) -> Array[int]:
	var out: Array[int] = []
	if _logins.has(actor):
		var list: Array = _logins[actor]
		for v: Variant in list:
			var id: int = v
			out.append(id)
	return out


func completed_count() -> int:
	return _completed


## Daemon slots the actor's carried device offers: memory_capacity / 1000 when it
## provides the coprocessor, else none.
func capacity(actor: int) -> int:
	var device: int = _actors.device_of(actor)
	if device == EntityIds.NONE or not _items.provides_of(device).has(PROVIDES):
		return 0
	return maxi(0, _stats.resolve(device, STAT_MEMORY)) / MEMORY_PER_SLOT


## Daemons the running hack and the logged-in terminals hold.
func slots_in_use(actor: int) -> int:
	var used: int = 0
	if _running.has(actor):
		var rec: Dictionary = _running[actor]
		used += _daemons(rec["target"])
	if _logins.has(actor):
		var list: Array = _logins[actor]
		for v: Variant in list:
			used += _daemons(v)
	return used


func free_slots(actor: int) -> int:
	return maxi(0, capacity(actor) - slots_in_use(actor))


func _template(target: int) -> Dictionary:
	var rec: Dictionary = _targets[target]
	var name: StringName = rec["target"]
	return _content.get_entry(KIND_TARGET, name)


func _daemons(target: Variant) -> int:
	var id: int = target
	var t: Dictionary = _template(id)
	return t["daemons"]


func _health_total(actor: int) -> int:
	var total: int = 0
	var health: Dictionary = _actors.health_of(actor)
	for node: Variant in health:
		var v: int = health[node]
		total += v
	return total


func _running_target(target: int) -> bool:
	for a: Variant in _running:
		var rec: Dictionary = _running[a]
		var t: int = rec["target"]
		if t == target:
			return true
	return false


# ---------------------------------------------------------------- mutation

## Starts a hack: a living actor with its footing, not already hacking, at a target
## nobody has done or is running, within its reach on its storey, with the slots free.
func start(actor: int, target: int) -> bool:
	if not _actors.is_alive(actor) or _running.has(actor) or not _targets.has(target) or is_done(target) or _running_target(target):
		return false
	if not _footing.is_valid() or not _footing.call(actor):
		return false
	var t: Dictionary = _template(target)
	var daemons: int = t["daemons"]
	if free_slots(actor) < daemons:
		return false
	if not _in_reach(actor, target):
		return false
	var pos: Vector3i = _actors.position_of(actor)
	var ticks: int = t["ticks"]
	_running[actor] = {"target": target, "ticks": ticks, "pos": [pos.x, pos.y, pos.z] as Array[int], "health": _health_total(actor)}
	return true


func _in_reach(actor: int, target: int) -> bool:
	var rec: Dictionary = _targets[target]
	var c: Array[int] = rec["cell"]
	var cell: Vector3i = Vector3i(c[0], c[1], c[2])
	var pos: Vector3i = _actors.position_of(actor)
	if BuildSystem.cell_of(pos).y != cell.y:
		return false
	var at: Vector3i = BuildSystem.cell_centre(cell)
	var dx: int = pos.x - at.x
	var dz: int = pos.z - at.z
	var reach: int = _template(target)["reach_mm"]
	return dx * dx + dz * dz <= reach * reach


func cancel(actor: int) -> bool:
	return _running.erase(actor)


func logout(actor: int, target: int) -> bool:
	if not _logins.has(actor):
		return false
	var list: Array = _logins[actor]
	if not list.has(target):
		return false
	list.erase(target)
	if list.is_empty():
		_logins.erase(actor)
	return true


# ---------------------------------------------------------------- effects

## spawn_item {template}: one item of the template into the hacker's inventory. The
## template names exactly one spawnable kind's entry.
func _check_spawn_item(params: Dictionary) -> bool:
	if params.size() != 1 or typeof(params.get("template")) != TYPE_STRING:
		return false
	return _spawn_kind(params) != &""


func _apply_spawn_item(actor: int, params: Dictionary, _piece: int) -> bool:
	var template: String = params["template"]
	var seed: int = _completed  # the completion's ordinal: deterministic, no rng draw
	return _items.spawn(_spawn_kind(params), StringName(template), ItemSystem.inventory_of(actor), seed) != EntityIds.NONE


func _spawn_kind(params: Dictionary) -> StringName:
	var template: String = params["template"]
	return spawnable_kind(_content, StringName(template))


## The one spawnable kind with a template of this id, or &"" for none or several.
static func spawnable_kind(content: ContentDb, template: StringName) -> StringName:
	var found: StringName = &""
	for kind: StringName in ItemSystem.SPAWNABLE:
		if content.has(kind, template):
			if found != &"":
				return &""
			found = kind
	return found


# ---------------------------------------------------------------- commands

## {"actor": int, "target": int}
func _on_start(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("target")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var target: int = payload["target"]
	return start(actor, target)


## {"actor": int}
func _on_cancel(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 1 or typeof(payload.get("actor")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	return cancel(actor)


## {"actor": int, "target": int}
func _on_logout(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("target")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var target: int = payload["target"]
	return logout(actor, target)


# ---------------------------------------------------------------- state

func snapshot() -> Dictionary:
	return {"targets": _targets.duplicate(true), "running": _running.duplicate(true), "logins": _logins.duplicate(true), "next": _next, "completed": _completed}


func restore(state: Dictionary) -> Error:
	if state.size() != 5 or typeof(state.get("targets")) != TYPE_DICTIONARY or typeof(state.get("running")) != TYPE_DICTIONARY \
			or typeof(state.get("logins")) != TYPE_DICTIONARY or typeof(state.get("next")) != TYPE_INT or typeof(state.get("completed")) != TYPE_INT:
		return _restore_fail("shape")
	var next: int = state["next"]
	var completed: int = state["completed"]
	if next < 1 or completed < 0:
		return _restore_fail("counters")
	var targets_in: Dictionary = state["targets"]
	var targets: Dictionary = {}
	for k: Variant in targets_in:
		if typeof(k) != TYPE_INT or typeof(targets_in[k]) != TYPE_DICTIONARY:
			return _restore_fail("target key")
		var id: int = k
		var rec: Dictionary = targets_in[k]
		if id < 1 or id >= next or rec.size() != 4 or (typeof(rec.get("target")) != TYPE_STRING and typeof(rec.get("target")) != TYPE_STRING_NAME) \
				or typeof(rec.get("cell")) != TYPE_ARRAY or typeof(rec.get("piece")) != TYPE_INT or typeof(rec.get("done")) != TYPE_BOOL:
			return _restore_fail("target %d record" % id)
		var name_s: String = rec["target"]
		var piece: int = rec["piece"]
		var cell: Array[int] = _ints3(rec["cell"])
		if not _content.has(KIND_TARGET, StringName(name_s)) or piece < 0 or cell.is_empty():
			return _restore_fail("target %d values" % id)
		var done: bool = rec["done"]
		targets[id] = {"target": StringName(name_s), "cell": cell, "piece": piece, "done": done}
	var running_in: Dictionary = state["running"]
	var running: Dictionary = {}
	var busy: Array[int] = []
	for k: Variant in running_in:
		if typeof(k) != TYPE_INT or typeof(running_in[k]) != TYPE_DICTIONARY:
			return _restore_fail("running key")
		var actor: int = k
		var rec: Dictionary = running_in[k]
		if rec.size() != 4 or typeof(rec.get("target")) != TYPE_INT or typeof(rec.get("ticks")) != TYPE_INT \
				or typeof(rec.get("pos")) != TYPE_ARRAY or typeof(rec.get("health")) != TYPE_INT:
			return _restore_fail("running %d record" % actor)
		var target: int = rec["target"]
		var ticks: int = rec["ticks"]
		var health: int = rec["health"]
		var pos: Array[int] = _ints3(rec["pos"])
		if not _actors.has_actor(actor) or not targets.has(target) or busy.has(target) or pos.is_empty() or health < 0:
			return _restore_fail("running %d values" % actor)
		var trec: Dictionary = targets[target]
		var done: bool = trec["done"]
		var tname: StringName = trec["target"]
		var t: Dictionary = _content.get_entry(KIND_TARGET, tname)
		var total: int = t["ticks"]
		if done or ticks < 1 or ticks > total:
			return _restore_fail("running %d progress" % actor)
		busy.append(target)
		running[actor] = {"target": target, "ticks": ticks, "pos": pos, "health": health}
	var logins_in: Dictionary = state["logins"]
	var logins: Dictionary = {}
	var held: Array[int] = []
	for k: Variant in logins_in:
		if typeof(k) != TYPE_INT or typeof(logins_in[k]) != TYPE_ARRAY:
			return _restore_fail("login key")
		var actor: int = k
		var list_in: Array = logins_in[k]
		if not _actors.has_actor(actor) or list_in.is_empty():
			return _restore_fail("login %d" % actor)
		var list: Array = []
		for v: Variant in list_in:
			if typeof(v) != TYPE_INT:
				return _restore_fail("login %d entry" % actor)
			var target: int = v
			if not targets.has(target) or held.has(target):
				return _restore_fail("login %d target" % actor)
			var trec: Dictionary = targets[target]
			var done: bool = trec["done"]
			if not done:
				return _restore_fail("login %d to an undone target" % actor)
			held.append(target)
			list.append(target)
		logins[actor] = list
	_targets = targets
	_running = running
	_logins = logins
	_next = next
	_completed = completed
	return OK


static func _ints3(v: Variant) -> Array[int]:
	var out: Array[int] = []
	if typeof(v) != TYPE_ARRAY:
		return out
	var arr: Array = v
	if arr.size() != 3:
		return out
	for e: Variant in arr:
		if typeof(e) != TYPE_INT:
			return [] as Array[int]
		var n: int = e
		out.append(n)
	return out


func _restore_fail(reason: String) -> Error:
	push_error("HackSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
