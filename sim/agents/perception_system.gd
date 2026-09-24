## Perception is a process, not a check (design doc §14.1; M4 spec claims 1–5). An
## agent is an actor with an `agent_profile`; every tick it gains integer awareness of
## each contact it can see (a cone, a range and an integer line walk over the build
## grid) and loses it while it cannot, hears shots as `combat.fire` events within the
## smaller of its hearing range and the shot's loudness, keeps a last-known position
## for a while, and emits `perception.alerted` once each time awareness crosses its
## profile's threshold. Facing is integer degrees about y: 0 looks along +x, 90 along
## +z. Owns `agent.spawn` and `agent.set_profile` (debug-class, G1 debt item 4).
class_name PerceptionSystem extends SimSystem

const SYSTEM_ID: StringName = &"perception"
const KIND_AGENT: StringName = &"agent_profile"
const KIND_PERCEPTION: StringName = &"perception_profile"
const KIND_ROUTE: StringName = &"patrol_route"
const COMMAND_SPAWN: StringName = &"agent.spawn"
const COMMAND_SET_PROFILE: StringName = &"agent.set_profile"
const EVENT_ALERTED: StringName = &"perception.alerted"
const STAT_NOISE: StringName = &"noise"
const AWARENESS_MAX: int = 1_000_000
## The longest line walk accepted, in cells; sight ranges are at most 100 m.
const MAX_WALK: int = 4096
## cos(a) × 1000 for a in whole degrees 0..180: integer trigonometry, no float in the sim.
const COS_MILLI: Array[int] = [1000, 1000, 999, 999, 998, 996, 995, 993, 990, 988, 985, 982, 978, 974, 970, 966, 961, 956, 951, 946, 940, 934, 927, 921, 914, 906, 899, 891, 883, 875, 866, 857, 848, 839, 829, 819, 809, 799, 788, 777, 766, 755, 743, 731, 719, 707, 695, 682, 669, 656, 643, 629, 616, 602, 588, 574, 559, 545, 530, 515, 500, 485, 469, 454, 438, 423, 407, 391, 375, 358, 342, 326, 309, 292, 276, 259, 242, 225, 208, 191, 174, 156, 139, 122, 105, 87, 70, 52, 35, 17, 0, -17, -35, -52, -70, -87, -105, -122, -139, -156, -174, -191, -208, -225, -242, -259, -276, -292, -309, -326, -342, -358, -375, -391, -407, -423, -438, -454, -469, -485, -500, -515, -530, -545, -559, -574, -588, -602, -616, -629, -643, -656, -669, -682, -695, -707, -719, -731, -743, -755, -766, -777, -788, -799, -809, -819, -829, -839, -848, -857, -866, -875, -883, -891, -899, -906, -914, -921, -927, -934, -940, -946, -951, -956, -961, -966, -970, -974, -978, -982, -985, -988, -990, -993, -995, -996, -998, -999, -999, -1000, -1000]

var _content: ContentDb
var _stats: StatResolver
var _actors: ActorSystem
var _build: BuildSystem
var _events: EventBus
## actor id -> {"profile": StringName, "facing": int (degrees), "squad": int, "route": String,
## "faction": String}. Faction is an owner tag, or empty for an agent that answers to no
## faction but its squad (M7 spec claim 12).
var _agents: Dictionary = {}
## observer -> contact -> {"aw": int, "last": [x, y, z] or [], "memory": int, "alerted": bool}
var _contacts: Dictionary = {}
## actor id -> [x, y, z] at the end of the previous tick, for the speed term.
var _last_pos: Dictionary = {}
var _alerts: int = 0
## observer -> contact -> true for shots heard since the last tick. Not state: it is
## always empty when a snapshot is taken.
var _heard: Dictionary = {}
## observer -> contact -> bool: what each agent saw on its last tick. Derived, not
## state: rebuilt every tick before any later system reads it (`sees`), so the line
## walk runs once per pair per tick however many systems ask.
var _visible: Dictionary = {}
var _faction_regex: RegEx = RegEx.create_from_string(LandSystem.OWNER_PATTERN)


