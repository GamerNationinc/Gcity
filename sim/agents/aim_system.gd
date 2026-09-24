## Aim quality is separate from awareness (design doc §14.2; M4 spec claim 6). Each
## agent aims at the visible contact it is most aware of. Its error cone starts wide,
## converges linearly over `settle_ticks` while that target stays visible, resets
## when sight breaks or the target changes, and carries a swing-through penalty for
## `swing_ticks` after a target appears (a swing outlives a broken contact). The cone reaches combat as one `aim`
## modifier on the agent's `hit_chance`, tagged `weapon` so the wielded weapon
## inherits it (design doc §10.2): `hit_roll` needs no branch, and an actor without
## an aim profile (the player) is untouched. With no target the cone sits at its
## widest, so breaking contact never improves a shot.
class_name AimSystem extends SimSystem

const SYSTEM_ID: StringName = &"aim"
const KIND_AIM: StringName = &"aim_profile"
const SOURCE: StringName = &"aim"
const TAG_WEAPON: StringName = &"weapon"

var _content: ContentDb
var _stats: StatResolver
var _actors: ActorSystem
var _perception: PerceptionSystem
var _events: EventBus
## agent -> {"target": int (0 = none), "settle": int, "swing": int, "handle": int, "value": int}
var _aim: Dictionary = {}


func _init(content: ContentDb, stats: StatResolver, actors: ActorSystem, perception: PerceptionSystem, events: EventBus) -> void:
	_content = content
	_stats = stats
	_actors = actors
	_perception = perception
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func snapshot() -> Dictionary:
	return {"aim": _aim.duplicate(true)}


func attach(sim: SimRoot) -> Error:
	var err: Error = validate_content()
	if err != OK:
		return err
	err = sim.register_system(self)
	if err != OK:
		return err
	return _events.subscribe(ActorSystem.EVENT_REMOVED, _on_removed)


## A removed agent's aim goes with it, its modifier released first; anyone aiming at a
## removed actor is aiming at nothing, and picks again on its next tick.
func _on_removed(payload: Dictionary) -> void:
	var actor: int = payload["actor"]
	if _aim.has(actor):
		var rec: Dictionary = _aim[actor]
		var handle: int = rec["handle"]
		if handle != 0:
			var removed: Error = _stats.remove_modifier(handle)
			assert(removed == OK, "the aim modifier is live until the agent goes")
		_aim.erase(actor)
	for key: Variant in _aim:
		var rec: Dictionary = _aim[key]
		var target: int = rec["target"]
		if target == actor:
			rec["target"] = EntityIds.NONE


## Every agent profile binds an aim profile that exists; hit_chance is registered.
func validate_content() -> Error:
	if not _stats.has_stat(CombatSystem.STAT_HIT_CHANCE):
		push_error("AimSystem: no stat '%s'" % CombatSystem.STAT_HIT_CHANCE)
		return ERR_INVALID_DATA
	for id: StringName in _content.ids(PerceptionSystem.KIND_AGENT):
		var t: Dictionary = _content.get_entry(PerceptionSystem.KIND_AGENT, id)
		if typeof(t.get("aim_profile")) != TYPE_STRING:
			push_error("AimSystem: agent_profile/%s has no aim_profile" % id)
			return ERR_INVALID_DATA
		var aim_s: String = t["aim_profile"]
		if not _content.has(KIND_AIM, StringName(aim_s)):
			push_error("AimSystem: agent_profile/%s: no aim_profile/%s" % [id, aim_s])
			return ERR_INVALID_DATA
	return OK


# ---------------------------------------------------------------- queries

## The aim profile entry of an agent, or an empty dictionary.
func aim_profile_of(agent: int) -> Dictionary:
	var profile: StringName = _perception.profile_of(agent)
	if profile.is_empty():
		return {}
	var t: Dictionary = _content.get_entry(PerceptionSystem.KIND_AGENT, profile)
	var aim_s: String = t["aim_profile"]
	return _content.get_entry(KIND_AIM, StringName(aim_s))


func target_of(agent: int) -> int:
	var rec: Dictionary = _record(agent)
	if rec.is_empty():
		return EntityIds.NONE
	return rec["target"]


func settle_of(agent: int) -> int:
	var rec: Dictionary = _record(agent)
	if rec.is_empty():
		return 0
	return rec["settle"]


## The agent's current error cone in milli-degrees: the profile's start with no
## record, otherwise the settled state.
func cone_of(agent: int) -> int:
	var p: Dictionary = aim_profile_of(agent)
	if p.is_empty():
		return 0
	var rec: Dictionary = _record(agent)
	if rec.is_empty():
		return cone_mdeg(p, 0, 0)
	var settle: int = rec["settle"]
	var swing: int = rec["swing"]
	return cone_mdeg(p, settle, swing)


