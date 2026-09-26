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
	var actors: ActorSystem = ActorSystem.new(content, stats, ids, items)
	if actors.attach(sim) != OK:
		return null
	items.set_actor_check(actors.has_actor)
	var events: EventBus = EventBus.new()
	var combat: CombatSystem = CombatSystem.new(content, stats, items, actors, events)
	if combat.attach(sim) != OK:
		return null
	var progression: ProgressionSystem = ProgressionSystem.new(content, stats, actors, events)
	if progression.attach(sim) != OK:
		return null
	var land: LandSystem = LandSystem.new(content, actors, events)
	if land.attach(sim) != OK:
		return null
	var structures: StructureSystem = StructureSystem.new(content, stats, ids, land, actors)
	if structures.attach(sim) != OK:
		return null
	var build: BuildSystem = BuildSystem.new(content, stats, ids, land, actors, events)
	if build.attach(sim) != OK:
		return null
	var portals: PortalGraph = PortalGraph.new(content, stats, build)
	if portals.attach(sim, events) != OK:
		return null
	var movement: MovementSystem = MovementSystem.new(content, actors, land, build)
	if movement.attach(sim, events) != OK:
		return null
	var raids: RaidTokenSystem = RaidTokenSystem.new(content, build, portals, events)
	if raids.attach(sim) != OK:
		return null
	var breaches: BreachSystem = BreachSystem.new(content, stats, items, actors, build, land, events)
	if breaches.attach(sim) != OK:
		return null
	var perception: PerceptionSystem = PerceptionSystem.new(content, stats, actors, build, events)
	if perception.attach(sim) != OK:
		return null
	combat.set_sight_check(perception.can_target)
	var aim: AimSystem = AimSystem.new(content, stats, actors, perception)
	if aim.attach(sim) != OK:
		return null
	var stress: StressSystem = StressSystem.new(content, stats, actors, perception, events)
	if stress.attach(sim) != OK:
		return null
	var pathing: PathingSystem = PathingSystem.new(actors, build, movement, perception, events)
	if pathing.attach(sim) != OK:
		return null
	var squads: SquadSystem = SquadSystem.new(content, actors, perception, portals, build, events)
	if squads.attach(sim) != OK:
		return null
	var stances: StanceSystem = StanceSystem.new(content, actors, items, perception, aim, stress, pathing, squads)
	if stances.attach(sim) != OK:
		return null
	var quests: QuestSystem = QuestSystem.new(content, actors, items, events)
	if quests.attach(sim) != OK:
		return null
	var sites: SiteSystem = SiteSystem.new(content, land, build, perception)
	if sites.attach(sim) != OK:
		return null
	return sim


## Loads a save (M2 spec claim 13): a fresh sim over the same content, every system
## restored in registration order, then the root. Returns null (after an error) when
## the content digest differs or any part of the save is rejected.
static func load_save(file: SaveFile, content: ContentDb) -> SimRoot:
	if not file.is_valid():
		push_error("SimAssembly.load_save: invalid save: %s" % file.error)
		return null
	if file.content_digest != content.digest():
		push_error("SimAssembly.load_save: save was made over different content (%s, have %s)" % [file.content_digest, content.digest()])
		return null
	var seed_v: Variant = file.snapshot.get("seed")
	if typeof(seed_v) != TYPE_INT:
		push_error("SimAssembly.load_save: snapshot has no integer seed")
		return null
	var seed: int = seed_v
	var sim: SimRoot = build(seed, content)
	if sim == null:
		return null
	if restore_systems(sim, file.snapshot) != OK:
		return null
	if sim.restore_root(file.snapshot) != OK:
		return null
	return sim


