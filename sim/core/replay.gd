## Drives a [SimRoot] through a [ReplayFixture] and returns the resulting state hash.
##
## The caller builds the sim (seed, systems, command handlers) so that the same
## fixture can be replayed against any configuration; this class only checks that the
## sim it was handed is fresh and matches the fixture's seed.
class_name Replay extends RefCounted


## Returns the state hash after the run, or the empty string if the fixture is invalid
## or the sim does not match it. The empty string is never a valid hash.
static func run(fixture: ReplayFixture, sim: SimRoot) -> String:
	if not fixture.is_valid():
		push_error("Replay: invalid fixture: %s" % fixture.error)
		return ""
	if sim.get_tick() != 0:
		push_error("Replay: sim is at tick %d, expected a fresh sim" % sim.get_tick())
		return ""
	if sim.get_seed() != fixture.seed:
		push_error("Replay: sim seed %d does not match fixture seed %d" % [sim.get_seed(), fixture.seed])
		return ""
	for command: SimCommand in fixture.commands:
		var err: Error = sim.submit(command)
		if err != OK:
			push_error("Replay: submit of '%s' for tick %d failed: %s" % [command.kind, command.tick, error_string(err)])
			return ""
	sim.step_n(fixture.ticks)
	return sim.state_hash()
