## Stealth scoring (design doc §15.4; M6 spec claim 7). A run is the span from
## accepting a contract to turning it in, and it is scored by four counters, each
## raised by an event the sim already emits:
##
##   times_detected   a guard's awareness of the player crossed its threshold
##   alarms_raised    a guard that had seen the player got a report out on the radio
##   bodies           the player killed someone
##   traces_left      a gap still open in somebody's wall, or a terminal left un-wiped,
##                    or a body left where it fell — all read from the world, not
##                    tallied as they happen, so tidying up afterwards really does
##                    undo them
##
## All four at zero is the full stealth bonus. Partial credit is a multiplier from
## `content/payout_curve/`. "Nobody saw you" is the bar, not "nobody survived": a
## body counts even if no one witnessed it, which is what forces avoidance over
## silent takedowns.
class_name RunScoreSystem extends SimSystem

const SYSTEM_ID: StringName = &"score"
const KIND_CURVE: StringName = &"payout_curve"
const COMMAND_BEGIN: StringName = &"run.begin"
const COMMAND_END: StringName = &"run.end"
const EVENT_SCORED: StringName = &"run.scored"
## Milli-units: the multiplier a payout is scaled by.
const ONE: int = 1000

var _content: ContentDb
var _actors: ActorSystem
var _perception: PerceptionSystem
var _terminals: TerminalSystem
var _build: BuildSystem
var _events: EventBus
## actor -> {"running": bool, "detected": int, "alarms": int, "bodies": int,
##           "breaches": Array[String], "corpses": Array[int], "traces": int}
## `breaches` holds the slots the actor emptied. A slot something stands in again is
## not a trace: putting the grate back is the difference between a break-in nobody
## can see and one anybody can.
## `traces` is -1 while the run is on, because traces are read from the world rather
## than counted as they happen; ending the run freezes the reading into it.
var _runs: Dictionary = {}


func _init(content: ContentDb, actors: ActorSystem, perception: PerceptionSystem, terminals: TerminalSystem, build: BuildSystem, events: EventBus) -> void:
	_content = content
	_actors = actors
	_perception = perception
	_terminals = terminals
	_build = build
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


func snapshot() -> Dictionary:
	return {"runs": _runs.duplicate(true)}


func attach(sim: SimRoot) -> Error:
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_BEGIN, _on_begin, true)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_END, _on_end, true)
	if err != OK:
		return err
	err = _events.subscribe(PerceptionSystem.EVENT_ALERTED, _on_alerted)
	if err != OK:
		return err
	err = _events.subscribe(SquadSystem.EVENT_REPORT, _on_report)
	if err != OK:
		return err
	err = _events.subscribe(CombatSystem.EVENT_HIT, _on_hit)
	if err != OK:
		return err
	return _events.subscribe(BuildSystem.EVENT_CHANGED, _on_build_changed)


# ---------------------------------------------------------------- queries

## True when the actor has a run on record, whether it is still on or already scored.
## The device needs the difference between "no run" and "a run that ended at zero",
## which the counters alone cannot tell it.
func has_run(actor: int) -> bool:
	return not _record(actor).is_empty()


func is_running(actor: int) -> bool:
	var rec: Dictionary = _record(actor)
	if rec.is_empty():
		return false
	return rec["running"]


func times_detected(actor: int) -> int:
	return _counter(actor, "detected")


func alarms_raised(actor: int) -> int:
	return _counter(actor, "alarms")


func bodies(actor: int) -> int:
	return _counter(actor, "bodies")


## Traces are read now, not counted as they happen: a breached piece, a terminal left
## open, a body still lying where it fell. Wiping a terminal takes its trace away.
func traces_left(actor: int) -> int:
	var rec: Dictionary = _record(actor)
	if rec.is_empty():
		return 0
	var frozen: int = rec["traces"]
	if frozen >= 0:
		return frozen
	var breaches: int = 0
	for v: Variant in rec["breaches"]:
		var slot: String = v
		if _build.slot_is_empty(slot):
			breaches += 1
	var bodies_left: int = 0
	for v: Variant in rec["corpses"]:
		var id: int = v
		if _actors.has_actor(id) and not _actors.is_alive(id):
			bodies_left += 1
	return breaches + _terminals.traces() + bodies_left


## The four counters of the actor's run, in the design doc's order.
func counters(actor: int) -> Array[int]:
	return [times_detected(actor), alarms_raised(actor), bodies(actor), traces_left(actor)] as Array[int]


func is_clean(actor: int) -> bool:
	for n: int in counters(actor):
		if n != 0:
			return false
	return true


## The payout multiplier in milli-units under a curve: the clean bonus when all four
## counters are zero, otherwise the base less each counter's penalty, never below the
## curve's floor.
func multiplier(actor: int, curve: StringName) -> int:
	if not _content.has(KIND_CURVE, curve):
		return ONE
	var c: Dictionary = _content.get_entry(KIND_CURVE, curve)
	var counts: Array[int] = counters(actor)
	var clean: bool = true
	for n: int in counts:
		if n != 0:
			clean = false
	if clean:
		var bonus: int = c["clean_bonus"]
		return bonus
	var base: int = c["base"]
	var per_detection: int = c["per_detection"]
	var per_alarm: int = c["per_alarm"]
	var per_body: int = c["per_body"]
	var per_trace: int = c["per_trace"]
	var value: int = base - counts[0] * per_detection - counts[1] * per_alarm - counts[2] * per_body - counts[3] * per_trace
	var floor_value: int = c["floor"]
	return maxi(value, floor_value)


func _record(actor: int) -> Dictionary:
	var stored: Variant = _runs.get(actor)
	if typeof(stored) != TYPE_DICTIONARY:
		return {}
	return stored


