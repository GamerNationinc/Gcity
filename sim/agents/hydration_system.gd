## Hydration (M7 spec claim 12; design doc §6.2; ADR-010 B). **A token near the player
## becomes a squad in the world; a squad the player has left becomes a token again.**
##
## ADR-010 B is one rule for everything: unloaded runs on tokens, loaded runs fully. So
## a hydrated squad is not a puppet of its token. Its members are real agents with real
## perception and real stances, and they walk the token's route themselves, a step a
## tick along the road line through MovementSystem, at the token's pace. While they do,
## the token is held and the macro tier leaves it alone. When the player has gone they
## hand the route back where they actually got to, with however many are still alive,
## and their kit goes into the token's container until the next time.
##
## The squad advances its route by the same rule the token does ([MacroTokenSystem.along])
## and only when its lead actually stands where that rule says it should. Nothing
## interferes, and a district ticked loaded ends exactly where it would have unloaded:
## that is ADR-010's metamorphic property, and the test that asserts it. Something does
## interfere — a wall, a fight, the player in the road — and the walk stops for as long
## as it does, which is the point of loading anything.
##
## Payload a token needs to hydrate: `profile` (an agent profile with the travel stance)
## and `members` (1..MAX_MEMBERS); optionally a kit, `frame`, `magazine`, `ammo` and
## `rounds`, that arms each member the first time the squad appears. A token without
## them, or faster than its members can walk, stays a token however close the player
## comes: there is nothing honest to turn it into.
class_name HydrationSystem extends SimSystem

const SYSTEM_ID: StringName = &"hydration"
## A token this close to a player, on the ground plane, hydrates.
const HYDRATE_MM: int = 120_000
## A squad with no player this close to any living member dehydrates. Wider than
## [HYDRATE_MM] so a player at the edge does not make a squad flicker in and out.
const DEHYDRATE_MM: int = 160_000
## How far apart a squad walks in file along the road.
const SPACING_MM: int = 2_000
const MAX_MEMBERS: int = 8
## Squad ids for hydrated squads: this plus the token id, so they never meet a site's.
const SQUAD_BASE: int = 1_000_000

var _content: ContentDb
var _tokens: MacroTokenSystem
var _routes: RouteGraph
var _actors: ActorSystem
var _perception: PerceptionSystem
var _movement: MovementSystem
var _items: ItemSystem
var _stances: StanceSystem
var _events: EventBus
## token id -> {"members": Array[int] (lead first), "leg": int, "progress": int}: who
## the squad is and how far along the token's route it has actually walked.
var _squads: Dictionary = {}


func _init(content: ContentDb, routes: RouteGraph, tokens: MacroTokenSystem, actors: ActorSystem, perception: PerceptionSystem, movement: MovementSystem, items: ItemSystem, stances: StanceSystem, events: EventBus) -> void:
	_content = content
	_routes = routes
	_tokens = tokens
	_actors = actors
	_perception = perception
	_movement = movement
	_items = items
	_stances = stances
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func snapshot() -> Dictionary:
	return {"squads": _squads.duplicate(true)}


func attach(sim: SimRoot) -> Error:
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	return _events.subscribe(ActorSystem.EVENT_REMOVED, _on_removed)


## Walks every squad, then lets go of the ones the player has left, then brings in the
## tokens the player has come near. Walking first means the tick a squad is let go is
## a tick it walked, exactly as the token would have.
func tick(_sim: SimRoot) -> void:
	for token: int in squad_tokens():
		_walk(token)
	for token: int in squad_tokens():
		if _left_alone(token):
			_dehydrate(token)
	for token: int in _tokens.token_ids():
		if not _tokens.is_held(token) and _player_within(_tokens.position_of(token), HYDRATE_MM):
			_hydrate(token)


# ---------------------------------------------------------------- queries

func squad_tokens() -> Array[int]:
	var out: Array[int] = []
	for key: Variant in _squads:
		var id: int = key
		out.append(id)
	out.sort()
	return out


func is_hydrated(token: int) -> bool:
	return _squads.has(token)


## The squad a token became, lead first; empty if it is not hydrated.
func members_of(token: int) -> Array[int]:
	var out: Array[int] = []
	if not _squads.has(token):
		return out
	var rec: Dictionary = _squads[token]
	for v: Variant in rec["members"]:
		var id: int = v
		out.append(id)
	return out


## True while an agent belongs to a hydrated squad with road still ahead of it. The
## stance system's travel check.
func is_travelling(agent: int) -> bool:
	for token: int in squad_tokens():
		var rec: Dictionary = _squads[token]
		var members: Array = rec["members"]
		if members.has(agent):
			return not _arrived(token, rec)
	return false


# ---------------------------------------------------------------- hydrating

