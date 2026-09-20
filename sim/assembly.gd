## The one place the game's sim is put together (docs/extending-sim-systems.md: assemble
## systems in one place, in one fixed order, because the order is part of the state).
## LocalHost, the replay tool and the tests all build the sim through here so that a
## fixture replays against the same system set the player runs.
class_name SimAssembly extends RefCounted


## Builds a fresh sim at tick 0 over the given content. Returns null (after an error)
## if any system refuses to register or the content is unusable.
static func build(seed: int, content: ContentDb) -> SimRoot:
	var sim: SimRoot = SimRoot.new(seed)
	if sim.register_system(content) != OK:
		return null
	var stats: StatResolver = StatResolver.new()
	if stats.register_stats_from(content) != OK:
		return null
	if sim.register_system(stats) != OK:
		return null
	return sim


## The resolver of a sim built by [method build], for callers that hold the sim only.
static func stats_of(sim: SimRoot) -> StatResolver:
	var system: SimSystem = sim.get_system(StatResolver.SYSTEM_ID)
	if system == null:
		push_error("SimAssembly: sim has no '%s' system" % StatResolver.SYSTEM_ID)
		return null
	var stats: StatResolver = system
	return stats
