extends GcityTest

## M6 spec claim 12: a site is content, raised by `site.spawn {site, origin}` in one
## step. Its parcels go to its owner tag, its basement is dug, its pieces go in as one
## all-or-nothing batch without rights, its sensors watch their pieces, its hack targets
## sit at their cells (tied to their piece), its agents patrol routes measured from the
## origin, and its exfil polygon answers "is this out". A refused spawn changes nothing.
## Metamorphic: spawning at another origin moves everything by the difference.

const SEED: int = 20261038
const O1: Vector3i = Vector3i(500, 0, 500)
const O2: Vector3i = Vector3i(-340, 0, 712)


func _site() -> Dictionary:
	var pieces: Array = []
	for c: Array in [[-1, 0, 0], [0, 0, 1], [0, 0, -1], [3, 0, 0]]:
		pieces.append({"piece": "foundation_block", "cell": c, "facing": "", "sensor": "", "squad": 0})
	pieces.append({"piece": "floor_panel", "cell": [0, 0, 0], "facing": "py", "sensor": "", "squad": 0})
	pieces.append({"piece": "window_frame", "cell": [0, 0, 0], "facing": "px", "sensor": "power_monitor", "squad": 1})
	pieces.append({"piece": "street_grate", "cell": [2, -1, 0], "facing": "py", "sensor": "", "squad": 0})
	return {"schema_version": 1, "description": "test", "district": "starter_ghetto", "owner": "zz_corp",
		"parcels": [{"id": "yard", "footprint": [[-2, -2], [5, -2], [5, 5], [-2, 5]], "floor": -1, "ceiling": 3, "district": "", "owner": ""}],
		"excavate": [[2, -1, 0]],
		"pieces": pieces,
		"agents": [{"profile": "guard_sim", "cell": [1, 0, 3], "facing": 0, "squad": 1, "route": "zz_rel"}],
		"hack_targets": [{"target": "power_monitor_spoof", "cell": [1, 0, 0], "piece": 5}],
		"containers": [{"piece": 3, "items": [{"kind": "key_item", "template": "cold_storage_keycard"}, {"kind": "ammo", "template": "9x19_fmj"}]}],
		"placement": [0, 0, 0], "exfil": [[6, 6], [9, 6], [9, 9], [6, 9]]}


func _db(patch: Dictionary = {}) -> ContentDb:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	assert_eq(db.add(&"patrol_route", &"zz_rel", {"schema_version": 1, "description": "test", "cells": [[1, 0, 3], [4, 0, 3]]}), OK, "a route in site cells")
	var site: Dictionary = _site()
	site.merge(patch, true)
	assert_eq(db.add(&"site", &"zz_shed", site), OK, "the test site")
	var twin: Dictionary = _site()
	assert_eq(db.add(&"site", &"zz_twin", twin), OK, "its twin, for collisions")
	return db


func _sim(db: ContentDb = null) -> SimRoot:
	var sim: SimRoot = SimAssembly.build(SEED, db if db != null else _db())
	assert_true(sim != null, "assembly")
	return sim


func _spawn(sim: SimRoot, site: String, origin: Vector3i) -> bool:
	var before: int = sim.dispatched_count()
	sim.submit(SimCommand.new(sim.get_tick() + 1, &"site.spawn", {"site": site, "origin": [origin.x, origin.y, origin.z]}))
	sim.step()
	return sim.dispatched_count() == before + 1


## What a spawn can touch. Time moves on with each step (a spawned guard patrols), so
## the whole sim is not the right comparison; these systems and the agent list are.
func _systems(sim: SimRoot) -> String:
	var systems: Dictionary = sim.snapshot()["systems"]
	var touched: Dictionary = {"agents": SimAssembly.perception_of(sim).agent_ids()}
	for key: String in ["build", "land", "entities", "sites", "sensors", "hacks"]:
		touched[key] = systems[key]
	return StateHash.of(touched)


