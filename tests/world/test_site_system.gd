extends GcityTest

## M6 spec claims 3–4: a site is content the sim raises with one command; the M4
## building is a site file by the same schema; Cold Storage stands with three routes
## in, each proving a different existing rule (a tag-checked door, a fire stair, a
## breachable grate over a tunnel).

const SEED: int = 20261180
const M: int = 1000

var _sim: SimRoot
var _sites: SiteSystem
var _build: BuildSystem
var _actors: ActorSystem
var _movement: MovementSystem
var _items: ItemSystem
var _player: int = 0


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	_sites = SimAssembly.sites_of(_sim)
	_build = SimAssembly.build_of(_sim)
	_actors = SimAssembly.actors_of(_sim)
	_movement = SimAssembly.movement_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_player = _actors.spawn(&"arcade", 0)


## Submits a command for the next tick and steps once. True when it was applied.
func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


func _raise(site: StringName) -> void:
	# the site's own parcels must be the builder's, exactly as the client transfers
	# them before raising (unparcelled land lets anyone build, and needs none of this)
	var db: ContentDb = _sim.get_system(&"content")
	var t: Dictionary = db.get_entry(SiteSystem.KIND_SITE, site)
	var parcels: Array = t["parcels"]
	if not parcels.is_empty():
		var at: int = _sim.get_tick() + 1
		_sim.submit(SimCommand.new(at, &"land.identify", {"actor": _player, "owner": "player"}))
		for p: Variant in parcels:
			var id_s: String = p
			_sim.submit(SimCommand.new(at, &"land.transfer", {"parcel": id_s, "owner": "player"}))
		_sim.step()
	assert_true(_sites.raise_site(_player, site), "raised %s" % site)


## Walks one cell in a direction at the actor's own pace; true when the cell changed.
func _walk(dx: int, dz: int) -> bool:
	var speed: int = _movement.speed_of(_player)
	var start: Vector3i = BuildSystem.cell_of(_actors.position_of(_player))
	for i: int in 40:
		if not _movement.move(_player, signi(dx) * speed, signi(dz) * speed):
			return false
		if BuildSystem.cell_of(_actors.position_of(_player)) != start:
			return true
	return false


## The middle of a site cell, at that level's floor.
func _at(site: StringName, rel: Vector3i) -> Vector3i:
	var centre: Vector3i = BuildSystem.cell_centre(_sites.cell_of(site, rel))
	return Vector3i(centre.x, rel.y * M, centre.z)


func test_the_m4_building_is_a_site_file_and_raises_whole() -> void:
	_setup()
	assert_true(_sites.site_ids().has(&"m4_test_building"), "the site is content")
	assert_false(_sites.is_raised(&"m4_test_building"), "not raised yet")
	_raise(&"m4_test_building")
	assert_true(_sites.is_raised(&"m4_test_building"), "raised")
	assert_eq(_sites.pieces_of(&"m4_test_building").size(), 197, "every piece of the building at human scale (M7.5 claim 6)")
	assert_eq(_sites.agents_of(&"m4_test_building").size(), 4, "and its four guards")
	for id: int in _sites.pieces_of(&"m4_test_building"):
		assert_true(_build.is_supported(id), "piece %d stands" % id)
	assert_false(_sites.raise_site(_player, &"m4_test_building"), "a second raise is refused")
	assert_eq(_build.piece_ids().size(), 197, "and nothing was placed twice")


