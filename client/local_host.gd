## The local host: owns the authoritative [SimRoot] and steps it on the fixed physics
## tick. In solo play the host and the client live in the same process (design doc
## §4.1); co-op later puts a socket between them, not a rewrite.
##
## Nothing in the client writes sim state directly. It reads, and it submits commands.
class_name LocalHost extends Node

## 0 picks a random seed at startup; any other value is used as-is (for reproduction).
## `--seed=N` on the command line sets it, and a `--demo` without one plays the world the
## M6 fixtures record (M7.5 claim 13): a scripted run is only a demonstration of
## anything in a world it was proven in.
@export var seed_override: int = 0
## The seed `tools/make_m6_fixtures.gd` records its runs at.
const DEMO_SEED: int = 20261230

var _sim: SimRoot
var _content: ContentDb


func _ready() -> void:
	# The physics tick is the sim tick. If the project setting drifts from
	# SimRoot.TICK_HZ the sim would run at the wrong speed, so fail loudly.
	assert(Engine.physics_ticks_per_second == SimRoot.TICK_HZ,
		"physics_ticks_per_second (%d) must equal SimRoot.TICK_HZ (%d)" % [Engine.physics_ticks_per_second, SimRoot.TICK_HZ])
	seed_override = seed_from_args(OS.get_cmdline_user_args(), seed_override)
	var seed: int = seed_override if seed_override != 0 else randi()
	_content = ContentDb.new()
	var load_err: Error = ContentLoader.load_all(_content)
	assert(load_err == OK, "content failed to load: %s" % error_string(load_err))
	_sim = SimAssembly.build(seed, _content)
	assert(_sim != null, "sim assembly failed")


func _physics_process(_delta: float) -> void:
	_sim.step()


## The seed the command line asks for: `--seed=N`, else the demo seed under `--demo`,
## else `fallback`. A `--seed` that is not a whole non-zero number is refused loudly.
static func seed_from_args(args: PackedStringArray, fallback: int) -> int:
	for arg: String in args:
		if arg.begins_with("--seed="):
			var text: String = arg.trim_prefix("--seed=")
			if not text.is_valid_int() or text.to_int() == 0:
				push_error("LocalHost: --seed must be a whole non-zero number, not '%s'" % text)
				return fallback
			return text.to_int()
	if args.has("--demo"):
		return DEMO_SEED
	return fallback


func sim() -> SimRoot:
	return _sim


## Replaces the running sim with one loaded from a save (M2 spec claims 13, 20). The
## old sim is dropped; the client re-reads everything from the new one.
func adopt(loaded: SimRoot) -> void:
	assert(loaded != null, "adopt needs a sim")
	_sim = loaded


## A fresh sim over the same content with a new seed (or the override): the client's
## restart on the Deck. The old sim is dropped.
func restart() -> void:
	var seed: int = seed_override if seed_override != 0 else randi()
	_sim = SimAssembly.build(seed, _content)
	assert(_sim != null, "sim assembly failed")


func content() -> ContentDb:
	return _content
