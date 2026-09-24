## Corpses (M6 spec claim 10; ADR-007 C, accepted 2026-09-22). Death does not destroy
## a kit and does not hand it back: it leaves it on the body, where it stays until
## somebody picks it up. That is the whole cost model, and it is what makes a mission
## worth not dying in.
##
## A corpse is an entity with a position and a container (`corpse.<id>`) holding every
## item the dead actor was carrying. Nothing is spawned and nothing is destroyed: the
## inventory moves, once, so M1 claim 10's conservation property covers death and
## looting the same way it covers every other item command.
class_name CorpseSystem extends SimSystem

const SYSTEM_ID: StringName = &"corpses"
const KIND_RECOVERY: StringName = &"recovery_rule"
## The one rule M6 ships. A faction or a district could name its own later; nothing
## here would change but this constant becoming a lookup.
const RULE: StringName = &"police"
const COMMAND_LOOT: StringName = &"corpse.loot"
const COMMAND_RESPAWN: StringName = &"actor.respawn"
const EVENT_LEFT: StringName = &"corpse.left"
const EVENT_LOOTED: StringName = &"corpse.looted"
const EVENT_RESPAWNED: StringName = &"actor.respawned"
## How close a looter must stand, in millimetres. An arm's length over a body.
const REACH_MM: int = 1500
## Milli-units: a fraction of a kit.
const PERMILLE: int = 1000

var _content: ContentDb
var _actors: ActorSystem
var _items: ItemSystem
var _ids: EntityIds
var _land: LandSystem
var _events: EventBus
## corpse id -> {"actor": int, "pos": Array[int]}
var _corpses: Dictionary = {}


func _init(content: ContentDb, actors: ActorSystem, items: ItemSystem, ids: EntityIds, land: LandSystem, events: EventBus) -> void:
	_content = content
	_actors = actors
	_items = items
	_ids = ids
	_land = land
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


func snapshot() -> Dictionary:
	return {"corpses": _corpses.duplicate(true)}


func attach(sim: SimRoot) -> Error:
	var err: Error = validate_content()
	if err != OK:
		return err
	err = sim.register_system(self)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_LOOT, _on_loot, false)
	if err != OK:
		return err
	# pause-safe: coming back is a menu choice, not something done in the world
	err = sim.commands().register(COMMAND_RESPAWN, _on_respawn, true)
	if err != OK:
		return err
	return _events.subscribe(ActorSystem.EVENT_DIED, _on_died)


## The recovery rule must exist and must name a parcel to fall back to, because a
## player with no plot still has to stand somewhere.
func validate_content() -> Error:
	if not _content.has(KIND_RECOVERY, RULE):
		push_error("CorpseSystem: no recovery_rule/%s" % RULE)
		return ERR_INVALID_DATA
	var rule: Dictionary = _content.get_entry(KIND_RECOVERY, RULE)
	var fallback_s: String = rule["fallback_parcel"]
	if not _content.has(LandSystem.KIND_PARCEL, StringName(fallback_s)):
		push_error("CorpseSystem: recovery_rule/%s falls back to a parcel that does not exist: %s" % [RULE, fallback_s])
		return ERR_INVALID_DATA
	return OK


# ---------------------------------------------------------------- queries

## Corpse ids, lowest first: the order they fell in, since ids only ever rise.
func corpse_ids() -> Array[int]:
	var out: Array[int] = []
	for key: Variant in _corpses:
		var id: int = key
		out.append(id)
	out.sort()
	return out


func has_corpse(corpse: int) -> bool:
	return _corpses.has(corpse)


## The actor's most recent corpse, or EntityIds.NONE if that actor has never died. An
## actor who died, came back and died again has two bodies; this is the one respawn
## recovers from, and the older one stays where it fell until somebody strips it.
func corpse_of(actor: int) -> int:
	var latest: int = EntityIds.NONE
	for corpse: int in corpse_ids():
		var rec: Dictionary = _corpses[corpse]
		var who: int = rec["actor"]
		if who == actor:
			latest = corpse
	return latest


func position_of(corpse: int) -> Vector3i:
	var stored: Variant = _corpses.get(corpse)
	if typeof(stored) != TYPE_DICTIONARY:
		return Vector3i.ZERO
	var rec: Dictionary = stored
	var pos: Array = rec["pos"]
	return PathingSystem._vec(pos)


func actor_of(corpse: int) -> int:
	var stored: Variant = _corpses.get(corpse)
	if typeof(stored) != TYPE_DICTIONARY:
		return EntityIds.NONE
	var rec: Dictionary = stored
	var actor: int = rec["actor"]
	return actor