func test_a_site_spawns_everything_it_declares() -> void:
	var sim: SimRoot = _sim()
	var spawned: Array[Dictionary] = []
	SimAssembly.combat_of(sim).events().subscribe(SiteSystem.EVENT_SPAWNED, func(p: Dictionary) -> void: spawned.append(p))
	assert_true(_spawn(sim, "zz_shed", O1), "spawned")
	var build: BuildSystem = SimAssembly.build_of(sim)
	var land: LandSystem = SimAssembly.land_of(sim)
	var sites: SiteSystem = SimAssembly.sites_of(sim)
	assert_eq(build.piece_ids().size(), 7, "seven pieces")
	assert_eq(land.owner_of(&"zz_shed_yard"), &"zz_corp", "its parcel, owned by the site's tag")
	assert_eq(land.district_of(&"zz_shed_yard"), &"starter_ghetto", "in its district")
	assert_false(build.is_solid(O1 + Vector3i(2, -1, 0)), "the shaft under the grate is dug")
	var window: int = build.face_piece_at(BuildSystem.face_key(O1, "px"))
	assert_true(SimAssembly.sensors_of(sim).has_sensor(window), "the window has its monitor")
	var targets: Dictionary = SimAssembly.hacks_of(sim).snapshot()["targets"]
	assert_eq(targets.size(), 1, "one hack target")
	var target: Dictionary = targets.values()[0]
	assert_eq(target["piece"], window, "tied to the window")
	assert_eq(target["cell"], [O1.x + 1, 0, O1.z] as Array[int], "at its cell")
	var perception: PerceptionSystem = SimAssembly.perception_of(sim)
	assert_eq(perception.agent_ids().size(), 1, "one guard")
	var guard: int = perception.agent_ids()[0]
	assert_eq(BuildSystem.cell_of(SimAssembly.actors_of(sim).position_of(guard)), O1 + Vector3i(1, 0, 3), "at its post")
	assert_eq(perception.route_origin_of(guard), O1, "patrolling from the site's origin")
	assert_true(sites.in_exfil(&"zz_shed", BuildSystem.cell_centre(O1 + Vector3i(7, 0, 7))), "the exfil zone")
	assert_false(sites.in_exfil(&"zz_shed", BuildSystem.cell_centre(O1)), "the shed is not out")
	assert_eq(spawned, [{"site": &"zz_shed", "x": O1.x, "y": O1.y, "z": O1.z}], "site.spawned")
	# M6 claims 13 and 16: a site's crate is a place holding what the site puts in it
	var crates: Array[StringName] = sites.crates_of(&"zz_shed")
	assert_eq(crates.size(), 1, "one crate")
	var corpses: CorpseSystem = SimAssembly.corpses_of(sim)
	assert_eq(corpses.position_of(crates[0]), BuildSystem.cell_centre(O1 + Vector3i(3, 0, 0)) - Vector3i(0, BuildSystem.CELL / 2, 0), "at its piece's cell")
	var items: ItemSystem = SimAssembly.items_of(sim)
	var held: Array[StringName] = []
	for id: int in items.items_in(crates[0]):
		held.append(items.item_template(id))
	assert_eq(held, [&"cold_storage_keycard", &"9x19_fmj"] as Array[StringName], "the keycard and a round, in order")
	assert_false(_spawn(sim, "zz_shed", O2), "a site spawns once")
	assert_eq(land.violation_count(), 0, "no rights asked")


func test_metamorphic_another_origin_moves_everything_by_the_difference() -> void:
	var layouts: Array = []
	for origin: Vector3i in [O1, O2]:
		var sim: SimRoot = _sim()
		assert_true(_spawn(sim, "zz_shed", origin), "spawned at %s" % origin)
		var build: BuildSystem = SimAssembly.build_of(sim)
		var rows: Array[String] = []
		for id: int in build.piece_ids():
			rows.append("%s %s %s" % [build.template_of(id), build.cell_of_piece(id) - origin, build.facing_of(id)])
		var actors: ActorSystem = SimAssembly.actors_of(sim)
		for a: int in SimAssembly.perception_of(sim).agent_ids():
			rows.append("agent %s" % (actors.position_of(a) - origin * BuildSystem.CELL))
		sim.step_n(400)
		for a: int in SimAssembly.perception_of(sim).agent_ids():
			rows.append("agent later %s" % (BuildSystem.cell_of(actors.position_of(a)) - origin))
		layouts.append(rows)
	assert_eq(layouts[0], layouts[1], "the same site, moved")


