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
	var ids: EntityIds = EntityIds.new()
	if sim.register_system(ids) != OK:
		return null
	var stats: StatResolver = StatResolver.new()
	if stats.register_stats_from(content) != OK:
		return null
	if sim.register_system(stats) != OK:
		return null
	var items: ItemSystem = ItemSystem.new(content, stats, ids)
	if items.attach(sim) != OK:
		return null
	return sim


## Restores every system of a freshly built sim from a full [method SimRoot.snapshot]
## taken of another sim built over the same content. The tick, RNG and inbox are not
## restored here (full save/load is G2); this is the item-and-stats round trip of
## ADR-009's G1 verification.
static func restore_systems(sim: SimRoot, snapshot: Dictionary) -> Error:
	var systems_v: Variant = snapshot.get("systems")
	if typeof(systems_v) != TYPE_DICTIONARY:
		push_error("SimAssembly.restore_systems: snapshot has no systems")
		return ERR_INVALID_DATA
	var systems: Dictionary = systems_v
	for id: StringName in [EntityIds.SYSTEM_ID, StatResolver.SYSTEM_ID, ItemSystem.SYSTEM_ID]:
		var state_v: Variant = systems.get(id)
		if typeof(state_v) != TYPE_DICTIONARY:
			push_error("SimAssembly.restore_systems: no state for '%s'" % id)
			return ERR_INVALID_DATA
		var state: Dictionary = state_v
		var err: Error = ERR_BUG
		match id:
			EntityIds.SYSTEM_ID:
				err = entities_of(sim).restore(state)
			StatResolver.SYSTEM_ID:
				err = stats_of(sim).restore(state)
			ItemSystem.SYSTEM_ID:
				err = items_of(sim).restore(state)
		if err != OK:
			return err
	return OK


static func stats_of(sim: SimRoot) -> StatResolver:
	var system: SimSystem = sim.get_system(StatResolver.SYSTEM_ID)
	if system == null:
		push_error("SimAssembly: sim has no '%s' system" % StatResolver.SYSTEM_ID)
		return null
	var stats: StatResolver = system
	return stats


static func items_of(sim: SimRoot) -> ItemSystem:
	var system: SimSystem = sim.get_system(ItemSystem.SYSTEM_ID)
	if system == null:
		push_error("SimAssembly: sim has no '%s' system" % ItemSystem.SYSTEM_ID)
		return null
	var items: ItemSystem = system
	return items


static func entities_of(sim: SimRoot) -> EntityIds:
	var system: SimSystem = sim.get_system(EntityIds.SYSTEM_ID)
	if system == null:
		push_error("SimAssembly: sim has no '%s' system" % EntityIds.SYSTEM_ID)
		return null
	var ids: EntityIds = system
	return ids