func _hydrate(token: int) -> void:
	var payload: Dictionary = _tokens.payload_of(token)
	if not _can_hydrate(token, payload):
		return
	var profile_s: String = payload["profile"]
	var count: int = payload["members"]
	var route: Array[int] = _tokens.route_of(token)
	var leg: int = _tokens.leg_of(token)
	var progress: int = _tokens.progress_of(token)
	var ahead: Vector2i = _routes_position(route[leg + 1]) - _routes_position(route[leg])
	var facing: int = StanceSystem.facing_toward(ahead)
	var stash: StringName = ItemSystem.token_container(token)
	var frames: Array[int] = []
	var loose: Array[int] = []
	for item: int in _items.items_in(stash):
		if _items.item_kind(item) == ItemSystem.KIND_FRAME:
			frames.append(item)
		else:
			loose.append(item)
	var members: Array[int] = []
	for i: int in count:
		var at: Vector2i = _tokens.point_at(route, leg, progress, i * SPACING_MM)
		var cell: Vector3i = BuildSystem.cell_of(Vector3i(at.x, 0, at.y))
		var agent: int = _perception.spawn(StringName(profile_s), cell, facing, SQUAD_BASE + token, "", _tokens.faction_of(token))
		if agent == EntityIds.NONE:
			continue
		# on the road itself rather than the middle of its cell: the walk measures from here
		_actors.set_position(agent, Vector3i(at.x, 0, at.y))
		members.append(agent)
		_equip(agent, i, frames, payload)
	if members.is_empty():
		return
	if not loose.is_empty():
		_items.move_items(loose, ItemSystem.inventory_of(members[0]))
	_tokens.hold(token)
	_squads[token] = {"members": members, "leg": leg, "progress": progress}


## A kit the squad carried off-screen comes back to it, a frame each in the order they
## went; a squad appearing for the first time is armed from the payload's kit, if it
## names one.
func _equip(agent: int, index: int, frames: Array[int], payload: Dictionary) -> void:
	var weapon: int = EntityIds.NONE
	if index < frames.size():
		weapon = frames[index]
		_items.move_items([weapon] as Array[int], ItemSystem.inventory_of(agent))
	elif frames.is_empty() and payload.has("frame"):
		var frame_s: String = payload["frame"]
		var magazine_s: String = payload["magazine"]
		var ammo_s: String = payload["ammo"]
		var rounds: int = payload["rounds"]
		weapon = _items.arm(agent, StringName(frame_s), StringName(magazine_s), StringName(ammo_s), rounds, agent * 1000)
	if weapon != EntityIds.NONE:
		_actors.wield(agent, weapon)


## Whether a token names something that can walk its route: a profile that exists and
## travels, a sensible number of members, a whole kit or none, and a pace its members
## can keep.
func _can_hydrate(token: int, payload: Dictionary) -> bool:
	if typeof(payload.get("profile")) != TYPE_STRING or typeof(payload.get("members")) != TYPE_INT:
		return false
	var profile_s: String = payload["profile"]
	var count: int = payload["members"]
	if count < 1 or count > MAX_MEMBERS or not _content.has(PerceptionSystem.KIND_AGENT, StringName(profile_s)):
		return false
	var t: Dictionary = _content.get_entry(PerceptionSystem.KIND_AGENT, StringName(profile_s))
	var travels: bool = false
	for v: Variant in t["stances"]:
		var entry: Dictionary = v
		var stance_s: String = entry["stance"]
		travels = travels or StringName(stance_s) == StanceSystem.STANCE_TRAVEL
	if not travels:
		return false
	var combat_s: String = t["combat_profile"]
	var combat: Dictionary = _content.get_entry(ActorSystem.KIND_PROFILE, StringName(combat_s))
	var pace: int = combat["speed_mm_per_tick"]
	if _tokens.speed_of(token) > pace:
		return false
	var kit: int = 0
	for key: String in ["frame", "magazine", "ammo", "rounds"]:
		if payload.has(key):
			kit += 1
	if kit != 0 and (kit != 4 or typeof(payload["rounds"]) != TYPE_INT or typeof(payload["frame"]) != TYPE_STRING
			or typeof(payload["magazine"]) != TYPE_STRING or typeof(payload["ammo"]) != TYPE_STRING):
		return false
	return true


# ---------------------------------------------------------------- walking

## One tick of the walk. The route advances only when the lead is standing exactly
## where the token's own rule puts it, so a squad that is held up is a squad that has
## not got anywhere. Members not in the travel stance are left to what they are doing.
func _walk(token: int) -> void:
	var rec: Dictionary = _squads[token]
	var living: Array[int] = _living(rec)
	if living.is_empty() or _arrived(token, rec):
		return
	var route: Array[int] = _tokens.route_of(token)
	var leg: int = rec["leg"]
	var progress: int = rec["progress"]
	var lead: int = living[0]
	if _stances.stance_of(lead) == StanceSystem.STANCE_TRAVEL:
		var next: Vector2i = _tokens.along(route, leg, progress, _tokens.speed_of(token))
		if _step_to(lead, _tokens.point_at(route, next.x, next.y)):
			rec["leg"] = next.x
			rec["progress"] = next.y
			leg = next.x
			progress = next.y
	for i: int in range(1, living.size()):
		var member: int = living[i]
		if _stances.stance_of(member) == StanceSystem.STANCE_TRAVEL:
			_step_to(member, _tokens.point_at(route, leg, progress, i * SPACING_MM))


