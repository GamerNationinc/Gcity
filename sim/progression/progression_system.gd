## Skills and perks, event-coupled (design doc §10.1, §10.3; M1 spec claims 13–14).
##
## Gameplay systems emit events and know nothing about progression. This system
## subscribes to the events named in `content/skill/*.json`, credits xp to the actor
## the event names, raises levels at the skill's thresholds and grants points. A perk
## (`content/perk/*.json`) is prerequisites, a cost and modifiers; `perk.unlock` turns
## its numbers into resolver modifiers on the actor, tagged so they reach wielded
## items. There is no perk-hook category: a perk that needs behaviour does not exist yet.
class_name ProgressionSystem extends SimSystem

const SYSTEM_ID: StringName = &"progression"
const KIND_SKILL: StringName = &"skill"
const KIND_PERK: StringName = &"perk"
const COMMAND_UNLOCK: StringName = &"perk.unlock"
const MAX_PREREQ_DEPTH: int = 32

var _content: ContentDb
var _stats: StatResolver
var _actors: ActorSystem
var _events: EventBus
## actor -> skill id -> {"xp": int, "level": int, "points": int}
var _skills: Dictionary = {}
## actor -> perk id -> Array[int] resolver handles
var _perks: Dictionary = {}
## event name -> Array of [skill id, rule dictionary]
var _rules: Dictionary = {}


func _init(content: ContentDb, stats: StatResolver, actors: ActorSystem, events: EventBus) -> void:
	_content = content
	_stats = stats
	_actors = actors
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


func snapshot() -> Dictionary:
	return {"skills": _skills.duplicate(true), "perks": _perks.duplicate(true)}


func attach(sim: SimRoot) -> Error:
	var err: Error = validate_content()
	if err != OK:
		return err
	err = sim.register_system(self)
	if err != OK:
		return err
	err = _events.subscribe(ActorSystem.EVENT_REMOVED, _on_removed)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_UNLOCK, _on_unlock)
	if err != OK:
		return err
	_rules.clear()
	for skill: StringName in _content.ids(KIND_SKILL):
		var t: Dictionary = _content.get_entry(KIND_SKILL, skill)
		var xp_rules: Array = t["xp"]
		for r: Variant in xp_rules:
			var rule: Dictionary = r
			var event_s: String = rule["event"]
			var event: StringName = StringName(event_s)
			if not _rules.has(event):
				_rules[event] = []
				err = _events.subscribe(event, _on_event.bind(event))
				if err != OK:
					return err
			var list: Array = _rules[event]
			list.append([skill, rule])
	return OK


## Thresholds start at 0 and strictly increase; perks name real skills, stats, classes
## and perks; prerequisites form no cycle.
func validate_content() -> Error:
	for skill: StringName in _content.ids(KIND_SKILL):
		var t: Dictionary = _content.get_entry(KIND_SKILL, skill)
		var levels: Array = t["levels"]
		var previous: int = -1
		for i: int in range(levels.size()):
			var threshold: int = levels[i]
			if (i == 0 and threshold != 0) or threshold <= previous:
				return _fail("skill/%s levels must start at 0 and strictly increase" % skill)
			previous = threshold
	for perk: StringName in _content.ids(KIND_PERK):
		var t: Dictionary = _content.get_entry(KIND_PERK, perk)
		var mods: Array = t["modifiers"]
		for m: Variant in mods:
			var md: Dictionary = m
			var cls_s: String = md["class"]
			var stat_s: String = md["stat"]
			if not _stats.class_ids().has(StringName(cls_s)):
				return _fail("perk/%s uses unregistered modifier class '%s'" % [perk, cls_s])
			if not _stats.has_stat(StringName(stat_s)):
				return _fail("perk/%s modifies unregistered stat '%s'" % [perk, stat_s])
		var seen: Array[StringName] = [perk]
		var frontier: Array[StringName] = _prereq_perks(perk)
		var depth: int = 0
		while not frontier.is_empty():
			depth += 1
			if depth > MAX_PREREQ_DEPTH:
				return _fail("perk/%s prerequisite chain too deep" % perk)
			var next: Array[StringName] = []
			for p: StringName in frontier:
				if p == perk:
					return _fail("perk/%s is its own prerequisite (cycle)" % perk)
				if seen.has(p):
					continue
				seen.append(p)
				next.append_array(_prereq_perks(p))
			frontier = next
	return OK


