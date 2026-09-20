## Test double: a system that counts its ticks and draws one value from the sim RNG
## per tick, so its snapshot depends on both registration order and the seed.
class_name CounterSystemDouble extends SimSystem

const COMMAND_ADD: StringName = &"counter.add"

var _id: StringName
var ticks_seen: int = 0
var last_draw: int = 0
var total: int = 0
var ticks_of_sim_seen: Array[int] = []


func _init(p_id: StringName = &"counter") -> void:
	_id = p_id


func system_id() -> StringName:
	return _id


## Registers this system and its command with a fresh sim. Returns the first error.
func attach(sim: SimRoot) -> Error:
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	return sim.commands().register(COMMAND_ADD, _on_add)


func tick(sim: SimRoot) -> void:
	ticks_seen += 1
	ticks_of_sim_seen.append(sim.get_tick())
	last_draw = sim.rng().randi()


func snapshot() -> Dictionary:
	return {"ticks_seen": ticks_seen, "last_draw": last_draw, "total": total}


## Payload contract: {"amount": int}. Anything else is rejected.
func _on_add(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 1 or not payload.has("amount"):
		return false
	var raw: Variant = payload["amount"]
	var amount: int = 0
	match typeof(raw):
		TYPE_INT:
			amount = raw
		TYPE_FLOAT:
			var f: float = raw
			if f != floorf(f):
				return false
			amount = int(f)
		_:
			return false
	total += amount
	return true
