extends GcityTest

## M7 spec claim 12: hydration is a round trip. A token within range of the player
## becomes real agents at the world position its progress maps to, walks its route
## itself, and dehydrates back when the player leaves.
##
## The property is the one ADR-010 names, and it is metamorphic because nothing else
## can be: there is no oracle for where a squad ought to be, but a district ticked N
## times unloaded must end where the same district ends when it is loaded, ticked N
## times and unloaded again — for every quantity the macro model claims to track. The
## macro model tracks the token: its route, where along it, whose it is and what it
## carries. So the whole token record is compared, not a summary of it.

const SEED: int = 20261280
const SEED_PROPERTY: int = 20261281
const FACTION: String = "faction.scrapline"
## A squad on foot at the guard's walking pace.
const PACE: int = 50
## Where the player stands to bring a squad in: off to the side of the road, inside
## [HydrationSystem.HYDRATE_MM] and well outside anything a guard can see or hear.
const WATCH_MM: int = 100_000
const FAR_MM: int = 5_000_000
## Visits made in the property, each one token loaded and let go again. Worlds are
## reused for several visits because building a sim costs more than a visit does.
const PROPERTY_VISITS: int = 10_000
const VISITS_PER_WORLD: int = 10
## A visit is skipped when another token is this close to where the player would stand:
## a guard sees 40 m and hears 60 m, and a squad walks a few metres closer during the
## stay. A squad that sees the player reacts to them, which is loading doing its job,
## not a disagreement with the macro model. Other squads hydrating further out than
## this still happen, and are part of what the property checks.
const NOTICE_MM: int = 75_000

var _sim: SimRoot
var _routes: RouteGraph
var _tokens: MacroTokenSystem
var _hydration: HydrationSystem
var _actors: ActorSystem
var _items: ItemSystem
var _stances: StanceSystem
var _player: int = 0


func _db() -> ContentDb:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	return db


func _setup(world: int = SEED) -> void:
	_sim = SimAssembly.build(world, _db())
	assert_true(_sim != null, "assembly")
	_routes = SimAssembly.routes_of(_sim)
	_tokens = SimAssembly.tokens_of(_sim)
	_hydration = SimAssembly.hydration_of(_sim)
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_stances = SimAssembly.stances_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_park(_player)


func _park(actor: int) -> void:
	_actors.set_position(actor, Vector3i(FAR_MM, 0, FAR_MM))


## Two places joined by a route that never passes through the city gate: the city's
## parcels sit at the gate, and a squad walking into a lot it may not enter is held up
## for a reason that has nothing to do with hydration.
static func _wild_pair(routes: RouteGraph, rng: RandomNumberGenerator) -> Array[int]:
	var nodes: Array[int] = routes.node_ids()
	for attempt: int in 200:
		var a: int = nodes[rng.randi_range(0, nodes.size() - 1)]
		var b: int = nodes[rng.randi_range(0, nodes.size() - 1)]
		if a == b:
			continue
		var path: Array[int] = routes.path_between(a, b)
		if path.has(1) or path.size() < 3:
			continue
		return [a, b]
	return [] as Array[int]


## Stands the player off to the side of a token, on the ground there: out in the wilds
## the ground is wherever the terrain puts it, and a player dropped from the wrong
## height falls, and can die of it.
func _watch(token: int) -> void:
	var at: Vector2i = _tokens.position_of(token)
	_actors.set_position(_player, _on_ground(SimAssembly.regions_of(_sim), at.x, at.y + WATCH_MM))


static func _on_ground(regions: Regions, x: int, z: int) -> Vector3i:
	return Vector3i(x, regions.standing_cell_y(x, z) * BuildSystem.CELL, z)


static func _patrol(members: int, armed: bool) -> Dictionary:
	var payload: Dictionary = {"profile": "foot_patrol", "members": members}
	if armed:
		payload.merge({"frame": "g19", "magazine": "g19_mag_15", "ammo": "9x19_fmj", "rounds": 15})
	return payload


func test_a_token_near_the_player_becomes_a_squad_walking_its_road() -> void:
	_setup()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var pair: Array[int] = _wild_pair(_routes, rng)
	var token: int = _tokens.spawn(FACTION, pair[0], pair[1], PACE, _patrol(3, true))
	_sim.step_n(20)
	assert_false(_hydration.is_hydrated(token), "nobody near: a token")
	_watch(token)
	_sim.step()
	assert_true(_hydration.is_hydrated(token), "the player comes near and it is a squad")
	assert_true(_tokens.is_held(token), "and the macro tier has let go of it")
	var squad: Array[int] = _hydration.members_of(token)
	assert_eq(squad.size(), 3, "of three")
	var route: Array[int] = _tokens.route_of(token)
	for i: int in squad.size():
		var member: int = squad[i]
		var at: Vector3i = _actors.position_of(member)
		var want: Vector2i = _tokens.point_at(route, _tokens.leg_of(token), _tokens.progress_of(token), i * HydrationSystem.SPACING_MM)
		assert_eq(Vector2i(at.x, at.z), want, "member %d stands on the road, in file" % i)
		assert_true(_actors.wielded(member) != EntityIds.NONE, "armed from the token's kit")
	_sim.step()
	assert_eq(_stances.stance_of(squad[0]), StanceSystem.STANCE_TRAVEL, "and walking from its first tick")
	var before: Vector3i = _actors.position_of(squad[0])
	_sim.step_n(40)
	var after: Vector3i = _actors.position_of(squad[0])
	assert_true(after != before, "the lead has walked on (%s to %s)" % [before, after])