func _init(content: ContentDb, stats: StatResolver, actors: ActorSystem, build: BuildSystem, events: EventBus) -> void:
	_content = content
	_stats = stats
	_actors = actors
	_build = build
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func snapshot() -> Dictionary:
	return {"agents": _agents.duplicate(true), "contacts": _contacts.duplicate(true), "last_pos": _last_pos.duplicate(true), "alerts": _alerts}


func attach(sim: SimRoot) -> Error:
	var err: Error = validate_content()
	if err != OK:
		return err
	err = sim.register_system(self)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_SPAWN, _on_spawn)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_SET_PROFILE, _on_set_profile)
	if err != OK:
		return err
	err = _events.subscribe(CombatSystem.EVENT_FIRE, _on_fire)
	if err != OK:
		return err
	return _events.subscribe(ActorSystem.EVENT_REMOVED, _on_removed)


## A removed actor is forgotten from both sides: it is no longer an agent watching
## anyone, and nobody still remembers it as a contact.
func _on_removed(payload: Dictionary) -> void:
	var actor: int = payload["actor"]
	_agents.erase(actor)
	_last_pos.erase(actor)
	for table: Dictionary in [_contacts, _heard, _visible]:
		table.erase(actor)
		for key: Variant in table:
			var inner: Dictionary = table[key]
			inner.erase(actor)


## Every agent profile binds profiles that exist, and the noise stat is registered.
func validate_content() -> Error:
	if not _stats.has_stat(STAT_NOISE):
		return _content_fail("no stat '%s' (content/stat/noise.json)" % STAT_NOISE)
	for id: StringName in _content.ids(KIND_AGENT):
		var t: Dictionary = _content.get_entry(KIND_AGENT, id)
		var combat_s: String = t["combat_profile"]
		if not _content.has(ActorSystem.KIND_PROFILE, StringName(combat_s)):
			return _content_fail("agent_profile/%s: no combat_profile/%s" % [id, combat_s])
		var perception_s: String = t["perception_profile"]
		if not _content.has(KIND_PERCEPTION, StringName(perception_s)):
			return _content_fail("agent_profile/%s: no perception_profile/%s" % [id, perception_s])
	return OK


func _content_fail(reason: String) -> Error:
	push_error("PerceptionSystem: %s" % reason)
	return ERR_INVALID_DATA


# ---------------------------------------------------------------- queries

func is_agent(actor: int) -> bool:
	return _agents.has(actor)


func agent_ids() -> Array[int]:
	var out: Array[int] = []
	for key: Variant in _agents:
		var id: int = key
		out.append(id)
	out.sort()
	return out


func profile_of(actor: int) -> StringName:
	if not _agents.has(actor):
		return &""
	var rec: Dictionary = _agents[actor]
	return rec["profile"]


func facing_of(actor: int) -> int:
	if not _agents.has(actor):
		return 0
	var rec: Dictionary = _agents[actor]
	return rec["facing"]


func route_of(actor: int) -> String:
	if not _agents.has(actor):
		return ""
	var rec: Dictionary = _agents[actor]
	return rec["route"]


func squad_of(actor: int) -> int:
	if not _agents.has(actor):
		return 0
	var rec: Dictionary = _agents[actor]
	return rec["squad"]


## The perception profile entry of an agent, or an empty dictionary.
func perception_of(actor: int) -> Dictionary:
	if not _agents.has(actor):
		return {}
	var rec: Dictionary = _agents[actor]
	var profile: StringName = rec["profile"]
	var agent: Dictionary = _content.get_entry(KIND_AGENT, profile)
	var perception_s: String = agent["perception_profile"]
	return _content.get_entry(KIND_PERCEPTION, StringName(perception_s))


func awareness_of(observer: int, contact: int) -> int:
	var rec: Dictionary = _contact_record(observer, contact)
	if rec.is_empty():
		return 0
	return rec["aw"]