## Restores every system of a freshly built sim from a full [method SimRoot.snapshot]
## taken of another sim built over the same content, in registration order. The root
## (tick, RNG, inbox, counters) is restored separately by [method SimRoot.restore_root].
static func restore_systems(sim: SimRoot, snapshot: Dictionary) -> Error:
	var systems_v: Variant = snapshot.get("systems")
	if typeof(systems_v) != TYPE_DICTIONARY:
		push_error("SimAssembly.restore_systems: snapshot has no systems")
		return ERR_INVALID_DATA
	var systems: Dictionary = systems_v
	for id: StringName in [EntityIds.SYSTEM_ID, StatResolver.SYSTEM_ID, ItemSystem.SYSTEM_ID, ActorSystem.SYSTEM_ID, CombatSystem.SYSTEM_ID, ProgressionSystem.SYSTEM_ID, LandSystem.SYSTEM_ID, StructureSystem.SYSTEM_ID, BuildSystem.SYSTEM_ID, PortalGraph.SYSTEM_ID, MovementSystem.SYSTEM_ID, RaidTokenSystem.SYSTEM_ID, BreachSystem.SYSTEM_ID, PerceptionSystem.SYSTEM_ID, AimSystem.SYSTEM_ID, StressSystem.SYSTEM_ID, PathingSystem.SYSTEM_ID, SquadSystem.SYSTEM_ID, StanceSystem.SYSTEM_ID, QuestSystem.SYSTEM_ID, SiteSystem.SYSTEM_ID]:
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
			ActorSystem.SYSTEM_ID:
				err = actors_of(sim).restore(state)
			CombatSystem.SYSTEM_ID:
				err = combat_of(sim).restore(state)
			ProgressionSystem.SYSTEM_ID:
				err = progression_of(sim).restore(state)
			LandSystem.SYSTEM_ID:
				err = land_of(sim).restore(state)
			StructureSystem.SYSTEM_ID:
				err = structures_of(sim).restore(state)
			BuildSystem.SYSTEM_ID:
				err = build_of(sim).restore(state)
			PortalGraph.SYSTEM_ID:
				err = portals_of(sim).restore(state)
			MovementSystem.SYSTEM_ID:
				err = movement_of(sim).restore(state)
			RaidTokenSystem.SYSTEM_ID:
				err = raids_of(sim).restore(state)
			BreachSystem.SYSTEM_ID:
				err = breaches_of(sim).restore(state)
			PerceptionSystem.SYSTEM_ID:
				err = perception_of(sim).restore(state)
			AimSystem.SYSTEM_ID:
				err = aim_of(sim).restore(state)
			StressSystem.SYSTEM_ID:
				err = stress_of(sim).restore(state)
			PathingSystem.SYSTEM_ID:
				err = pathing_of(sim).restore(state)
			SquadSystem.SYSTEM_ID:
				err = squads_of(sim).restore(state)
			StanceSystem.SYSTEM_ID:
				err = stances_of(sim).restore(state)
			QuestSystem.SYSTEM_ID:
				err = quests_of(sim).restore(state)
			SiteSystem.SYSTEM_ID:
				err = sites_of(sim).restore(state)
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


static func actors_of(sim: SimRoot) -> ActorSystem:
	var system: SimSystem = sim.get_system(ActorSystem.SYSTEM_ID)
	if system == null:
		push_error("SimAssembly: sim has no '%s' system" % ActorSystem.SYSTEM_ID)
		return null
	var actors: ActorSystem = system
	return actors


static func combat_of(sim: SimRoot) -> CombatSystem:
	var system: SimSystem = sim.get_system(CombatSystem.SYSTEM_ID)
	if system == null:
		push_error("SimAssembly: sim has no '%s' system" % CombatSystem.SYSTEM_ID)
		return null
	var combat: CombatSystem = system
	return combat


static func progression_of(sim: SimRoot) -> ProgressionSystem:
	var system: SimSystem = sim.get_system(ProgressionSystem.SYSTEM_ID)
	if system == null:
		push_error("SimAssembly: sim has no '%s' system" % ProgressionSystem.SYSTEM_ID)
		return null
	var progression: ProgressionSystem = system
	return progression


static func land_of(sim: SimRoot) -> LandSystem:
	var system: SimSystem = sim.get_system(LandSystem.SYSTEM_ID)
	if system == null:
		push_error("SimAssembly: sim has no '%s' system" % LandSystem.SYSTEM_ID)
		return null
	var land: LandSystem = system
	return land


static func structures_of(sim: SimRoot) -> StructureSystem:
	var system: SimSystem = sim.get_system(StructureSystem.SYSTEM_ID)
	if system == null:
		push_error("SimAssembly: sim has no '%s' system" % StructureSystem.SYSTEM_ID)
		return null
	var structures: StructureSystem = system
	return structures


