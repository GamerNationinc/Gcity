## Sensors on openings (design doc §9.1; M6 spec claim 8). A sensor is content naming
## the triggers it raises an alarm on; an installed sensor watches one opening for one
## squad. Opening the watched piece (`opened`) or breaching it (`breached`) while the
## sensor is live emits `security.alarm {sensor, piece, squad, actor}` and puts a report
## of the actor on the squad's radio after the sensor's latency, as a guard's report
## would be. A spoofed sensor (claim 9's hack) stays silent; a sensor goes with its piece.
class_name SensorSystem extends SimSystem

const SYSTEM_ID: StringName = &"sensors"
const KIND_SENSOR: StringName = &"sensor"
const COMMAND_INSTALL: StringName = &"sensor.install"
const EVENT_ALARM: StringName = &"security.alarm"
const TRIGGER_OPENED: StringName = &"opened"
const TRIGGER_BREACHED: StringName = &"breached"
const TRIGGERS: Array[StringName] = [TRIGGER_OPENED, TRIGGER_BREACHED]

var _content: ContentDb
var _actors: ActorSystem
var _build: BuildSystem
var _squads: SquadSystem
var _events: EventBus
var _now: Callable = Callable()
## piece id -> {"sensor": StringName, "squad": int, "spoofed": bool}
var _sensors: Dictionary = {}
var _alarms: int = 0
## pieces removed this tick: their sensors go at this system's tick, after a breach's own
## event (which follows build.changed) has had its chance to trip them
var _gone: Array[int] = []


func _init(content: ContentDb, actors: ActorSystem, build: BuildSystem, squads: SquadSystem, events: EventBus) -> void:
	_content = content
	_actors = actors
	_build = build
	_squads = squads
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	for piece: int in _gone:
		_sensors.erase(piece)
	_gone.clear()


func snapshot() -> Dictionary:
	return {"sensors": _sensors.duplicate(true), "alarms": _alarms, "gone": _gone.duplicate()}


func attach(sim: SimRoot) -> Error:
	var err: Error = validate_content()
	if err != OK:
		return err
	err = sim.register_system(self)
	if err != OK:
		return err
	_now = sim.get_tick
	err = sim.commands().register(COMMAND_INSTALL, _on_install)
	if err != OK:
		return err
	err = _events.subscribe(BuildSystem.EVENT_OPENING, _on_opening)
	if err != OK:
		return err
	err = _events.subscribe(BuildSystem.EVENT_BREACHED, _on_breached)
	if err != OK:
		return err
	return _events.subscribe(BuildSystem.EVENT_CHANGED, _on_build_changed)


## Every trigger a sensor names is one this system raises.
func validate_content() -> Error:
	for id: StringName in _content.ids(KIND_SENSOR):
		var t: Dictionary = _content.get_entry(KIND_SENSOR, id)
		var triggers: Array = t["triggers"]
		for v: Variant in triggers:
			var trigger: String = v
			if not TRIGGERS.has(StringName(trigger)):
				push_error("SensorSystem: content rejected: sensor/%s names an unknown trigger '%s'" % [id, trigger])
				return ERR_INVALID_DATA
	return OK


# ---------------------------------------------------------------- queries and mutation

func has_sensor(piece: int) -> bool:
	return _sensors.has(piece)


func is_spoofed(piece: int) -> bool:
	if not _sensors.has(piece):
		return false
	var rec: Dictionary = _sensors[piece]
	return rec["spoofed"]


func alarm_count() -> int:
	return _alarms


## Installs a sensor on an opening for a squad (sites at claim 12; a debug command until
## then). False for an unknown sensor, a piece that is not an opening, squad 0, or a
## piece that already has one.
func install(sensor: StringName, piece: int, squad: int) -> bool:
	if not _content.has(KIND_SENSOR, sensor) or not _build.is_opening(piece) or squad <= 0 or _sensors.has(piece) or _gone.has(piece):
		return false
	_sensors[piece] = {"sensor": sensor, "squad": squad, "spoofed": false}
	return true


## Silences the sensor on a piece for good (claim 9's hack effect). False if there is none
## or it is already spoofed.
func spoof(piece: int) -> bool:
	if not _sensors.has(piece) or is_spoofed(piece):
		return false
	var rec: Dictionary = _sensors[piece]
	rec["spoofed"] = true
	return true


# ---------------------------------------------------------------- events