func is_alerted(observer: int, contact: int) -> bool:
	var rec: Dictionary = _contact_record(observer, contact)
	if rec.is_empty():
		return false
	return rec["alerted"]


## Ticks of memory left for a contact, 0 when there is none.
func memory_of(observer: int, contact: int) -> int:
	var rec: Dictionary = _contact_record(observer, contact)
	if rec.is_empty():
		return 0
	return rec["memory"]


## The last-known position of a contact, or Vector3i.ZERO with `has_last_known` false.
func has_last_known(observer: int, contact: int) -> bool:
	var rec: Dictionary = _contact_record(observer, contact)
	if rec.is_empty():
		return false
	var last: Array = rec["last"]
	return not last.is_empty()


func last_known(observer: int, contact: int) -> Vector3i:
	if not has_last_known(observer, contact):
		return Vector3i.ZERO
	var rec: Dictionary = _contact_record(observer, contact)
	var last: Array = rec["last"]
	var x: int = last[0]
	var y: int = last[1]
	var z: int = last[2]
	return Vector3i(x, y, z)


func alert_count() -> int:
	return _alerts


func _contact_record(observer: int, contact: int) -> Dictionary:
	var stored: Variant = _contacts.get(observer)
	if typeof(stored) != TYPE_DICTIONARY:
		return {}
	var table: Dictionary = stored
	var rec_v: Variant = table.get(contact)
	if typeof(rec_v) != TYPE_DICTIONARY:
		return {}
	return rec_v


# ---------------------------------------------------------------- sight

## What the observer saw on its last perception tick (the cached answer of
## `can_see`, for the systems that tick after this one). False before the first tick.
func sees(observer: int, contact: int) -> bool:
	var stored: Variant = _visible.get(observer)
	if typeof(stored) != TYPE_DICTIONARY:
		return false
	var table: Dictionary = stored
	return table.get(contact, false)


## Whether `observer` (an agent) sees `contact` now: inside its range and cone, with a
## clear line over the build grid. Computed live; `sees` is the per-tick cache.
func can_see(observer: int, contact: int) -> bool:
	var p: Dictionary = perception_of(observer)
	if p.is_empty() or not _actors.has_actor(contact) or observer == contact:
		return false
	var a: Vector3i = _actors.position_of(observer)
	var b: Vector3i = _actors.position_of(contact)
	var d: Vector3i = b - a
	var range_mm: int = p["sight_range_mm"]
	if distance_mm(a, b) > range_mm:
		return false
	var fov: int = p["fov_deg"]
	if not in_cone(facing_of(observer), Vector2i(d.x, d.z), fov):
		return false
	return line_of_sight(a, b)


## The sight check combat runs before a shot (spec claim 7): an agent must see its
## target (cone, range, line); any other actor needs only a clear line.
func can_target(shooter: int, target: int) -> bool:
	if is_agent(shooter):
		return can_see(shooter, target)
	if shooter == target or not _actors.has_actor(shooter) or not _actors.has_actor(target):
		return false
	return line_of_sight(_actors.position_of(shooter), _actors.position_of(target))


## Whether the segment between two positions crosses no solid face and enters no solid
## cell. Walked from both ends and accepted only if both walks are clear, so the answer
## is the same in both directions whatever the tie-breaking at corners.
func line_of_sight(a: Vector3i, b: Vector3i) -> bool:
	return _walk_clear(a, b) and _walk_clear(b, a)


## Whether `v` (the observer-to-contact offset on the ground plane) lies within
## `fov_deg` about `facing_deg`. A zero offset is inside every cone.
static func in_cone(facing_deg: int, v: Vector2i, fov_deg: int) -> bool:
	var v2: int = v.x * v.x + v.y * v.y
	if v2 == 0:
		return true
	var f: Vector2i = Vector2i(cos_milli(facing_deg), sin_milli(facing_deg))
	var f2: int = f.x * f.x + f.y * f.y
	var dot: int = f.x * v.x + f.y * v.y
	var cos_theta: int = dot * 1000 / isqrt(f2 * v2)
	return cos_theta >= cos_milli(fov_deg / 2)


