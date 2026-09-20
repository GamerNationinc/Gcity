## Maps command kinds to handlers. Registration, not modification (standards §6.4):
## a new command kind is one [method register] call from the system that owns it.
class_name CommandRegistry extends RefCounted

## Handler contract: [code]func(sim: SimRoot, payload: Dictionary) -> bool[/code].
## Returns true if the command was accepted and applied, false if rejected.
var _handlers: Dictionary[StringName, Callable] = {}


func register(kind: StringName, handler: Callable) -> Error:
	if kind.is_empty():
		push_error("CommandRegistry: empty command kind")
		return ERR_INVALID_PARAMETER
	if not handler.is_valid():
		push_error("CommandRegistry: invalid handler for kind '%s'" % kind)
		return ERR_INVALID_PARAMETER
	if _handlers.has(kind):
		push_error("CommandRegistry: kind '%s' already registered" % kind)
		return ERR_ALREADY_EXISTS
	_handlers[kind] = handler
	return OK


func has(kind: StringName) -> bool:
	return _handlers.has(kind)


## Registered kinds in lexical order (StringName's own ordering is by identity,
## not text, so the sort goes through String).
func kinds() -> Array[StringName]:
	var names: PackedStringArray = PackedStringArray()
	for kind: StringName in _handlers.keys():
		names.append(String(kind))
	names.sort()
	var result: Array[StringName] = []
	for name: String in names:
		result.append(StringName(name))
	return result


## Dispatches one command. Returns OK when applied, ERR_DOES_NOT_EXIST for an unknown
## kind, ERR_INVALID_PARAMETER when the handler rejected it, ERR_BUG when a handler
## broke its contract (that last case is a programming error, and is logged loudly).
func dispatch(sim: SimRoot, command: SimCommand) -> Error:
	if not _handlers.has(command.kind):
		return ERR_DOES_NOT_EXIST
	var handler: Callable = _handlers[command.kind]
	var result: Variant = handler.call(sim, command.payload)
	if typeof(result) != TYPE_BOOL:
		push_error("CommandRegistry: handler for '%s' returned %s, expected bool" % [command.kind, type_string(typeof(result))])
		return ERR_BUG
	var accepted: bool = result
	return OK if accepted else ERR_INVALID_PARAMETER
