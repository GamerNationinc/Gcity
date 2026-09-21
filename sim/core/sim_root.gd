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


## Advances exactly one tick: dispatches the commands due on the new tick in
## submission order, then ticks every system in registration order.
func step() -> void:
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
		"inbox": inbox,
		"systems": systems,
	}


## SHA-256 hex of [method snapshot]. Empty string means a system produced an
## unhashable snapshot, which is a programming error already logged by StateHash.
func state_hash() -> String:
	return StateHash.of(snapshot())