static func cos_milli(deg: int) -> int:
	var a: int = posmod(deg, 360)
	if a > 180:
		a = 360 - a
	return COS_MILLI[a]


static func sin_milli(deg: int) -> int:
	return cos_milli(deg - 90)


static func distance_mm(a: Vector3i, b: Vector3i) -> int:
	var dx: int = a.x - b.x
	var dy: int = a.y - b.y
	var dz: int = a.z - b.z
	return isqrt(dx * dx + dy * dy + dz * dz)


static func isqrt(n: int) -> int:
	if n <= 0:
		return 0
	var x: int = int(sqrt(float(n)))
	while x * x > n:
		x -= 1
	while (x + 1) * (x + 1) <= n:
		x += 1
	return x


## Awareness gained in one tick of sight at `dist_mm` from a contact that moved
## `moved_mm` since the previous tick: full inside half the range, linear to zero at
## the range, plus the movement term (spec claim 2).
static func exposure_gain(p: Dictionary, dist_mm: int, moved_mm: int) -> int:
	var range_mm: int = p["sight_range_mm"]
	var gain: int = p["gain_per_tick"]
	var speed_gain: int = p["speed_gain_per_mm_per_tick"]
	var base: int = gain
	if dist_mm * 2 > range_mm:
		base = gain * maxi(range_mm - dist_mm, 0) * 2 / range_mm
	return mini(base + moved_mm * speed_gain, AWARENESS_MAX)


## An integer grid walk from a toward b (Amanatides–Woo with exact rational
## comparisons). Every face crossed must carry no impassable piece and every cell
## entered must hold no cell piece.
func _walk_clear(a: Vector3i, b: Vector3i) -> bool:
	var cell: Vector3i = BuildSystem.cell_of(a)
	var target: Vector3i = BuildSystem.cell_of(b)
	var d: Vector3i = b - a
	var step: Vector3i = Vector3i(signi(d.x), signi(d.y), signi(d.z))
	var den: Vector3i = Vector3i(absi(d.x), absi(d.y), absi(d.z))
	var num: Vector3i = Vector3i.ZERO
	for axis: int in 3:
		if step[axis] > 0:
			num[axis] = (cell[axis] + 1) * BuildSystem.CELL - a[axis]
		elif step[axis] < 0:
			num[axis] = a[axis] - cell[axis] * BuildSystem.CELL
	var walked: int = 0
	while cell != target:
		walked += 1
		if walked > MAX_WALK:
			return false
		var best: int = -1
		for axis: int in 3:
			if den[axis] == 0:
				continue
			if best < 0 or num[axis] * den[best] < num[best] * den[axis]:
				best = axis
		if best < 0:
			return false
		var next: Vector3i = cell
		next[best] += step[best]
		var facing: String = ("p" if step[best] > 0 else "n") + BuildSystem.AXES[best]
		var piece: int = _build.face_piece_at(BuildSystem.face_key(cell, facing))
		if piece != EntityIds.NONE:
			var kind: Dictionary = _build.kind_data(piece)
			var passable: bool = kind["passable"]
			if not passable:
				return false
		if _build.cell_piece_at(next) != EntityIds.NONE:
			return false
		cell = next
		num[best] += BuildSystem.CELL
	return true


# ---------------------------------------------------------------- the tick