func test_a_refused_spawn_changes_nothing() -> void:
	var sim: SimRoot = _sim()
	assert_true(_spawn(sim, "zz_shed", O1), "the first")
	var before: String = _systems(sim)
	assert_false(_spawn(sim, "zz_twin", O1 + Vector3i(3, 0, 3)), "a twin whose parcel overlaps: refused")
	assert_eq(_systems(sim), before, "nothing changed")
	# a piece in the way, on unparcelled ground
	sim = _sim()
	var player: int = SimAssembly.actors_of(sim).spawn(&"arcade", 0)
	SimAssembly.actors_of(sim).set_position(player, BuildSystem.cell_centre(O2 + Vector3i(-20, 0, -20)) - Vector3i(0, 500, 0))
	assert_true(SimAssembly.build_of(sim).place(player, &"foundation_block", BuildSystem.cell_centre(O2 + Vector3i(1, 0, 0)), "") > 0, "a block where the shed's window looks out")
	before = _systems(sim)
	assert_false(_spawn(sim, "zz_shed", O2 + Vector3i(1, 0, 0) - Vector3i(-1, 0, 0)), "the shed's foundation lands on it: refused")
	assert_eq(_systems(sim), before, "nothing changed")
	# someone standing where a crate of the site would go
	SimAssembly.actors_of(sim).set_position(player, BuildSystem.cell_centre(O1 + Vector3i(3, 0, 0)) - Vector3i(0, 500, 0))
	before = _systems(sim)
	assert_false(_spawn(sim, "zz_shed", O1), "an actor in a piece's cell: refused")
	assert_eq(_systems(sim), before, "nothing changed")
	for bad: Dictionary in [{}, {"site": "zz_shed"}, {"site": "zz_nothing", "origin": [0, 0, 0]}, {"site": "zz_shed", "origin": [0, 0]}, {"site": "zz_shed", "origin": [0, 9, 0]}]:
		var n: int = sim.dispatched_count()
		sim.submit(SimCommand.new(sim.get_tick() + 1, &"site.spawn", bad))
		sim.step()
		assert_eq(sim.dispatched_count(), n, "refused: %s" % str(bad))


func test_site_content_is_validated() -> void:
	var patches: Array[Dictionary] = [
		{"owner": "Bad Tag"},
		{"district": "zz_nowhere"},
		{"pieces": [{"piece": "zz_nothing", "cell": [0, 0, 0], "facing": "", "sensor": "", "squad": 0}]},
		{"pieces": [{"piece": "window_frame", "cell": [0, 0, 0], "facing": "px", "sensor": "power_monitor", "squad": 0}]},
		{"hack_targets": [{"target": "power_monitor_spoof", "cell": [0, 0, 0], "piece": 99}]},
		{"agents": [{"profile": "guard_sim", "cell": [0, 0, 0], "facing": 0, "squad": 1, "route": "zz_nothing"}]},
		{"placement": [0, 0, 0], "exfil": [[0, 0], [1, 0]]},
		{"parcels": [{"id": "a", "footprint": [[0, 0], [1, 0], [1, 1], [0, 1]], "floor": 1, "ceiling": 1, "district": "", "owner": ""}]},
		{"containers": [{"piece": 99, "items": []}]},
		{"containers": [{"piece": 0, "items": [{"kind": "key_item", "template": "zz_nothing"}]}]},
		{"containers": [{"piece": 0, "items": [{"kind": "stat", "template": "hit_chance"}]}]},
		{"containers": [{"piece": 0}]},
	]
	for patch: Dictionary in patches:
		assert_eq(SimAssembly.build(SEED, _db(patch)), null, "rejected: %s" % str(patch))


func test_the_spawned_record_survives_the_restore() -> void:
	var sim: SimRoot = _sim()
	assert_true(_spawn(sim, "zz_shed", O1), "spawned")
	var other: SimRoot = _sim()
	assert_eq(SimAssembly.restore_systems(other, sim.snapshot()), OK, "restores")
	assert_true(SimAssembly.sites_of(other).is_spawned(&"zz_shed"), "spawned")
	assert_eq(SimAssembly.sites_of(other).origin_of(&"zz_shed"), O1, "where")
	assert_eq(SimAssembly.sites_of(other).crates_of(&"zz_shed"), SimAssembly.sites_of(sim).crates_of(&"zz_shed"), "its crate")
	var good: Dictionary = {"origin": [0, 0, 0], "pieces": [1, 2], "agents": [3], "targets": [1], "crates": ["crate.1"]}
	assert_eq(SimAssembly.sites_of(other).restore({"spawned": {"zz_nothing": good}}), ERR_INVALID_DATA, "an unknown site is refused")
	for patch: Dictionary in [{"origin": [0, 0]}, {"pieces": [1, 1]}, {"agents": [0]}, {"targets": ["1"]}, {"crates": ["pile.1"]}, {"crates": [1]}, {"extra": 1}]:
		var bad: Dictionary = good.duplicate(true)
		bad.merge(patch, true)
		assert_eq(SimAssembly.sites_of(other).restore({"spawned": {"zz_shed": bad}}), ERR_INVALID_DATA, "refused: %s" % str(patch))
	assert_eq(SimAssembly.sites_of(other).pieces_of(&"zz_shed").size(), 7, "the shed's seven pieces are remembered")
	assert_eq(SimAssembly.sites_of(other).agents_of(&"zz_shed").size(), 1, "its guard")
	assert_eq(SimAssembly.sites_of(other).targets_of(&"zz_shed").size(), 1, "its hack target")