func test_cold_storage_stands_with_its_three_routes_in() -> void:
	_setup()
	var site: StringName = &"cold_storage"
	_raise(site)
	assert_eq(_sites.pieces_of(site).size(), 711, "every piece of the site stands")
	assert_eq(_sites.agents_of(site).size(), 4, "four guards (design doc §15.3)")
	var unsupported: int = 0
	for id: int in _sites.pieces_of(site):
		if not _build.is_supported(id):
			unsupported += 1
	assert_eq(unsupported, 0, "every piece is supported")
	# the front route: the lobby door reads a token
	_actors.set_position(_player, _at(site, Vector3i(2, 2, -1)))
	assert_false(_walk(0, 1), "no token: the door is a wall")
	var token: int = _items.spawn(&"ammo", &"access_token", ItemSystem.inventory_of(_player), 1)
	assert_true(token > 0, "a stolen token")
	assert_true(_walk(0, 1), "with it, the door opens")
	assert_eq(BuildSystem.cell_of(_actors.position_of(_player)), _sites.cell_of(site, Vector3i(2, 2, 0)), "inside the lobby")
	# the side route: the fire stair outside the east wall, then the window
	_actors.set_position(_player, _at(site, Vector3i(5, 2, 7)))
	assert_true(_movement.is_standable(_sites.cell_of(site, Vector3i(5, 2, 7))), "the fire stair's foot, on the slab")
	for level: int in 3:
		assert_true(_movement.move(_player, 0, 0, 1), "up the fire stair, level %d of a storey" % (level + 1))
	assert_eq(_actors.position_of(_player).y, 5 * M, "on the upper landing")
	assert_true(_walk(-1, 0), "in through the maintenance window")
	assert_eq(BuildSystem.cell_of(_actors.position_of(_player)), _sites.cell_of(site, Vector3i(4, 5, 7)), "upstairs, inside")
	# the under route: the street grate, the tunnel, the ladder into the hall
	_actors.set_position(_player, _at(site, Vector3i(4, 2, -2)))
	assert_false(_movement.move(_player, 0, 0, -1), "the grate is shut: no way down")
	var grate: int = _build.face_piece_at(BuildSystem.face_key(_sites.cell_of(site, Vector3i(4, 2, -2)), "ny"))
	assert_true(grate > 0, "the grate is a piece in the street")
	assert_false(_build.remove(_player, grate).is_empty(), "cut it: the badlands let anyone build here")
	for level: int in 2:
		assert_true(_movement.move(_player, 0, 0, -1), "down the ladder into the tunnel, level %d of the slab" % (level + 1))
	assert_eq(_actors.position_of(_player).y, 0, "in the tunnel, under the slab")
	var walked: int = 0
	for i: int in 10:
		if _walk(0, 1):
			walked += 1
	assert_true(walked >= 9, "the tunnel runs north under the building (%d cells)" % walked)
	_actors.set_position(_player, _at(site, Vector3i(4, 0, 8)))
	for level: int in 2:
		assert_true(_movement.move(_player, 0, 0, 1), "and up the ladder into the back hall, level %d" % (level + 1))
	assert_eq(BuildSystem.cell_of(_actors.position_of(_player)), _sites.cell_of(site, Vector3i(4, 2, 8)), "inside, past the lobby entirely")


func test_a_site_raises_through_its_command_and_survives_the_round_trip() -> void:
	_setup()
	# the site's lot first: `site.raise` places as the actor, and the operator's land
	# is not the player's until it is transferred
	var at: int = _sim.get_tick() + 1
	assert_eq(_sim.submit(SimCommand.new(at, &"land.identify", {"actor": _player, "owner": "player"})), OK, "identify")
	assert_eq(_sim.submit(SimCommand.new(at, &"land.transfer", {"parcel": "cold_storage_lot", "owner": "player"})), OK, "transfer")
	_sim.step()
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, &"site.raise", {"actor": _player, "site": "cold_storage"})), OK, "submit")
	_sim.step()
	assert_eq(_sim.dispatched_count(), before + 1, "raised through the command")
	assert_true(_sites.is_raised(&"cold_storage"), "raised")
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var snap: Dictionary = _sim.snapshot()
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "restored")
	assert_eq(other.restore_root(snap), OK, "root restored")
	var sites: SiteSystem = SimAssembly.sites_of(other)
	assert_true(sites.is_raised(&"cold_storage"), "still raised")
	assert_eq(sites.pieces_of(&"cold_storage").size(), 711, "with its pieces")
	_sim.step()
	other.step()
	assert_eq(other.state_hash(), _sim.state_hash(), "hashes agree")
	var state: Dictionary = _sites.snapshot()
	assert_eq(sites.restore({}), ERR_INVALID_DATA, "empty")
	var bad: Dictionary = state.duplicate(true)
	var raised: Dictionary = bad["raised"]
	raised[&"nowhere"] = raised[&"cold_storage"]
	assert_eq(sites.restore(bad), ERR_INVALID_DATA, "an unknown site")
	bad = state.duplicate(true)
	raised = bad["raised"]
	var rec: Dictionary = raised[&"cold_storage"]
	rec["pieces"] = [9999]
	assert_eq(sites.restore(bad), ERR_INVALID_DATA, "a piece that is not standing")
	# M7.6 mutation pass (site_system.gd:412): a base at the world's edge restores, past it not
	bad = state.duplicate(true)
	raised = bad["raised"]
	rec = raised[&"cold_storage"]
	rec["base"] = [BuildSystem.MAX_CELL, 0, 0]
	assert_eq(sites.restore(bad), OK, "a base at the last cell is a base")
	rec["base"] = [BuildSystem.MAX_CELL + 1, 0, 0]
	assert_eq(sites.restore(bad), ERR_INVALID_DATA, "one past it is not")
	assert_eq(sites.restore(state), OK, "and the real state back")
	assert_eq(sites.snapshot(), state, "rejections leave the state untouched")