func tick(sim: SimRoot) -> void:
	var actors: Array[int] = _actors.actor_ids()
	_visible.clear()
	for observer: int in agent_ids():
		if not _actors.is_alive(observer):
			_contacts.erase(observer)
			continue
		var p: Dictionary = perception_of(observer)
		var stored: Variant = _contacts.get(observer)
		var table: Dictionary = stored if typeof(stored) == TYPE_DICTIONARY else {}
		var heard_v: Variant = _heard.get(observer)
		var heard: Dictionary = heard_v if typeof(heard_v) == TYPE_DICTIONARY else {}
		var seen: Dictionary = {}
		_visible[observer] = seen
		for contact: int in actors:
			if contact == observer:
				continue
			if not _actors.is_alive(contact) or same_side(observer, contact):
				table.erase(contact)
				continue
			var rec_v: Variant = table.get(contact)
			var rec: Dictionary = rec_v if typeof(rec_v) == TYPE_DICTIONARY else {"aw": 0, "last": [] as Array[int], "memory": 0, "alerted": false}
			var aw: int = rec["aw"]
			var memory: int = rec["memory"]
			var visible: bool = can_see(observer, contact)
			seen[contact] = visible
			if visible:
				var pos: Vector3i = _actors.position_of(contact)
				var moved: int = 0
				var prev_v: Variant = _last_pos.get(contact)
				if typeof(prev_v) == TYPE_ARRAY:
					var prev: Array = prev_v
					var px: int = prev[0]
					var py: int = prev[1]
					var pz: int = prev[2]
					moved = distance_mm(Vector3i(px, py, pz), pos)
				aw = mini(aw + exposure_gain(p, distance_mm(_actors.position_of(observer), pos), moved), AWARENESS_MAX)
				rec["last"] = [pos.x, pos.y, pos.z] as Array[int]
				memory = p["memory_ticks"]
			elif not heard.has(contact):
				var decay: int = p["decay_per_tick"]
				aw = maxi(aw - decay, 0)
				if memory > 0:
					memory -= 1
				if memory == 0:
					rec["last"] = [] as Array[int]
			rec["aw"] = aw
			rec["memory"] = memory
			var threshold: int = p["alert_threshold"]
			var alerted: bool = rec["alerted"]
			if aw >= threshold:
				if not alerted:
					rec["alerted"] = true
					_alerts += 1
					_events.emit(EVENT_ALERTED, {"observer": observer, "contact": contact, "tick": sim.get_tick()})
			else:
				rec["alerted"] = false
			if aw == 0 and memory == 0:
				table.erase(contact)
			else:
				table[contact] = rec
		if table.is_empty():
			_contacts.erase(observer)
		else:
			_contacts[observer] = table
	_heard.clear()
	_last_pos.clear()
	for actor: int in actors:
		if _actors.is_alive(actor):
			var pos: Vector3i = _actors.position_of(actor)
			_last_pos[actor] = [pos.x, pos.y, pos.z] as Array[int]


## Whether two actors are on the same side: the same squad, or agents of the same
## faction. Two hydrated squads of one faction meeting on a road are colleagues, not a
## contact each (M7 spec claim 12); anyone with no faction — a player — is a contact
## to everyone who is not in their squad.
func same_side(a: int, b: int) -> bool:
	if not _agents.has(a) or not _agents.has(b):
		return false
	var squad: int = squad_of(a)
	if squad > 0 and squad == squad_of(b):
		return true
	var faction: String = faction_of(a)
	return not faction.is_empty() and faction == faction_of(b)


func faction_of(agent: int) -> String:
	if not _agents.has(agent):
		return ""
	var rec: Dictionary = _agents[agent]
	return rec["faction"]