static func build_of(sim: SimRoot) -> BuildSystem:
	var system: SimSystem = sim.get_system(BuildSystem.SYSTEM_ID)
	if system == null:
		push_error("SimAssembly: sim has no '%s' system" % BuildSystem.SYSTEM_ID)
		return null
	var build: BuildSystem = system
	return build


static func portals_of(sim: SimRoot) -> PortalGraph:
	var system: SimSystem = sim.get_system(PortalGraph.SYSTEM_ID)
	if system == null:
		push_error("SimAssembly: sim has no '%s' system" % PortalGraph.SYSTEM_ID)
		return null
	var portals: PortalGraph = system
	return portals


static func movement_of(sim: SimRoot) -> MovementSystem:
	var system: SimSystem = sim.get_system(MovementSystem.SYSTEM_ID)
	if system == null:
		push_error("SimAssembly: sim has no '%s' system" % MovementSystem.SYSTEM_ID)
		return null
	var movement: MovementSystem = system
	return movement


static func raids_of(sim: SimRoot) -> RaidTokenSystem:
	var system: SimSystem = sim.get_system(RaidTokenSystem.SYSTEM_ID)
	if system == null:
		push_error("SimAssembly: sim has no '%s' system" % RaidTokenSystem.SYSTEM_ID)
		return null
	var raids: RaidTokenSystem = system
	return raids


static func perception_of(sim: SimRoot) -> PerceptionSystem:
	var system: SimSystem = sim.get_system(PerceptionSystem.SYSTEM_ID)
	if system == null:
		push_error("SimAssembly: sim has no '%s' system" % PerceptionSystem.SYSTEM_ID)
		return null
	var perception: PerceptionSystem = system
	return perception


static func aim_of(sim: SimRoot) -> AimSystem:
	var system: SimSystem = sim.get_system(AimSystem.SYSTEM_ID)
	if system == null:
		push_error("SimAssembly: sim has no '%s' system" % AimSystem.SYSTEM_ID)
		return null
	var aim: AimSystem = system
	return aim


static func stress_of(sim: SimRoot) -> StressSystem:
	var system: SimSystem = sim.get_system(StressSystem.SYSTEM_ID)
	if system == null:
		push_error("SimAssembly: sim has no '%s' system" % StressSystem.SYSTEM_ID)
		return null
	var stress: StressSystem = system
	return stress


static func pathing_of(sim: SimRoot) -> PathingSystem:
	var system: SimSystem = sim.get_system(PathingSystem.SYSTEM_ID)
	if system == null:
		push_error("SimAssembly: sim has no '%s' system" % PathingSystem.SYSTEM_ID)
		return null
	var pathing: PathingSystem = system
	return pathing


static func stances_of(sim: SimRoot) -> StanceSystem:
	var system: SimSystem = sim.get_system(StanceSystem.SYSTEM_ID)
	if system == null:
		push_error("SimAssembly: sim has no '%s' system" % StanceSystem.SYSTEM_ID)
		return null
	var stances: StanceSystem = system
	return stances


static func squads_of(sim: SimRoot) -> SquadSystem:
	var system: SimSystem = sim.get_system(SquadSystem.SYSTEM_ID)
	if system == null:
		push_error("SimAssembly: sim has no '%s' system" % SquadSystem.SYSTEM_ID)
		return null
	var squads: SquadSystem = system
	return squads


static func quests_of(sim: SimRoot) -> QuestSystem:
	var system: SimSystem = sim.get_system(QuestSystem.SYSTEM_ID)
	if system == null:
		push_error("SimAssembly: sim has no '%s' system" % QuestSystem.SYSTEM_ID)
		return null
	var quests: QuestSystem = system
	return quests


static func breaches_of(sim: SimRoot) -> BreachSystem:
	var system: SimSystem = sim.get_system(BreachSystem.SYSTEM_ID)
	if system == null:
		push_error("SimAssembly: sim has no '%s' system" % BreachSystem.SYSTEM_ID)
		return null
	var breaches: BreachSystem = system
	return breaches


static func sites_of(sim: SimRoot) -> SiteSystem:
	var system: SimSystem = sim.get_system(SiteSystem.SYSTEM_ID)
	if system == null:
		push_error("SimAssembly: sim has no '%s' system" % SiteSystem.SYSTEM_ID)
		return null
	var sites: SiteSystem = system
	return sites
