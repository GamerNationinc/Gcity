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


func test_the_m4_building_is_a_site_file_and_raises_as_it_always_did() -> void:
	_setup()
	assert_true(_sites.site_ids().has(&"m4_test_building"), "the site is content")
	assert_false(_sites.is_raised(&"m4_test_building"), "not raised yet")
	_raise(&"m4_test_building")
	assert_true(_sites.is_raised(&"m4_test_building"), "raised")
	assert_eq(_sites.pieces_of(&"m4_test_building").size(), 93, "the same ninety-three pieces as the hand-built one")
	assert_eq(_sites.agents_of(&"m4_test_building").size(), 4, "and its four guards")
	for id: int in _sites.pieces_of(&"m4_test_building"):
		assert_true(_build.is_supported(id), "piece %d stands" % id)
	assert_false(_sites.raise_site(_player, &"m4_test_building"), "a second raise is refused")
	assert_eq(_build.piece_ids().size(), 93, "and nothing was placed twice")


func test_cold_storage_stands_with_its_three_routes_in() -> void:
	_setup()
	var site: StringName = &"cold_storage"
	_raise(site)
	assert_eq(_sites.pieces_of(site).size(), 366, "every piece of the site stands")
	assert_eq(_sites.agents_of(site).size(), 4, "four guards (design doc §15.3)")
	var unsupported: int = 0
	for id: int in _sites.pieces_of(site):
		if not _build.is_supported(id):
			unsupported += 1
	assert_eq(unsupported, 0, "every piece is supported")
	# the front route: the lobby door reads a token
	_actors.set_position(_player, _at(site, Vector3i(2, 1, -1)))
	assert_false(_walk(0, 1), "no token: the door is a wall")
	var token: int = _items.spawn(&"ammo", &"access_token", ItemSystem.inventory_of(_player), 1)
	assert_true(token > 0, "a stolen token")
	assert_true(_walk(0, 1), "with it, the door opens")
	assert_eq(BuildSystem.cell_of(_actors.position_of(_player)), _sites.cell_of(site, Vector3i(2, 1, 0)), "inside the lobby")
	# the side route: the fire stair outside the east wall, then the window
	_actors.set_position(_player, _at(site, Vector3i(5, 1, 7)))
	assert_true(_movement.is_standable(_sites.cell_of(site, Vector3i(5, 1, 7))), "the fire stair's foot, on the slab")
	assert_true(_movement.move(_player, 0, 0, 1), "up the fire stair")
	assert_eq(_actors.position_of(_player).y, 2 * M, "on the upper landing")
	assert_true(_walk(-1, 0), "in through the maintenance window")
	assert_eq(BuildSystem.cell_of(_actors.position_of(_player)), _sites.cell_of(site, Vector3i(4, 2, 7)), "upstairs, inside")
	# the under route: the street grate, the tunnel, the ladder into the hall
	_actors.set_position(_player, _at(site, Vector3i(4, 1, -2)))
	assert_false(_movement.move(_player, 0, 0, -1), "the grate is shut: no way down")
	var grate: int = _build.face_piece_at(BuildSystem.face_key(_sites.cell_of(site, Vector3i(4, 1, -2)), "ny"))
	assert_true(grate > 0, "the grate is a piece in the street")
	assert_false(_build.remove(_player, grate).is_empty(), "cut it: the badlands let anyone build here")
	assert_true(_movement.move(_player, 0, 0, -1), "down the ladder into the tunnel")
	assert_eq(_actors.position_of(_player).y, 0, "in the tunnel, under the slab")
	var walked: int = 0
	for i: int in 10:
		if _walk(0, 1):
			walked += 1
	assert_true(walked >= 9, "the tunnel runs north under the building (%d cells)" % walked)
	_actors.set_position(_player, _at(site, Vector3i(4, 0, 8)))
	assert_true(_movement.move(_player, 0, 0, 1), "and up the ladder into the back hall")
	assert_eq(BuildSystem.cell_of(_actors.position_of(_player)), _sites.cell_of(site, Vector3i(4, 1, 8)), "inside, past the lobby entirely")


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
	assert_eq(sites.pieces_of(&"cold_storage").size(), 366, "with its pieces")
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
	assert_eq(land.parcel_at(_at(site, Vector3i(4, 1, -2))), &"", "the grate is out in the street")
	assert_eq(land.parcel_at(_at(site, Vector3i(4, 1, 8))), &"cold_storage_lot", "the back hall is not")
	# cutting a grate in a public street is nobody's business
	var before: int = land.violation_count()
	var grate: int = _build.face_piece_at(BuildSystem.face_key(_sites.cell_of(site, Vector3i(4, 1, -2)), "ny"))
	assert_true(grate > 0, "the grate")
	_actors.set_position(_player, _at(site, Vector3i(4, 1, -2)))
	assert_false(_build.remove(_player, grate).is_empty(), "cut it")
	assert_eq(land.violation_count(), before, "and no trespass: the street is public")
	# the tunnel goes under the wall, which is where the trespass starts
	assert_true(_movement.move(_player, 0, 0, -1), "down into the tunnel")
	var walked: int = 0
	for i: int in 10:
		if _walk(0, 1):
			walked += 1
	assert_true(walked >= 9, "north under the building (%d cells)" % walked)
	_actors.set_position(_player, _at(site, Vector3i(4, 0, 8)))
	assert_true(_movement.move(_player, 0, 0, 1), "up the ladder")
	assert_eq(BuildSystem.cell_of(_actors.position_of(_player)), _sites.cell_of(site, Vector3i(4, 1, 8)), "inside the operator's building, owning nothing")
	assert_eq(land.parcel_at(_actors.position_of(_player)), &"cold_storage_lot", "standing on their land")


## M6 spec claim 4, the thing every other test quietly skipped: you have to be able to
## walk up to the building. The slab is a metre above the pavement and a level change
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
	assert_true(_movement.move(_player, 0, 0, 1), "up the step onto the slab")
	assert_eq(_actors.position_of(_player).y, M, "a metre up, on the slab")
	# and on north across the street to the grate, without touching the lobby
	var reached: bool = false
	for i: int in 30:
		_walk(0, 1)
		if BuildSystem.cell_of(_actors.position_of(_player)) == _sites.cell_of(site, Vector3i(4, 1, -2)):
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
