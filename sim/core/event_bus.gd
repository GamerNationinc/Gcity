## Synchronous, ordered event delivery between sim systems (design doc §10.1): a
## gameplay system emits `hit{...}` and knows nothing about who listens. Subscribers
## are registered at assembly, in a fixed order, and run in that order; the bus itself
## holds no state that matters to the hash (its effects live in the subscribers).
class_name EventBus extends RefCounted

const NAME_PATTERN: String = "^[a-z0-9][a-z0-9_.]*$"

var _name_regex: RegEx = RegEx.create_from_string(NAME_PATTERN)
## event name -> Array[Callable]
var _handlers: Dictionary = {}
var _emitted: int = 0


## Handler contract: func(payload: Dictionary) -> void. The payload is read-only.
func subscribe(event: StringName, handler: Callable) -> Error:
	if not _name_regex.search(String(event)):
		push_error("EventBus: event name must match %s, got '%s'" % [NAME_PATTERN, event])
		return ERR_INVALID_PARAMETER
	if not handler.is_valid():
		push_error("EventBus: invalid handler for '%s'" % event)
		return ERR_INVALID_PARAMETER
	if not _handlers.has(event):
		_handlers[event] = [] as Array[Callable]
	var list: Array[Callable] = _handlers[event]
	list.append(handler)
	return OK


## Delivers the payload to every subscriber of the event, in subscription order.
## Returns how many handlers ran.
func emit(event: StringName, payload: Dictionary) -> int:
	_emitted += 1
	var stored: Variant = _handlers.get(event)
	if typeof(stored) != TYPE_ARRAY:
		return 0
	var frozen: Dictionary = payload.duplicate(true)
	frozen.make_read_only()
	var list: Array[Callable] = stored
	for handler: Callable in list:
		handler.call(frozen)
	return list.size()


func subscriber_count(event: StringName) -> int:
	var stored: Variant = _handlers.get(event)
	if typeof(stored) != TYPE_ARRAY:
		return 0
	var list: Array = stored
	return list.size()


func emitted_count() -> int:
	return _emitted
