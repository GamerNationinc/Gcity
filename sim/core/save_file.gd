## The save: `world seed + overlay` as text (design doc §5.6; M2 spec claims 13–16).
##
## A save is the root snapshot ([method SimRoot.snapshot]) serialised to JSON with a
## small typed encoding, because JSON has only string keys and only doubles:
## dictionary keys are written "i:<n>" (int) or "s:<text>" (string), integers beyond
## 2^53 are written as "int:<decimal>" strings, and any string that begins with
## "int:" or "str:" is written with a "str:" prefix. Floats are not save state and are
## refused on both sides.
##
## Save text is untrusted (standards §5.1): the envelope's key set, versions and types
## are checked here, the systems are checked by their own `restore()`, and the root by
## [method SimRoot.restore_root]. Nothing is applied unless the whole file is valid.
class_name SaveFile extends RefCounted

## Version 2 (M7 spec claim 15) is version 1 with the world's overlay in it: the route
## graph's seed and hash, the terrain's, the regions' edits and gate transits, bound
## sites, tokens, hydrated squads and what has been discovered. A version-1 save still
## loads: SimAssembly starts every system it predates as a new world at its seed.
const SCHEMA_VERSION: int = 2
const OLDEST_VERSION: int = 1
const MAX_BYTES: int = 16 * 1024 * 1024
const MAX_DEPTH: int = 64
## Beyond this magnitude a double no longer represents every integer.
const MAX_EXACT_INT: int = 1 << 53
const _KEYS: Array[String] = ["save_schema_version", "content_digest", "snapshot"]

var content_digest: String = ""
var snapshot: Dictionary = {}
## The schema version the file was written in.
var version: int = 0
## Empty when the file is valid; otherwise the first problem found.
var error: String = ""


func is_valid() -> bool:
	return error.is_empty()


## The save text for a sim built over content with the given digest, or "" (after an
## error) if the snapshot holds something a save cannot carry.
static func serialize(sim: SimRoot, content_digest_of_sim: String) -> String:
	var encoded: Variant = _encode(sim.snapshot(), 0)
	if typeof(encoded) == TYPE_NIL:
		return ""
	var envelope: Dictionary = {
		"save_schema_version": SCHEMA_VERSION,
		"content_digest": content_digest_of_sim,
		"snapshot": encoded,
	}
	return JSON.stringify(envelope, "\t", true)


static func parse(text: String) -> SaveFile:
	var file := SaveFile.new()
	file.error = file._load(text)
	if not file.error.is_empty():
		file.snapshot = {}
		file.content_digest = ""
	return file


func _load(text: String) -> String:
	if text.length() > MAX_BYTES:
		return "save exceeds %d bytes" % MAX_BYTES
	var json := JSON.new()
	if json.parse(text) != OK:
		return "line %d: %s" % [json.get_error_line(), json.get_error_message()]
	if typeof(json.data) != TYPE_DICTIONARY:
		return "top level must be an object"
	var envelope: Dictionary = json.data
	for key: String in _KEYS:
		if not envelope.has(key):
			return "missing key '%s'" % key
	for key: Variant in envelope.keys():
		if not _KEYS.has(str(key)):
			return "unknown key '%s'" % str(key)
	var version_v: Variant = envelope["save_schema_version"]
	if typeof(version_v) != TYPE_FLOAT and typeof(version_v) != TYPE_INT:
		return "save_schema_version must be an integer"
	var version_f: float = version_v
	if version_f != floorf(version_f) or version_f < OLDEST_VERSION or version_f > SCHEMA_VERSION:
		return "save_schema_version %s is not supported (expected %d to %d)" % [version_v, OLDEST_VERSION, SCHEMA_VERSION]
	version = int(version_f)
	if typeof(envelope["content_digest"]) != TYPE_STRING:
		return "content_digest must be a string"
	content_digest = envelope["content_digest"]
	if content_digest.length() != 64:
		return "content_digest must be 64 hex characters"
	var decoded: Variant = _decode(envelope["snapshot"], 0)
	if typeof(decoded) == TYPE_NIL:
		return _decode_error
	if typeof(decoded) != TYPE_DICTIONARY:
		return "snapshot must be an object"
	snapshot = decoded
	return ""


# ---------------------------------------------------------------- encoding

