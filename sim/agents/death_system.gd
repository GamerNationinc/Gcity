## Death, bodies and respawn (M6 spec claims 14, 16; ADR-007 C). A hit that kills
## (`combat.hit` with `killed`) queues the death; this system's tick settles it with
## the sim's seeded random numbers: the actor's hands are emptied, the district's
## `law_index` (per mille) of its top-level items, chosen at random, go to its impound
## (`impound.<actor>`), the rest to a new body at the place it fell, and
## `actor.died {actor, corpse, killer, impounded, x, y, z}` is emitted (corpse 0 when
## nothing was left to carry). Every actor dies this way, guards included.
##
## `actor.set_home {actor, site}` records where an actor comes back: a site with a
## `respawn` point. `actor.respawn {actor}` brings a dead actor with a home back whole
## at that point. Both are debug-class, as spawning is: the new-game path sends them.
## Getting the impound back for credits is the ledger's (group G).
class_name DeathSystem extends SimSystem

const SYSTEM_ID: StringName = &"deaths"
const COMMAND_SET_HOME: StringName = &"actor.set_home"
const COMMAND_RESPAWN: StringName = &"actor.respawn"
const EVENT_DIED: StringName = &"actor.died"
const POINT_RESPAWN: StringName = &"respawn"

var _content: ContentDb
var _actors: ActorSystem
var _items: ItemSystem
var _land: LandSystem
var _loot: LootSystem
var _events: EventBus
## [[actor, killer], ...] in the order they died, settled on the next tick
var _pending: Array = []
## actor -> site id
var _homes: Dictionary = {}
var _deaths: int = 0


func _init(content: ContentDb, actors: ActorSystem, items: ItemSystem, land: LandSystem, loot: LootSystem, events: EventBus) -> void:
	_content = content
	_actors = actors
	_items = items
	_land = land
	_loot = loot
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func snapshot() -> Dictionary:
	return {"pending": _pending.duplicate(true), "homes": _homes.duplicate(), "deaths": _deaths}


func attach(sim: SimRoot) -> Error:
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_SET_HOME, _on_set_home)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_RESPAWN, _on_respawn)
	if err != OK:
		return err
	return _events.subscribe(CombatSystem.EVENT_HIT, _on_hit)


# ---------------------------------------------------------------- queries

static func impound_of(actor: int) -> StringName:
	return ItemSystem.holding_container(&"impound", actor)


func home_of(actor: int) -> StringName:
	var site_v: Variant = _homes.get(actor)
	if typeof(site_v) != TYPE_STRING:
		return &""
	var site_s: String = site_v
	return StringName(site_s)


func death_count() -> int:
	return _deaths


# ---------------------------------------------------------------- dying

func _on_hit(payload: Dictionary) -> void:
	var killed_v: Variant = payload.get("killed")
	var target_v: Variant = payload.get("target")
	var shooter_v: Variant = payload.get("shooter")
	if typeof(killed_v) != TYPE_BOOL or typeof(target_v) != TYPE_INT or typeof(shooter_v) != TYPE_INT:
		return
	var killed: bool = killed_v
	var target: int = target_v
	var shooter: int = shooter_v
	if killed and _actors.has_actor(target):
		_pending.append([target, shooter] as Array[int])


func tick(sim: SimRoot) -> void:
	var pending: Array = _pending
	_pending = []
	for entry: Variant in pending:
		var pair: Array = entry
		var actor: int = pair[0]
		var killer: int = pair[1]
		_settle(sim, actor, killer)


func _settle(sim: SimRoot, actor: int, killer: int) -> void:
	_deaths += 1
	_actors.release_hands(actor)
	var pos: Vector3i = _actors.position_of(actor)
	var carried: Array[int] = _items.items_in(ItemSystem.inventory_of(actor)).duplicate()
	var district: Dictionary = _content.get_entry(LandSystem.KIND_DISTRICT, _land.district_of(_land.parcel_at(pos)))
	var law: int = district["law_index"]
	var share: int = carried.size() * law / 1000
	# a seeded partial shuffle: the first `share` items after it are impounded
	var rng: RandomNumberGenerator = sim.rng()
	for i: int in share:
		var j: int = rng.randi_range(i, carried.size() - 1)
		var swap: int = carried[i]
		carried[i] = carried[j]
		carried[j] = swap
	for i: int in share:
		var moved: bool = _items.move_item(carried[i], impound_of(actor))
		assert(moved, "an inventory item moves to an impound")
	var corpse: int = EntityIds.NONE
	if carried.size() > share:
		corpse = _loot.make_corpse(actor, pos)
		for i: int in range(share, carried.size()):
			var moved: bool = _items.move_item(carried[i], _loot.container_name(corpse))
			assert(moved, "an inventory item moves to a body")
	_events.emit(EVENT_DIED, {"actor": actor, "corpse": corpse, "killer": killer, "impounded": share, "x": pos.x, "y": pos.y, "z": pos.z})


# ---------------------------------------------------------------- home and respawn

## {"actor": int, "site": string}: the site must have a respawn point.
func _on_set_home(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("site")) != TYPE_STRING:
		return false
	var actor: int = payload["actor"]
	var site_s: String = payload["site"]
	if not _actors.has_actor(actor) or not SiteSystem.has_point(_content, StringName(site_s), POINT_RESPAWN):
		return false
	_homes[actor] = site_s
	return true


## {"actor": int}: a dead actor with a home comes back whole at its respawn point.
func _on_respawn(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 1 or typeof(payload.get("actor")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var home: StringName = home_of(actor)
	if home.is_empty() or not _actors.has_actor(actor) or _actors.is_alive(actor):
		return false
	return _actors.revive(actor, SiteSystem.point_position(_content, home, POINT_RESPAWN))


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 3 or typeof(state.get("pending")) != TYPE_ARRAY or typeof(state.get("homes")) != TYPE_DICTIONARY \
			or typeof(state.get("deaths")) != TYPE_INT:
		return _restore_fail("shape")
	var deaths: int = state["deaths"]
	if deaths < 0:
		return _restore_fail("negative count")
	var pending: Array = []
	var pending_in: Array = state["pending"]
	for entry: Variant in pending_in:
		if typeof(entry) != TYPE_ARRAY:
			return _restore_fail("pending entry")
		var pair: Array = entry
		if pair.size() != 2 or typeof(pair[0]) != TYPE_INT or typeof(pair[1]) != TYPE_INT:
			return _restore_fail("pending pair")
		var actor: int = pair[0]
		var killer: int = pair[1]
		if not _actors.has_actor(actor):
			return _restore_fail("pending actor %d" % actor)
		pending.append([actor, killer] as Array[int])
	var homes: Dictionary = {}
	var homes_in: Dictionary = state["homes"]
	for key: Variant in homes_in:
		if typeof(key) != TYPE_INT or typeof(homes_in[key]) != TYPE_STRING:
			return _restore_fail("home entry")
		var actor: int = key
		var site_s: String = homes_in[key]
		if not _actors.has_actor(actor) or not SiteSystem.has_point(_content, StringName(site_s), POINT_RESPAWN):
			return _restore_fail("home of %d" % actor)
		homes[actor] = site_s
	_pending = pending
	_homes = homes
	_deaths = deaths
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("DeathSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
