## Stress and morale (design doc §14.3; M4 spec claim 8). Per-agent integer stress in
## [0, STRESS_MAX] rises when the agent is fired at (a `combat.fire` at it, or one
## whose line passes within its profile's `near_miss_mm`), when it is hit, and when
## a squadmate goes down; it decays every tick. Stress degrades aim as one `stress`
## modifier on `hit_chance` tagged `weapon` (design doc §10.2), and the profile's
## thresholds tell the stance scorer when the agent prefers to retreat (broken) or
## may only retreat or surrender (routed). Suppression that changes behaviour is
## readable across the room; suppression that only changes accuracy is not.
class_name StressSystem extends SimSystem

const SYSTEM_ID: StringName = &"stress"
const KIND_STRESS: StringName = &"stress_profile"
const SOURCE: StringName = &"stress"
const TAG_WEAPON: StringName = &"weapon"
const STRESS_MAX: int = 1_000_000

var _content: ContentDb
var _stats: StatResolver
var _actors: ActorSystem
var _perception: PerceptionSystem
var _events: EventBus
## agent -> {"stress": int, "handle": int, "value": int}
var _stress: Dictionary = {}


func _init(content: ContentDb, stats: StatResolver, actors: ActorSystem, perception: PerceptionSystem, events: EventBus) -> void:
	_content = content
	_stats = stats
	_actors = actors
	_perception = perception
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func snapshot() -> Dictionary:
	return {"stress": _stress.duplicate(true)}


func attach(sim: SimRoot) -> Error:
	var err: Error = validate_content()
	if err != OK:
		return err
	err = sim.register_system(self)
	if err != OK:
		return err
	err = _events.subscribe(CombatSystem.EVENT_FIRE, _on_fire)
	if err != OK:
		return err
	err = _events.subscribe(CombatSystem.EVENT_HIT, _on_hit)
	if err != OK:
		return err
	return _events.subscribe(ActorSystem.EVENT_REMOVED, _on_removed)


func _on_removed(payload: Dictionary) -> void:
	var actor: int = payload["actor"]
	if not _stress.has(actor):
		return
	var rec: Dictionary = _stress[actor]
	var handle: int = rec["handle"]
	if handle != 0:
		var removed: Error = _stats.remove_modifier(handle)
		assert(removed == OK, "the stress modifier is live until the agent goes")
	_stress.erase(actor)


## Every agent profile binds a stress profile that exists.
func validate_content() -> Error:
	for id: StringName in _content.ids(PerceptionSystem.KIND_AGENT):
		var t: Dictionary = _content.get_entry(PerceptionSystem.KIND_AGENT, id)
		if typeof(t.get("stress_profile")) != TYPE_STRING:
			push_error("StressSystem: agent_profile/%s has no stress_profile" % id)
			return ERR_INVALID_DATA
		var stress_s: String = t["stress_profile"]
		if not _content.has(KIND_STRESS, StringName(stress_s)):
			push_error("StressSystem: agent_profile/%s: no stress_profile/%s" % [id, stress_s])
			return ERR_INVALID_DATA
	return OK


# ---------------------------------------------------------------- queries

## The stress profile entry of an agent, or an empty dictionary.
func stress_profile_of(agent: int) -> Dictionary:
	var profile: StringName = _perception.profile_of(agent)
	if profile.is_empty():
		return {}
	var t: Dictionary = _content.get_entry(PerceptionSystem.KIND_AGENT, profile)
	var stress_s: String = t["stress_profile"]
	return _content.get_entry(KIND_STRESS, StringName(stress_s))


func stress_of(agent: int) -> int:
	var rec: Dictionary = _record(agent)
	if rec.is_empty():
		return 0
	return rec["stress"]


## Above the break threshold: the agent prefers to retreat.
func is_broken(agent: int) -> bool:
	var p: Dictionary = stress_profile_of(agent)
	if p.is_empty():
		return false
	var threshold: int = p["break_threshold"]
	return stress_of(agent) >= threshold


## Above the rout threshold: the agent may only retreat or surrender.
func is_routed(agent: int) -> bool:
	var p: Dictionary = stress_profile_of(agent)
	if p.is_empty():
		return false
	var threshold: int = p["rout_threshold"]
	return stress_of(agent) >= threshold


## The hit_chance penalty (basis points of a percent) the agent's stress imposes.
func penalty_of(agent: int) -> int:
	var p: Dictionary = stress_profile_of(agent)
	if p.is_empty():
		return 0
	return penalty(p, stress_of(agent))


static func penalty(p: Dictionary, stress: int) -> int:
	var at_max: int = p["hit_penalty_at_max"]
	return clampi(stress, 0, STRESS_MAX) * at_max / STRESS_MAX


func _record(agent: int) -> Dictionary:
	var stored: Variant = _stress.get(agent)
	if typeof(stored) != TYPE_DICTIONARY:
		return {}
	return stored