static func _encode(value: Variant, depth: int) -> Variant:
	if depth > MAX_DEPTH:
		push_error("SaveFile: snapshot nests deeper than %d" % MAX_DEPTH)
		return null
	match typeof(value):
		TYPE_NIL:
			push_error("SaveFile: null is not save state")
			return null
		TYPE_BOOL:
			return value
		TYPE_INT:
			var i: int = value
			if absi(i) >= MAX_EXACT_INT:
				return "int:%d" % i
			return i
		TYPE_FLOAT:
			push_error("SaveFile: floats are not save state")
			return null
		TYPE_STRING, TYPE_STRING_NAME:
			var s: String = str(value)
			if s.begins_with("int:") or s.begins_with("str:"):
				return "str:" + s
			return s
		TYPE_ARRAY:
			var arr: Array = value
			var out: Array = []
			for element: Variant in arr:
				var e: Variant = _encode(element, depth + 1)
				if typeof(e) == TYPE_NIL:
					return null
				out.append(e)
			return out
		TYPE_DICTIONARY:
			var dict: Dictionary = value
			var out: Dictionary = {}
			for key: Variant in dict:
				var encoded_key: String = ""
				match typeof(key):
					TYPE_INT:
						encoded_key = "i:%d" % key
					TYPE_STRING, TYPE_STRING_NAME:
						encoded_key = "s:" + str(key)
					_:
						push_error("SaveFile: dictionary key of type %s is not save state" % type_string(typeof(key)))
						return null
				var e: Variant = _encode(dict[key], depth + 1)
				if typeof(e) == TYPE_NIL:
					return null
				out[encoded_key] = e
			return out
		_:
			push_error("SaveFile: %s is not save state" % type_string(typeof(value)))
			return null


var _decode_error: String = ""


## Returns the decoded value, or null with [member _decode_error] set. Null is never a
## valid decoded value, so the sentinel is unambiguous.
func _decode(value: Variant, depth: int) -> Variant:
	if depth > MAX_DEPTH:
		return _fail("nests deeper than %d" % MAX_DEPTH)
	match typeof(value):
		TYPE_BOOL:
			return value
		TYPE_INT:
			return value
		TYPE_FLOAT:
			var f: float = value
			if is_nan(f) or is_inf(f) or f != floorf(f) or absf(f) >= float(MAX_EXACT_INT):
				return _fail("number %s is not an exact integer" % str(f))
			return int(f)
		TYPE_STRING:
			var s: String = value
			if s.begins_with("int:"):
				var digits: String = s.substr(4)
				var parsed: Array[int] = _parse_int64(digits)
				if parsed.is_empty():
					return _fail("malformed big integer '%s'" % s)
				var i: int = parsed[0]
				if absi(i) < MAX_EXACT_INT:
					return _fail("big integer '%s' is out of its range" % s)
				return i
			if s.begins_with("str:"):
				return s.substr(4)
			return s
		TYPE_ARRAY:
			var arr: Array = value
			var out: Array = []
			for element: Variant in arr:
				var d: Variant = _decode(element, depth + 1)
				if typeof(d) == TYPE_NIL:
					return null
				out.append(d)
			return out
		TYPE_DICTIONARY:
			var dict: Dictionary = value
			var out: Dictionary = {}
			for key: Variant in dict:
				var ks: String = str(key)
				var decoded_key: Variant
				if ks.begins_with("i:"):
					var parsed: Array[int] = _parse_int64(ks.substr(2))
					if parsed.is_empty():
						return _fail("malformed integer key '%s'" % ks)
					decoded_key = parsed[0]
				elif ks.begins_with("s:"):
					decoded_key = ks.substr(2)
				else:
					return _fail("key '%s' has no type prefix" % ks)
				if out.has(decoded_key):
					return _fail("duplicate key '%s'" % ks)
				var d: Variant = _decode(dict[key], depth + 1)
				if typeof(d) == TYPE_NIL:
					return null
				out[decoded_key] = d
			return out
		_:
			return _fail("%s is not save state" % type_string(typeof(value)))


## Canonical decimal text (no leading zeros, no plus sign, optional minus) to int64,
## refusing anything that would overflow. Empty on failure; [value] on success.
static func _parse_int64(text: String) -> Array[int]:
	var none: Array[int] = []
	var negative: bool = text.begins_with("-")
	var digits: String = text.substr(1) if negative else text
	if digits.is_empty() or digits.length() > 19 or (digits.length() > 1 and digits.begins_with("0")):
		return none
	if negative and digits == "0":
		return none
	var value: int = 0
	for i: int in digits.length():
		var c: int = digits.unicode_at(i) - 0x30
		if c < 0 or c > 9:
			return none
		# value * 10 + c must stay within int64; check before multiplying
		var limit: int = 9223372036854775807 if not negative else 9223372036854775807
		if value > (limit - c) / 10:
			if not (negative and value == 922337203685477580 and c == 8):
				return none
			return [-9223372036854775807 - 1]
		value = value * 10 + c
	return [-value if negative else value]


func _fail(reason: String) -> Variant:
	if _decode_error.is_empty():
		_decode_error = reason
	return null
