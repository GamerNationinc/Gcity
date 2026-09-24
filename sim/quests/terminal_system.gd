## Terminals and the hack (M6 spec claim 5; design doc §15.2). A terminal is an
## entity a site places; hacking it is `terminal.hack_start {actor, terminal}`, which
## runs a tick a tick while the actor stays alive and within the terminal's reach.
## Moving out of reach cancels it and the progress is lost: that is the exposure the
## mission is built on, and why the device cannot pause on a site (ADR-006 C). On
## completion the data item goes into the actor's inventory, `terminal.hacked` is
## emitted with the terminal's signal name for the threat director (M8), and the
## terminal stays hacked — a trace, until `terminal.wipe` clears it.
class_name TerminalSystem extends SimSystem

const SYSTEM_ID: StringName = &"terminals"
const KIND_TERMINAL: StringName = &"terminal"
const COMMAND_START: StringName = &"terminal.hack_start"
const COMMAND_CANCEL: StringName = &"terminal.hack_cancel"
const COMMAND_WIPE: StringName = &"terminal.wipe"
const EVENT_HACKED: StringName = &"terminal.hacked"
const EVENT_CANCELLED: StringName = &"terminal.hack_cancelled"

var _content: ContentDb
var _actors: ActorSystem
var _items: ItemSystem
var _ids: EntityIds
var _events: EventBus
## terminal entity -> {"template": StringName, "pos": [x, y, z], "hacked": bool, "actor": int, "progress": int}
var _terminals: Dictionary = {}
var _hacks: int = 0


func _init(content: ContentDb, actors: ActorSystem, items: ItemSystem, ids: EntityIds, events: EventBus) -> void:
	_content = content
	_actors = actors
	_items = items
	_ids = ids
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func snapshot() -> Dictionary:
	return {"terminals": _terminals.duplicate(true), "hacks": _hacks}


func attach(sim: SimRoot) -> Error:
	var err: Error = validate_content()
	if err != OK:
		return err
	err = sim.register_system(self)
	if err != OK:
		return err
	err = _events.subscribe(ActorSystem.EVENT_REMOVED, _on_removed)
	if err != OK:
		return err
	for pair: Array in [[COMMAND_START, _on_start], [COMMAND_CANCEL, _on_cancel], [COMMAND_WIPE, _on_wipe]]:
		var kind: StringName = pair[0]
		var handler: Callable = pair[1]
		err = sim.commands().register(kind, handler)
		if err != OK:
			return err
	return OK


## Every terminal yields a template the item system can spawn.
func validate_content() -> Error:
	for id: StringName in _content.ids(KIND_TERMINAL):
		var t: Dictionary = _content.get_entry(KIND_TERMINAL, id)
		var kind_s: String = t["yields_kind"]
		var template_s: String = t["yields"]
		if not ItemSystem.SPAWNABLE.has(StringName(kind_s)):
			push_error("TerminalSystem: terminal/%s yields a kind that cannot be spawned: %s" % [id, kind_s])
			return ERR_INVALID_DATA
		if not _content.has(StringName(kind_s), StringName(template_s)):
			push_error("TerminalSystem: terminal/%s yields %s/%s, which does not exist" % [id, kind_s, template_s])
			return ERR_INVALID_DATA
	return OK


# ---------------------------------------------------------------- queries

func terminal_ids() -> Array[int]:
	var out: Array[int] = []
	for key: Variant in _terminals:
		var id: int = key
		out.append(id)
	out.sort()
	return out


func has_terminal(terminal: int) -> bool:
	return _terminals.has(terminal)


func template_of(terminal: int) -> StringName:
	var rec: Dictionary = _record(terminal)
	if rec.is_empty():
		return &""
	return rec["template"]


func position_of(terminal: int) -> Vector3i:
	var rec: Dictionary = _record(terminal)
	if rec.is_empty():
		return Vector3i.ZERO
	return PathingSystem._vec(rec["pos"])


func is_hacked(terminal: int) -> bool:
	var rec: Dictionary = _record(terminal)
	if rec.is_empty():
		return false
	return rec["hacked"]


## The actor hacking this terminal, or NONE.
func hacker_of(terminal: int) -> int:
	var rec: Dictionary = _record(terminal)
	if rec.is_empty():
		return EntityIds.NONE
	return rec["actor"]


