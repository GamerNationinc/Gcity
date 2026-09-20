## The one place a gameplay number is computed (design doc §10.2; M1 spec claims 1–5).
##
## A stat is a base plus modifiers. Modifiers belong to a registered class; the
## modifiers of one class sum, and classes fold in registration order:
##   value = fold_n(... fold_1(base, Σclass_1) ..., Σclass_n)
## with the two built-in classes giving (base + Σadd) × (10 000 + Σmul) / 10 000 in
## integer arithmetic, truncated once. Values are integers in milli-units.
##
## Entities are ints. An item entity may inherit its wielder's modifiers: a modifier
## on the wielder whose tags intersect the item's tags applies to the item (claim 4).
## Untagged modifiers apply to their own entity only.
##
## Resolution is cached per (entity, stat) and invalidated by every mutation that can
## change it; the cache is never observable (claim 3d) and is not part of the snapshot.
class_name StatResolver extends SimSystem

const SYSTEM_ID: StringName = &"stats"
const CLASS_ADD: StringName = &"add"
const CLASS_MUL: StringName = &"mul"
const BASIS_POINTS: int = 10_000
const ID_PATTERN: String = "^[a-z0-9][a-z0-9_.]*$"
const MAX_INHERIT_DEPTH: int = 8

var _id_regex: RegEx = RegEx.create_from_string(ID_PATTERN)
## stat id (StringName) -> default base (int)
var _stats: Dictionary = {}
## class id (StringName) -> {"order": int, "fold": Callable}
var _classes: Dictionary = {}
## class ids sorted by (order, id); rebuilt on registration
var _class_order: Array[StringName] = []
## entity (int) -> stat id -> base (int)
var _bases: Dictionary = {}
## handle (int) -> {"entity", "stat", "class", "value", "source", "tags"}
var _modifiers: Dictionary = {}
## entity (int) -> stat id -> Array[int] of handles, in handle order
var _index: Dictionary = {}
## entity (int) -> Array[String] sorted tags
var _tags: Dictionary = {}
## entity (int) -> parent entity (int)
var _inherits: Dictionary = {}
## parent (int) -> Array[int] children
var _children: Dictionary = {}
var _next_handle: int = 1
## entity -> stat -> value. Not state.
var _cache: Dictionary = {}


func _init() -> void:
	var add_err: Error = register_modifier_class(CLASS_ADD, 0, _fold_add)
	var mul_err: Error = register_modifier_class(CLASS_MUL, 100, _fold_mul)
	assert(add_err == OK and mul_err == OK, "built-in modifier classes must register")


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


func snapshot() -> Dictionary:
	var classes: Dictionary = {}
	for id: StringName in _classes:
		var entry: Dictionary = _classes[id]
		classes[id] = entry["order"]
	return {
		"stats": _stats.duplicate(),
		"classes": classes,
		"bases": _bases.duplicate(true),
		"modifiers": _modifiers.duplicate(true),
		"tags": _tags.duplicate(true),
		"inherits": _inherits.duplicate(),
		"next_handle": _next_handle,
	}


# ---------------------------------------------------------------- registration

## Registers a stat with the base every entity has until set_base() says otherwise.
func register_stat(id: StringName, default_base: int) -> Error:
	if not _id_regex.search(String(id)):
		push_error("StatResolver: stat id must match %s, got '%s'" % [ID_PATTERN, id])
		return ERR_INVALID_PARAMETER
	if _stats.has(id):
		push_error("StatResolver: stat '%s' already registered" % id)
		return ERR_ALREADY_EXISTS
	_stats[id] = default_base
	_cache.clear()
	return OK


## Registers stats from every content/stat/<id>.json entry in the database.
func register_stats_from(content: ContentDb) -> Error:
	for id: StringName in content.ids(&"stat"):
		var entry: Dictionary = content.get_entry(&"stat", id)
		var base: Variant = entry.get("default_base")
		if typeof(base) != TYPE_INT:
			push_error("StatResolver: stat/%s has no integer default_base" % id)
			return ERR_INVALID_DATA
		var base_int: int = base
		var err: Error = register_stat(id, base_int)
		if err != OK:
			return err
	return OK


