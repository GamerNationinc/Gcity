## The declared root of all authoritative simulation state (standards §1.1).
##
## Owns the tick counter, the seeded RNG, the command registry, the command inbox and
## the ordered list of registered systems. Everything the game considers true lives
## under this object, and nothing under it may touch rendering, input or UI.
##
## Time is integer ticks. There is no float delta anywhere in the sim (ADR-002).
class_name SimRoot extends RefCounted

## Fixed simulation rate. Equal to the Deck frame target so one tick maps to one frame
## at a locked 40 fps. Proposed in ADR-002; a change there changes this constant and
## project.godot's physics tick rate together.
const TICK_HZ: int = 40
## Exact integer tick length. TICK_HZ must divide 1 000 000 evenly (asserted by test).
const TICK_USEC: int = 1_000_000 / TICK_HZ
## Version of the snapshot layout produced by [method snapshot].
const SNAPSHOT_SCHEMA_VERSION: int = 1

var _seed: int
var _tick: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _commands: CommandRegistry = CommandRegistry.new()
var _systems: Array[SimSystem] = []
var _system_ids: Dictionary[StringName, bool] = {}
## Pending commands keyed by target tick; each value is an Array of SimCommand in
## submission order.
var _inbox: Dictionary[int, Array] = {}
var _dispatched: int = 0
var _rejected: int = 0
## Paused (ADR-006 C; M5 spec claim 7): the tick does not advance, no system ticks,
## and only pause-safe commands dispatch from the next tick's queue. `paused_steps`
## counts the frozen steps so a paused sim's state is still its own.
var _paused: bool = false
var _paused_steps: int = 0


func _init(p_seed: int) -> void:
	_seed = p_seed
	_rng.seed = p_seed


func get_seed() -> int:
	return _seed


func get_tick() -> int:
	return _tick


## The only source of randomness the sim may use. Global randi()/randf() are banned in
## sim/ by tools/check_dependencies.py.
func rng() -> RandomNumberGenerator:
	return _rng


func commands() -> CommandRegistry:
	return _commands


func dispatched_count() -> int:
	return _dispatched


func rejected_count() -> int:
	return _rejected


## Registers a system. Only allowed before the first tick, so that every sim built
## from the same seed and inputs has the same system order (which the hash depends on).
func register_system(system: SimSystem) -> Error:
	if _tick != 0:
		push_error("SimRoot: cannot register '%s' after tick 0" % system.system_id())
		return ERR_LOCKED
	var id: StringName = system.system_id()
	if id.is_empty():
		push_error("SimRoot: system has an empty id")
		return ERR_INVALID_PARAMETER
	if _system_ids.has(id):
		push_error("SimRoot: system '%s' already registered" % id)
		return ERR_ALREADY_EXISTS
	_system_ids[id] = true
	_systems.append(system)
	return OK


## The registered system with this id, or null.
func get_system(id: StringName) -> SimSystem:
	for system: SimSystem in _systems:
		if system.system_id() == id:
			return system
	return null


func system_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for system: SimSystem in _systems:
		result.append(system.system_id())
	return result


## Queues a command for a future tick. A command for the current tick or earlier is
## late and is rejected: the sim never rewrites the past.
func submit(command: SimCommand) -> Error:
	if command.tick <= _tick:
		return ERR_INVALID_PARAMETER
	if not _inbox.has(command.tick):
		_inbox[command.tick] = []
	var queue: Array = _inbox[command.tick]
	queue.append(command)
	return OK


func is_paused() -> bool:
	return _paused


func paused_steps() -> int:
	return _paused_steps


## The land authority's pause and resume commands call these; nothing else does.
func set_paused(paused: bool) -> void:
	_paused = paused


## Advances exactly one tick: dispatches the commands due on the new tick in
## submission order, then ticks every system in registration order. Paused, it
## dispatches only the pause-safe commands due on the next tick, keeps the rest
## queued in order, advances nothing and ticks nothing.
func step() -> void:
	if _paused:
		_paused_steps += 1
		var next: int = _tick + 1
		if _inbox.has(next):
			var due: Array = _inbox[next]
			var kept: Array = []
			for entry: Variant in due:
				var command: SimCommand = entry
				if not _commands.is_pause_safe(command.kind):
					kept.append(command)
					continue
				var err: Error = _commands.dispatch(self, command)
				if err == OK:
					_dispatched += 1
				else:
					_rejected += 1
			if kept.is_empty():
				_inbox.erase(next)
			else:
				_inbox[next] = kept
		return
	_tick += 1
	if _inbox.has(_tick):
		var due: Array = _inbox[_tick]
		_inbox.erase(_tick)
		for entry: Variant in due:
			var command: SimCommand = entry
			var err: Error = _commands.dispatch(self, command)
			if err == OK:
				_dispatched += 1
			else:
				_rejected += 1
	for system: SimSystem in _systems:
		system.tick(self)


