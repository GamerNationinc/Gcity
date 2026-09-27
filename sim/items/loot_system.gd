## Bodies and stores (M6 spec claims 1, 14, 15; ADR-007 C, ADR-011 C): holders of
## whole items at a place. A body (`corpse`) is made where an actor died and holds
## what it carried; a store is a site's named container, stocked when the site is
## raised. `container.take {actor, container, item}` moves one top-level item from a
## holder into the taker's inventory when the taker stands beside it (within one
## cell). An actor's own body is always theirs; anyone else's, or a store, is `loot`
## (`LandSystem.offend`: the take proceeds and a denied right is one violation). A
## body emptied is gone; a store stays. Scavengers are M8's: a body waits.
class_name LootSystem extends SimSystem

const SYSTEM_ID: StringName = &"loot"
const COMMAND_TAKE: StringName = &"container.take"
const KIND_CORPSE: String = "corpse"
const KIND_STORE: String = "store"

var _content: ContentDb
var _ids: EntityIds
var _items: ItemSystem
var _actors: ActorSystem
var _land: LandSystem
## holder id -> {"kind": "corpse" | "store", "owner": actor or 0, "site": String,
##               "name": String, "pos": [x, y, z]}
var _holders: Dictionary = {}


func _init(content: ContentDb, ids: EntityIds, items: ItemSystem, actors: ActorSystem, land: LandSystem) -> void:
	_content = content
	_ids = ids
	_items = items
	_actors = actors
	_land = land


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


func snapshot() -> Dictionary:
	return {"holders": _holders.duplicate(true)}


func attach(sim: SimRoot) -> Error:
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	return sim.commands().register(COMMAND_TAKE, _on_take)


# ---------------------------------------------------------------- making holders

## A body for `owner` at `pos` (millimetres). Returns its id; its container is
## [method container_name].
func make_corpse(owner: int, pos: Vector3i) -> int:
	var id: int = _ids.allocate()
	_holders[id] = {"kind": KIND_CORPSE, "owner": owner, "site": "", "name": "", "pos": [pos.x, pos.y, pos.z] as Array[int]}
	return id


## A site's named store at `pos`. Returns its id.
func install_store(site: StringName, name: StringName, pos: Vector3i) -> int:
	var id: int = _ids.allocate()
	_holders[id] = {"kind": KIND_STORE, "owner": EntityIds.NONE, "site": String(site), "name": String(name), "pos": [pos.x, pos.y, pos.z] as Array[int]}
	return id


## Whether a site's store entry can be stocked: every item a spawnable kind and a
## template that exists, in a positive count.
func store_entry_is_valid(entry: Dictionary) -> bool:
	var items: Array = entry["items"]
	for i: Variant in items:
		var d: Dictionary = i
		var kind_s: String = d["kind"]
		var template_s: String = d["template"]
		var count: int = d["count"]
		if count < 1 or not ItemSystem.SPAWNABLE.has(StringName(kind_s)) or not _content.has(StringName(kind_s), StringName(template_s)):
			return false
	return true


# ---------------------------------------------------------------- queries

func holder_ids() -> Array[int]:
	var out: Array[int] = []
	for key: Variant in _holders:
		var id: int = key
		out.append(id)
	out.sort()
	return out


func holder_kind(holder: int) -> StringName:
	if not _holders.has(holder):
		return &""
	var rec: Dictionary = _holders[holder]
	var kind: String = rec["kind"]
	return StringName(kind)


func holder_name(holder: int) -> StringName:
	if not _holders.has(holder):
		return &""
	var rec: Dictionary = _holders[holder]
	var name: String = rec["name"]
	return StringName(name)


## Whose body it is, or NONE for a store or an unknown holder.
func owner_of(holder: int) -> int:
	if not _holders.has(holder):
		return EntityIds.NONE
	var rec: Dictionary = _holders[holder]
	return rec["owner"]


func position_of(holder: int) -> Vector3i:
	if not _holders.has(holder):
		return Vector3i.ZERO
	var rec: Dictionary = _holders[holder]
	return PathingSystem._vec(rec["pos"])


func container_name(holder: int) -> StringName:
	return ItemSystem.holding_container(holder_kind(holder), holder)


# ---------------------------------------------------------------- taking

## Moves one item from a holder to the actor's inventory (see the class comment).
func take(actor: int, holder: int, item: int) -> bool:
	if not _actors.is_alive(actor) or not _holders.has(holder) or _items.container_of(item) != container_name(holder):
		return false
	var here: Vector3i = BuildSystem.cell_of(_actors.position_of(actor))
	var there: Vector3i = BuildSystem.cell_of(position_of(holder))
	var d: Vector3i = here - there
	if absi(d.x) + absi(d.y) + absi(d.z) > 1:
		return false
	if owner_of(holder) != actor:
		_land.offend(position_of(holder), actor, &"loot")
	var moved: bool = _items.move_item(item, ItemSystem.inventory_of(actor))
	assert(moved, "a top-level item in a holder moves to an inventory")
	if holder_kind(holder) == &"corpse" and _items.items_in(container_name(holder)).is_empty():
		_holders.erase(holder)
	return true


## {"actor": int, "container": int, "item": int}
func _on_take(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 3 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("container")) != TYPE_INT \
			or typeof(payload.get("item")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var holder: int = payload["container"]
	var item: int = payload["item"]
	return take(actor, holder, item)


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 1 or typeof(state.get("holders")) != TYPE_DICTIONARY:
		return _restore_fail("shape")
	var in_all: Dictionary = state["holders"]
	var out: Dictionary = {}
	for key: Variant in in_all:
		if typeof(key) != TYPE_INT or typeof(in_all[key]) != TYPE_DICTIONARY:
			return _restore_fail("holder key")
		var id: int = key
		var rec: Dictionary = in_all[key]
		if rec.size() != 5 or typeof(rec.get("kind")) != TYPE_STRING or typeof(rec.get("owner")) != TYPE_INT \
				or typeof(rec.get("site")) != TYPE_STRING or typeof(rec.get("name")) != TYPE_STRING or typeof(rec.get("pos")) != TYPE_ARRAY:
			return _restore_fail("holder %d fields" % id)
		var kind: String = rec["kind"]
		var owner: int = rec["owner"]
		var site: String = rec["site"]
		var name: String = rec["name"]
		var pos: Array = rec["pos"]
		var kind_ok: bool = (kind == KIND_CORPSE and _actors.has_actor(owner)) or (kind == KIND_STORE and owner == EntityIds.NONE and _content.has(SiteSystem.KIND_SITE, StringName(site)))
		if id < 1 or not kind_ok or pos.size() != 3:
			return _restore_fail("holder %d values" % id)
		for v: Variant in pos:
			if typeof(v) != TYPE_INT:
				return _restore_fail("holder %d position" % id)
		var x: int = pos[0]
		var y: int = pos[1]
		var z: int = pos[2]
		out[id] = {"kind": kind, "owner": owner, "site": site, "name": name, "pos": [x, y, z] as Array[int]}
	_holders = out
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("LootSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