## M6 spec claim 4, the part the other tests do not reach: the under route has to work
## for somebody who owns nothing. The operator's lot begins at the building's wall, so
## the grate in the street is public and cutting it is legal; what it buys is a way in
## that never touches the lobby, the token or the operator's own property.
func test_the_under_route_is_a_break_in_by_somebody_who_owns_nothing() -> void:
	_setup()
	var site: StringName = &"cold_storage"
	# the operator raises its own building; the player is nobody and owns nothing
	var operator: int = _actors.spawn(&"arcade", 0)
	var at: int = _sim.get_tick() + 1
	assert_eq(_sim.submit(SimCommand.new(at, &"land.identify", {"actor": operator, "owner": "corp.coldchain"})), OK, "the operator is itself")
	_sim.step()
	assert_true(_sites.raise_site(operator, site), "the cold store stands on its own lot")
	var land: LandSystem = SimAssembly.land_of(_sim)
	assert_eq(land.owner_of(&"cold_storage_lot"), &"corp.coldchain", "and the lot is not the player's")
	assert_eq(land.parcel_at(_at(site, Vector3i(4, 2, -2))), &"", "the grate is out in the street")
	assert_eq(land.parcel_at(_at(site, Vector3i(4, 2, 8))), &"cold_storage_lot", "the back hall is not")
	# cutting a grate in a public street is nobody's business
	var before: int = land.violation_count()
	var grate: int = _build.face_piece_at(BuildSystem.face_key(_sites.cell_of(site, Vector3i(4, 2, -2)), "ny"))
	assert_true(grate > 0, "the grate")
	_actors.set_position(_player, _at(site, Vector3i(4, 2, -2)))
	assert_false(_build.remove(_player, grate).is_empty(), "cut it")
	assert_eq(land.violation_count(), before, "and no trespass: the street is public")
	# the tunnel goes under the wall, which is where the trespass starts
	for level: int in 2:
		assert_true(_movement.move(_player, 0, 0, -1), "down into the tunnel, level %d" % (level + 1))
	var walked: int = 0
	for i: int in 10:
		if _walk(0, 1):
			walked += 1
	assert_true(walked >= 9, "north under the building (%d cells)" % walked)
	_actors.set_position(_player, _at(site, Vector3i(4, 0, 8)))
	for level: int in 2:
		assert_true(_movement.move(_player, 0, 0, 1), "up the ladder, level %d" % (level + 1))
	assert_eq(BuildSystem.cell_of(_actors.position_of(_player)), _sites.cell_of(site, Vector3i(4, 2, 8)), "inside the operator's building, owning nothing")
	assert_eq(land.parcel_at(_actors.position_of(_player)), &"cold_storage_lot", "standing on their land")


