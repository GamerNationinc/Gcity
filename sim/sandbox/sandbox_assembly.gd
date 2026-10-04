## The sandbox's sim (M7.6 spec decision 2): the game's own assembly, unchanged, with
## `SandboxSystem` attached last, always last, so the order is still fixed. The game never
## builds through here, so its fixtures and their hashes do not move, and the release
## export leaves this folder out (decision 1). The caller loads `sandbox_content/` into the
## content first: reading files is the client's (`client/sandbox/sandbox_mode.gd`).
class_name SandboxAssembly extends RefCounted


## Builds a fresh sandbox sim at tick 0, or null (after an error) when the game's assembly
## or the sandbox system refuses.
static func build(seed: int, content: ContentDb) -> SimRoot:
	var sim: SimRoot = SimAssembly.build(seed, content)
	if sim == null:
		return null
	var sandbox: SandboxSystem = SandboxSystem.new(SimAssembly.actors_of(sim), SimAssembly.build_of(sim), SimAssembly.movement_of(sim))
	if sandbox.attach(sim) != OK:
		return null
	return sim


static func sandbox_of(sim: SimRoot) -> SandboxSystem:
	var system: SimSystem = sim.get_system(SandboxSystem.SYSTEM_ID)
	assert(system is SandboxSystem, "the sim has no sandbox system: build it with SandboxAssembly")
	return system
