## Player standing (design doc §7.3; M6 spec claim 11): per-actor scalars (heat,
## notoriety, and later visible wealth), one `content/standing_scalar/` file each with
## its decay per tick and its max, raised by `content/standing_rule/` rules on bus
## events exactly as a skill's xp rules are: the event, the payload field naming the
## actor credited, optional `tags_any`, the scalar, the amount. Milli-units.
##
## Heat cools every tick by its decay; a scalar with no decay keeps its value. Nothing
## here decides what a scalar means: at M6 the readers are a lock's `heat_max`, the
## contract payout and the HUD; the threat director that weighs them is M8.
class_name StandingSystem extends SimSystem

const SYSTEM_ID: StringName = &"standing"
const KIND_SCALAR: StringName = &"standing_scalar"
const KIND_RULE: StringName = &"standing_rule"

var _content: ContentDb
var _actors: ActorSystem
var _events: EventBus
## event -> [rule id, ...], in content order
var _rules: Dictionary = {}
## actor -> scalar -> int, only non-zero values
var _standing: Dictionary = {}


func _init(content: ContentDb, actors: ActorSystem, events: EventBus) -> void:
	_content = content
	_actors = actors
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func snapshot() -> Dictionary:
	return {"standing": _standing.duplicate(true)}


func attach(sim: SimRoot) -> Error:
	var err: Error = validate_content()
	if err != OK:
		return err
	err = sim.register_system(self)
	if err != OK:
		return err
	_rules.clear()
	for rule: StringName in _content.ids(KIND_RULE):
		var t: Dictionary = _content.get_entry(KIND_RULE, rule)
		var event_s: String = t["event"]
		var event: StringName = StringName(event_s)
		if not _rules.has(event):
			_rules[event] = [] as Array[StringName]
			err = _events.subscribe(event, _on_event.bind(event))
			if err != OK:
				return err
		var list: Array[StringName] = _rules[event]
		list.append(rule)
	return OK


## Every rule names a scalar that exists (the build-time validator checks the
## reference; assembly checks it again for content that bypassed it).
func validate_content() -> Error:
	for rule: StringName in _content.ids(KIND_RULE):
		var t: Dictionary = _content.get_entry(KIND_RULE, rule)
		var scalar_s: String = t["scalar"]
		if not _content.has(KIND_SCALAR, StringName(scalar_s)):
			push_error("StandingSystem: standing_rule/%s names no standing_scalar/%s" % [rule, scalar_s])
			return ERR_INVALID_DATA
	return OK


# ---------------------------------------------------------------- queries

## An actor's value of a scalar; 0 for anyone or anything unknown.
func value_of(actor: int, scalar: StringName) -> int:
	var table_v: Variant = _standing.get(actor)
	if typeof(table_v) != TYPE_DICTIONARY:
		return 0
	var table: Dictionary = table_v
	return table.get(String(scalar), 0)


# ---------------------------------------------------------------- raising

## Adds `amount` of a scalar to an actor, stopping at the scalar's max. False, changing
## nothing, for an unknown actor or scalar or a non-positive amount. Rules call this;
## so will a contract's payout.
func raise(actor: int, scalar: StringName, amount: int) -> bool:
	if amount <= 0 or not _actors.has_actor(actor) or not _content.has(KIND_SCALAR, scalar):
		return false
	var t: Dictionary = _content.get_entry(KIND_SCALAR, scalar)
	var cap: int = t["max"]
	var table_v: Variant = _standing.get(actor)
	var table: Dictionary = table_v if typeof(table_v) == TYPE_DICTIONARY else {}
	var now: int = table.get(String(scalar), 0)
	table[String(scalar)] = mini(cap, now + amount)
	_standing[actor] = table
	return true


func _on_event(payload: Dictionary, event: StringName) -> void:
	var list: Array[StringName] = _rules.get(event, [] as Array[StringName])
	var payload_tags: Array[String] = []
	var tags_v: Variant = payload.get("tags", [])
	if typeof(tags_v) == TYPE_ARRAY:
		var arr: Array = tags_v
		for tag: Variant in arr:
			if typeof(tag) == TYPE_STRING or typeof(tag) == TYPE_STRING_NAME:
				payload_tags.append(str(tag))
	for rule: StringName in list:
		var t: Dictionary = _content.get_entry(KIND_RULE, rule)
		var credit_s: String = t["credit"]
		var actor_v: Variant = payload.get(credit_s)
		if typeof(actor_v) != TYPE_INT:
			continue
		var tags_any: Array = t["tags_any"]
		if not tags_any.is_empty():
			var matched: bool = false
			for tag: Variant in tags_any:
				var tag_s: String = tag
				if payload_tags.has(tag_s):
					matched = true
			if not matched:
				continue
		var actor: int = actor_v
		var scalar_s: String = t["scalar"]
		var amount: int = t["amount"]
		raise(actor, StringName(scalar_s), amount)


# ---------------------------------------------------------------- the tick

## Every value cools by its scalar's decay, never below zero; a value that reaches
## zero leaves no record.
func tick(_sim: SimRoot) -> void:
	for actor_v: Variant in _standing.keys():
		var table: Dictionary = _standing[actor_v]
		for scalar_v: Variant in table.keys():
			var scalar_s: String = scalar_v
			var t: Dictionary = _content.get_entry(KIND_SCALAR, StringName(scalar_s))
			var decay: int = t["decay_per_tick"]
			if decay == 0:
				continue
			var now: int = table[scalar_v]
			if now <= decay:
				table.erase(scalar_v)
			else:
				table[scalar_v] = now - decay
		if table.is_empty():
			_standing.erase(actor_v)


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 1 or typeof(state.get("standing")) != TYPE_DICTIONARY:
		return _restore_fail("shape")
	var in_all: Dictionary = state["standing"]
	var out: Dictionary = {}
	for key: Variant in in_all:
		if typeof(key) != TYPE_INT or typeof(in_all[key]) != TYPE_DICTIONARY:
			return _restore_fail("actor key")
		var actor: int = key
		if not _actors.has_actor(actor):
			return _restore_fail("actor %d is not an actor" % actor)
		var table_in: Dictionary = in_all[key]
		var table: Dictionary = {}
		for sk: Variant in table_in:
			if typeof(sk) != TYPE_STRING and typeof(sk) != TYPE_STRING_NAME:
				return _restore_fail("scalar key")
			var scalar: StringName = StringName(str(sk))
			if not _content.has(KIND_SCALAR, scalar) or typeof(table_in[sk]) != TYPE_INT:
				return _restore_fail("scalar %s" % scalar)
			var t: Dictionary = _content.get_entry(KIND_SCALAR, scalar)
			var cap: int = t["max"]
			var value: int = table_in[sk]
			if value < 1 or value > cap:
				return _restore_fail("scalar %s value" % scalar)
			table[String(scalar)] = value
		if table.is_empty():
			return _restore_fail("actor %d has an empty record" % actor)
		out[actor] = table
	_standing = out
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("StandingSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