## M6 spec claim 4, the thing every other test quietly skipped: you have to be able to
## walk up to the building. The slab is two cells above the pavement and a level change
## needs something to climb, so without a step at the edge the site is unreachable on
## foot and every test that "entered" it had placed the actor inside by hand.
func test_the_site_can_be_walked_into_from_the_street() -> void:
	_setup()
	var site: StringName = &"cold_storage"
	_raise(site)
	# start on bare ground, two cells south of the slab, at ground level
	var ground: Vector3i = BuildSystem.cell_centre(_sites.cell_of(site, Vector3i(4, 0, -7)))
	assert_eq(_actors.set_position(_player, Vector3i(ground.x, 0, ground.z)), OK, "out on the street")
	assert_eq(_actors.position_of(_player).y, 0, "at pavement level")
	var walked: int = 0
	for i: int in 30:
		if _walk(0, 1):
			walked += 1
		if BuildSystem.cell_of(_actors.position_of(_player)) == _sites.cell_of(site, Vector3i(4, 0, -5)):
			break
	assert_eq(BuildSystem.cell_of(_actors.position_of(_player)), _sites.cell_of(site, Vector3i(4, 0, -5)), "up to the foot of the step (%d cells)" % walked)
	for level: int in 2:
		assert_true(_movement.move(_player, 0, 0, 1), "up the step onto the slab, level %d" % (level + 1))
	assert_eq(_actors.position_of(_player).y, 2 * M, "two metres up, on the slab")
	# and on north across the street to the grate, without touching the lobby
	var reached: bool = false
	for i: int in 30:
		_walk(0, 1)
		if BuildSystem.cell_of(_actors.position_of(_player)) == _sites.cell_of(site, Vector3i(4, 2, -2)):
			reached = true
			break
	assert_true(reached, "standing on the grate, having walked the whole way")
	assert_eq(SimAssembly.land_of(_sim).parcel_at(_actors.position_of(_player)), &"", "still out in the public street")


## M6 spec claim 4: a guard with nothing in its hands cannot defend anything, so what
## the guard is holding is part of the site rather than something whoever raises it has
## to remember. Cold Storage's four guards come armed; the M4 building's do not,
## because its client arms them itself.
func test_a_site_arms_the_guards_it_raises() -> void:
	_setup()
	_raise(&"cold_storage")
	var items: ItemSystem = SimAssembly.items_of(_sim)
	var armed: int = 0
	for guard: int in _sites.agents_of(&"cold_storage"):
		var weapon: int = _actors.wielded(guard)
		if weapon == EntityIds.NONE:
			continue
		armed += 1
		assert_eq(items.item_template(weapon), &"g19", "guard %d holds the kit's frame" % guard)
		var magazine: int = items.magazine_of(weapon)
		assert_true(magazine > 0, "with a magazine in it")
		assert_eq(items.rounds_in(magazine).size(), 14, "fourteen in the magazine")
		assert_true(items.chambered(weapon) > 0, "and one chambered")
		assert_eq(items.container_of(weapon), ItemSystem.inventory_of(guard), "carried, not lying about")
	assert_eq(armed, 4, "all four guards are armed")
	_setup()
	_raise(&"m4_test_building")
	for guard: int in _sites.agents_of(&"m4_test_building"):
		assert_eq(_actors.wielded(guard), EntityIds.NONE, "the M4 guards are still empty-handed")


