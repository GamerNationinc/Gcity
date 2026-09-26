extends GcityTest

## M6 spec claims 1, 2 and 4: a site is a data record raised by one command. Every
## shipped site raises cleanly and stands (the support check the validator cannot do
## in Python); the M4 building raised as a site equals the same building placed one
## command at a time, in one portal rebuild; a site raises once; quests name sites.

const SEED: int = 20261110
const M4_PIECES: int = 93

var _db: ContentDb


func _content() -> ContentDb:
	if _db == null:
		_db = ContentDb.new()
		assert_eq(ContentLoader.load_all(_db), OK, "content loads")
	return _db


func _do(sim: SimRoot, kind: StringName, payload: Dictionary) -> bool:
	var before: int = sim.dispatched_count()
	assert_eq(sim.submit(SimCommand.new(sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	sim.step()
	return sim.dispatched_count() == before + 1


func test_every_shipped_site_raises_and_stands() -> void:
	var sites: Array[StringName] = _content().ids(SiteSystem.KIND_SITE)
	assert_true(sites.has(&"home") and sites.has(&"m4_building"), "home and the M4 building ship")
	for site: StringName in sites:
		var sim: SimRoot = SimAssembly.build(SEED, _content())
		var build: BuildSystem = SimAssembly.build_of(sim)
		var t: Dictionary = _content().get_entry(SiteSystem.KIND_SITE, site)
		var pieces: Array = t["pieces"]
		var agents: Array = t["agents"]
		var parcels: Array = t["parcels"]
		assert_true(_do(sim, SiteSystem.COMMAND_RAISE, {"site": String(site)}), "%s raises" % site)
		assert_eq(build.piece_ids().size(), pieces.size(), "%s: every piece stands" % site)
		for id: int in build.piece_ids():
			assert_true(build.is_supported(id), "%s: piece %d is supported" % [site, id])
		assert_eq(SimAssembly.perception_of(sim).agent_ids().size(), agents.size(), "%s: every agent is posted" % site)
		for p: Variant in parcels:
			var pd: Dictionary = p
			var parcel_s: String = pd["parcel"]
			var owner_s: String = pd["owner"]
			assert_eq(SimAssembly.land_of(sim).owner_of(StringName(parcel_s)), StringName(owner_s), "%s: %s goes to '%s'" % [site, parcel_s, owner_s])
		assert_true(SimAssembly.sites_of(sim).is_raised(site), "%s is recorded as raised" % site)


func test_the_m4_site_equals_the_m4_building_placed_command_by_command() -> void:
	# one by one, as the M4 fixtures do it
	var one: SimRoot = SimAssembly.build(SEED, _content())
	var one_player: int = SimAssembly.actors_of(one).spawn(&"arcade", 0)
	var at: int = one.get_tick() + 1
	one.submit(SimCommand.new(at, &"land.identify", {"actor": one_player, "owner": "player"}))
	one.submit(SimCommand.new(at, &"land.transfer", {"parcel": "starter_plot", "owner": "player"}))
	one.submit(SimCommand.new(at, &"land.transfer", {"parcel": "neighbour_north", "owner": "player"}))
	for c: Dictionary in M4Building.commands(one_player):
		one.submit(SimCommand.new(at, &"build.place", c))
	for g: Dictionary in M4Building.guards("guard_sim"):
		one.submit(SimCommand.new(at, &"agent.spawn", g))
	one.step()
	assert_eq(one.rejected_count(), 0, "the command list applies")
	# as a site
	var raised: SimRoot = SimAssembly.build(SEED, _content())
	var raised_player: int = SimAssembly.actors_of(raised).spawn(&"arcade", 0)
	var portals: PortalGraph = SimAssembly.portals_of(raised)
	var rebuilds: int = portals.rebuild_count()
	at = raised.get_tick() + 1
	raised.submit(SimCommand.new(at, &"land.identify", {"actor": raised_player, "owner": "player"}))
	raised.submit(SimCommand.new(at, SiteSystem.COMMAND_RAISE, {"site": "m4_building"}))
	raised.step()
	assert_eq(raised.rejected_count(), 0, "the raise applies")
	assert_eq(portals.rebuild_count() - rebuilds, 1, "one portal rebuild for %d pieces" % M4_PIECES)
	assert_eq(SimAssembly.build_of(raised).piece_ids().size(), M4_PIECES, "all of the building")
	for id: StringName in [EntityIds.SYSTEM_ID, BuildSystem.SYSTEM_ID, PortalGraph.SYSTEM_ID, LandSystem.SYSTEM_ID, PerceptionSystem.SYSTEM_ID, ActorSystem.SYSTEM_ID]:
		assert_eq(StateHash.of(raised.get_system(id).snapshot()), StateHash.of(one.get_system(id).snapshot()), "'%s' state equals the command-by-command build" % id)


func test_a_site_raises_once_and_bad_payloads_are_refused() -> void:
	var sim: SimRoot = SimAssembly.build(SEED, _content())
	var sites: SiteSystem = SimAssembly.sites_of(sim)
	assert_false(sites.is_raised(&"home"), "nothing is raised at the start")
	for payload: Dictionary in [{}, {"site": 1}, {"site": "nowhere"}, {"site": "home", "extra": 1}, {"site": ["home"]}]:
		assert_false(_do(sim, SiteSystem.COMMAND_RAISE, payload), "refused: %s" % [payload])
		assert_eq(sites.raised_sites(), [] as Array[StringName], "still nothing raised after %s" % [payload])
	assert_true(_do(sim, SiteSystem.COMMAND_RAISE, {"site": "m4_building"}), "raised")
	var build_state: String = StateHash.of(SimAssembly.build_of(sim).snapshot())
	assert_false(_do(sim, SiteSystem.COMMAND_RAISE, {"site": "m4_building"}), "not twice")
	assert_eq(StateHash.of(SimAssembly.build_of(sim).snapshot()), build_state, "no second copy of the building")
	assert_eq(SimAssembly.build_of(sim).piece_ids().size(), M4_PIECES, "one building")
	assert_eq(sites.raised_sites(), [&"m4_building"] as Array[StringName], "the raised list")


func test_a_site_whose_pieces_cannot_stand_raises_nothing() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	assert_eq(db.add(SiteSystem.KIND_SITE, &"zz_floating", {
		"schema_version": 1, "description": "A wall with nothing under it.", "origin": [400, 0, 400],
		"parcels": [{"parcel": "neighbour_east", "owner": "npc.somebody"}],
		"pieces": [{"piece": "wall_panel", "cell": [0, 0, 0], "facing": "px"}],
		"points": [], "agents": [{"profile": "guard_sim", "cell": [1, 0, 1], "facing": 0, "squad": 1, "route": ""}],
	}), OK, "added")
	var sim: SimRoot = SimAssembly.build(SEED, db)
	assert_true(sim != null, "assembly accepts it: support is checked when raised")
	var before: StringName = SimAssembly.land_of(sim).owner_of(&"neighbour_east")
	var ids_before: String = StateHash.of(SimAssembly.entities_of(sim).snapshot())
	assert_false(_do(sim, SiteSystem.COMMAND_RAISE, {"site": "zz_floating"}), "refused")
	assert_eq(StateHash.of(SimAssembly.entities_of(sim).snapshot()), ids_before, "no id allocated")
	assert_eq(SimAssembly.build_of(sim).piece_ids().size(), 0, "no piece")
	assert_eq(SimAssembly.perception_of(sim).agent_ids().size(), 0, "no agent")
	assert_eq(SimAssembly.land_of(sim).owner_of(&"neighbour_east"), before, "no parcel changed hands")
	assert_false(SimAssembly.sites_of(sim).is_raised(&"zz_floating"), "not recorded")


func test_assembly_refuses_a_site_with_bad_references() -> void:
	var good: Dictionary = {
		"schema_version": 1, "description": "x", "origin": [0, 0, 0], "parcels": [],
		"pieces": [{"piece": "foundation_block", "cell": [0, 0, 0], "facing": ""}],
		"points": [{"id": "a", "cell": [1, 0, 1]}],
		"agents": [{"profile": "guard_sim", "cell": [1, 0, 1], "facing": 0, "squad": 1, "route": "lobby_round"}],
	}
	var db_ok := ContentDb.new()
	assert_eq(ContentLoader.load_all(db_ok), OK, "content loads")
	assert_eq(db_ok.add(SiteSystem.KIND_SITE, &"zz_good", good), OK, "added")
	assert_true(SimAssembly.build(SEED, db_ok) != null, "the good site assembles")
	var bad_cases: Array[Array] = [
		["parcels", [{"parcel": "nowhere", "owner": "player"}]],
		["parcels", [{"parcel": "starter_plot", "owner": "Not A Tag"}]],
		["pieces", [{"piece": "no_such_piece", "cell": [0, 0, 0], "facing": ""}]],
		["pieces", [{"piece": "wall_panel", "cell": [0, 0, 0], "facing": "py"}]],
		["pieces", [{"piece": "foundation_block", "cell": [0, 0, 0], "facing": "px"}]],
		["points", [{"id": "a", "cell": [1, 0, 1]}, {"id": "a", "cell": [2, 0, 2]}]],
		["agents", [{"profile": "nobody", "cell": [1, 0, 1], "facing": 0, "squad": 1, "route": ""}]],
		["agents", [{"profile": "guard_sim", "cell": [1, 0, 1], "facing": 0, "squad": 1, "route": "no_route"}]],
		["origin", [0, 0, 200000]],
	]
	for case: Array in bad_cases:
		var field: String = case[0]
		var site: Dictionary = good.duplicate(true)
		site[field] = case[1]
		var db := ContentDb.new()
		assert_eq(ContentLoader.load_all(db), OK, "content loads")
		assert_eq(db.add(SiteSystem.KIND_SITE, &"zz_bad", site), OK, "db takes the shape")
		assert_true(SimAssembly.build(SEED, db) == null, "assembly refuses %s = %s" % [field, case[1]])


func test_points_are_cell_centres_on_the_floor_of_their_cell() -> void:
	var db: ContentDb = _content()
	assert_true(SiteSystem.has_point(db, &"m4_building", &"player_start"), "the M4 site has a start")
	assert_eq(SiteSystem.point_position(db, &"m4_building", &"player_start"), M4Building.PLAYER_START, "which is the M4 start")
	assert_false(SiteSystem.has_point(db, &"m4_building", &"nowhere"), "an unknown point")
	assert_false(SiteSystem.has_point(db, &"nowhere", &"player_start"), "an unknown site")


func test_snapshot_restore_round_trip_and_rejections() -> void:
	var sim: SimRoot = SimAssembly.build(SEED, _content())
	assert_true(_do(sim, SiteSystem.COMMAND_RAISE, {"site": "home"}), "raised")
	var sites: SiteSystem = SimAssembly.sites_of(sim)
	var state: Dictionary = sites.snapshot()
	var fresh: SiteSystem = SimAssembly.sites_of(SimAssembly.build(SEED, _content()))
	assert_eq(fresh.restore(state), OK, "restores")
	assert_eq(StateHash.of(fresh.snapshot()), StateHash.of(state), "round trip")
	for bad: Dictionary in [{}, {"raised": "home"}, {"raised": ["nowhere"]}, {"raised": ["home", "home"]}, {"raised": [1]}, {"raised": [], "x": 1}]:
		assert_eq(fresh.restore(bad), ERR_INVALID_DATA, "rejects %s" % [bad])


func test_a_quest_binds_its_site_on_accept() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var quest: Dictionary = db.get_entry(&"quest", &"first_blood").duplicate(true)
	quest["site"] = "m4_building"
	assert_eq(db.add(&"quest", &"zz_sited", quest), OK, "a quest with a site")
	var sim: SimRoot = SimAssembly.build(SEED, db)
	assert_true(sim != null, "assembles")
	var quests: QuestSystem = SimAssembly.quests_of(sim)
	var player: int = SimAssembly.actors_of(sim).spawn(&"arcade", 0)
	assert_true(_do(sim, &"quest.accept", {"actor": player, "quest": "zz_sited"}), "accepted")
	assert_eq(quests.site_of(player, &"zz_sited"), &"m4_building", "bound to its site")
	assert_true(_do(sim, &"quest.accept", {"actor": player, "quest": "first_blood"}), "an unsited quest")
	assert_eq(quests.site_of(player, &"first_blood"), &"", "has no binding")
	var snap: Dictionary = quests.snapshot()
	var all: Dictionary = snap["quests"]
	var mine: Dictionary = all[player]
	var unsited: Dictionary = mine[&"first_blood"]
	assert_eq(unsited.size(), 2, "an unsited record keeps its M5 shape")
	var fresh_sim: SimRoot = SimAssembly.build(SEED, db)
	SimAssembly.actors_of(fresh_sim).spawn(&"arcade", 0)
	var fresh: QuestSystem = SimAssembly.quests_of(fresh_sim)
	assert_eq(fresh.restore(snap), OK, "restores")
	assert_eq(fresh.site_of(player, &"zz_sited"), &"m4_building", "the binding survives the round trip")
	var tampered: Dictionary = snap.duplicate(true)
	var t_all: Dictionary = tampered["quests"]
	var t_mine: Dictionary = t_all[player]
	var t_rec: Dictionary = t_mine[&"zz_sited"]
	t_rec["site"] = "home"
	assert_eq(fresh.restore(tampered), ERR_INVALID_DATA, "a binding the quest does not name is refused")
	var t_unsited: Dictionary = t_mine[&"first_blood"]
	t_rec["site"] = "m4_building"
	t_unsited["site"] = "home"
	assert_eq(fresh.restore(tampered), ERR_INVALID_DATA, "an unsited quest cannot carry a binding")


func test_assembly_refuses_a_quest_naming_an_unknown_site() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var quest: Dictionary = db.get_entry(&"quest", &"first_blood").duplicate(true)
	quest["site"] = "nowhere"
	assert_eq(db.add(&"quest", &"zz_lost", quest), OK, "added")
	assert_true(SimAssembly.build(SEED, db) == null, "refused")