func _on_opening(payload: Dictionary) -> void:
	var open: bool = payload["open"]
	if open:
		var piece: int = payload["piece"]
		var actor: int = payload["actor"]
		_trip(piece, TRIGGER_OPENED, actor)


## A player's breach names its actor; a raid token's does not, and trips nothing yet
## (the base's own sensors are M8).
func _on_breached(payload: Dictionary) -> void:
	if not payload.has("actor"):
		return
	var actor: int = payload["actor"]
	var removed: Array = payload["removed"]
	for v: Variant in removed:
		var piece: int = v
		_trip(piece, TRIGGER_BREACHED, actor)


## A sensor goes with its piece, whatever removed it, at the end of the tick.
func _on_build_changed(payload: Dictionary) -> void:
	var removed: Array = payload["removed"]
	for v: Variant in removed:
		var piece: int = v
		if _sensors.has(piece):
			_gone.append(piece)


func _trip(piece: int, trigger: StringName, actor: int) -> void:
	if not _sensors.has(piece) or is_spoofed(piece) or not _actors.has_actor(actor):
		return
	var rec: Dictionary = _sensors[piece]
	var sensor: StringName = rec["sensor"]
	var t: Dictionary = _content.get_entry(KIND_SENSOR, sensor)
	var triggers: Array = t["triggers"]
	if not triggers.has(String(trigger)):
		return
	var squad: int = rec["squad"]
	var latency: int = t["radio_latency_ticks"]
	var now: int = _now.call()
	_alarms += 1
	_events.emit(EVENT_ALARM, {"sensor": sensor, "piece": piece, "squad": squad, "actor": actor})
	_squads.queue_report(squad, EntityIds.NONE, actor, BuildSystem.cell_of(_actors.position_of(actor)), latency, now)


# ---------------------------------------------------------------- commands

## {"sensor": string, "piece": int, "squad": int}
func _on_install(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 3 or typeof(payload.get("sensor")) != TYPE_STRING or typeof(payload.get("piece")) != TYPE_INT \
			or typeof(payload.get("squad")) != TYPE_INT:
		return false
	var sensor_s: String = payload["sensor"]
	var piece: int = payload["piece"]
	var squad: int = payload["squad"]
	return install(StringName(sensor_s), piece, squad)


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 3 or typeof(state.get("sensors")) != TYPE_DICTIONARY or typeof(state.get("alarms")) != TYPE_INT \
			or typeof(state.get("gone")) != TYPE_ARRAY:
		return _restore_fail("shape")
	var alarms: int = state["alarms"]
	if alarms < 0:
		return _restore_fail("negative count")
	var sensors_in: Dictionary = state["sensors"]
	var sensors: Dictionary = {}
	for k: Variant in sensors_in:
		if typeof(k) != TYPE_INT or typeof(sensors_in[k]) != TYPE_DICTIONARY:
			return _restore_fail("sensor key")
		var piece: int = k
		var rec: Dictionary = sensors_in[k]
		if rec.size() != 3 or (typeof(rec.get("sensor")) != TYPE_STRING and typeof(rec.get("sensor")) != TYPE_STRING_NAME) \
				or typeof(rec.get("squad")) != TYPE_INT or typeof(rec.get("spoofed")) != TYPE_BOOL:
			return _restore_fail("sensor %d record" % piece)
		var sensor_s: String = rec["sensor"]
		var squad: int = rec["squad"]
		var spoofed: bool = rec["spoofed"]
		if not _content.has(KIND_SENSOR, StringName(sensor_s)) or squad <= 0:
			return _restore_fail("sensor %d values" % piece)
		sensors[piece] = {"sensor": StringName(sensor_s), "squad": squad, "spoofed": spoofed}
	var gone_in: Array = state["gone"]
	var gone: Array[int] = []
	for v: Variant in gone_in:
		if typeof(v) != TYPE_INT:
			return _restore_fail("gone entry")
		var piece: int = v
		if not sensors.has(piece) or gone.has(piece):
			return _restore_fail("gone %d has no sensor" % piece)
		gone.append(piece)
	for k: Variant in sensors:
		var piece: int = k
		if not gone.has(piece) and not _build.is_opening(piece):
			return _restore_fail("sensor %d is not on an opening" % piece)
	_sensors = sensors
	_alarms = alarms
	_gone = gone
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("SensorSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