## M7 spec claim 10: Cold Storage becomes a bound site. Raised with its contract, the
## building goes up where the contract's handle is bound, out in the wilds, and its lot,
## its guards' rounds and its terminals go with it; the ground under and round it is
## levelled first. Nothing in the site's content changes, only where it goes.
func test_a_site_raised_with_its_contract_stands_where_the_contract_bound_it() -> void:
	_setup()
	var binder: SiteBinder = SimAssembly.binder_of(_sim)
	var routes: RouteGraph = SimAssembly.routes_of(_sim)
	var regions: Regions = SimAssembly.regions_of(_sim)
	var land: LandSystem = SimAssembly.land_of(_sim)
	var perception: PerceptionSystem = SimAssembly.perception_of(_sim)
	var terminals: TerminalSystem = SimAssembly.terminals_of(_sim)
	var operator: int = _actors.spawn(&"arcade", 0)
	assert_true(_do(&"land.identify", {"actor": operator, "owner": "corp.coldchain"}), "the operator is the owner")
	assert_false(_do(&"site.raise", {"actor": operator, "site": "cold_storage", "quest": "cold_storage"}), "no contract taken, nowhere to raise it")
	assert_true(_do(&"quest.accept", {"actor": _player, "quest": "cold_storage"}), "the contract is taken")
	var slot: int = binder.slot_of(&"cold_storage")
	assert_true(_do(&"site.raise", {"actor": operator, "site": "cold_storage", "quest": "cold_storage"}), "and raised where it bound")
	var at: Vector2i = routes.slot_position(slot)
	var base: Vector3i = _sites.base_of(&"cold_storage")
	assert_eq(Vector2i(base.x, base.z), Vector2i(Terrain._floor_div(at.x, M), Terrain._floor_div(at.y, M)), "at the slot")
	assert_eq(regions.region_at(at.x, at.y).id(), &"wilds", "out in the wilds")
	assert_eq(_sites.pieces_of(&"cold_storage").size(), 711, "every piece of it")
	# the lot moved with it
	var authored: Vector3i = Vector3i(40, 0, 40)
	var offset: Vector3i = (base - authored) * M
	assert_eq(land.parcel_at(Vector3i(42 * M, 500, 45 * M) + offset), &"cold_storage_lot", "the lot is under the building")
	assert_eq(land.parcel_at(Vector3i(42 * M, 500, 45 * M)), &"", "and not where content first put it")
	# the ground is level round it: standing ground at the base across the street
	for dx: int in [-6, 0, 12]:
		var cell: Vector3i = base + Vector3i(dx, 0, -7)
		assert_true(regions.stands_on_ground(cell), "the street round it is level ground (%s)" % cell)
	# its guards walk their rounds where the building is, and its terminals are up there
	for agent: int in _sites.agents_of(&"cold_storage"):
		assert_eq(perception.route_offset(agent), base - authored, "guard %d's round moved with the building" % agent)
	for terminal: int in _sites.terminals_of(&"cold_storage"):
		assert_true(absi(terminals.position_of(terminal).y - (base.y + 1) * M) <= M, "the terminal is on the floor it stands on")
	# and a save of it loads with the building where it is
	var snap: Dictionary = _sim.snapshot()
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "a save with the building out there loads")
	assert_eq(SimAssembly.sites_of(other).base_of(&"cold_storage"), base, "with it where it was")
	var good: Dictionary = _sites.snapshot()
	var bad: Dictionary = good.duplicate(true)
	bad["raised"]["cold_storage"]["base"] = [1, 2]
	assert_eq(_sites.restore(bad), ERR_INVALID_DATA, "a base that is not a cell is refused")
	assert_eq(_sites.snapshot(), good, "and nothing changed")


## M7.5 spec claim 8: a bound site's levelling clears from its base to a storey over its
## top, where someone on the roof stands, and no further; under the base it fills. Set
## into a hillside well below the ground, so every one of those rows had ground to take.
func test_levelling_leaves_a_storey_of_air_over_the_roof_and_no_more() -> void:
	_setup()
	var regions: Regions = SimAssembly.regions_of(_sim)
	var db: ContentDb = _sim.get_system(&"content")
	var t: Dictionary = db.get_entry(SiteSystem.KIND_SITE, &"cold_storage")
	var top: int = SiteSystem.top_of(t)
	assert_eq(top, 8, "Cold Storage's roof is eight levels up: a slab and two storeys")
	assert_eq(SiteSystem.top_of(db.get_entry(SiteSystem.KIND_SITE, &"m4_test_building")), 3, "the M4 building's is a storey up")
	# M7.5 mutation pass 1: a site that is only a floor on the ground tops out at the ground
	assert_eq(SiteSystem.top_of({"pieces": [{"piece": "floor_panel", "rel": [0, 0, 0], "facing": "ny"}]}), 0, "a ground floor alone is at 0")
	var column: Vector2i = Vector2i(300, -1500)
	var ground: int = regions.standing_cell_y(column.x * M, column.y * M)
	var base: Vector3i = Vector3i(column.x, ground - top - SiteSystem.LEVEL_HEADROOM - 4, column.y)
	_sites._level(base, t)
	var person: int = _movement.body_cells(_player)
	for rel: Vector3i in [Vector3i(0, 0, 0), Vector3i(5, 0, 7), Vector3i(-SiteSystem.LEVEL_MARGIN, 0, 2)]:
		var at: Vector3i = base + rel
		for y: int in range(0, top + SiteSystem.LEVEL_HEADROOM):
			assert_false(regions.is_solid(at + Vector3i(0, y, 0)), "air %d up at %s" % [y, at])
		assert_true(regions.is_solid(at + Vector3i(0, top + SiteSystem.LEVEL_HEADROOM, 0)), "and the ground a storey over the roof is left (%s)" % at)
		assert_true(regions.is_solid(at - Vector3i(0, 1, 0)), "with ground under the base")
		assert_true(_movement.body_fits(at + Vector3i(0, top, 0), person), "a person fits on the roof")
	assert_true(person >= 2 and SiteSystem.LEVEL_HEADROOM > person, "and a storey is more than a person (%d over %d)" % [SiteSystem.LEVEL_HEADROOM, person])