func step_n(count: int) -> void:
	for _i: int in count:
		step()


## Complete authoritative state in hashable form. Includes the inbox, because two sims
## with equal visible state but different pending commands would diverge.
func snapshot() -> Dictionary:
	var systems: Dictionary = {}
	for system: SimSystem in _systems:
		systems[system.system_id()] = system.snapshot()
	var inbox: Dictionary = {}
	for target_tick: int in _inbox.keys():
		var queued: Array = []
		var queue: Array = _inbox[target_tick]
		for entry: Variant in queue:
			var command: SimCommand = entry
			queued.append({"kind": command.kind, "payload": command.payload})
		inbox[target_tick] = queued
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"seed": _seed,
		"tick": _tick,
		"rng_state": _rng.state,
		"dispatched": _dispatched,
		"rejected": _rejected,
		"paused": _paused,
		"paused_steps": _paused_steps,
		"inbox": inbox,
		"systems": systems,
	}


## Restores the root's own state (tick, RNG, inbox, dispatch counters) from a snapshot
## whose systems have already been restored. The seed must match the one this sim was
## built with; every queued command must name a registered kind and a future tick.
## Nothing changes unless the whole snapshot is valid.
func restore_root(snap: Dictionary) -> Error:
	var expected: Array[String] = ["schema_version", "seed", "tick", "rng_state", "dispatched", "rejected", "paused", "paused_steps", "inbox", "systems"]
	if snap.size() != expected.size():
		return _restore_fail("key count")
	for key: String in expected:
		if not snap.has(key):
			return _restore_fail("missing '%s'" % key)
	for key: String in ["schema_version", "seed", "tick", "rng_state", "dispatched", "rejected", "paused_steps"]:
		if typeof(snap[key]) != TYPE_INT:
			return _restore_fail("'%s' must be an int" % key)
	if typeof(snap["paused"]) != TYPE_BOOL:
		return _restore_fail("'paused' must be a bool")
	if typeof(snap["inbox"]) != TYPE_DICTIONARY or typeof(snap["systems"]) != TYPE_DICTIONARY:
		return _restore_fail("inbox and systems must be dictionaries")
	var version: int = snap["schema_version"]
	if version != SNAPSHOT_SCHEMA_VERSION:
		return _restore_fail("schema_version %d (expected %d)" % [version, SNAPSHOT_SCHEMA_VERSION])
	var seed: int = snap["seed"]
	if seed != _seed:
		return _restore_fail("seed %d does not match this sim's %d" % [seed, _seed])
	var tick: int = snap["tick"]
	var dispatched: int = snap["dispatched"]
	var rejected: int = snap["rejected"]
	var paused_steps: int = snap["paused_steps"]
	if tick < 0 or dispatched < 0 or rejected < 0 or paused_steps < 0:
		return _restore_fail("negative counter")
	var inbox_in: Dictionary = snap["inbox"]
	var inbox: Dictionary[int, Array] = {}
	for tk: Variant in inbox_in:
		if typeof(tk) != TYPE_INT or tk <= tick or typeof(inbox_in[tk]) != TYPE_ARRAY:
			return _restore_fail("inbox tick %s" % var_to_str(tk))
		var queue: Array = []
		var entries: Array = inbox_in[tk]
		for entry: Variant in entries:
			if typeof(entry) != TYPE_DICTIONARY:
				return _restore_fail("inbox entry")
			var e: Dictionary = entry
			if e.size() != 2 or typeof(e.get("payload")) != TYPE_DICTIONARY:
				return _restore_fail("inbox entry shape")
			var kind_v: Variant = e.get("kind")
			if typeof(kind_v) != TYPE_STRING and typeof(kind_v) != TYPE_STRING_NAME:
				return _restore_fail("inbox entry kind")
			var kind: StringName = StringName(str(kind_v))
			if not _commands.has(kind):
				return _restore_fail("inbox names unregistered kind '%s'" % kind)
			var target: int = tk
			var payload: Dictionary = e["payload"]
			queue.append(SimCommand.new(target, kind, payload))
		inbox[tk] = queue
	_tick = tick
	_rng.state = snap["rng_state"]
	_dispatched = dispatched
	_rejected = rejected
	_paused = snap["paused"]
	_paused_steps = paused_steps
	_inbox = inbox
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("SimRoot.restore_root: rejected: %s" % reason)
	return ERR_INVALID_DATA


## SHA-256 hex of [method snapshot]. Empty string means a system produced an
## unhashable snapshot, which is a programming error already logged by StateHash.
func state_hash() -> String:
	return StateHash.of(snapshot())