## A shot is heard by every agent within the smaller of its hearing range and the
## weapon's resolved `noise`: awareness of the shooter rises by `hearing_gain` and the
## shot's position becomes the last-known position (spec claim 4).
func _on_fire(payload: Dictionary) -> void:
	var shooter: int = payload["shooter"]
	var weapon: int = payload["weapon"]
	if not _actors.is_alive(shooter):
		return
	var loudness: int = _stats.resolve(weapon, STAT_NOISE)
	var origin: Vector3i = _actors.position_of(shooter)
	for observer: int in agent_ids():
		if observer == shooter or not _actors.is_alive(observer) or same_side(observer, shooter):
			continue
		var p: Dictionary = perception_of(observer)
		var hearing: int = p["hearing_range_mm"]
		if distance_mm(_actors.position_of(observer), origin) > mini(hearing, loudness):
			continue
		var stored: Variant = _contacts.get(observer)
		var table: Dictionary = stored if typeof(stored) == TYPE_DICTIONARY else {}
		var rec_v: Variant = table.get(shooter)
		var rec: Dictionary = rec_v if typeof(rec_v) == TYPE_DICTIONARY else {"aw": 0, "last": [] as Array[int], "memory": 0, "alerted": false}
		var aw: int = rec["aw"]
		var gain: int = p["hearing_gain"]
		rec["aw"] = mini(aw + gain, AWARENESS_MAX)
		rec["last"] = [origin.x, origin.y, origin.z] as Array[int]
		rec["memory"] = p["memory_ticks"]
		table[shooter] = rec
		_contacts[observer] = table
		var heard_v: Variant = _heard.get(observer)
		var heard: Dictionary = heard_v if typeof(heard_v) == TYPE_DICTIONARY else {}
		heard[shooter] = true
		_heard[observer] = heard


# ---------------------------------------------------------------- reports

## A squad report reaches this agent (spec claim 11): it learns the contact's
## position as last known, keeps it for its memory, and rises to its own alert
## threshold and is alerted at once (the event fires now, with `tick_now`). Returns
## false when the agent already knew as much, or is not an agent, or the contact is
## not an actor.
func receive_report(agent: int, contact: int, position: Vector3i, tick_now: int) -> bool:
	if not _agents.has(agent) or not _actors.has_actor(contact) or agent == contact:
		return false
	var p: Dictionary = perception_of(agent)
	var stored: Variant = _contacts.get(agent)
	var table: Dictionary = stored if typeof(stored) == TYPE_DICTIONARY else {}
	var rec_v: Variant = table.get(contact)
	var rec: Dictionary = rec_v if typeof(rec_v) == TYPE_DICTIONARY else {"aw": 0, "last": [] as Array[int], "memory": 0, "alerted": false}
	var aw: int = rec["aw"]
	var threshold: int = p["alert_threshold"]
	var already: bool = rec["alerted"]
	rec["aw"] = maxi(aw, threshold)
	rec["last"] = [position.x, position.y, position.z] as Array[int]
	rec["memory"] = p["memory_ticks"]
	rec["alerted"] = true
	table[contact] = rec
	_contacts[agent] = table
	var heard_v: Variant = _heard.get(agent)
	var heard: Dictionary = heard_v if typeof(heard_v) == TYPE_DICTIONARY else {}
	heard[contact] = true
	_heard[agent] = heard
	if already:
		return false
	_alerts += 1
	_events.emit(EVENT_ALERTED, {"observer": agent, "contact": contact, "tick": tick_now})
	return true


# ---------------------------------------------------------------- mutation

## Spawns an actor of the profile's combat profile at the centre of `cell` on the
## ground and registers it as an agent. Returns its id, or 0 with an error.
func spawn(profile: StringName, cell: Vector3i, facing: int, squad: int, route: String, faction: String = "") -> int:
	if not _content.has(KIND_AGENT, profile):
		push_error("PerceptionSystem: no agent_profile/%s" % profile)
		return EntityIds.NONE
	if absi(cell.x) > BuildSystem.MAX_CELL or absi(cell.y) > BuildSystem.MAX_CELL or absi(cell.z) > BuildSystem.MAX_CELL:
		push_error("PerceptionSystem: cell out of range")
		return EntityIds.NONE
	if facing < 0 or facing > 359 or squad < 0:
		push_error("PerceptionSystem: facing must be 0..359 and squad >= 0")
		return EntityIds.NONE
	if not route.is_empty() and not _content.has(KIND_ROUTE, StringName(route)):
		push_error("PerceptionSystem: no patrol_route/%s" % route)
		return EntityIds.NONE
	var t: Dictionary = _content.get_entry(KIND_AGENT, profile)
	var combat_s: String = t["combat_profile"]
	var actor: int = _actors.spawn(StringName(combat_s), 0)
	if actor == EntityIds.NONE:
		return EntityIds.NONE
	var c: int = BuildSystem.CELL
	var err: Error = _actors.set_position(actor, Vector3i(cell.x * c + c / 2, cell.y * c, cell.z * c + c / 2))
	assert(err == OK, "a cell within MAX_CELL is within MAX_COORD")
	_agents[actor] = {"profile": profile, "facing": facing, "squad": squad, "route": route, "faction": faction}
	return actor