## Gate item 27: Cold Storage is a closed building. Its inside is one volume of the
## portal graph, not the outside, and nobody walks in at the back: from M6 until M7.5 the
## back wall stopped a cell short at both corners and the server room was open from the
## north, so the squad planner never saw an inside to plan entries into either.
func test_cold_storage_is_closed_and_nobody_walks_in_at_the_back() -> void:
	_setup()
	_raise(&"cold_storage")
	var portals: PortalGraph = SimAssembly.portals_of(_sim)
	var inside: int = portals.node_at(_sites.cell_of(&"cold_storage", Vector3i(1, 2, 1)))
	assert_true(inside != PortalGraph.EXTERIOR and inside != PortalGraph.SOLID, "the lobby is inside something")
	for rel: Vector3i in [Vector3i(2, 2, 6), Vector3i(2, 2, 9), Vector3i(0, 2, 11), Vector3i(4, 2, 11), Vector3i(1, 5, 2)]:
		assert_eq(portals.node_at(_sites.cell_of(&"cold_storage", rel)), inside, "and so is %s" % rel)
	for x: int in [0, 4]:
		var start: Vector3i = _sites.cell_of(&"cold_storage", Vector3i(x, 2, 12))
		_actors.set_position(_player, BuildSystem.cell_centre(start) - Vector3i(0, M / 2, 0))
		_sim.step_n(3)
		for i: int in 30:
			_movement.move(_player, 0, -100)
		assert_eq(BuildSystem.cell_of(_actors.position_of(_player)), start, "walking in from the north at x %d goes nowhere" % x)


## Gate item 36: the archive is entered by its door. From M6 until M7.5 the side passages
## north of the hall opened into it, and a person in the hall walked round its
## token-checked door. (They still open into the server room, which has no lock.)
func test_the_archive_is_entered_only_by_its_door() -> void:
	_setup()
	_raise(&"cold_storage")
	for walk: Array in [[Vector3i(0, 2, 11), 100], [Vector3i(4, 2, 11), -100]]:
		var rel: Vector3i = walk[0]
		var dx: int = walk[1]
		var start: Vector3i = _sites.cell_of(&"cold_storage", rel)
		_actors.set_position(_player, BuildSystem.cell_centre(start) - Vector3i(0, M / 2, 0))
		_sim.step_n(3)
		for i: int in 30:
			_movement.move(_player, dx, 0)
		assert_eq(BuildSystem.cell_of(_actors.position_of(_player)), start, "from the passage at %s nobody walks into the archive" % rel)
	var portals: PortalGraph = SimAssembly.portals_of(_sim)
	var hall: int = portals.node_at(_sites.cell_of(&"cold_storage", Vector3i(2, 2, 9)))
	var archive: int = portals.node_at(_sites.cell_of(&"cold_storage", Vector3i(2, 2, 11)))
	assert_true(archive != hall and archive != PortalGraph.EXTERIOR and archive != PortalGraph.SOLID, "the archive is a room of its own")
	var id: int = _build.face_piece_at(BuildSystem.face_key(_sites.cell_of(&"cold_storage", Vector3i(2, 2, 10)), "pz"))
	assert_eq(_build.template_of(id), &"door_archive", "and its way in is its door")