## The hit_chance penalty (basis points of a percent) the cone imposes.
func penalty_of(agent: int) -> int:
	var p: Dictionary = aim_profile_of(agent)
	if p.is_empty():
		return 0
	var per: int = p["penalty_per_mdeg"]
	return cone_of(agent) * per


func _record(agent: int) -> Dictionary:
	var stored: Variant = _aim.get(agent)
	if typeof(stored) != TYPE_DICTIONARY:
		return {}
	return stored


## The cone for a settle count in [0, settle_ticks] and the swing ticks left: the
## settled cone plus the unsettled remainder, plus the swing penalty while it lasts.
static func cone_mdeg(p: Dictionary, settle: int, swing: int) -> int:
	var start: int = p["cone_start_mdeg"]
	var settled: int = p["cone_settled_mdeg"]
	var ticks: int = p["settle_ticks"]
	var swing_penalty: int = p["swing_penalty_mdeg"]
	var s: int = clampi(settle, 0, ticks)
	var cone: int = settled + (start - settled) * (ticks - s) / ticks
	if swing > 0:
		cone += swing_penalty
	return cone


# ---------------------------------------------------------------- the tick

func tick(_sim: SimRoot) -> void:
	for agent: int in _perception.agent_ids():
		if not _actors.is_alive(agent):
			continue
		var p: Dictionary = aim_profile_of(agent)
		var rec_v: Variant = _aim.get(agent)
		var rec: Dictionary = rec_v if typeof(rec_v) == TYPE_DICTIONARY else {"target": EntityIds.NONE, "settle": 0, "swing": 0, "handle": 0, "value": 0}
		var previous: int = rec["target"]
		var target: int = _best_target(agent)
		var settle: int = rec["settle"]
		var swing: int = rec["swing"]
		var settle_ticks: int = p["settle_ticks"]
		if target == EntityIds.NONE:
			# nothing to settle on; a swing in progress stays, so a break never narrows the cone
			settle = 0
		elif target == previous:
			settle = mini(settle + 1, settle_ticks)
			swing = maxi(swing - 1, 0)
		else:
			settle = 0
			swing = p["swing_ticks"]
		rec["target"] = target
		rec["settle"] = settle
		rec["swing"] = swing
		var per: int = p["penalty_per_mdeg"]
		var value: int = -cone_mdeg(p, settle, swing) * per
		var handle: int = rec["handle"]
		var current: int = rec["value"]
		if handle == 0 or value != current:
			if handle != 0:
				var removed: Error = _stats.remove_modifier(handle)
				assert(removed == OK, "the aim modifier exists until this system removes it")
			handle = _stats.add_modifier(agent, {"stat": CombatSystem.STAT_HIT_CHANCE, "class": StatResolver.CLASS_ADD, "value": value, "source": SOURCE, "tags": [TAG_WEAPON] as Array[StringName]})
			assert(handle > 0, "hit_chance and the add class are registered")
			rec["handle"] = handle
			rec["value"] = value
		_aim[agent] = rec


## The visible contact the agent is most aware of; ties go to the lowest id. An
## actor it has no awareness of at all (a squadmate, or a stranger it has not
## noticed) is never a target.
func _best_target(agent: int) -> int:
	var best: int = EntityIds.NONE
	var best_aw: int = 0
	for contact: int in _actors.actor_ids():
		if contact == agent or not _actors.is_alive(contact):
			continue
		var aw: int = _perception.awareness_of(agent, contact)
		if aw > best_aw and _perception.sees(agent, contact):
			best = contact
			best_aw = aw
	return best


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 1 or typeof(state.get("aim")) != TYPE_DICTIONARY:
		return _restore_fail("shape")
	var aim_in: Dictionary = state["aim"]
	var aim: Dictionary = {}
	for key: Variant in aim_in:
		if typeof(key) != TYPE_INT or typeof(aim_in[key]) != TYPE_DICTIONARY:
			return _restore_fail("agent key")
		var agent: int = key
		if not _perception.is_agent(agent):
			return _restore_fail("agent %d is not an agent" % agent)
		var rec: Dictionary = aim_in[key]
		if rec.size() != 5:
			return _restore_fail("agent %d record" % agent)
		for field: String in ["target", "settle", "swing", "handle", "value"]:
			if typeof(rec.get(field)) != TYPE_INT:
				return _restore_fail("agent %d %s" % [agent, field])
		var target: int = rec["target"]
		var settle: int = rec["settle"]
		var swing: int = rec["swing"]
		var handle: int = rec["handle"]
		var value: int = rec["value"]
		if (target != EntityIds.NONE and not _actors.has_actor(target)) or settle < 0 or swing < 0 or handle < 0 or value > 0:
			return _restore_fail("agent %d values" % agent)
		aim[agent] = {"target": target, "settle": settle, "swing": swing, "handle": handle, "value": value}
	_aim = aim
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("AimSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