## A modifier class: modifiers of the class sum, then `fold(acc: int, sum: int) -> int`
## combines the sum into the running value. Classes fold in ascending order (ties by
## id). The fold must be a pure function of its arguments.
func register_modifier_class(id: StringName, order: int, fold: Callable) -> Error:
	if not _id_regex.search(String(id)):
		push_error("StatResolver: class id must match %s, got '%s'" % [ID_PATTERN, id])
		return ERR_INVALID_PARAMETER
	if _classes.has(id):
		push_error("StatResolver: modifier class '%s' already registered" % id)
		return ERR_ALREADY_EXISTS
	if not fold.is_valid():
		push_error("StatResolver: class '%s' needs a valid fold callable" % id)
		return ERR_INVALID_PARAMETER
	_classes[id] = {"order": order, "fold": fold}
	_class_order.append(id)
	_class_order.sort_custom(_class_less)
	_cache.clear()
	return OK


func has_stat(id: StringName) -> bool:
	return _stats.has(id)


func stat_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	var keys: Array = _stats.keys()
	keys.sort_custom(_name_less)
	for key: Variant in keys:
		var name: StringName = key
		out.append(name)
	return out


func class_ids() -> Array[StringName]:
	return _class_order.duplicate()


# ---------------------------------------------------------------- bases, tags, inheritance

func set_base(entity: int, stat: StringName, value: int) -> Error:
	if not _stats.has(stat):
		push_error("StatResolver: set_base on unregistered stat '%s'" % stat)
		return ERR_DOES_NOT_EXIST
	if not _bases.has(entity):
		_bases[entity] = {}
	var per_entity: Dictionary = _bases[entity]
	per_entity[stat] = value
	_invalidate(entity)
	return OK


## The entity's base for the stat: what set_base() stored, else the stat's default.
func get_base(entity: int, stat: StringName) -> int:
	if not _stats.has(stat):
		push_error("StatResolver: get_base on unregistered stat '%s'" % stat)
		return 0
	var per_entity: Variant = _bases.get(entity)
	if typeof(per_entity) == TYPE_DICTIONARY:
		var dict: Dictionary = per_entity
		if dict.has(stat):
			return dict[stat]
	return _stats[stat]


## Tags decide which of a wielder's modifiers reach this entity. Stored sorted.
func set_tags(entity: int, tags: Array[StringName]) -> Error:
	var sorted: Array[String] = []
	for tag: StringName in tags:
		if not _id_regex.search(String(tag)):
			push_error("StatResolver: tag must match %s, got '%s'" % [ID_PATTERN, tag])
			return ERR_INVALID_PARAMETER
		var text: String = String(tag)
		if not sorted.has(text):
			sorted.append(text)
	sorted.sort()
	if sorted.is_empty():
		_tags.erase(entity)
	else:
		_tags[entity] = sorted
	_invalidate(entity)
	return OK


func get_tags(entity: int) -> Array[StringName]:
	var out: Array[StringName] = []
	var stored: Variant = _tags.get(entity)
	if typeof(stored) == TYPE_ARRAY:
		var arr: Array = stored
		for tag: Variant in arr:
			var text: String = tag
			out.append(StringName(text))
	return out


## Makes `entity` inherit tagged modifiers from `parent`; -1 clears. Rejects cycles.
func set_inherits(entity: int, parent: int) -> Error:
	if parent == entity:
		push_error("StatResolver: entity %d cannot inherit from itself" % entity)
		return ERR_INVALID_PARAMETER
	if parent >= 0:
		var walk: int = parent
		var depth: int = 0
		while _inherits.has(walk):
			walk = _inherits[walk]
			depth += 1
			if walk == entity or depth >= MAX_INHERIT_DEPTH:
				push_error("StatResolver: inheritance cycle or chain too deep at entity %d" % entity)
				return ERR_INVALID_PARAMETER
	_detach_from_parent(entity)
	if parent >= 0:
		_inherits[entity] = parent
		if not _children.has(parent):
			_children[parent] = []
		var siblings: Array = _children[parent]
		siblings.append(entity)
	_invalidate(entity)
	return OK


