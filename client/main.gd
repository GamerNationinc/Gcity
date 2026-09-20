## Entry scene. A read-only view of the local host's sim: tick, seed and state hash.
## Exists to prove the sim/client split runs end to end; there is no gameplay here.
extends Control

@onready var _host: LocalHost = $LocalHost
@onready var _status: Label = $Status


func _process(_delta: float) -> void:
	var sim: SimRoot = _host.sim()
	_status.text = "Gcity M0 skeleton\nseed %d\ntick %d\nstate %s" % [sim.get_seed(), sim.get_tick(), sim.state_hash()]
