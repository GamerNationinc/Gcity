## Three standing scalars, not one wanted level (design doc §7.3; M6 spec claim 8).
## `heat` is the attention the law is paying you now, `notoriety` is what the city
## remembers, and `visible_wealth` is what you look worth to whoever is watching.
##
## Each scalar is a file in `content/standing_rule/` whose id is the scalar's name.
## An event-raised scalar is credited by bus events exactly as `skill` xp is — an
## event, the payload key naming the actor to credit, a tag filter, a condition and an
## amount — and decays every `period_ticks` at a rate the actor's district scales. A
## derived scalar is not credited at all: it is recomputed from the world on the same
## clock, which is how visible wealth falls the moment the kit is put down.
##
## Nothing reads these yet but the device and the payout. The threat director, raids
## and suspicion are M8.
class_name StandingSystem extends SimSystem

const SYSTEM_ID: StringName = &"standing"
const KIND_RULE: StringName = &"standing_rule"
const KIND_DISTRICT: StringName = &"district"
## The stat every item's worth is resolved through.
const STAT_VALUE: StringName = &"value"
## A district index is 0..1000, and scales a decay by that fraction.
const INDEX_ONE: int = 1000
const SOURCE_EVENTS: String = "events"
const SOURCE_CARRIED: String = "carried_value"
const WHEN_ALWAYS: StringName = &"always"
const WHEN_FOREIGN_PARCEL: StringName = &"actor_on_foreign_parcel"

var _content: ContentDb
var _actors: ActorSystem
var _items: ItemSystem
var _stats: StatResolver
var _land: LandSystem
var _events: EventBus
## The scalars, sorted: the order decay is applied in, and so part of the state.
var _scalars: Array[StringName] = []
## scalar -> the content record
var _rules: Dictionary = {}
## event name -> Array of [scalar, raise rule]
var _raises: Dictionary = {}
## condition name -> Callable(actor: int, payload: Dictionary) -> bool
var _conditions: Dictionary = {}
## actor -> scalar -> int. An actor with nothing on any scalar is not in it.
var _standing: Dictionary = {}


func _init(content: ContentDb, actors: ActorSystem, items: ItemSystem, stats: StatResolver, land: LandSystem, events: EventBus) -> void:
	_content = content
	_actors = actors
	_items = items
	_stats = stats
	_land = land
	_events = events
	_conditions[WHEN_ALWAYS] = _when_always
	_conditions[WHEN_FOREIGN_PARCEL] = _when_on_foreign_parcel


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
	err = _events.subscribe(ActorSystem.EVENT_REMOVED, _on_removed)
	if err != OK:
		return err
	for event: StringName in _sorted_names(_raises.keys()):
		err = _events.subscribe(event, _on_event.bind(event))
		if err != OK:
			return err
	return OK


# ---------------------------------------------------------------- content

## Reads `content/standing_rule/` into the rule table and the event index. A derived
## scalar may not also be credited by events: two ways to set one number is two
## answers to the same question.
func validate_content() -> Error:
	_scalars = _content.ids(KIND_RULE)
	_rules.clear()
	_raises.clear()
	for scalar: StringName in _scalars:
		var rule: Dictionary = _content.get_entry(KIND_RULE, scalar)
		_rules[scalar] = rule
		var source: String = rule["source"]
		var raises: Array = rule["raise"]
		var decay: Dictionary = rule["decay"]
		var decay_amount: int = decay["amount"]
		if source == SOURCE_CARRIED and not (raises.is_empty() and decay_amount == 0):
			return _content_fail("%s is derived, so it can have neither raise rules nor a decay" % scalar)
		if source == SOURCE_EVENTS and raises.is_empty():
			return _content_fail("%s is raised by events but names none" % scalar)
		var index: String = decay["index"]
		var mode: String = decay["mode"]
		if mode != "flat" and index.is_empty():
			return _content_fail("%s scales its decay by a district index but names none" % scalar)
		if mode == "flat" and not index.is_empty():
			return _content_fail("%s names the index '%s' but does not scale by it" % [scalar, index])
		for r: Variant in raises:
			var raise_rule: Dictionary = r
			var when_s: String = raise_rule["when"]
			var when: StringName = StringName(when_s)
			if not _conditions.has(when):
				return _content_fail("%s names the unknown condition '%s'" % [scalar, when])
			var event_s: String = raise_rule["event"]
			var event: StringName = StringName(event_s)
			if not _raises.has(event):
				_raises[event] = []
			var list: Array = _raises[event]
			list.append([scalar, raise_rule])
	for district: StringName in _content.ids(KIND_DISTRICT):
		var d: Dictionary = _content.get_entry(KIND_DISTRICT, district)
		for key: String in ["law_index", "wealth_index", "informant_density"]:
			if typeof(d.get(key)) != TYPE_INT:
				return _content_fail("district/%s has no %s" % [district, key])
	return OK


