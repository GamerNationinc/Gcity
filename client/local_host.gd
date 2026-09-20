## The local host: owns the authoritative [SimRoot] and steps it on the fixed physics
## tick. In solo play the host and the client live in the same process (design doc
## §4.1); co-op later puts a socket between them, not a rewrite.
##
## Nothing in the client writes sim state directly. It reads, and it submits commands.
class_name LocalHost extends Node

## 0 picks a random seed at startup; any other value is used as-is (for reproduction).
@export var seed_override: int = 0

var _sim: SimRoot


func _ready() -> void:
	# The physics tick is the sim tick. If the project setting drifts from
	# SimRoot.TICK_HZ the sim would run at the wrong speed, so fail loudly.
	assert(Engine.physics_ticks_per_second == SimRoot.TICK_HZ,
		"physics_ticks_per_second (%d) must equal SimRoot.TICK_HZ (%d)" % [Engine.physics_ticks_per_second, SimRoot.TICK_HZ])
	var seed: int = seed_override if seed_override != 0 else randi()
	_sim = SimRoot.new(seed)


func _physics_process(_delta: float) -> void:
	_sim.step()


func sim() -> SimRoot:
	return _sim
