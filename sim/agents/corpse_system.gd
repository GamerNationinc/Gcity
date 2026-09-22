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
const COMMAND_LOOT: StringName = &"corpse.loot"
const EVENT_LEFT: StringName = &"corpse.left"
const EVENT_LOOTED: StringName = &"corpse.looted"
## How close a looter must stand, in millimetres. An arm's length over a body.
const REACH_MM: int = 1500

var _actors: ActorSystem
var _items: ItemSystem
var _ids: EntityIds
var _events: EventBus
## corpse id -> {"actor": int, "pos": Array[int]}
var _corpses: Dictionary = {}


func _init(actors: ActorSystem, items: ItemSystem, ids: EntityIds, events: EventBus) -> void:
	_actors = actors
	_items = items
	_ids = ids
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


func snapshot() -> Dictionary:
	return {"corpses": _corpses.duplicate(true)}


func attach(sim: SimRoot) -> Error:
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_LOOT, _on_loot, false)
	if err != OK:
		return err
	return _events.subscribe(ActorSystem.EVENT_DIED, _on_died)


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


## The corpse of an actor, or EntityIds.NONE if that actor left none.
func corpse_of(actor: int) -> int:
	for corpse: int in corpse_ids():
		var rec: Dictionary = _corpses[corpse]
		var who: int = rec["actor"]
		if who == actor:
			return corpse
	return EntityIds.NONE


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


# ---------------------------------------------------------------- events

## One corpse per death, holding everything the actor carried. An actor that dies
## empty-handed still leaves a body: it is evidence whether or not it is loot.
func _on_died(payload: Dictionary) -> void:
	var actor: int = payload["actor"]
	if corpse_of(actor) != EntityIds.NONE:
		return
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


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 1 or typeof(state.get("corpses")) != TYPE_DICTIONARY:
		return _restore_fail("shape")
	var in_all: Dictionary = state["corpses"]
	var out: Dictionary = {}
	var seen_actors: Array[int] = []
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
		if not _actors.has_actor(actor):
			return _restore_fail("corpse %d is nobody" % corpse)
		if _actors.is_alive(actor):
			return _restore_fail("corpse %d belongs to a living actor" % corpse)
		if seen_actors.has(actor):
			return _restore_fail("actor %d has two corpses" % actor)
		seen_actors.append(actor)
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