## Turns an agent: movement faces the way it walks (spec claim 9); stances turn it
## toward what it does. Degrees 0..359, 0 along +x, 90 along +z.
func set_facing(actor: int, facing: int) -> bool:
	if not _agents.has(actor) or facing < 0 or facing > 359:
		return false
	var rec: Dictionary = _agents[actor]
	rec["facing"] = facing
	return true


## Swaps a live agent's profile. The actor's combat profile is fixed at spawn (its
## health graph is shaped by it); both M4 guard profiles share one.
func set_profile(actor: int, profile: StringName) -> bool:
	if not _agents.has(actor) or not _content.has(KIND_AGENT, profile):
		return false
	var rec: Dictionary = _agents[actor]
	rec["profile"] = profile
	return true


## {"profile": string, "cell": [x, y, z], "facing": int, "squad": int, "route": string}
func _on_spawn(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 5 or typeof(payload.get("profile")) != TYPE_STRING or typeof(payload.get("cell")) != TYPE_ARRAY \
			or typeof(payload.get("facing")) != TYPE_INT or typeof(payload.get("squad")) != TYPE_INT or typeof(payload.get("route")) != TYPE_STRING:
		return false
	var cell_a: Array = payload["cell"]
	if cell_a.size() != 3:
		return false
	for v: Variant in cell_a:
		if typeof(v) != TYPE_INT:
			return false
	var x: int = cell_a[0]
	var y: int = cell_a[1]
	var z: int = cell_a[2]
	var profile_s: String = payload["profile"]
	var facing: int = payload["facing"]
	var squad: int = payload["squad"]
	var route: String = payload["route"]
	if not _content.has(KIND_AGENT, StringName(profile_s)) or facing < 0 or facing > 359 or squad < 0:
		return false
	if absi(x) > BuildSystem.MAX_CELL or absi(y) > BuildSystem.MAX_CELL or absi(z) > BuildSystem.MAX_CELL:
		return false
	if not route.is_empty() and not _content.has(KIND_ROUTE, StringName(route)):
		return false
	return spawn(StringName(profile_s), Vector3i(x, y, z), facing, squad, route) != EntityIds.NONE


## {"agent": int, "profile": string}
func _on_set_profile(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("agent")) != TYPE_INT or typeof(payload.get("profile")) != TYPE_STRING:
		return false
	var actor: int = payload["agent"]
	var profile_s: String = payload["profile"]
	return set_profile(actor, StringName(profile_s))


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 4 or typeof(state.get("agents")) != TYPE_DICTIONARY or typeof(state.get("contacts")) != TYPE_DICTIONARY \
			or typeof(state.get("last_pos")) != TYPE_DICTIONARY or typeof(state.get("alerts")) != TYPE_INT:
		return _restore_fail("shape")
	var alerts: int = state["alerts"]
	if alerts < 0:
		return _restore_fail("negative alert count")
	var agents_in: Dictionary = state["agents"]
	var agents: Dictionary = {}
	for key: Variant in agents_in:
		if typeof(key) != TYPE_INT or typeof(agents_in[key]) != TYPE_DICTIONARY:
			return _restore_fail("agent key")
		var id: int = key
		var rec: Dictionary = agents_in[key]
		if not _actors.has_actor(id):
			return _restore_fail("agent %d is not an actor" % id)
		if rec.size() != 5 or typeof(rec.get("profile")) != TYPE_STRING_NAME and typeof(rec.get("profile")) != TYPE_STRING \
				or typeof(rec.get("facing")) != TYPE_INT or typeof(rec.get("squad")) != TYPE_INT or typeof(rec.get("route")) != TYPE_STRING \
				or typeof(rec.get("faction")) != TYPE_STRING:
			return _restore_fail("agent %d record" % id)
		var profile_s: String = rec["profile"]
		var facing: int = rec["facing"]
		var squad: int = rec["squad"]
		var route: String = rec["route"]
		if not _content.has(KIND_AGENT, StringName(profile_s)) or facing < 0 or facing > 359 or squad < 0:
			return _restore_fail("agent %d values" % id)
		if not route.is_empty() and not _content.has(KIND_ROUTE, StringName(route)):
			return _restore_fail("agent %d route" % id)
		var faction: String = rec["faction"]
		if not faction.is_empty() and not _faction_regex.search(faction):
			return _restore_fail("agent %d faction" % id)
		agents[id] = {"profile": StringName(profile_s), "facing": facing, "squad": squad, "route": route, "faction": faction}
	var contacts_in: Dictionary = state["contacts"]
	var contacts: Dictionary = {}
	for key: Variant in contacts_in:
		if typeof(key) != TYPE_INT or typeof(contacts_in[key]) != TYPE_DICTIONARY:
			return _restore_fail("observer key")
		var observer: int = key
		if not agents.has(observer):
			return _restore_fail("observer %d is not an agent" % observer)
		var table_in: Dictionary = contacts_in[key]
		var table: Dictionary = {}
		for ckey: Variant in table_in:
			if typeof(ckey) != TYPE_INT or typeof(table_in[ckey]) != TYPE_DICTIONARY:
				return _restore_fail("contact key")
			var contact: int = ckey
			if not _actors.has_actor(contact) or contact == observer:
				return _restore_fail("contact %d" % contact)
			var rec: Dictionary = table_in[ckey]
			if rec.size() != 4 or typeof(rec.get("aw")) != TYPE_INT or typeof(rec.get("last")) != TYPE_ARRAY \
					or typeof(rec.get("memory")) != TYPE_INT or typeof(rec.get("alerted")) != TYPE_BOOL:
				return _restore_fail("contact record")
			var aw: int = rec["aw"]
			var memory: int = rec["memory"]
			var last_in: Array = rec["last"]
			if aw < 0 or aw > AWARENESS_MAX or memory < 0 or (last_in.size() != 0 and last_in.size() != 3):
				return _restore_fail("contact values")
			var last: Array[int] = []
			for v: Variant in last_in:
				if typeof(v) != TYPE_INT:
					return _restore_fail("contact position")
				var coord: int = v
				last.append(coord)
			var alerted: bool = rec["alerted"]
			table[contact] = {"aw": aw, "last": last, "memory": memory, "alerted": alerted}
		contacts[observer] = table
	var last_in_all: Dictionary = state["last_pos"]
	var last_pos: Dictionary = {}
	for key: Variant in last_in_all:
		if typeof(key) != TYPE_INT or typeof(last_in_all[key]) != TYPE_ARRAY:
			return _restore_fail("last_pos key")
		var actor: int = key
		if not _actors.has_actor(actor):
			return _restore_fail("last_pos of a non-actor")
		var pos_in: Array = last_in_all[key]
		if pos_in.size() != 3:
			return _restore_fail("last_pos shape")
		var pos: Array[int] = []
		for v: Variant in pos_in:
			if typeof(v) != TYPE_INT:
				return _restore_fail("last_pos value")
			var coord: int = v
			pos.append(coord)
		last_pos[actor] = pos
	_agents = agents
	_contacts = contacts
	_last_pos = last_pos
	_alerts = alerts
	_heard.clear()
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("PerceptionSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