func get_inherits(entity: int) -> int:
	return _inherits.get(entity, -1)


# ---------------------------------------------------------------- modifiers

## Adds a modifier: {"stat": StringName, "class": StringName, "value": int,
## "source": StringName, "tags": Array[StringName] (optional)}. Returns a handle
## (>= 1) for remove_modifier(), or -1 with an error for any malformed input.
func add_modifier(entity: int, modifier: Dictionary) -> int:
	var stat_v: Variant = modifier.get("stat")
	var class_v: Variant = modifier.get("class")
	var value_v: Variant = modifier.get("value")
	var source_v: Variant = modifier.get("source")
	var tags_v: Variant = modifier.get("tags", [] as Array[StringName])
	var allowed: Array[String] = ["stat", "class", "value", "source", "tags"]
	for key: Variant in modifier.keys():
		if typeof(key) != TYPE_STRING or not allowed.has(key):
			push_error("StatResolver: unexpected modifier key %s" % var_to_str(key))
			return -1
	if typeof(stat_v) != TYPE_STRING_NAME or not _stats.has(stat_v):
		push_error("StatResolver: modifier names unregistered stat %s" % var_to_str(stat_v))
		return -1
	if typeof(class_v) != TYPE_STRING_NAME or not _classes.has(class_v):
		push_error("StatResolver: modifier names unregistered class %s" % var_to_str(class_v))
		return -1
	if typeof(value_v) != TYPE_INT:
		push_error("StatResolver: modifier value must be int, got %s" % var_to_str(value_v))
		return -1
	if typeof(source_v) != TYPE_STRING_NAME:
		push_error("StatResolver: modifier source must be a StringName, got %s" % var_to_str(source_v))
		return -1
	var source: StringName = source_v
	if not _id_regex.search(String(source)):
		push_error("StatResolver: modifier source must be id-like, got '%s'" % source)
		return -1
	if typeof(tags_v) != TYPE_ARRAY:
		push_error("StatResolver: modifier tags must be an array")
		return -1
	var tags_in: Array = tags_v
	var tags: Array[String] = []
	for tag: Variant in tags_in:
		if typeof(tag) != TYPE_STRING_NAME:
			push_error("StatResolver: modifier tag must be a StringName, got %s" % var_to_str(tag))
			return -1
		var tag_name: StringName = tag
		var text: String = String(tag_name)
		if not _id_regex.search(text):
			push_error("StatResolver: modifier tag must be id-like, got '%s'" % text)
			return -1
		if not tags.has(text):
			tags.append(text)
	tags.sort()
	var stat: StringName = stat_v
	var cls: StringName = class_v
	var value: int = value_v
	var handle: int = _next_handle
	_next_handle += 1
	_modifiers[handle] = {"entity": entity, "stat": stat, "class": cls, "value": value, "source": source, "tags": tags}
	if not _index.has(entity):
		_index[entity] = {}
	var per_entity: Dictionary = _index[entity]
	if not per_entity.has(stat):
		per_entity[stat] = [] as Array[int]
	var handles: Array[int] = per_entity[stat]
	handles.append(handle)
	_invalidate(entity)
	return handle


func remove_modifier(handle: int) -> Error:
	if not _modifiers.has(handle):
		push_error("StatResolver: no modifier with handle %d" % handle)
		return ERR_DOES_NOT_EXIST
	var m: Dictionary = _modifiers[handle]
	var entity: int = m["entity"]
	var stat: StringName = m["stat"]
	_modifiers.erase(handle)
	var per_entity: Dictionary = _index[entity]
	var handles: Array[int] = per_entity[stat]
	handles.erase(handle)
	if handles.is_empty():
		per_entity.erase(stat)
	if per_entity.is_empty():
		_index.erase(entity)
	_invalidate(entity)
	return OK


func has_modifier(handle: int) -> bool:
	return _modifiers.has(handle)


func modifier_count() -> int:
	return _modifiers.size()


# ---------------------------------------------------------------- resolution