func _fail(reason: String) -> Error:
	push_error("ProgressionSystem: content rejected: %s" % reason)
	return ERR_INVALID_DATA


# ---------------------------------------------------------------- queries

func skill_ids() -> Array[StringName]:
	return _content.ids(KIND_SKILL)


func perk_ids() -> Array[StringName]:
	return _content.ids(KIND_PERK)


func xp_of(actor: int, skill: StringName) -> int:
	var rec: Dictionary = _record(actor, skill)
	return rec.get("xp", 0)


func level_of(actor: int, skill: StringName) -> int:
	var rec: Dictionary = _record(actor, skill)
	return rec.get("level", 0)


func points_of(actor: int, skill: StringName) -> int:
	var rec: Dictionary = _record(actor, skill)
	return rec.get("points", 0)


func has_perk(actor: int, perk: StringName) -> bool:
	var per_actor: Variant = _perks.get(actor)
	if typeof(per_actor) != TYPE_DICTIONARY:
		return false
	var dict: Dictionary = per_actor
	return dict.has(perk)


func perks_of(actor: int) -> Array[StringName]:
	var out: Array[StringName] = []
	var per_actor: Variant = _perks.get(actor)
	if typeof(per_actor) != TYPE_DICTIONARY:
		return out
	var dict: Dictionary = per_actor
	for key: Variant in dict:
		var id: StringName = key
		out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## Xp needed for the next level, or -1 at the top level.
func next_level_xp(actor: int, skill: StringName) -> int:
	if not _content.has(KIND_SKILL, skill):
		return -1
	var t: Dictionary = _content.get_entry(KIND_SKILL, skill)
	var levels: Array = t["levels"]
	var level: int = level_of(actor, skill)
	if level + 1 >= levels.size():
		return -1
	return levels[level + 1]


## Why an unlock would be refused right now, or "" if it would succeed. For HUDs.
func unlock_blocker(actor: int, perk: StringName) -> String:
	if not _content.has(KIND_PERK, perk):
		return "no such perk"
	if not _actors.is_alive(actor):
		return "actor not alive"
	if has_perk(actor, perk):
		return "already unlocked"
	var t: Dictionary = _content.get_entry(KIND_PERK, perk)
	var skill_s: String = t["skill"]
	var skill: StringName = StringName(skill_s)
	var prereq: Dictionary = t["prerequisites"]
	var level_needed: int = prereq["level"]
	if level_of(actor, skill) < level_needed:
		return "needs %s level %d" % [skill, level_needed]
	for p: StringName in _prereq_perks(perk):
		if not has_perk(actor, p):
			return "needs perk %s" % p
	var cost: int = t["cost"]
	if points_of(actor, skill) < cost:
		return "needs %d point(s)" % cost
	return ""


# ---------------------------------------------------------------- events

func _on_event(payload: Dictionary, event: StringName) -> void:
	var list: Array = _rules.get(event, [])
	var payload_tags: Array[String] = []
	var tags_v: Variant = payload.get("tags", [])
	if typeof(tags_v) == TYPE_ARRAY:
		var arr: Array = tags_v
		for t: Variant in arr:
			if typeof(t) == TYPE_STRING:
				payload_tags.append(t)
	for entry: Variant in list:
		var pair: Array = entry
		var skill: StringName = pair[0]
		var rule: Dictionary = pair[1]
		var credit_s: String = rule["credit"]
		var actor_v: Variant = payload.get(credit_s)
		if typeof(actor_v) != TYPE_INT:
			continue
		var actor: int = actor_v
		if not _actors.has_actor(actor):
			continue
		var wanted: Array = rule["tags_any"]
		if not wanted.is_empty():
			var matched: bool = false
			for w: Variant in wanted:
				if payload_tags.has(w):
					matched = true
					break
			if not matched:
				continue
		var amount: int = rule["amount"]
		_credit(actor, skill, amount)


