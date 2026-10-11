## Corpses and other places items lie in the world (M6 spec claim 16, ADR-007 C).
## When an actor dies (`actor.died`), a `corpse.<n>` place is made where it fell and
## everything in its inventory moves there in container order, the wielded weapon
## and its magazines included; the device stays with its owner, since it is the UI
## and how a recovery run finds the body. `item.take {actor, from, item}` moves a
## loose item from a place within reach into the actor's inventory; `item.drop
## {actor, item}` puts one on the pile at the actor's feet (made if there is none).
## Taking from a corpse that is not the actor's own needs `loot` where it lies: a
## violation is recorded like any other and the take still happens, as trespass and
## breaching are recorded and not prevented. A site's crate (`crate.<n>`, made by
## the site system) is a place too, with no loot check: the spec names corpses. A place
## goes when it is emptied.
class_name CorpseSystem extends SimSystem

const SYSTEM_ID: StringName = &"corpses"
const COMMAND_TAKE: StringName = &"item.take"
const COMMAND_DROP: StringName = &"item.drop"
## {corpse, actor, x, y, z, items}
const EVENT_CREATED: StringName = &"corpse.created"
## {actor, item, from, to}
const EVENT_MOVED: StringName = &"item.moved"
const KIND_CORPSE: String = "corpse"
const KIND_PILE: String = "pile"
const KIND_CRATE: String = "crate"
## How far a hand reaches into a place: the neighbouring cell, on the same storey.
const REACH_MM: int = 1500

var _items: ItemSystem
var _actors: ActorSystem
var _land: LandSystem
var _events: EventBus
## place name -> {"kind": String, "owner": int (0 for a pile), "pos": [x, y, z]}
var _places: Dictionary = {}
## the number the next place takes
var _next: int = 1


func _init(items: ItemSystem, actors: ActorSystem, land: LandSystem, events: EventBus) -> void:
	_items = items
	_actors = actors
	_land = land
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


func attach(sim: SimRoot) -> Error:
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_TAKE, _on_take)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_DROP, _on_drop)
	if err != OK:
		return err
	return _events.subscribe(ActorSystem.EVENT_DIED, _on_died)


# ---------------------------------------------------------------- queries

## Every place, in name order.
func place_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: Variant in _places:
		var name: String = key
		out.append(StringName(name))
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


func has_place(place: StringName) -> bool:
	return _places.has(String(place))


## The actor's most recent corpse, or &"" if it has none.
func corpse_of(actor: int) -> StringName:
	var best: StringName = &""
	var best_n: int = 0
	for place: StringName in place_ids():
		var rec: Dictionary = _places[String(place)]
		var n: int = int(String(place).split(".")[1])
		if rec["kind"] == KIND_CORPSE and rec["owner"] == actor and n > best_n:
			best = place
			best_n = n
	return best


func position_of(place: StringName) -> Vector3i:
	if not has_place(place):
		return Vector3i.ZERO
	var rec: Dictionary = _places[String(place)]
	var pos: Array = rec["pos"]
	var x: int = pos[0]
	var y: int = pos[1]
	var z: int = pos[2]
	return Vector3i(x, y, z)


func storey_of(place: StringName) -> int:
	return BuildSystem.cell_of(position_of(place)).y


## The actor whose body a corpse is; 0 for a pile or an unknown place.
func owner_of(place: StringName) -> int:
	if not has_place(place):
		return EntityIds.NONE
	var rec: Dictionary = _places[String(place)]
	return rec["owner"]


## Within reach: on the same storey and no more than REACH_MM away on the ground.
func in_reach(actor: int, place: StringName) -> bool:
	if not has_place(place):
		return false
	var a: Vector3i = _actors.position_of(actor)
	var p: Vector3i = position_of(place)
	if BuildSystem.cell_of(a).y != BuildSystem.cell_of(p).y:
		return false
	var dx: int = a.x - p.x
	var dz: int = a.z - p.z
	return dx * dx + dz * dz <= REACH_MM * REACH_MM


# ---------------------------------------------------------------- events and commands

func _on_died(payload: Dictionary) -> void:
	var actor: int = payload["actor"]
	var x: int = payload["x"]
	var y: int = payload["y"]
	var z: int = payload["z"]
	var corpse: StringName = _make(KIND_CORPSE, actor, Vector3i(x, y, z))
	var device: int = _actors.device_of(actor)
	var moved: int = 0
	for item: int in _items.items_in(ItemSystem.inventory_of(actor)):
		if item == device:
			continue
		var ok: bool = _items.transfer(item, corpse)
		assert(ok, "a place takes any loose item")
		moved += 1
	_events.emit(EVENT_CREATED, {"corpse": String(corpse), "actor": actor, "x": x, "y": y, "z": z, "items": moved})