## What is still on the body.
func items_on(corpse: int) -> Array[int]:
	if not _corpses.has(corpse):
		return [] as Array[int]
	return _items.items_in(ItemSystem.corpse_container(corpse))


## A body nobody has stripped yet. A stripped one is still there, and still a trace.
func is_stripped(corpse: int) -> bool:
	return _corpses.has(corpse) and items_on(corpse).is_empty()


## Where the actor would come back: the middle of a parcel they own, or the recovery
## rule's fallback. The client draws the death screen from this.
func respawn_position_of(actor: int) -> Vector3i:
	return _centre_of(_plot_of(actor))


# ---------------------------------------------------------------- events

## One corpse per death, holding everything the actor carried. An actor that dies
## empty-handed still leaves a body: it is evidence whether or not it is loot.
func _on_died(payload: Dictionary) -> void:
	var actor: int = payload["actor"]
	var x: int = payload["x"]
	var y: int = payload["y"]
	var z: int = payload["z"]
	var corpse: int = _ids.allocate()
	_corpses[corpse] = {"actor": actor, "pos": [x, y, z] as Array[int]}
	var moved: int = _items.move_container(ItemSystem.inventory_of(actor), ItemSystem.corpse_container(corpse))
	_events.emit(EVENT_LEFT, {"corpse": corpse, "actor": actor, "items": moved, "x": x, "y": y, "z": z})


# ---------------------------------------------------------------- commands