func test_the_squad_goes_back_to_being_a_token_and_keeps_its_kit() -> void:
	_setup()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var pair: Array[int] = _wild_pair(_routes, rng)
	var token: int = _tokens.spawn(FACTION, pair[0], pair[1], PACE, _patrol(3, true))
	_watch(token)
	_sim.step()
	var squad: Array[int] = _hydration.members_of(token)
	var pistols: Array[int] = []
	for member: int in squad:
		pistols.append(_actors.wielded(member))
	var items: int = _items.item_count()
	_sim.step_n(30)
	_park(_player)
	_sim.step()
	assert_false(_hydration.is_hydrated(token), "the player leaves and it is a token again")
	assert_false(_tokens.is_held(token), "walking on by itself")
	assert_eq(_tokens.payload_of(token)["members"], 3, "all three of them")
	for member: int in squad:
		assert_false(_actors.has_actor(member), "the agents are gone")
	assert_eq(_items.item_count(), items, "and nothing was made or lost")
	for pistol: int in pistols:
		assert_eq(_items.container_of(pistol), ItemSystem.token_container(token), "the pistols went with the token")
	_sim.step_n(20)
	_watch(token)
	_sim.step()
	var again: Array[int] = _hydration.members_of(token)
	assert_eq(again.size(), 3, "and when the player comes back, so does the squad")
	var held: Array[int] = []
	for member: int in again:
		held.append(_actors.wielded(member))
	assert_eq(held, pistols, "holding the same pistols, not new ones")
	assert_eq(_items.item_count(), items, "still nothing made")


func test_the_dead_stay_and_a_squad_with_nobody_left_leaves_no_token() -> void:
	_setup()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var pair: Array[int] = _wild_pair(_routes, rng)
	var token: int = _tokens.spawn(FACTION, pair[0], pair[1], PACE, _patrol(2, false))
	_watch(token)
	_sim.step()
	var squad: Array[int] = _hydration.members_of(token)
	_actors.damage_node(squad[1], &"body", 999999)
	_park(_player)
	_sim.step()
	assert_eq(_tokens.payload_of(token)["members"], 1, "one went back into the token")
	assert_true(_actors.has_actor(squad[1]), "and the dead one is still lying there")
	_watch(token)
	_sim.step()
	var survivor: int = _hydration.members_of(token)[0]
	_actors.damage_node(survivor, &"body", 999999)
	_park(_player)
	_sim.step()
	assert_false(_tokens.has_token(token), "nobody left, no token")
	assert_false(_hydration.is_hydrated(token), "and no squad")


func test_a_token_that_cannot_walk_stays_a_token() -> void:
	_setup()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var pair: Array[int] = _wild_pair(_routes, rng)
	var cases: Array[Dictionary] = [
		{"profile": "guard_sim", "members": 2},
		{"profile": "nobody", "members": 2},
		{"profile": "foot_patrol", "members": 0},
		{"profile": "foot_patrol", "members": HydrationSystem.MAX_MEMBERS + 1},
		{"profile": "foot_patrol"},
		{"profile": "foot_patrol", "members": 2, "frame": "g19"},
		{},
	]
	for payload: Dictionary in cases:
		var token: int = _tokens.spawn(FACTION, pair[0], pair[1], PACE, payload)
		_watch(token)
		_sim.step()
		assert_false(_hydration.is_hydrated(token), "%s stays a token" % [payload])
	var fast: int = _tokens.spawn(FACTION, pair[0], pair[1], MacroTokenSystem.MAX_SPEED_MM_PER_TICK, _patrol(2, false))
	_watch(fast)
	_sim.step()
	assert_false(_hydration.is_hydrated(fast), "and so does one faster than its members can walk")


