## Issues sim-unique entity ids (actors, items, rounds). Ids start at 1 and are never
## reused within a run; 0 means "none". Part of the state so a replay allocates the
## same ids (M1 spec claim 6).
class_name EntityIds extends SimSystem

const SYSTEM_ID: StringName = &"entities"
const NONE: int = 0

var _next: int = 1


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


func snapshot() -> Dictionary:
	return {"next": _next}


func allocate() -> int:
	var id: int = _next
	_next += 1
	return id


func peek_next() -> int:
	return _next


## Loads state from a snapshot produced by [method snapshot]. The input is untrusted.
func restore(state: Dictionary) -> Error:
	if state.size() != 1 or typeof(state.get("next")) != TYPE_INT:
		push_error("EntityIds: snapshot must be {\"next\": int}")
		return ERR_INVALID_DATA
	var next: int = state["next"]
	if next < 1:
		push_error("EntityIds: next must be >= 1")
		return ERR_INVALID_DATA
	_next = next
	return OK
