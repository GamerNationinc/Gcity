## Standing: heat and notoriety (design doc §7.3; M6 spec claim 11). A standing is
## content (`standing`: how much it falls every 1000 ticks); a rule is content
## (`standing_rule`: standing, event, credit, tags_any, violating, amount) and raises a
## standing on a bus event the way skill xp rules credit xp. A rule naming a right in
## `violating` applies only while the credited actor stands where it lacks that right,
## which is how an alert on a trespasser becomes a witnessed trespass. Values are
## per-actor integers, never negative; zeros are not stored.
class_name StandingSystem extends SimSystem

const SYSTEM_ID: StringName = &"standing"
const KIND_STANDING: StringName = &"standing"
const KIND_RULE: StringName = &"standing_rule"
const DECAY_EVERY: int = 1000

var _content: ContentDb
var _actors: ActorSystem
var _land: LandSystem
var _events: EventBus
## event -> [rule dictionaries, by rule id]
var _rules: Dictionary = {}
## actor -> standing -> int (> 0)
var _standing: Dictionary = {}


func _init(content: ContentDb, actors: ActorSystem, land: LandSystem, events: EventBus) -> void:
	_content = content
	_actors = actors
	_land = land
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func attach(sim: SimRoot) -> Error:
	var err: Error = validate_content()
	if err != OK:
		return err
	err = sim.register_system(self)
	if err != OK:
		return err
	_rules.clear()
	var ids: Array[StringName] = _content.ids(KIND_RULE)
	ids.sort()
	for id: StringName in ids:
		var rule: Dictionary = _content.get_entry(KIND_RULE, id)
		var event_s: String = rule["event"]
		var event: StringName = StringName(event_s)
		if not _rules.has(event):
			_rules[event] = []
			err = _events.subscribe(event, _on_event.bind(event))
			if err != OK:
				return err
		var list: Array = _rules[event]
		list.append(rule)
	return OK


## Rules name a real standing and, when they name one, a real right.
func validate_content() -> Error:
	for id: StringName in _content.ids(KIND_STANDING):
		var t: Dictionary = _content.get_entry(KIND_STANDING, id)
		if typeof(t.get("decay_per_1000_ticks")) != TYPE_INT:
			return _content_fail("standing/%s needs an integer decay_per_1000_ticks" % id)
		var decay: int = t["decay_per_1000_ticks"]
		if decay < 0:
			return _content_fail("standing/%s decays by a negative amount" % id)
	for id: StringName in _content.ids(KIND_RULE):
		var r: Dictionary = _content.get_entry(KIND_RULE, id)
		for key: String in ["standing", "event", "credit", "violating"]:
			if typeof(r.get(key)) != TYPE_STRING:
				return _content_fail("standing_rule/%s needs a string %s" % [id, key])
		if typeof(r.get("amount")) != TYPE_INT or typeof(r.get("tags_any")) != TYPE_ARRAY:
			return _content_fail("standing_rule/%s needs an integer amount and a tags_any list" % id)
		var standing: String = r["standing"]
		var violating: String = r["violating"]
		var amount: int = r["amount"]
		if not _content.has(KIND_STANDING, StringName(standing)):
			return _content_fail("standing_rule/%s names unknown standing '%s'" % [id, standing])
		if not violating.is_empty() and not LandSystem.RIGHTS.has(StringName(violating)):
			return _content_fail("standing_rule/%s names unknown right '%s'" % [id, violating])
		if amount < 1:
			return _content_fail("standing_rule/%s raises by less than 1" % id)
	return OK


func _content_fail(reason: String) -> Error:
	push_error("StandingSystem: content rejected: %s" % reason)
	return ERR_INVALID_DATA


# ---------------------------------------------------------------- tick and events

## Every 1000th tick each stored standing falls by its rate, to no lower than zero.
func tick(sim: SimRoot) -> void:
	if sim.get_tick() % DECAY_EVERY != 0:
		return
	var actors: Array = _standing.keys()
	actors.sort()
	for a: Variant in actors:
		var per: Dictionary = _standing[a]
		var names: Array = per.keys()
		names.sort()
		for n: Variant in names:
			var standing: StringName = n
			var t: Dictionary = _content.get_entry(KIND_STANDING, standing)
			var decay: int = t["decay_per_1000_ticks"]
			var value: int = per[standing]
			value -= decay
			if value > 0:
				per[standing] = value
			else:
				per.erase(standing)
		if per.is_empty():
			_standing.erase(a)


func _on_event(payload: Dictionary, event: StringName) -> void:
	var list: Array = _rules.get(event, [])
	var payload_tags: Array[String] = []
	var tags_v: Variant = payload.get("tags", [])
	if typeof(tags_v) == TYPE_ARRAY:
		var arr: Array = tags_v
		for t: Variant in arr:
			if typeof(t) == TYPE_STRING or typeof(t) == TYPE_STRING_NAME:
				var tag: String = t
				payload_tags.append(tag)
	for entry: Variant in list:
		var rule: Dictionary = entry
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
				var want: String = w
				if payload_tags.has(want):
					matched = true
					break
			if not matched:
				continue
		var violating: String = rule["violating"]
		if not violating.is_empty():
			var rights: Dictionary = _land.rights_at(_actors.position_of(actor), actor)
			var held: bool = rights[StringName(violating)]
			if held:
				continue
		var standing_s: String = rule["standing"]
		var amount: int = rule["amount"]
		_raise(actor, StringName(standing_s), amount)


func _raise(actor: int, standing: StringName, amount: int) -> void:
	if not _standing.has(actor):
		_standing[actor] = {}
	var per: Dictionary = _standing[actor]
	var value: int = per.get(standing, 0)
	per[standing] = value + amount


# ---------------------------------------------------------------- queries

## An actor's standing; 0 for none, an unknown actor or an unknown standing.
func standing_of(actor: int, standing: StringName) -> int:
	if not _standing.has(actor):
		return 0
	var per: Dictionary = _standing[actor]
	return per.get(standing, 0)


# ---------------------------------------------------------------- state

func snapshot() -> Dictionary:
	return {"standing": _standing.duplicate(true)}


func restore(state: Dictionary) -> Error:
	if state.size() != 1 or typeof(state.get("standing")) != TYPE_DICTIONARY:
		return _restore_fail("shape")
	var src: Dictionary = state["standing"]
	var out: Dictionary = {}
	for k: Variant in src:
		if typeof(k) != TYPE_INT or typeof(src[k]) != TYPE_DICTIONARY:
			return _restore_fail("actor key")
		var actor: int = k
		if not _actors.has_actor(actor):
			return _restore_fail("actor %d does not exist" % actor)
		var per_in: Dictionary = src[k]
		if per_in.is_empty():
			return _restore_fail("actor %d has an empty record" % actor)
		var per: Dictionary = {}
		for n: Variant in per_in:
			if typeof(n) != TYPE_STRING and typeof(n) != TYPE_STRING_NAME:
				return _restore_fail("standing key")
			var name_s: String = n
			var standing: StringName = StringName(name_s)
			if typeof(per_in[n]) != TYPE_INT or not _content.has(KIND_STANDING, standing):
				return _restore_fail("standing '%s'" % name_s)
			var value: int = per_in[n]
			if value <= 0:
				return _restore_fail("standing '%s' of actor %d is not positive" % [name_s, actor])
			per[standing] = value
		out[actor] = per
	_standing = out
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("StandingSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