## {"actor": int, "corpse": int}: take everything off a body within reach. All of it
## or none: a half-emptied pocket is a rule nobody can see from the device.
func _on_loot(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("corpse")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var corpse: int = payload["corpse"]
	if not _actors.is_alive(actor) or not _corpses.has(corpse):
		return false
	if _actors.position_of(actor).distance_squared_to(position_of(corpse)) > REACH_MM * REACH_MM:
		return false
	var on_it: Array[int] = items_on(corpse)
	if on_it.is_empty():
		return false
	var moved: int = _items.move_container(ItemSystem.corpse_container(corpse), ItemSystem.inventory_of(actor))
	if moved == 0:
		return false
	_events.emit(EVENT_LOOTED, {"corpse": corpse, "actor": actor, "items": moved})
	return true


## {"actor": int}: come back. Where you died decides what you come back with.
##
## Inside a district whose `law_index` is above the rule's threshold the police held
## the scene: a fraction of the kit is at the station, and you buy it back a piece at
## a time out of what you are carrying. Outside, nobody touched anything, which means
## everything is still lying on the body and the walk back is the price.
func _on_respawn(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 1 or typeof(payload.get("actor")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	if not _actors.has_actor(actor) or _actors.is_alive(actor):
		return false
	var corpse: int = corpse_of(actor)
	if corpse == EntityIds.NONE:
		return false
	var returned: int = 0
	var fee: int = 0
	if _police_hold(corpse):
		var held: StringName = ItemSystem.corpse_container(corpse)
		var rule: Dictionary = _rule()
		var permille: int = rule["returned_permille"]
		var per_item: int = rule["fee_per_item"]
		var wanted: int = items_on(corpse).size() * permille / PERMILLE
		# the station is holding your money as well as your kit, and takes its fee out
		# of that before handing anything back: a dead player has nothing else to pay with
		var purse: int = _items.credits_in(held)
		var affordable: int = wanted if per_item <= 0 else mini(wanted, purse / per_item)
		if affordable > 0:
			fee = affordable * per_item
			var notes: Array[int] = _notes_for(held, fee)
			if notes.is_empty() and fee > 0:
				affordable = 0
				fee = 0
			else:
				_items.move_items(notes, ItemSystem.WORLD)
		if affordable > 0:
			var taking: Array[int] = items_on(corpse).slice(0, affordable)
			returned = _items.move_items(taking, ItemSystem.inventory_of(actor))
			if returned == 0:
				fee = 0
	var plot: StringName = _plot_of(actor)
	var where: Vector3i = _centre_of(plot)
	if _actors.set_position(actor, where) != OK:
		return false
	if not _actors.revive(actor):
		return false
	_events.emit(EVENT_RESPAWNED, {"actor": actor, "corpse": corpse, "returned": returned, "fee": fee, "x": where.x, "y": where.y, "z": where.z})
	return true


## True when the corpse fell somewhere the law holds scenes.
func _police_hold(corpse: int) -> bool:
	var rule: Dictionary = _rule()
	var threshold: int = rule["law_threshold"]
	var parcel: StringName = _land.parcel_at(position_of(corpse))
	var district: StringName = _land.wild_district() if parcel.is_empty() else _land.district_of(parcel)
	if not _content.has(LandSystem.KIND_DISTRICT, district):
		return false
	var record: Dictionary = _content.get_entry(LandSystem.KIND_DISTRICT, district)
	var law: int = record["law_index"]
	return law > threshold


## Enough notes out of a container to cover a fee, in the order they lie; empty if
## they do not cover it. The police do not make change.
func _notes_for(container: StringName, fee: int) -> Array[int]:
	var out: Array[int] = []
	if fee <= 0:
		return out
	var paid: int = 0
	for item: int in _items.items_in(container):
		if _items.item_kind(item) != ItemSystem.KIND_CURRENCY:
			continue
		out.append(item)
		paid += _items.face_value_of_template(_items.item_template(item))
		if paid >= fee:
			return out
	return [] as Array[int]


func _rule() -> Dictionary:
	return _content.get_entry(KIND_RECOVERY, RULE)


## Where the actor stands again: the middle of a parcel they own, or the rule's
## fallback if they own none. Non-convex parcels exist (the north neighbour is an L),
## so the average of the corners is only used when it really is inside.
func _plot_of(actor: int) -> StringName:
	var tag: StringName = _land.owner_tag_of_actor(actor)
	if not tag.is_empty():
		for id: StringName in _land.parcel_ids():
			if _land.owner_of(id) == tag:
				return id
	var rule: Dictionary = _rule()
	var fallback: String = rule["fallback_parcel"]
	return StringName(fallback)


func _centre_of(parcel: StringName) -> Vector3i:
	var record: Dictionary = _land.parcel(parcel)
	if record.is_empty():
		return Vector3i.ZERO
	var footprint: Array = record["footprint"]
	var floor_y: int = record["floor_y"]
	var y: int = maxi(floor_y, 0)
	var sum_x: int = 0
	var sum_z: int = 0
	var min_x: int = 0
	var min_z: int = 0
	var max_x: int = 0
	var max_z: int = 0
	for i: int in footprint.size():
		var pair: Array = footprint[i]
		var px: int = pair[0]
		var pz: int = pair[1]
		sum_x += px
		sum_z += pz
		if i == 0 or px < min_x:
			min_x = px
		if i == 0 or px > max_x:
			max_x = px
		if i == 0 or pz < min_z:
			min_z = pz
		if i == 0 or pz > max_z:
			max_z = pz
	var average := Vector3i(sum_x / footprint.size(), y, sum_z / footprint.size())
	if _land.parcel_at(average) == parcel:
		return average
	# an L or worse: take the first metre square whose middle really is inside
	var step: int = BuildSystem.CELL
	var x: int = min_x + step / 2
	while x < max_x:
		var z: int = min_z + step / 2
		while z < max_z:
			var probe := Vector3i(x, y, z)
			if _land.parcel_at(probe) == parcel:
				return probe
			z += step
		x += step
	return average


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 1 or typeof(state.get("corpses")) != TYPE_DICTIONARY:
		return _restore_fail("shape")
	var in_all: Dictionary = state["corpses"]
	var out: Dictionary = {}
	for key: Variant in in_all:
		if typeof(key) != TYPE_INT or typeof(in_all[key]) != TYPE_DICTIONARY:
			return _restore_fail("corpse key")
		var corpse: int = key
		if corpse < 1:
			return _restore_fail("corpse %d is not an entity id" % corpse)
		var rec: Dictionary = in_all[key]
		if rec.size() != 2 or typeof(rec.get("actor")) != TYPE_INT or typeof(rec.get("pos")) != TYPE_ARRAY:
			return _restore_fail("corpse %d record" % corpse)
		var actor: int = rec["actor"]
		# a body outlives a respawn, and a second death leaves a second one: neither a
		# standing actor nor an actor with two bodies is a corrupt save
		if not _actors.has_actor(actor):
			return _restore_fail("corpse %d is nobody" % corpse)
		var pos: Array = rec["pos"]
		if pos.size() != 3:
			return _restore_fail("corpse %d position" % corpse)
		var out_pos: Array[int] = []
		for v: Variant in pos:
			if typeof(v) != TYPE_INT:
				return _restore_fail("corpse %d position value" % corpse)
			var n: int = v
			out_pos.append(n)
		out[corpse] = {"actor": actor, "pos": out_pos}
	_corpses = out
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("CorpseSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