## {"actor": int, "from": place name, "item": int}
func _on_take(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 3 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("item")) != TYPE_INT:
		return false
	var from_v: Variant = payload.get("from")
	if typeof(from_v) != TYPE_STRING and typeof(from_v) != TYPE_STRING_NAME:
		return false
	var from_s: String = from_v
	var from: StringName = StringName(from_s)
	var actor: int = payload["actor"]
	var item: int = payload["item"]
	if not _actors.is_alive(actor) or not has_place(from) or _items.container_of(item) != from or not in_reach(actor, from):
		return false
	var rec: Dictionary = _places[from_s]
	var owner: int = rec["owner"]
	if rec["kind"] == KIND_CORPSE and owner != actor:
		_land.require(position_of(from), actor, &"loot")  # a crime is recorded, not prevented
	var inv: StringName = ItemSystem.inventory_of(actor)
	if not _items.transfer(item, inv):
		return false
	_moved(actor, item, from, inv)
	return true


## {"actor": int, "item": int}
func _on_drop(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("item")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var item: int = payload["item"]
	var inv: StringName = ItemSystem.inventory_of(actor)
	if not _actors.is_alive(actor) or _items.container_of(item) != inv or _actors.wielded(actor) == item or _actors.device_of(actor) == item:
		return false
	var feet: Vector3i = _actors.position_of(actor)
	var pile: StringName = _pile_at(BuildSystem.cell_of(feet))
	var made: bool = pile.is_empty()
	if made:
		pile = _make(KIND_PILE, EntityIds.NONE, feet)
	if not _items.transfer(item, pile):
		if made:
			_places.erase(String(pile))
		return false
	_moved(actor, item, inv, pile)
	return true


## A crate place at `at` (M6 claims 13 and 16: a site's container), empty; the
## caller fills it with ItemSystem.spawn.
func make_crate(at: Vector3i) -> StringName:
	return _make(KIND_CRATE, EntityIds.NONE, at)


func _pile_at(cell: Vector3i) -> StringName:
	for place: StringName in place_ids():
		var rec: Dictionary = _places[String(place)]
		if rec["kind"] == KIND_PILE and BuildSystem.cell_of(position_of(place)) == cell:
			return place
	return &""


func _make(kind: String, owner: int, at: Vector3i) -> StringName:
	var name: String = "%s.%d" % [kind, _next]
	_next += 1
	_places[name] = {"kind": kind, "owner": owner, "pos": [at.x, at.y, at.z] as Array[int]}
	return StringName(name)


func _moved(actor: int, item: int, from: StringName, to: StringName) -> void:
	_events.emit(EVENT_MOVED, {"actor": actor, "item": item, "from": String(from), "to": String(to)})
	# a place goes when it is emptied (after the event, so listeners can still read it)
	if has_place(from) and _items.items_in(from).is_empty():
		_places.erase(String(from))


# ---------------------------------------------------------------- state

func snapshot() -> Dictionary:
	return {"places": _places.duplicate(true), "next": _next}


func restore(state: Dictionary) -> Error:
	if state.size() != 2 or typeof(state.get("places")) != TYPE_DICTIONARY or typeof(state.get("next")) != TYPE_INT:
		return _restore_fail("shape")
	var next: int = state["next"]
	var src: Dictionary = state["places"]
	var out: Dictionary = {}
	for k: Variant in src:
		if typeof(k) != TYPE_STRING or typeof(src[k]) != TYPE_DICTIONARY:
			return _restore_fail("place key")
		var name: String = k
		var rec: Dictionary = src[k]
		if not ItemSystem.is_place(StringName(name)) or rec.size() != 3 or typeof(rec.get("kind")) != TYPE_STRING \
				or typeof(rec.get("owner")) != TYPE_INT or typeof(rec.get("pos")) != TYPE_ARRAY:
			return _restore_fail("place %s record" % name)
		var kind: String = rec["kind"]
		var owner: int = rec["owner"]
		var pos: Array = rec["pos"]
		var parts: PackedStringArray = name.split(".")
		if kind != parts[0] or int(parts[1]) >= next:
			return _restore_fail("place %s kind or number" % name)
		if (kind == KIND_CORPSE and not _actors.has_actor(owner)) or (kind != KIND_CORPSE and owner != EntityIds.NONE):
			return _restore_fail("place %s owner" % name)
		if pos.size() != 3:
			return _restore_fail("place %s position" % name)
		var at: Array[int] = []
		for v: Variant in pos:
			if typeof(v) != TYPE_INT:
				return _restore_fail("place %s position" % name)
			var c: int = v
			at.append(c)
		out[name] = {"kind": kind, "owner": owner, "pos": at}
	_places = out
	_next = next
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("CorpseSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