func _content_fail(reason: String) -> Error:
	push_error("StandingSystem: content rejected: %s" % reason)
	return ERR_INVALID_DATA


# ---------------------------------------------------------------- queries

func scalars() -> Array[StringName]:
	return _scalars.duplicate()


## The ceiling the scalar is clamped to, from its rule; 0 for a scalar no file defines.
func ceiling_of(scalar: StringName) -> int:
	var rule: Dictionary = _rules_of(scalar)
	if rule.is_empty():
		return 0
	var ceiling: int = rule["max"]
	return ceiling


func standing_of(actor: int, scalar: StringName) -> int:
	var stored: Variant = _standing.get(actor)
	if typeof(stored) != TYPE_DICTIONARY:
		return 0
	var per_actor: Dictionary = stored
	var value: Variant = per_actor.get(scalar)
	if typeof(value) != TYPE_INT:
		return 0
	return value


func heat_of(actor: int) -> int:
	return standing_of(actor, &"heat")


func notoriety_of(actor: int) -> int:
	return standing_of(actor, &"notoriety")


func visible_wealth_of(actor: int) -> int:
	return standing_of(actor, &"visible_wealth")


## What the actor is carrying is worth, resolved now: the sum over the items in their
## inventory. A part fitted into one of them rides on its host's resolved value.
func carried_value(actor: int) -> int:
	var total: int = 0
	for item: int in _items.items_in(ItemSystem.inventory_of(actor)):
		total += maxi(_stats.resolve(item, STAT_VALUE), 0)
	return total


# ---------------------------------------------------------------- tick

## Every scalar is revisited on its own clock, in the scalars' sorted order.
func tick(sim: SimRoot) -> void:
	var now: int = sim.get_tick()
	for scalar: StringName in _scalars:
		var rule: Dictionary = _rules_of(scalar)
		var period: int = rule["period_ticks"]
		if period <= 0 or now % period != 0:
			continue
		var source: String = rule["source"]
		if source == SOURCE_CARRIED:
			_recompute(scalar)
		else:
			_decay(scalar, rule)


func _rules_of(scalar: StringName) -> Dictionary:
	var stored: Variant = _rules.get(scalar)
	if typeof(stored) != TYPE_DICTIONARY:
		return {}
	return stored


func _recompute(scalar: StringName) -> void:
	for actor: int in _actors.actor_ids():
		_write(actor, scalar, carried_value(actor))


func _decay(scalar: StringName, rule: Dictionary) -> void:
	var decay: Dictionary = rule["decay"]
	var amount: int = decay["amount"]
	if amount <= 0:
		return
	var index_name: String = decay["index"]
	var mode: String = decay["mode"]
	var actors: Array[int] = []
	for key: Variant in _standing:
		var actor: int = key
		actors.append(actor)
	actors.sort()
	for actor: int in actors:
		var value: int = standing_of(actor, scalar)
		if value <= 0:
			continue
		_write(actor, scalar, maxi(0, value - _scaled(amount, index_name, mode, actor)))


## A decay scaled by the index of the district the actor is standing in: `direct`
## falls faster where the index is high, `inverse` falls slower. Never below one, so
## a scalar always drains in the end.
func _scaled(amount: int, index_name: String, mode: String, actor: int) -> int:
	if mode == "flat":
		return amount
	var index: int = _district_index(actor, index_name)
	var scale: int = index if mode == "direct" else INDEX_ONE - index
	return maxi(1, amount * scale / INDEX_ONE)


func _district_index(actor: int, index_name: String) -> int:
	var parcel: StringName = _land.parcel_at(_actors.position_of(actor))
	var district: StringName = _land.wild_district() if parcel.is_empty() else _land.district_of(parcel)
	if not _content.has(KIND_DISTRICT, district):
		return 0
	var record: Dictionary = _content.get_entry(KIND_DISTRICT, district)
	var index: int = record[index_name]
	return clampi(index, 0, INDEX_ONE)


