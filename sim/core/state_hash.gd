## Canonical hashing of simulation state.
##
## Encodes a value into a byte string whose layout does not depend on dictionary
## insertion order, then SHA-256s it. Two states hash equal only if they are
## structurally equal, which is what deterministic replay (standards §3.1) asserts.
##
## Supported types: null, bool, int, float, String, StringName, PackedByteArray,
## Array, Dictionary. Dictionary keys must be int, String or StringName. Anything
## else is a programming error: it is logged and the hash is the empty string,
## which no caller may treat as a valid hash.
class_name StateHash extends RefCounted

const _TAG_NIL: int = 0x00
const _TAG_BOOL: int = 0x01
const _TAG_INT: int = 0x02
const _TAG_FLOAT: int = 0x03
const _TAG_STRING: int = 0x04
const _TAG_STRING_NAME: int = 0x05
const _TAG_ARRAY: int = 0x06
const _TAG_DICTIONARY: int = 0x07
const _TAG_BYTES: int = 0x08

## Key ordering rank: ints sort before strings; String and StringName share a rank
## and compare as text.
const _KEY_RANK_INT: int = 0
const _KEY_RANK_TEXT: int = 1


## SHA-256 of the canonical encoding, as lowercase hex. Empty string on error.
static func of(value: Variant) -> String:
	var bytes: PackedByteArray = canonical_bytes(value)
	if bytes.is_empty():
		return ""
	var ctx := HashingContext.new()
	var err: Error = ctx.start(HashingContext.HASH_SHA256)
	if err != OK:
		push_error("StateHash: HashingContext.start failed: %s" % error_string(err))
		return ""
	err = ctx.update(bytes)
	if err != OK:
		push_error("StateHash: HashingContext.update failed: %s" % error_string(err))
		return ""
	return ctx.finish().hex_encode()


## The canonical encoding itself. Empty on error (every valid encoding has at least
## one tag byte, so empty is unambiguous).
static func canonical_bytes(value: Variant) -> PackedByteArray:
	var out := PackedByteArray()
	if not _encode(value, out):
		return PackedByteArray()
	return out


static func _encode(value: Variant, out: PackedByteArray) -> bool:
	match typeof(value):
		TYPE_NIL:
			out.append(_TAG_NIL)
		TYPE_BOOL:
			var b: bool = value
			out.append(_TAG_BOOL)
			out.append(1 if b else 0)
		TYPE_INT:
			var i: int = value
			out.append(_TAG_INT)
			_append_s64(out, i)
		TYPE_FLOAT:
			var f: float = value
			out.append(_TAG_FLOAT)
			var at: int = out.size()
			out.resize(at + 8)
			out.encode_double(at, f)
		TYPE_STRING:
			var s: String = value
			out.append(_TAG_STRING)
			_append_text(out, s)
		TYPE_STRING_NAME:
			var sn: StringName = value
			out.append(_TAG_STRING_NAME)
			_append_text(out, String(sn))
		TYPE_PACKED_BYTE_ARRAY:
			var pba: PackedByteArray = value
			out.append(_TAG_BYTES)
			_append_u32(out, pba.size())
			out.append_array(pba)
		TYPE_ARRAY:
			var arr: Array = value
			out.append(_TAG_ARRAY)
			_append_u32(out, arr.size())
			for element: Variant in arr:
				if not _encode(element, out):
					return false
		TYPE_DICTIONARY:
			var dict: Dictionary = value
			return _encode_dictionary(dict, out)
		_:
			push_error("StateHash: unsupported type %s" % type_string(typeof(value)))
			return false
	return true


static func _encode_dictionary(dict: Dictionary, out: PackedByteArray) -> bool:
	var keys: Array = dict.keys()
	for key: Variant in keys:
		var t: int = typeof(key)
		if t != TYPE_INT and t != TYPE_STRING and t != TYPE_STRING_NAME:
			push_error("StateHash: unsupported dictionary key type %s" % type_string(t))
			return false
	keys.sort_custom(_key_less)
	out.append(_TAG_DICTIONARY)
	_append_u32(out, keys.size())
	for key: Variant in keys:
		if not _encode(key, out):
			return false
		if not _encode(dict[key], out):
			return false
	return true


static func _key_less(a: Variant, b: Variant) -> bool:
	var rank_a: int = _KEY_RANK_INT if typeof(a) == TYPE_INT else _KEY_RANK_TEXT
	var rank_b: int = _KEY_RANK_INT if typeof(b) == TYPE_INT else _KEY_RANK_TEXT
	if rank_a != rank_b:
		return rank_a < rank_b
	if rank_a == _KEY_RANK_INT:
		var ia: int = a
		var ib: int = b
		return ia < ib
	var sa: String = str(a)
	var sb: String = str(b)
	return sa < sb


static func _append_text(out: PackedByteArray, text: String) -> void:
	var utf8: PackedByteArray = text.to_utf8_buffer()
	_append_u32(out, utf8.size())
	out.append_array(utf8)


static func _append_u32(out: PackedByteArray, value: int) -> void:
	var at: int = out.size()
	out.resize(at + 4)
	out.encode_u32(at, value)


static func _append_s64(out: PackedByteArray, value: int) -> void:
	var at: int = out.size()
	out.resize(at + 8)
	out.encode_s64(at, value)