## Ticks of progress on the terminal's current hack, 0 when nobody is hacking it.
func progress_of(terminal: int) -> int:
	var rec: Dictionary = _record(terminal)
	if rec.is_empty():
		return 0
	return rec["progress"]


func hack_ticks_of(terminal: int) -> int:
	var rec: Dictionary = _record(terminal)
	if rec.is_empty():
		return 0
	var template: StringName = rec["template"]
	var t: Dictionary = _content.get_entry(KIND_TERMINAL, template)
	return t["hack_ticks"]


## Terminals within an actor's reach of it, in id order.
func in_reach_of(actor: int) -> Array[int]:
	var out: Array[int] = []
	if not _actors.has_actor(actor):
		return out
	var here: Vector3i = _actors.position_of(actor)
	for terminal: int in terminal_ids():
		if PerceptionSystem.distance_mm(here, position_of(terminal)) <= _reach_of(terminal):
			out.append(terminal)
	return out


## How many terminals have been hacked since assembly (a trace counter for the score).
func hack_count() -> int:
	return _hacks


## Terminals hacked and not wiped: traces left behind (M6 spec claim 7).
func traces() -> int:
	var n: int = 0
	for terminal: int in terminal_ids():
		if is_hacked(terminal):
			n += 1
	return n


func _record(terminal: int) -> Dictionary:
	var stored: Variant = _terminals.get(terminal)
	if typeof(stored) != TYPE_DICTIONARY:
		return {}
	return stored


func _reach_of(terminal: int) -> int:
	var rec: Dictionary = _record(terminal)
	if rec.is_empty():
		return 0
	var template: StringName = rec["template"]
	var t: Dictionary = _content.get_entry(KIND_TERMINAL, template)
	return t["reach_mm"]


## Whether the actor's device provides what the terminal requires.
func can_hack(actor: int, terminal: int) -> bool:
	var rec: Dictionary = _record(terminal)
	if rec.is_empty() or not _actors.is_alive(actor):
		return false
	var template: StringName = rec["template"]
	var t: Dictionary = _content.get_entry(KIND_TERMINAL, template)
	var requires_s: String = t["requires"]
	if requires_s.is_empty():
		return true
	var device: int = _actors.device_of(actor)
	if device == EntityIds.NONE:
		return false
	return _items.provides_of(device).has(StringName(requires_s))


# ---------------------------------------------------------------- placing

## Places a terminal at a position. Sites call this as they raise; nothing else does.
func place(template: StringName, position: Vector3i) -> int:
	if not _content.has(KIND_TERMINAL, template):
		push_error("TerminalSystem: no terminal/%s" % template)
		return EntityIds.NONE
	var id: int = _ids.allocate()
	_terminals[id] = {"template": template, "pos": PathingSystem._arr(position), "hacked": false, "actor": EntityIds.NONE, "progress": 0}
	return id


# ---------------------------------------------------------------- the tick

func tick(_sim: SimRoot) -> void:
	for terminal: int in terminal_ids():
		var rec: Dictionary = _terminals[terminal]
		var actor: int = rec["actor"]
		if actor == EntityIds.NONE:
			continue
		if not _in_reach(actor, terminal) or not _actors.is_alive(actor) or not can_hack(actor, terminal):
			_cancel(terminal, rec, "out of reach")
			continue
		var progress: int = rec["progress"] + 1
		rec["progress"] = progress
		if progress < hack_ticks_of(terminal):
			continue
		# done: the data is the actor's, the terminal stays hacked until it is wiped
		var template: StringName = rec["template"]
		var t: Dictionary = _content.get_entry(KIND_TERMINAL, template)
		var kind_s: String = t["yields_kind"]
		var template_s: String = t["yields"]
		var item: int = _items.spawn(StringName(kind_s), StringName(template_s), ItemSystem.inventory_of(actor), terminal)
		assert(item != EntityIds.NONE, "content was validated; the yield spawns")
		rec["hacked"] = true
		rec["actor"] = EntityIds.NONE
		rec["progress"] = 0
		_hacks += 1
		var emits_s: String = t["emits"]
		_events.emit(EVENT_HACKED, {"actor": actor, "terminal": terminal, "template": template, "item": item, "signal": emits_s})


func _in_reach(actor: int, terminal: int) -> bool:
	if not _actors.has_actor(actor):
		return false
	return PerceptionSystem.distance_mm(_actors.position_of(actor), position_of(terminal)) <= _reach_of(terminal)