# ---------------------------------------------------------------- events

func _on_event(payload: Dictionary, event: StringName) -> void:
	var list: Array = _raises.get(event, [])
	var payload_tags: Array[String] = []
	var tags_v: Variant = payload.get("tags", [])
	if typeof(tags_v) == TYPE_ARRAY:
		var arr: Array = tags_v
		for t: Variant in arr:
			if typeof(t) == TYPE_STRING:
				payload_tags.append(t)
	for entry: Variant in list:
		var pair: Array = entry
		var scalar: StringName = pair[0]
		var rule: Dictionary = pair[1]
		var credit: String = rule["credit"]
		var actor_v: Variant = payload.get(credit)
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
		var when_s: String = rule["when"]
		var when: StringName = StringName(when_s)
		var condition: Callable = _conditions[when]
		var holds: Variant = condition.call(actor, payload)
		if typeof(holds) != TYPE_BOOL or not holds:
			continue
		var amount: int = rule["amount"]
		_write(actor, scalar, standing_of(actor, scalar) + amount)


func _when_always(_actor: int, _payload: Dictionary) -> bool:
	return true


## True when the actor is standing inside a parcel that is not theirs. Land they own,
## land nobody has claimed, and open ground outside every parcel are all free of it:
## heat is for being somewhere someone can object to.
func _when_on_foreign_parcel(actor: int, _payload: Dictionary) -> bool:
	var parcel: StringName = _land.parcel_at(_actors.position_of(actor))
	if parcel.is_empty():
		return false
	var owner: StringName = _land.owner_of(parcel)
	if owner.is_empty():
		return false
	return owner != _land.owner_tag_of_actor(actor)


## Writes one scalar, clamped to the rule's ceiling, and drops an actor whose every
## scalar is zero so an untouched actor never enters the snapshot.
func _write(actor: int, scalar: StringName, value: int) -> void:
	var rule: Dictionary = _rules_of(scalar)
	var ceiling: int = rule["max"]
	var clamped: int = clampi(value, 0, ceiling)
	if not _standing.has(actor):
		if clamped == 0:
			return
		_standing[actor] = {}
	var per_actor: Dictionary = _standing[actor]
	if clamped == 0:
		per_actor.erase(scalar)
		if per_actor.is_empty():
			_standing.erase(actor)
		return
	per_actor[scalar] = clamped


## A removed actor has no standing (M7 spec claim 12).
func _on_removed(payload: Dictionary) -> void:
	var actor: int = payload["actor"]
	_standing.erase(actor)


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
		var per_actor: Dictionary = in_all[key]
		if per_actor.is_empty():
			return _restore_fail("actor %d has an empty record" % actor)
		var kept: Dictionary = {}
		for scalar_v: Variant in per_actor:
			if typeof(scalar_v) != TYPE_STRING_NAME and typeof(scalar_v) != TYPE_STRING:
				return _restore_fail("actor %d scalar key" % actor)
			var scalar: StringName = _as_name(scalar_v)
			if not _rules.has(scalar):
				return _restore_fail("actor %d names the unknown scalar '%s'" % [actor, scalar])
			if typeof(per_actor[scalar_v]) != TYPE_INT:
				return _restore_fail("actor %d %s is not an integer" % [actor, scalar])
			var value: int = per_actor[scalar_v]
			var rule: Dictionary = _rules_of(scalar)
			var ceiling: int = rule["max"]
			if value <= 0 or value > ceiling:
				return _restore_fail("actor %d %s is %d, outside 1..%d" % [actor, scalar, value, ceiling])
			kept[scalar] = value
		out[actor] = kept
	_standing = out
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("StandingSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA


static func _as_name(v: Variant) -> StringName:
	match typeof(v):
		TYPE_STRING:
			var s: String = v
			return StringName(s)
		TYPE_STRING_NAME:
			var n: StringName = v
			return n
		_:
			return &""


## Lexically sorted. StringName's own `<` compares the interned pointer, which is
## neither lexical nor the same from one run to the next, so anything the sim iterates
## in order sorts the text instead.
static func _sorted_names(keys: Array) -> Array[StringName]:
	var text: Array[String] = []
	for k: Variant in keys:
		text.append(String(_as_name(k)))
	text.sort()
	var out: Array[StringName] = []
	for t: String in text:
		out.append(StringName(t))
	return out