func _counter(actor: int, key: String) -> int:
	var rec: Dictionary = _record(actor)
	if rec.is_empty():
		return 0
	return rec[key]


# ---------------------------------------------------------------- events

func _on_alerted(payload: Dictionary) -> void:
	var contact: int = payload["contact"]
	var rec: Dictionary = _record(contact)
	if rec.is_empty() or not rec["running"]:
		return
	rec["detected"] = rec["detected"] + 1


## An alarm is a report about the player from a guard that had seen them: a radio
## call about a noise nobody has laid eyes on is not an alarm.
func _on_report(payload: Dictionary) -> void:
	var contact: int = payload["contact"]
	var reporter: int = payload["reporter"]
	var rec: Dictionary = _record(contact)
	if rec.is_empty() or not rec["running"]:
		return
	if not _perception.is_alerted(reporter, contact):
		return
	rec["alarms"] = rec["alarms"] + 1


func _on_hit(payload: Dictionary) -> void:
	var killed: bool = payload["killed"]
	if not killed:
		return
	var shooter: int = payload["shooter"]
	var rec: Dictionary = _record(shooter)
	if rec.is_empty() or not rec["running"]:
		return
	rec["bodies"] = rec["bodies"] + 1
	var target: int = payload["target"]
	var corpses: Array = rec["corpses"]
	if not corpses.has(target):
		corpses.append(target)


## A piece removed while a run is on is a trace: a cut grate, a breached wall. The
## builder is named on the event, so a guard's own work is not the player's trace.
func _on_build_changed(payload: Dictionary) -> void:
	var removed: Array = payload["removed"]
	if removed.is_empty():
		return
	var actor: int = payload["actor"]
	var rec: Dictionary = _record(actor)
	if rec.is_empty() or not rec["running"]:
		return
	var removed_at: Array = payload["removed_at"]
	var slots: Array = rec["breaches"]
	for v: Variant in removed_at:
		var slot: String = v
		if not slot.is_empty() and not slots.has(slot):
			slots.append(slot)


# ---------------------------------------------------------------- commands

## {"actor": int}: start a run, clearing the counters. Pause-safe: accepting a
## contract from the device starts it.
func _on_begin(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 1 or typeof(payload.get("actor")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	if not _actors.is_alive(actor) or is_running(actor):
		return false
	_runs[actor] = {"running": true, "detected": 0, "alarms": 0, "bodies": 0, "breaches": [] as Array[String], "corpses": [] as Array[int], "traces": -1}
	return true


## {"actor": int}: end a run, freezing its counters and emitting the score. The
## record stays so the payout can read it.
func _on_end(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 1 or typeof(payload.get("actor")) != TYPE_INT:
		return false
	var actor: int = payload["actor"]
	if not is_running(actor):
		return false
	var counts: Array[int] = counters(actor)
	var rec: Dictionary = _runs[actor]
	rec["running"] = false
	# the traces are fixed at the end: what is still open is what was left behind, and
	# tidying the site afterwards does not un-leave it
	rec["traces"] = counts[3]
	_events.emit(EVENT_SCORED, {"actor": actor, "detected": counts[0], "alarms": counts[1], "bodies": counts[2], "traces": counts[3], "clean": counts[0] == 0 and counts[1] == 0 and counts[2] == 0 and counts[3] == 0})
	return true


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 1 or typeof(state.get("runs")) != TYPE_DICTIONARY:
		return _restore_fail("shape")
	var in_all: Dictionary = state["runs"]
	var out: Dictionary = {}
	for key: Variant in in_all:
		if typeof(key) != TYPE_INT or typeof(in_all[key]) != TYPE_DICTIONARY:
			return _restore_fail("actor key")
		var actor: int = key
		if not _actors.has_actor(actor):
			return _restore_fail("actor %d is not an actor" % actor)
		var rec: Dictionary = in_all[key]
		if rec.size() != 7 or typeof(rec.get("running")) != TYPE_BOOL or typeof(rec.get("corpses")) != TYPE_ARRAY \
				or typeof(rec.get("breaches")) != TYPE_ARRAY:
			return _restore_fail("actor %d record" % actor)
		var counts: Dictionary = {}
		for field: String in ["detected", "alarms", "bodies"]:
			if typeof(rec.get(field)) != TYPE_INT:
				return _restore_fail("actor %d %s" % [actor, field])
			var n: int = rec[field]
			if n < 0:
				return _restore_fail("actor %d %s is negative" % [actor, field])
			counts[field] = n
		var corpses: Array[int] = []
		for v: Variant in rec["corpses"]:
			if typeof(v) != TYPE_INT:
				return _restore_fail("actor %d corpse id" % actor)
			var id: int = v
			if not _actors.has_actor(id):
				return _restore_fail("actor %d names a body that is not an actor" % actor)
			corpses.append(id)
		if typeof(rec.get("traces")) != TYPE_INT:
			return _restore_fail("actor %d traces" % actor)
		var traces: int = rec["traces"]
		var running: bool = rec["running"]
		if traces < -1 or (running and traces != -1) or (not running and traces < 0):
			return _restore_fail("actor %d traces %d does not match a %s run" % [actor, traces, "live" if running else "finished"])
		var breaches: Array[String] = []
		for v: Variant in rec["breaches"]:
			if typeof(v) != TYPE_STRING:
				return _restore_fail("actor %d breached slot" % actor)
			var slot: String = v
			if slot.is_empty() or breaches.has(slot):
				return _restore_fail("actor %d names an empty or repeated slot" % actor)
			breaches.append(slot)
		out[actor] = {"running": running, "detected": counts["detected"], "alarms": counts["alarms"], "bodies": counts["bodies"], "breaches": breaches, "corpses": corpses, "traces": traces}
	_runs = out
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("RunScoreSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
