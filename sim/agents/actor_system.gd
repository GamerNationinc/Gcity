## Minimal actors for M1 (spec claim 12): the player and target dummies as entities with
## an inventory container (owned by [ItemSystem] under `inv.<actor>`), a wielded-weapon
## slot and a health graph shaped by their combat profile (design doc §13.2). The
## perception, utility and squad layers of §14 arrive at M4 on top of this.
class_name ActorSystem extends SimSystem

const SYSTEM_ID: StringName = &"actors"
const KIND_PROFILE: StringName = &"combat_profile"
const COMMAND_SPAWN: StringName = &"actor.spawn"
const COMMAND_WIELD: StringName = &"actor.wield"
const MAX_RANGE_M: int = 10_000

var _content: ContentDb
var _stats: StatResolver
var _ids: EntityIds
var _items: ItemSystem
## actor id -> {"profile": StringName, "health": {node: int}, "wielded": int, "range_m": int, "alive": bool}
var _actors: Dictionary = {}


func _init(content: ContentDb, stats: StatResolver, ids: EntityIds, items: ItemSystem) -> void:
	_content = content
	_stats = stats
	_ids = ids
	_items = items


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


func snapshot() -> Dictionary:
	return {"actors": _actors.duplicate(true)}


func attach(sim: SimRoot) -> Error:
	var err: Error = validate_content()
	if err != OK:
		return err
	err = sim.register_system(self)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_SPAWN, _on_spawn)
	if err != OK:
		return err
	return sim.commands().register(COMMAND_WIELD, _on_wield)


## Health nodes must be unique and every routing entry must name one.
func validate_content() -> Error:
	for profile: StringName in _content.ids(KIND_PROFILE):
		var t: Dictionary = _content.get_entry(KIND_PROFILE, profile)
		var health: Dictionary = t["health"]
		var nodes: Array = health["nodes"]
		var seen: Array[String] = []
		var any_fatal: bool = false
		for n: Variant in nodes:
			var nd: Dictionary = n
			var id: String = nd["id"]
			if seen.has(id):
				push_error("ActorSystem: combat_profile/%s declares node '%s' twice" % [profile, id])
				return ERR_INVALID_DATA
			seen.append(id)
			var fatal: bool = nd["fatal"]
			any_fatal = any_fatal or fatal
		if not any_fatal:
			push_error("ActorSystem: combat_profile/%s has no fatal node; nothing could die" % profile)
			return ERR_INVALID_DATA
		var routing: Array = health["routing"]
		for r: Variant in routing:
			var rd: Dictionary = r
			var node: String = rd["node"]
			if not seen.has(node):
				push_error("ActorSystem: combat_profile/%s routes to unknown node '%s'" % [profile, node])
				return ERR_INVALID_DATA
	return OK


# ---------------------------------------------------------------- queries

func has_actor(actor: int) -> bool:
	return _actors.has(actor)


func actor_ids() -> Array[int]:
	var out: Array[int] = []
	for key: Variant in _actors:
		var id: int = key
		out.append(id)
	out.sort()
	return out


func profile_of(actor: int) -> StringName:
	if not _actors.has(actor):
		return &""
	var rec: Dictionary = _actors[actor]
	return rec["profile"]


func profile_data(actor: int) -> Dictionary:
	var profile: StringName = profile_of(actor)
	if profile.is_empty():
		return {}
	return _content.get_entry(KIND_PROFILE, profile)


## node -> current hit points (milli-hp). A copy.
func health_of(actor: int) -> Dictionary:
	if not _actors.has(actor):
		return {}
	var rec: Dictionary = _actors[actor]
	var health: Dictionary = rec["health"]
	return health.duplicate()


func max_health(actor: int, node: StringName) -> int:
	var t: Dictionary = profile_data(actor)
	if t.is_empty():
		return 0
	var health: Dictionary = t["health"]
	var nodes: Array = health["nodes"]
	for n: Variant in nodes:
		var nd: Dictionary = n
		var id_s: String = nd["id"]
		if StringName(id_s) == node:
			return nd["max"]
	return 0


func is_alive(actor: int) -> bool:
	if not _actors.has(actor):
		return false
	var rec: Dictionary = _actors[actor]
	return rec["alive"]


func wielded(actor: int) -> int:
	if not _actors.has(actor):
		return EntityIds.NONE
	var rec: Dictionary = _actors[actor]
	return rec["wielded"]


func range_of(actor: int) -> int:
	if not _actors.has(actor):
		return 0
	var rec: Dictionary = _actors[actor]
	return rec["range_m"]


# ---------------------------------------------------------------- mutation used by combat

## Spawns an actor of a profile at a declared range. Returns its id, or 0 with an error.
func spawn(profile: StringName, range_m: int) -> int:
	if not _content.has(KIND_PROFILE, profile):
		push_error("ActorSystem: no combat_profile/%s" % profile)
		return EntityIds.NONE
	if range_m < 0 or range_m > MAX_RANGE_M:
		push_error("ActorSystem: range_m out of range: %d" % range_m)
		return EntityIds.NONE
	var t: Dictionary = _content.get_entry(KIND_PROFILE, profile)
	var health_t: Dictionary = t["health"]
	var nodes: Array = health_t["nodes"]
	var health: Dictionary = {}
	for n: Variant in nodes:
		var nd: Dictionary = n
		var id_s: String = nd["id"]
		health[StringName(id_s)] = nd["max"]
	var id: int = _ids.allocate()
	_actors[id] = {"profile": profile, "health": health, "wielded": EntityIds.NONE, "range_m": range_m, "alive": true}
	return id


