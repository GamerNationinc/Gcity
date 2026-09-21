## JSON has one number type, so `1` arrives as `1.0`. Data crossing into the sim
## (content, replay fixtures) is canonicalised at the boundary: integral floats within
## the exactly-representable range become ints, everything else is left alone. Handlers
## then check `typeof() == TYPE_INT` and nothing else, and a payload that says `1.5`
## where an int belongs is rejected rather than truncated.
class_name JsonNumbers extends RefCounted

## Beyond this magnitude a double no longer represents every integer.
const MAX_EXACT: float = 9007199254740992.0


## Converts in place, recursively, through dictionaries and arrays. Returns the value
## for convenience (a top-level float is returned converted; containers are the same object).
static func normalise(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			var f: float = value
			if f == floorf(f) and absf(f) < MAX_EXACT:
				return int(f)
			return f
		TYPE_DICTIONARY:
			var dict: Dictionary = value
			for key: Variant in dict.keys():
				dict[key] = normalise(dict[key])
			return dict
		TYPE_ARRAY:
			var arr: Array = value
			for i: int in range(arr.size()):
				arr[i] = normalise(arr[i])
			return arr
		_:
			return value