func test_a_save_with_a_squad_on_the_road_loads_and_walks_on_the_same() -> void:
	_setup()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var pair: Array[int] = _wild_pair(_routes, rng)
	var token: int = _tokens.spawn(FACTION, pair[0], pair[1], PACE, _patrol(3, true))
	_watch(token)
	_sim.step_n(25)
	var snap: Dictionary = _sim.snapshot()
	var other: SimRoot = SimAssembly.build(SEED, _db())
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "restored mid-walk")
	assert_eq(other.restore_root(snap), OK, "root")
	_sim.step_n(60)
	other.step_n(60)
	assert_eq(other.state_hash(), _sim.state_hash(), "and walks on identically")
	var good: Dictionary = _hydration.snapshot()
	var bad: Array[Dictionary] = [
		{},
		{"squads": {99: {"members": [], "leg": 0, "progress": 0}}},
		{"squads": {}},
		{"squads": {token: {"members": [99999], "leg": 0, "progress": 0}}},
		{"squads": {token: {"members": [], "leg": 999, "progress": 0}}},
		{"squads": {token: {"members": [], "leg": 0, "progress": -1}}},
	]
	for state: Dictionary in bad:
		assert_eq(_hydration.restore(state), ERR_INVALID_DATA, "refused: %s" % [state])
		assert_eq(_hydration.snapshot(), good, "and nothing changed")


## ADR-010's metamorphic property. Two copies of a world with the same tokens on the
## same roads; in one the player never comes near, in the other the player visits one
## token after another, stays for a while and leaves. Afterwards every token must be
## exactly where the unvisited copy has it, carrying the same thing — the only
## difference loading may make is the one the player makes, and here the player does
## nothing but look.
func test_property_a_district_loaded_and_let_go_ends_where_it_would_have_unloaded() -> void:
	var db: ContentDb = _db()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	var visits: int = 0
	var worlds: int = 0
	var disagreed: int = 0
	var walked: int = 0
	var skipped: int = 0
	while visits < PROPERTY_VISITS:
		var world: int = SEED_PROPERTY + worlds
		worlds += 1
		var alone: SimRoot = SimAssembly.build(world, db)
		var visited: SimRoot = SimAssembly.build(world, db)
		var routes: RouteGraph = SimAssembly.routes_of(alone)
		var tokens_alone: MacroTokenSystem = SimAssembly.tokens_of(alone)
		var tokens_visited: MacroTokenSystem = SimAssembly.tokens_of(visited)
		var hydration: HydrationSystem = SimAssembly.hydration_of(visited)
		var actors_visited: ActorSystem = SimAssembly.actors_of(visited)
		var player: int = actors_visited.spawn(&"arcade", 0)
		actors_visited.set_position(player, Vector3i(FAR_MM, 0, FAR_MM))
		SimAssembly.actors_of(alone).spawn(&"arcade", 0)
		var ids: Array[int] = []
		for v: int in VISITS_PER_WORLD:
			var pair: Array[int] = _wild_pair(routes, rng)
			if pair.is_empty():
				break
			var pace: int = rng.randi_range(10, PACE)
			var payload: Dictionary = _patrol(rng.randi_range(1, 4), rng.randi_range(0, 1) == 1)
			var a: int = tokens_alone.spawn(FACTION, pair[0], pair[1], pace, payload)
			var b: int = tokens_visited.spawn(FACTION, pair[0], pair[1], pace, payload)
			assert_eq(a, b, "the same token in both copies")
			ids.append(a)
		for id: int in ids:
			var before: int = rng.randi_range(0, 40)
			var stay: int = rng.randi_range(1, 120)
			alone.step_n(before)
			visited.step_n(before)
			var at: Vector2i = tokens_visited.position_of(id)
			var watch: Vector2i = Vector2i(at.x, at.y + WATCH_MM)
			if _someone_else_near(tokens_visited, id, watch):
				skipped += 1
				continue
			actors_visited.set_position(player, _on_ground(SimAssembly.regions_of(visited), watch.x, watch.y))
			alone.step_n(stay)
			visited.step_n(stay)
			if hydration.is_hydrated(id):
				walked += 1
			actors_visited.set_position(player, Vector3i(FAR_MM, 0, FAR_MM))
			alone.step()
			visited.step()
			visits += 1
			var want: Dictionary = tokens_alone.snapshot()
			var got: Dictionary = tokens_visited.snapshot()
			if StateHash.of(got) != StateHash.of(want):
				disagreed += 1
				if disagreed <= 3:
					fail("world %d, token %d: loaded for %d ticks it ended at leg %d, %d mm; unloaded, leg %d, %d mm" % [
						world, id, stay, tokens_visited.leg_of(id), tokens_visited.progress_of(id),
						tokens_alone.leg_of(id), tokens_alone.progress_of(id)])
				break
	assert_eq(disagreed, 0, "every token let go was where it would have been (%d visits, %d worlds)" % [visits, worlds])
	assert_true(walked > visits / 2, "and most visits really did load a squad (%d of %d)" % [walked, visits])
	assert_true(skipped < visits / 4, "with few visits skipped for somebody else being close (%d)" % skipped)


static func _someone_else_near(tokens: MacroTokenSystem, visiting: int, watch: Vector2i) -> bool:
	for other: int in tokens.token_ids():
		if other == visiting:
			continue
		var d: Vector2i = tokens.position_of(other) - watch
		if d.x * d.x + d.y * d.y <= NOTICE_MM * NOTICE_MM:
			return true
	return false
