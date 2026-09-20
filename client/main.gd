## Entry scene. A read-only view of the local host's sim: tick, seed, state hash, the
## content digest and the registered stats. Exists to prove the sim/client split runs
## end to end; the M1 range view lands with the weapon system.
extends Control

@onready var _host: LocalHost = $LocalHost
@onready var _status: Label = $Status


func _process(_delta: float) -> void:
	var sim: SimRoot = _host.sim()
	var stats: StatResolver = SimAssembly.stats_of(sim)
	_status.text = "Gcity M1\nseed %d\ntick %d\nstate %s\ncontent %d entries, digest %s\nstats %s" % [
		sim.get_seed(), sim.get_tick(), sim.state_hash(), _host.content().count(),
		_host.content().digest().left(16), ", ".join(stats.stat_ids())]