## The resolved value. Unregistered stats resolve to 0 with an error (claim 5).
func resolve(entity: int, stat: StringName) -> int:
	if not _stats.has(stat):
		push_error("StatResolver: resolve of unregistered stat '%s'" % stat)
		return 0
	var cached: Variant = _cache.get(entity)
	if typeof(cached) == TYPE_DICTIONARY:
		var per_entity: Dictionary = cached
		if per_entity.has(stat):
			return per_entity[stat]
	var value: int = _compute(entity, stat)
	if not _cache.has(entity):
		_cache[entity] = {}
	var store: Dictionary = _cache[entity]
	store[stat] = value
	return value


func _compute(entity: int, stat: StringName) -> int:
	var sums: Dictionary = {}
	for cls: StringName in _class_order:
		sums[cls] = 0
	_sum_own(entity, stat, sums)
	var own_tags: Variant = _tags.get(entity)
	if typeof(own_tags) == TYPE_ARRAY:
		var tags: Array = own_tags
		var parent: int = _inherits.get(entity, -1)
		var depth: int = 0
		while parent >= 0 and depth < MAX_INHERIT_DEPTH:
			_sum_inherited(parent, stat, tags, sums)
			parent = _inherits.get(parent, -1)
			depth += 1
	var acc: int = get_base(entity, stat)
	for cls: StringName in _class_order:
		var entry: Dictionary = _classes[cls]
		var fold: Callable = entry["fold"]
		var folded: Variant = fold.call(acc, sums[cls])
		if typeof(folded) != TYPE_INT:
			push_error("StatResolver: fold of class '%s' returned a non-int" % cls)
			return 0
		acc = folded
	return acc


func _sum_own(entity: int, stat: StringName, sums: Dictionary) -> void:
	for handle: int in _handles(entity, stat):
		var m: Dictionary = _modifiers[handle]
		var cls: StringName = m["class"]
		var value: int = m["value"]
		sums[cls] += value


func _sum_inherited(parent: int, stat: StringName, tags: Array, sums: Dictionary) -> void:
	for handle: int in _handles(parent, stat):
		var m: Dictionary = _modifiers[handle]
		var m_tags: Array = m["tags"]
		if m_tags.is_empty():
			continue
		var matches: bool = false
		for tag: Variant in m_tags:
			if tags.has(tag):
				matches = true
				break
		if matches:
			var cls: StringName = m["class"]
			var value: int = m["value"]
			sums[cls] += value


func _handles(entity: int, stat: StringName) -> Array[int]:
	var per_entity: Variant = _index.get(entity)
	if typeof(per_entity) != TYPE_DICTIONARY:
		return [] as Array[int]
	var dict: Dictionary = per_entity
	if not dict.has(stat):
		return [] as Array[int]
	return dict[stat]


func _fold_add(acc: int, sum: int) -> int:
	return acc + sum


func _fold_mul(acc: int, sum: int) -> int:
	var factor: int = maxi(BASIS_POINTS + sum, 0)
	@warning_ignore("integer_division")
	return acc * factor / BASIS_POINTS


# ---------------------------------------------------------------- bookkeeping

## Drops cached values for the entity and everything that inherits from it.
func _invalidate(entity: int) -> void:
	_cache.erase(entity)
	var kids: Variant = _children.get(entity)
	if typeof(kids) == TYPE_ARRAY:
		var arr: Array = kids
		for child: Variant in arr:
			var child_id: int = child
			_invalidate(child_id)


func _detach_from_parent(entity: int) -> void:
	if not _inherits.has(entity):
		return
	var parent: int = _inherits[entity]
	_inherits.erase(entity)
	var siblings: Array = _children[parent]
	siblings.erase(entity)
	if siblings.is_empty():
		_children.erase(parent)


func _class_less(a: StringName, b: StringName) -> bool:
	var ea: Dictionary = _classes[a]
	var eb: Dictionary = _classes[b]
	var oa: int = ea["order"]
	var ob: int = eb["order"]
	if oa != ob:
		return oa < ob
	return String(a) < String(b)


static func _name_less(a: Variant, b: Variant) -> bool:
	var sa: StringName = a
	var sb: StringName = b
	return String(sa) < String(sb)