## Millimetres from `p` to the segment a–b, in integers (the closest point is found by
## projecting onto the segment with one division, then measured).
static func distance_to_segment_mm(p: Vector3i, a: Vector3i, b: Vector3i) -> int:
	var ab: Vector3i = b - a
	var ap: Vector3i = p - a
	var ab2: int = ab.x * ab.x + ab.y * ab.y + ab.z * ab.z
	if ab2 == 0:
		return PerceptionSystem.distance_mm(p, a)
	var dot: int = ap.x * ab.x + ap.y * ab.y + ap.z * ab.z
	var t: int = clampi(dot, 0, ab2)
	var closest: Vector3i = a + Vector3i(ab.x * t / ab2, ab.y * t / ab2, ab.z * t / ab2)
	return PerceptionSystem.distance_mm(p, closest)


# ---------------------------------------------------------------- events

## Fired at: the shot's target, or any agent the shot's line passes close to, gains
## `gain_fired_at`. The shooter's own squad is not stressed by its fire.
func _on_fire(payload: Dictionary) -> void:
	var shooter: int = payload["shooter"]
	var target: int = payload["target"]
	if not _actors.has_actor(shooter) or not _actors.has_actor(target):
		return
	var a: Vector3i = _actors.position_of(shooter)
	var b: Vector3i = _actors.position_of(target)
	for agent: int in _perception.agent_ids():
		if agent == shooter or not _actors.is_alive(agent) or _same_squad(agent, shooter):
			continue
		var p: Dictionary = stress_profile_of(agent)
		var near: int = p["near_miss_mm"]
		if agent == target or distance_to_segment_mm(_actors.position_of(agent), a, b) <= near:
			var gain: int = p["gain_fired_at"]
			_add(agent, gain)


## Hit: the target gains `gain_hit`; if it went down, its squadmates gain
## `gain_squadmate_down`.
func _on_hit(payload: Dictionary) -> void:
	var target: int = payload["target"]
	var killed: bool = payload["killed"]
	if _perception.is_agent(target):
		var p: Dictionary = stress_profile_of(target)
		var gain: int = p["gain_hit"]
		_add(target, gain)
	if not killed or not _perception.is_agent(target):
		return
	var squad: int = _perception.squad_of(target)
	if squad == 0:
		return
	for agent: int in _perception.agent_ids():
		if agent == target or not _actors.is_alive(agent) or _perception.squad_of(agent) != squad:
			continue
		var p: Dictionary = stress_profile_of(agent)
		var gain: int = p["gain_squadmate_down"]
		_add(agent, gain)


func _same_squad(a: int, b: int) -> bool:
	if not _perception.is_agent(a) or not _perception.is_agent(b):
		return false
	var squad: int = _perception.squad_of(a)
	return squad > 0 and squad == _perception.squad_of(b)


func _add(agent: int, gain: int) -> void:
	var rec: Dictionary = _record(agent)
	if rec.is_empty():
		rec = {"stress": 0, "handle": 0, "value": 0}
	var stress: int = rec["stress"]
	rec["stress"] = mini(stress + gain, STRESS_MAX)
	_stress[agent] = rec


# ---------------------------------------------------------------- the tick

func tick(_sim: SimRoot) -> void:
	for agent: int in _perception.agent_ids():
		if not _actors.is_alive(agent):
			continue
		var p: Dictionary = stress_profile_of(agent)
		var rec: Dictionary = _record(agent)
		if rec.is_empty():
			rec = {"stress": 0, "handle": 0, "value": 0}
		var stress: int = rec["stress"]
		var decay: int = p["decay_per_tick"]
		stress = maxi(stress - decay, 0)
		rec["stress"] = stress
		var value: int = -penalty(p, stress)
		var handle: int = rec["handle"]
		var current: int = rec["value"]
		if handle == 0 or value != current:
			if handle != 0:
				var removed: Error = _stats.remove_modifier(handle)
				assert(removed == OK, "the stress modifier exists until this system removes it")
			handle = _stats.add_modifier(agent, {"stat": CombatSystem.STAT_HIT_CHANCE, "class": StatResolver.CLASS_ADD, "value": value, "source": SOURCE, "tags": [TAG_WEAPON] as Array[StringName]})
			assert(handle > 0, "hit_chance and the add class are registered")
			rec["handle"] = handle
			rec["value"] = value
		_stress[agent] = rec


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 1 or typeof(state.get("stress")) != TYPE_DICTIONARY:
		return _restore_fail("shape")
	var stress_in: Dictionary = state["stress"]
	var stress: Dictionary = {}
	for key: Variant in stress_in:
		if typeof(key) != TYPE_INT or typeof(stress_in[key]) != TYPE_DICTIONARY:
			return _restore_fail("agent key")
		var agent: int = key
		if not _perception.is_agent(agent):
			return _restore_fail("agent %d is not an agent" % agent)
		var rec: Dictionary = stress_in[key]
		if rec.size() != 3 or typeof(rec.get("stress")) != TYPE_INT or typeof(rec.get("handle")) != TYPE_INT or typeof(rec.get("value")) != TYPE_INT:
			return _restore_fail("agent %d record" % agent)
		var level: int = rec["stress"]
		var handle: int = rec["handle"]
		var value: int = rec["value"]
		if level < 0 or level > STRESS_MAX or handle < 0 or value > 0:
			return _restore_fail("agent %d values" % agent)
		stress[agent] = {"stress": level, "handle": handle, "value": value}
	_stress = stress
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("StressSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