func _cancel(terminal: int, rec: Dictionary, reason: String) -> void:
	var actor: int = rec["actor"]
	var progress: int = rec["progress"]
	rec["actor"] = EntityIds.NONE
	rec["progress"] = 0
	_events.emit(EVENT_CANCELLED, {"actor": actor, "terminal": terminal, "progress": progress, "reason": reason})


# ---------------------------------------------------------------- commands

## {"actor": int, "terminal": int}: begin a hack. Refused when the terminal is
## already hacked or being hacked, the actor cannot reach it, or its device does not
## provide what the terminal requires.
func _on_start(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("terminal")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var terminal: int = payload["terminal"]
	var rec: Dictionary = _record(terminal)
	if rec.is_empty() or rec["hacked"] or rec["actor"] != EntityIds.NONE:
		return false
	if not _actors.is_alive(actor) or not _in_reach(actor, terminal) or not can_hack(actor, terminal):
		return false
	rec["actor"] = actor
	rec["progress"] = 0
	return true


## {"actor": int, "terminal": int}: stop a hack the actor started. The progress goes.
func _on_cancel(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("terminal")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var terminal: int = payload["terminal"]
	var rec: Dictionary = _record(terminal)
	if rec.is_empty() or rec["actor"] != actor:
		return false
	_cancel(terminal, rec, "cancelled")
	return true


## {"actor": int, "terminal": int}: wipe a hacked terminal, clearing the trace. The
## actor must be in reach; the data it already yielded stays where it is.
func _on_wipe(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("terminal")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	var terminal: int = payload["terminal"]
	var rec: Dictionary = _record(terminal)
	if rec.is_empty() or not rec["hacked"] or not _actors.is_alive(actor) or not _in_reach(actor, terminal):
		return false
	rec["hacked"] = false
	return true


## A hack whose hacker is removed is abandoned, exactly as walking away abandons it
## (M7 spec claim 12).
func _on_removed(payload: Dictionary) -> void:
	var actor: int = payload["actor"]
	for terminal: int in terminal_ids():
		var rec: Dictionary = _terminals[terminal]
		var hacker: int = rec["actor"]
		if hacker == actor:
			_cancel(terminal, rec, "removed")


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 2 or typeof(state.get("terminals")) != TYPE_DICTIONARY or typeof(state.get("hacks")) != TYPE_INT:
		return _restore_fail("shape")
	var hacks: int = state["hacks"]
	if hacks < 0:
		return _restore_fail("negative count")
	var in_all: Dictionary = state["terminals"]
	var out: Dictionary = {}
	for key: Variant in in_all:
		if typeof(key) != TYPE_INT or typeof(in_all[key]) != TYPE_DICTIONARY:
			return _restore_fail("terminal key")
		var terminal: int = key
		var rec: Dictionary = in_all[key]
		var template_v: Variant = rec.get("template")
		if rec.size() != 5 or (typeof(template_v) != TYPE_STRING and typeof(template_v) != TYPE_STRING_NAME) \
				or not PathingSystem._is_cell(rec.get("pos")) or typeof(rec.get("hacked")) != TYPE_BOOL \
				or typeof(rec.get("actor")) != TYPE_INT or typeof(rec.get("progress")) != TYPE_INT:
			return _restore_fail("terminal %d record" % terminal)
		var template_s: String = template_v
		var template: StringName = StringName(template_s)
		if not _content.has(KIND_TERMINAL, template):
			return _restore_fail("unknown terminal %s" % template_s)
		var actor: int = rec["actor"]
		var progress: int = rec["progress"]
		var t: Dictionary = _content.get_entry(KIND_TERMINAL, template)
		var ticks: int = t["hack_ticks"]
		if progress < 0 or progress >= ticks:
			return _restore_fail("terminal %d progress" % terminal)
		if actor != EntityIds.NONE and not _actors.has_actor(actor):
			return _restore_fail("terminal %d is hacked by nobody" % terminal)
		if actor == EntityIds.NONE and progress != 0:
			return _restore_fail("terminal %d has progress with no hacker" % terminal)
		var hacked: bool = rec["hacked"]
		out[terminal] = {"template": template, "pos": PathingSystem._arr(PathingSystem._vec(rec["pos"])), "hacked": hacked, "actor": actor, "progress": progress}
	_terminals = out
	_hacks = hacks
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("TerminalSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