## M7.5 Q4 (standards §11): a three-cell warehouse door on Cold Storage's loading side,
## added with content and `tools/make_sites.gd` only, zero `sim/` diff. It stands as three
## stacked faces of `door_warehouse`, it is an edge from the lobby to the outside, and a
## squad outside with the player in the lobby is offered it as an entry.
func test_the_warehouse_door_is_offered_to_a_squad_as_an_entry() -> void:
	_setup()
	_raise(&"cold_storage")
	var perception: PerceptionSystem = SimAssembly.perception_of(_sim)
	var squads: SquadSystem = SimAssembly.squads_of(_sim)
	var portals: PortalGraph = SimAssembly.portals_of(_sim)
	var doors: Array[int] = []
	for row: int in 3:
		var id: int = _build.face_piece_at(BuildSystem.face_key(_sites.cell_of(&"cold_storage", Vector3i(0, 2 + row, 1)), "nx"))
		assert_eq(_build.template_of(id), &"door_warehouse", "a warehouse door face, row %d" % row)
		doors.append(id)
	var lobby: int = portals.node_at(_sites.cell_of(&"cold_storage", Vector3i(1, 2, 1)))
	var outward: int = 0
	for e: Array in portals.edges_of(lobby):
		var piece: int = e[0]
		var other: int = e[1]
		if doors.has(piece) and other == PortalGraph.EXTERIOR:
			outward += 1
	assert_eq(outward, 3, "all three are edges from the lobby to the outside")
	_actors.set_position(_player, BuildSystem.cell_centre(_sites.cell_of(&"cold_storage", Vector3i(1, 2, 1))) - Vector3i(0, M / 2, 0))
	var members: Array[int] = []
	for rel: Vector3i in [Vector3i(-2, 2, 1), Vector3i(-2, 2, 4), Vector3i(1, 2, -3)]:
		var member: int = perception.spawn(&"guard_sim", _sites.cell_of(&"cold_storage", rel), 0, 9, "")
		assert_true(member != EntityIds.NONE, "a squad member outside at %s" % rel)
		members.append(member)
	_sim.step()
	for member: int in members:
		perception.receive_report(member, _player, _actors.position_of(_player), _sim.get_tick())
	_sim.step_n(30)
	for member: int in members:
		assert_true(perception.has_last_known(member, _player) or perception.is_alerted(member, _player), "%d knows where the player is" % member)
	var outside: Vector3i = _sites.cell_of(&"cold_storage", Vector3i(-1, 2, 1))
	var offered: int = 0
	for member: int in members:
		if squads.has_assignment(member) and squads.assignment_of(member) == outside:
			offered += 1
	assert_eq(offered, 1, "one member is sent to the warehouse door, at the street outside it")


## Found by the G7 mutation run: no site file offered placed the same piece twice, and
## the terminals a raised site records were only ever counted by the terminal tests.
func test_a_site_placing_two_pieces_in_one_spot_fails_assembly() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var twin: Dictionary = db.get_entry(SiteSystem.KIND_SITE, &"m4_test_building").duplicate(true)
	assert_eq(db.add(SiteSystem.KIND_SITE, &"twin", twin), OK, "a copy of a site")
	assert_true(SimAssembly.build(SEED, db) != null, "assembles as it is")
	var doubled: ContentDb = ContentDb.new()
	assert_eq(ContentLoader.load_all(doubled), OK, "content loads")
	var pieces: Array = twin["pieces"]
	pieces.append(pieces[0])
	assert_eq(doubled.add(SiteSystem.KIND_SITE, &"twin", twin), OK, "the copy with its first piece twice")
	assert_true(SimAssembly.build(SEED, doubled) == null, "refused")


func test_a_raised_site_records_the_terminals_it_placed() -> void:
	_setup()
	_raise(&"cold_storage")
	assert_eq(_sites.terminals_of(&"cold_storage").size(), 2, "the server and the archive")


