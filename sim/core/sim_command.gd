## A request from a client to the simulation (engineering standards §5.2).
##
## The client never asserts state; it submits commands, and the sim validates and
## applies them. A command names the tick it should apply on, a registered kind, and a
## payload the handler for that kind validates.
class_name SimCommand extends RefCounted

## Tick on which the command is dispatched. Must be later than the sim's current tick.
var tick: int
## Registry key. Kinds are registered at startup (see [CommandRegistry]); never an enum.
var kind: StringName
## Handler-specific data. Treated as untrusted by the handler.
var payload: Dictionary


func _init(p_tick: int, p_kind: StringName, p_payload: Dictionary) -> void:
	tick = p_tick
	kind = p_kind
	payload = p_payload