## Subtracts damage from a node, never below zero. A fatal node at zero kills the actor.
## Returns the amount actually applied.
func damage_node(actor: int, node: StringName, amount: int) -> int:
	if not _actors.has(actor) or amount <= 0:
		return 0
	var rec: Dictionary = _actors[actor]
	var health: Dictionary = rec["health"]
	if not health.has(node):
		push_error("ActorSystem: actor %d has no health node '%s'" % [actor, node])
		return 0
	var current: int = health[node]
	var applied: int = mini(current, amount)
	health[node] = current - applied
	var profile: StringName = rec["profile"]
	if health[node] == 0 and _is_fatal(profile, node):
		rec["alive"] = false
	return applied


func _is_fatal(profile: StringName, node: StringName) -> bool:
	var t: Dictionary = _content.get_entry(KIND_PROFILE, profile)
	var health: Dictionary = t["health"]
	var nodes: Array = health["nodes"]
	for n: Variant in nodes:
		var nd: Dictionary = n
		var id_s: String = nd["id"]
		if StringName(id_s) == node:
			return nd["fatal"]
	return false


# ---------------------------------------------------------------- commands

## {"profile": name, "range_m": int}. Debug-class (spec claim 12): gated before co-op.
func _on_spawn(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or not payload.has("profile") or not payload.has("range_m"):
		return false
	var profile: StringName = _as_name(payload["profile"])
	if profile.is_empty() or typeof(payload["range_m"]) != TYPE_INT:
		return false
	var range_m: int = payload["range_m"]
	if not _content.has(KIND_PROFILE, profile) or range_m < 0 or range_m > MAX_RANGE_M:
		return false
	var id: int = spawn(profile, range_m)
	return id != EntityIds.NONE


## {"actor": int, "weapon": int}: wield a weapon frame from the actor's inventory, or
## 0 to unwield. The wielded weapon inherits the actor's tagged modifiers.
func _on_wield(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("weapon")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var weapon: int = payload["weapon"]
	if not _actors.has(actor) or not is_alive(actor):
		return false
	var rec: Dictionary = _actors[actor]
	var current: int = rec["wielded"]
	if weapon == EntityIds.NONE:
		if current == EntityIds.NONE:
			return false
		_stats.set_inherits(current, -1)
		rec["wielded"] = EntityIds.NONE
		return true
	if _items.item_kind(weapon) != ItemSystem.KIND_FRAME or _items.container_of(weapon) != ItemSystem.inventory_of(actor):
		return false
	if current == weapon:
		return false
	if current != EntityIds.NONE:
		_stats.set_inherits(current, -1)
	if _stats.set_inherits(weapon, actor) != OK:
		return false
	rec["wielded"] = weapon
	return true


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 1 or typeof(state.get("actors")) != TYPE_DICTIONARY:
		return _restore_fail("shape")
	var actors_in: Dictionary = state["actors"]
	var out: Dictionary = {}
	for ak: Variant in actors_in:
		if typeof(ak) != TYPE_INT or ak < 1 or typeof(actors_in[ak]) != TYPE_DICTIONARY:
			return _restore_fail("actor key or record")
		var rec: Dictionary = actors_in[ak]
		if rec.size() != 5 or typeof(rec.get("health")) != TYPE_DICTIONARY or typeof(rec.get("wielded")) != TYPE_INT \
				or typeof(rec.get("range_m")) != TYPE_INT or typeof(rec.get("alive")) != TYPE_BOOL:
			return _restore_fail("actor %d fields" % ak)
		var profile: StringName = _as_name(rec.get("profile"))
		if not _content.has(KIND_PROFILE, profile):
			return _restore_fail("actor %d profile" % ak)
		var range_m: int = rec["range_m"]
		if range_m < 0 or range_m > MAX_RANGE_M:
			return _restore_fail("actor %d range" % ak)
		var t: Dictionary = _content.get_entry(KIND_PROFILE, profile)
		var health_t: Dictionary = t["health"]
		var nodes: Array = health_t["nodes"]
		var health_in: Dictionary = rec["health"]
		if health_in.size() != nodes.size():
			return _restore_fail("actor %d health nodes" % ak)
		var health: Dictionary = {}
		for n: Variant in nodes:
			var nd: Dictionary = n
			var id_s: String = nd["id"]
			var node: StringName = StringName(id_s)
			var hp_v: Variant = health_in.get(node, health_in.get(id_s))
			if typeof(hp_v) != TYPE_INT or hp_v < 0 or hp_v > nd["max"]:
				return _restore_fail("actor %d node %s" % [ak, node])
			health[node] = hp_v
		var wielded_v: int = rec["wielded"]
		var actor_id: int = ak
		if wielded_v != EntityIds.NONE and (_items.item_kind(wielded_v) != ItemSystem.KIND_FRAME or _items.container_of(wielded_v) != ItemSystem.inventory_of(actor_id)):
			return _restore_fail("actor %d wields something it does not hold" % ak)
		out[ak] = {"profile": profile, "health": health, "wielded": wielded_v, "range_m": range_m, "alive": rec["alive"]}
	_actors = out
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("ActorSystem.restore: rejected snapshot: %s" % reason)
	return ERR_INVALID_DATA


static func _as_name(v: Variant) -> StringName:
	match typeof(v):
		TYPE_STRING_NAME:
			return v
		TYPE_STRING:
			var s: String = v
			return StringName(s)
		_:
			return &""