## M7.6 claim 2: `site.raise` with `at` stands the site with its base in that cell, under
## the raiser's rights there; the two older forms are unchanged (every fixture replays).
func test_a_site_raises_with_its_base_where_it_is_put() -> void:
	_setup()
	# the creator's lots, the player's: a site goes up under its raiser's rights where it is put
	assert_true(_do(&"land.identify", {"actor": _player, "owner": "player"}), "the player is somebody")
	for lot: String in SiteCreator.LOTS:
		assert_true(_do(&"land.transfer", {"parcel": lot, "owner": "player"}), "and owns %s" % lot)
	var at: Vector3i = Vector3i(41, 0, 41)
	assert_false(_do(&"site.raise", {"actor": _player, "site": "m4_test_building", "at": [3, 0]}), "two numbers: refused")
	assert_false(_do(&"site.raise", {"actor": _player, "site": "m4_test_building", "at": [3, 0, 3.5]}), "a fraction: refused")
	assert_false(_do(&"site.raise", {"actor": _player, "site": "m4_test_building", "at": [3, 0, BuildSystem.MAX_CELL + 1]}), "out of the world: refused")
	assert_true(_do(&"site.raise", {"actor": _player, "site": "m4_test_building", "at": [at.x, at.y, at.z]}), "raised at the cell")
	var db: ContentDb = _sim.get_system(&"content")
	var t: Dictionary = db.get_entry(SiteSystem.KIND_SITE, &"m4_test_building")
	var pieces: Array = t["pieces"]
	assert_eq(_sites.pieces_of(&"m4_test_building").size(), pieces.size(), "every piece stands")
	assert_eq(_sites.cell_of(&"m4_test_building", Vector3i.ZERO), at, "with its base where it was put")
	var first: Dictionary = pieces[0]
	var rel: Vector3i = PathingSystem._vec(first["rel"])
	var facing: String = first["facing"]
	var id: int = _build.cell_piece_at(at + rel) if facing.is_empty() else _build.face_piece_at(BuildSystem.face_key(at + rel, facing))
	assert_true(id != EntityIds.NONE, "its first piece is at base + rel")


## M7.6 gate item 6 (CEOGG, 2026-10-07: the sandbox's clear un-raises sites): a site comes
## down only once nothing of it stands, its terminals with it, and then raises again whole.
func test_a_site_is_lowered_only_once_nothing_of_it_stands() -> void:
	_setup()
	_raise(&"cold_storage")
	var terminals: TerminalSystem = SimAssembly.terminals_of(_sim)
	var placed: Array[int] = _sites.terminals_of(&"cold_storage")
	assert_false(_sites.lower(&"m4_test_building"), "a site not raised: refused")
	# its guards first: one dead (bodies stay, item 3), the others removed
	var guards: Array[int] = _sites.agents_of(&"cold_storage")
	assert_true(guards.size() >= 2, "guards posted")
	for node: StringName in _actors.health_of(guards[0]):
		_actors.damage_node(guards[0], node, 1_000_000)
	assert_false(_actors.is_alive(guards[0]), "one guard dead")
	for guard: int in guards.slice(1):
		assert_true(_actors.remove(guard, ItemSystem.WORLD), "the others removed")
	assert_false(_sites.lower(&"cold_storage"), "no guard stands, but its pieces do: refused")
	assert_true(_sites.is_raised(&"cold_storage"), "still raised")
	var progress: bool = true
	while progress:
		progress = false
		for piece: int in _sites.pieces_of(&"cold_storage"):
			if _build.has_piece(piece) and not _build.remove(_player, piece).is_empty():
				progress = true
	assert_eq(_sites.pieces_of(&"cold_storage").filter(func(p: int) -> bool: return _build.has_piece(p)), [], "every piece gone")
	assert_true(_sites.lower(&"cold_storage"), "nothing of it stands: lowered")
	assert_false(_sites.is_raised(&"cold_storage"), "no longer raised")
	assert_true(_actors.has_actor(guards[0]), "the body stays (item 3)")
	for terminal: int in placed:
		assert_false(terminals.has_terminal(terminal), "its terminals went with it")
	assert_true(_sites.raise_site(_player, &"cold_storage"), "and it raises again")
	assert_eq(_sites.terminals_of(&"cold_storage").size(), 2, "with its two terminals, once each")
	assert_eq(terminals.terminal_ids().size(), 2, "and no old one left")


## A guard still standing keeps the site up, with every piece gone.
func test_a_site_with_a_guard_standing_is_not_lowered() -> void:
	_setup()
	_raise(&"cold_storage")
	var progress: bool = true
	while progress:
		progress = false
		for piece: int in _sites.pieces_of(&"cold_storage"):
			if _build.has_piece(piece) and not _build.remove(_player, piece).is_empty():
				progress = true
	assert_false(_sites.lower(&"cold_storage"), "its guards stand: refused")
	assert_true(_sites.is_raised(&"cold_storage"), "still raised")