## Moves an actor toward a point on the ground, as far as its pace allows in a tick.
## True when it is standing on the point afterwards.
func _step_to(actor: int, point: Vector2i) -> bool:
	var here: Vector3i = _actors.position_of(actor)
	var pace: int = _movement.speed_of(actor)
	var dx: int = clampi(point.x - here.x, -pace, pace)
	var dz: int = clampi(point.y - here.z, -pace, pace)
	if dx != 0 or dz != 0:
		_movement.move(actor, dx, dz)
	var now: Vector3i = _actors.position_of(actor)
	return now.x == point.x and now.z == point.y


func _arrived(token: int, rec: Dictionary) -> bool:
	var route: Array[int] = _tokens.route_of(token)
	var leg: int = rec["leg"]
	var progress: int = rec["progress"]
	if leg + 2 < route.size():
		return false
	var edge: Dictionary = _routes_edge(route[leg], route[leg + 1])
	var length: int = edge["length"]
	return progress == length


# ---------------------------------------------------------------- dehydrating

func _left_alone(token: int) -> bool:
	var rec: Dictionary = _squads[token]
	for member: int in _living(rec):
		var at: Vector3i = _actors.position_of(member)
		if _player_within(Vector2i(at.x, at.z), DEHYDRATE_MM):
			return false
	return true


## The living go back into the token with their kit; the dead stay where they fell,
## bodies like any other. A squad with nobody left leaves no token.
func _dehydrate(token: int) -> void:
	var rec: Dictionary = _squads[token]
	var leg: int = rec["leg"]
	var progress: int = rec["progress"]
	var stash: StringName = ItemSystem.token_container(token)
	var back: int = 0
	for member: int in _living(rec):
		if _actors.remove(member, stash):
			back += 1
	_squads.erase(token)
	if back == 0:
		_tokens.drop(token)
		return
	var payload: Dictionary = _tokens.payload_of(token)
	payload["members"] = back
	var released: bool = _tokens.release(token, leg, progress, payload)
	assert(released, "a held token takes back a place on its own route")


func _on_removed(payload: Dictionary) -> void:
	var actor: int = payload["actor"]
	for token: int in squad_tokens():
		var rec: Dictionary = _squads[token]
		var members: Array = rec["members"]
		members.erase(actor)


# ---------------------------------------------------------------- helpers

func _living(rec: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for v: Variant in rec["members"]:
		var id: int = v
		if _actors.is_alive(id):
			out.append(id)
	return out


## True when any living actor that is not an agent — a player — stands within `range`
## of a point on the ground plane.
func _player_within(point: Vector2i, range_mm: int) -> bool:
	for actor: int in _actors.actor_ids():
		if not _actors.is_alive(actor) or _perception.is_agent(actor):
			continue
		var at: Vector3i = _actors.position_of(actor)
		var dx: int = at.x - point.x
		var dz: int = at.z - point.y
		if dx * dx + dz * dz <= range_mm * range_mm:
			return true
	return false


func _routes_position(node: int) -> Vector2i:
	return _routes.position_of(node)


func _routes_edge(a: int, b: int) -> Dictionary:
	return _routes.edge(_routes.edge_between(a, b))


# ---------------------------------------------------------------- restore

## Every squad is a held token's, every held token has a squad, and every member is an
## actor; a plan is a place on the token's route.
func restore(state: Dictionary) -> Error:
	if state.size() != 1 or typeof(state.get("squads")) != TYPE_DICTIONARY:
		return _restore_fail("shape")
	var in_all: Dictionary = state["squads"]
	var out: Dictionary = {}
	for key: Variant in in_all:
		if typeof(key) != TYPE_INT or typeof(in_all[key]) != TYPE_DICTIONARY:
			return _restore_fail("squad key")
		var token: int = key
		if not _tokens.is_held(token):
			return _restore_fail("squad of token %d, which is not held" % token)
		var rec: Dictionary = in_all[key]
		if rec.size() != 3 or typeof(rec.get("members")) != TYPE_ARRAY or typeof(rec.get("leg")) != TYPE_INT \
				or typeof(rec.get("progress")) != TYPE_INT:
			return _restore_fail("squad %d record" % token)
		var members: Array[int] = []
		for v: Variant in rec["members"]:
			if typeof(v) != TYPE_INT:
				return _restore_fail("squad %d member" % token)
			var member: int = v
			if not _actors.has_actor(member):
				return _restore_fail("squad %d names somebody who is not there" % token)
			members.append(member)
		var route: Array[int] = _tokens.route_of(token)
		var leg: int = rec["leg"]
		var progress: int = rec["progress"]
		if leg < 0 or leg + 1 >= route.size():
			return _restore_fail("squad %d is off its route" % token)
		var edge: Dictionary = _routes_edge(route[leg], route[leg + 1])
		var length: int = edge["length"]
		if progress < 0 or progress > length:
			return _restore_fail("squad %d is off its road" % token)
		out[token] = {"members": members, "leg": leg, "progress": progress}
	for token: int in _tokens.token_ids():
		if _tokens.is_held(token) and not out.has(token):
			return _restore_fail("token %d is held by no squad" % token)
	_squads = out
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("HydrationSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
