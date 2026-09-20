## The sim's view of content: dictionaries handed in by the host, never files (the
## dependency rule keeps res://content/ out of sim/). Entries are validated at this
## boundary (M1 spec claim 16): id format, integer schema_version, hashable data, no
## duplicates. Adding stops at the first tick, so the digest in the snapshot is fixed
## for a run and a rebalance changes every fixture hash visibly.
class_name ContentDb extends SimSystem

const SYSTEM_ID: StringName = &"content"
const ID_PATTERN: String = "^[a-z0-9][a-z0-9_]*$"

var _id_regex: RegEx = RegEx.create_from_string(ID_PATTERN)
## kind (String) -> id (String) -> read-only Dictionary
var _entries: Dictionary = {}
var _count: int = 0
var _locked: bool = false
var _digest_cache: String = ""


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	_locked = true


func snapshot() -> Dictionary:
	return {"digest": digest(), "entries": _count}


## Adds one content entry. The data is copied and frozen; the caller's dictionary is
## not retained. Returns ERR_LOCKED after the first tick, ERR_ALREADY_EXISTS for a
## duplicate, ERR_INVALID_PARAMETER for a bad kind, id or data.
func add(kind: StringName, id: StringName, data: Dictionary) -> Error:
	if _locked:
		push_error("ContentDb: cannot add %s/%s after the first tick" % [kind, id])
		return ERR_LOCKED
	if not _id_regex.search(String(kind)) or not _id_regex.search(String(id)):
		push_error("ContentDb: kind and id must match %s, got %s/%s" % [ID_PATTERN, kind, id])
		return ERR_INVALID_PARAMETER
	var version: Variant = data.get("schema_version")
	if typeof(version) != TYPE_INT or version < 1:
		push_error("ContentDb: %s/%s needs an integer schema_version >= 1" % [kind, id])
		return ERR_INVALID_PARAMETER
	if StateHash.canonical_bytes(data).is_empty():
		push_error("ContentDb: %s/%s contains unhashable data" % [kind, id])
		return ERR_INVALID_PARAMETER
	var kind_key: String = String(kind)
	var id_key: String = String(id)
	if not _entries.has(kind_key):
		_entries[kind_key] = {}
	var by_id: Dictionary = _entries[kind_key]
	if by_id.has(id_key):
		push_error("ContentDb: duplicate %s/%s" % [kind, id])
		return ERR_ALREADY_EXISTS
	var frozen: Dictionary = data.duplicate(true)
	frozen.make_read_only()
	by_id[id_key] = frozen
	_count += 1
	_digest_cache = ""
	return OK


func has(kind: StringName, id: StringName) -> bool:
	var by_id: Variant = _entries.get(String(kind))
	if typeof(by_id) != TYPE_DICTIONARY:
		return false
	var dict: Dictionary = by_id
	return dict.has(String(id))


## The read-only entry, or an empty dictionary (and an error) if it does not exist.
func get_entry(kind: StringName, id: StringName) -> Dictionary:
	if not has(kind, id):
		push_error("ContentDb: no such entry %s/%s" % [kind, id])
		return {}
	var by_id: Dictionary = _entries[String(kind)]
	return by_id[String(id)]


## Ids of one kind, lexically sorted. Empty for an unknown kind.
func ids(kind: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	var by_id: Variant = _entries.get(String(kind))
	if typeof(by_id) != TYPE_DICTIONARY:
		return out
	var dict: Dictionary = by_id
	var keys: Array = dict.keys()
	keys.sort()
	for key: Variant in keys:
		var text: String = key
		out.append(StringName(text))
	return out


## Kinds present, lexically sorted.
func kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	var keys: Array = _entries.keys()
	keys.sort()
	for key: Variant in keys:
		var text: String = key
		out.append(StringName(text))
	return out


func count() -> int:
	return _count


func is_locked() -> bool:
	return _locked


## SHA-256 over every entry, independent of insertion order.
func digest() -> String:
	if _digest_cache.is_empty():
		_digest_cache = StateHash.of(_entries)
	return _digest_cache