func _credit(actor: int, skill: StringName, amount: int) -> void:
	if not _skills.has(actor):
		_skills[actor] = {}
	var per_actor: Dictionary = _skills[actor]
	if not per_actor.has(skill):
		per_actor[skill] = {"xp": 0, "level": 0, "points": 0}
	var rec: Dictionary = per_actor[skill]
	var xp: int = rec["xp"]
	xp += amount
	rec["xp"] = xp
	var t: Dictionary = _content.get_entry(KIND_SKILL, skill)
	var levels: Array = t["levels"]
	var per_level: int = t["points_per_level"]
	var level: int = rec["level"]
	while level + 1 < levels.size():
		var threshold: int = levels[level + 1]
		if xp < threshold:
			break
		level += 1
		var points: int = rec["points"]
		rec["points"] = points + per_level
	rec["level"] = level


# ---------------------------------------------------------------- command

## {"actor": int, "perk": name}: spend points on a perk whose prerequisites are met.
func _on_unlock(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT:
		return false
	var perk_v: Variant = payload.get("perk")
	var perk: StringName = &""
	match typeof(perk_v):
		TYPE_STRING:
			var s: String = perk_v
			perk = StringName(s)
		TYPE_STRING_NAME:
			perk = perk_v
		_:
			return false
	var actor: int = payload["actor"]
	if not unlock_blocker(actor, perk).is_empty():
		return false
	var t: Dictionary = _content.get_entry(KIND_PERK, perk)
	var skill_s: String = t["skill"]
	var skill: StringName = StringName(skill_s)
	var cost: int = t["cost"]
	var rec: Dictionary = _record(actor, skill)
	if rec.is_empty():
		if not _skills.has(actor):
			_skills[actor] = {}
		var per_actor: Dictionary = _skills[actor]
		per_actor[skill] = {"xp": 0, "level": 0, "points": 0}
		rec = per_actor[skill]
	var points: int = rec["points"]
	rec["points"] = points - cost
	var tags: Array[StringName] = []
	var tags_in: Array = t["tags"]
	for tg: Variant in tags_in:
		var tag_s: String = tg
		tags.append(StringName(tag_s))
	var handles: Array[int] = []
	var mods: Array = t["modifiers"]
	for m: Variant in mods:
		var md: Dictionary = m
		var stat_s: String = md["stat"]
		var cls_s: String = md["class"]
		var value: int = md["value"]
		var handle: int = _stats.add_modifier(actor, {"stat": StringName(stat_s), "class": StringName(cls_s), "value": value,
			"source": StringName("perk.%s" % perk), "tags": tags})
		assert(handle >= 1, "content was validated; modifier must be accepted")
		handles.append(handle)
	if not _perks.has(actor):
		_perks[actor] = {}
	var per_actor_perks: Dictionary = _perks[actor]
	per_actor_perks[perk] = handles
	return true


## A removed actor's skills go with it, and its perks' modifiers are released before
## the actor is forgotten by the resolver (M7 spec claim 12).
func _on_removed(payload: Dictionary) -> void:
	var actor: int = payload["actor"]
	_skills.erase(actor)
	if not _perks.has(actor):
		return
	var per_actor: Dictionary = _perks[actor]
	for perk: Variant in per_actor:
		var handles: Array = per_actor[perk]
		for v: Variant in handles:
			var handle: int = v
			var removed: Error = _stats.remove_modifier(handle)
			assert(removed == OK, "a perk's modifier is live until its actor goes")
	_perks.erase(actor)


# ---------------------------------------------------------------- restore

## Untrusted input. Perk handles must be live modifiers on the resolver (restore the
## resolver first); skills must exist; xp/level/points must be consistent with content.
func restore(state: Dictionary) -> Error:
	if state.size() != 2 or typeof(state.get("skills")) != TYPE_DICTIONARY or typeof(state.get("perks")) != TYPE_DICTIONARY:
		return _restore_fail("shape")
	var skills_in: Dictionary = state["skills"]
	var new_skills: Dictionary = {}
	for ak: Variant in skills_in:
		if typeof(ak) != TYPE_INT or typeof(skills_in[ak]) != TYPE_DICTIONARY:
			return _restore_fail("skills actor key")
		var per: Dictionary = skills_in[ak]
		var out: Dictionary = {}
		for sk: Variant in per:
			var skill: StringName = _as_name(sk)
			if not _content.has(KIND_SKILL, skill) or typeof(per[sk]) != TYPE_DICTIONARY:
				return _restore_fail("actor %d skill %s" % [ak, skill])
			var rec: Dictionary = per[sk]
			if rec.size() != 3 or typeof(rec.get("xp")) != TYPE_INT or typeof(rec.get("level")) != TYPE_INT or typeof(rec.get("points")) != TYPE_INT:
				return _restore_fail("actor %d skill %s record" % [ak, skill])
			var xp: int = rec["xp"]
			var level: int = rec["level"]
			var points: int = rec["points"]
			var t: Dictionary = _content.get_entry(KIND_SKILL, skill)
			var levels: Array = t["levels"]
			if xp < 0 or points < 0 or level < 0 or level >= levels.size() or xp < levels[level] or (level + 1 < levels.size() and xp >= levels[level + 1]):
				return _restore_fail("actor %d skill %s values" % [ak, skill])
			out[skill] = {"xp": xp, "level": level, "points": points}
		new_skills[ak] = out
	var perks_in: Dictionary = state["perks"]
	var new_perks: Dictionary = {}
	for ak: Variant in perks_in:
		if typeof(ak) != TYPE_INT or typeof(perks_in[ak]) != TYPE_DICTIONARY:
			return _restore_fail("perks actor key")
		var per: Dictionary = perks_in[ak]
		var out: Dictionary = {}
		for pk: Variant in per:
			var perk: StringName = _as_name(pk)
			if not _content.has(KIND_PERK, perk) or typeof(per[pk]) != TYPE_ARRAY:
				return _restore_fail("actor %d perk %s" % [ak, perk])
			var arr: Array = per[pk]
			var t: Dictionary = _content.get_entry(KIND_PERK, perk)
			var mods: Array = t["modifiers"]
			if arr.size() != mods.size():
				return _restore_fail("actor %d perk %s handle count" % [ak, perk])
			var handles: Array[int] = []
			for h: Variant in arr:
				if typeof(h) != TYPE_INT:
					return _restore_fail("actor %d perk %s handle" % [ak, perk])
				var handle: int = h
				if not _stats.has_modifier(handle):
					return _restore_fail("actor %d perk %s handle %d is not a live modifier" % [ak, perk, handle])
				handles.append(handle)
			out[perk] = handles
		new_perks[ak] = out
	_skills = new_skills
	_perks = new_perks
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("ProgressionSystem.restore: rejected snapshot: %s" % reason)
	return ERR_INVALID_DATA


# ---------------------------------------------------------------- internals

func _record(actor: int, skill: StringName) -> Dictionary:
	var per_actor: Variant = _skills.get(actor)
	if typeof(per_actor) != TYPE_DICTIONARY:
		return {}
	var dict: Dictionary = per_actor
	var rec: Variant = dict.get(skill)
	if typeof(rec) != TYPE_DICTIONARY:
		return {}
	return rec


func _prereq_perks(perk: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	if not _content.has(KIND_PERK, perk):
		return out
	var t: Dictionary = _content.get_entry(KIND_PERK, perk)
	var prereq: Dictionary = t["prerequisites"]
	var list: Array = prereq["perks"]
	for p: Variant in list:
		var s: String = p
		out.append(StringName(s))
	return out


static func _as_name(v: Variant) -> StringName:
	match typeof(v):
		TYPE_STRING_NAME:
			return v
		TYPE_STRING:
			var s: String = v
			return StringName(s)
		_:
			return &""
