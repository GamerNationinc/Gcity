## Decisions (design doc §14.4; M4 spec claim 10). Utility scoring picks a stance;
## a small state machine executes it; hysteresis keeps it. Stances are content
## (`content/stance/`) with a scorer registered by name here, the combat-stage
## pattern: a profile that names a stance with no scorer fails assembly. Every
## SCORE_EVERY ticks an agent scores the stances its profile allows from what it
## perceives (awareness, sight, a last-known position), how stressed it is and how
## far the contact is, and switches only when the winner beats the current stance
## by HYSTERESIS after MIN_STANCE_TICKS. Scoring is time-sliced: agent `i` scores on
## the ticks where `tick % SCORE_EVERY == i % SCORE_EVERY`. Execution runs every
## tick: the agent faces what it sees, fires through `weapon.fire` (the client's
## command path, submitted for the next tick) at an alerted target it can see, and
## walks through PathingSystem toward the stance's goal, or toward the squad's
## assigned entry edge when it has one (claim 11). A routed agent may only retreat
## or surrender.
class_name StanceSystem extends SimSystem

const SYSTEM_ID: StringName = &"stances"
const KIND_STANCE: StringName = &"stance"
const KIND_ROUTE: StringName = &"patrol_route"
const SCORE_EVERY: int = 8
const MIN_STANCE_TICKS: int = 40
const HYSTERESIS: int = 100_000
const STANCE_HOLD: StringName = &"hold"
const STANCE_ADVANCE: StringName = &"advance"
const STANCE_FLANK: StringName = &"flank"
const STANCE_RETREAT: StringName = &"retreat"
const STANCE_INVESTIGATE: StringName = &"investigate"
const STANCE_SURRENDER: StringName = &"surrender"
## Walking a token's route (M7 spec claim 12). The walking is the hydration system's;
## this stance is the agent deciding that walking is what it is doing, and it gives way
## the moment the agent knows anyone is there.
const STANCE_TRAVEL: StringName = &"travel"
## Stances that fire at an alerted target in sight.
const FIRING_STANCES: Array[StringName] = [&"hold", &"advance", &"flank"]
const ENGAGE_CELLS: int = 5
const FLANK_CELLS: int = 4
const RETREAT_CELLS: int = 6
const SURRENDER_MM: int = 8000
## Below this awareness a remembered contact is a flicker, not worth starting a look.
const INVESTIGATE_MIN: int = 200_000

var _content: ContentDb
var _actors: ActorSystem
var _items: ItemSystem
var _perception: PerceptionSystem
var _aim: AimSystem
var _stress: StressSystem
var _pathing: PathingSystem
var _squads: SquadSystem
var _events: EventBus
## stance name -> Callable(ctx: Dictionary) -> int (0..1 000 000)
var _scorers: Dictionary = {}
## agent -> {"stance": StringName, "since": int, "score": int, "waypoint": int, "goal": [] | [x, y, z]}
var _stances: Dictionary = {}
## (agent) -> bool: true while the agent belongs to a hydrated squad with a route to
## walk. Wired by the assembly to the hydration system.
var _travelling: Callable = Callable()
var _fires: int = 0
var _scored: int = 0


func _init(content: ContentDb, actors: ActorSystem, items: ItemSystem, perception: PerceptionSystem, aim: AimSystem, stress: StressSystem, pathing: PathingSystem, squads: SquadSystem, events: EventBus) -> void:
	_events = events
	_content = content
	_actors = actors
	_items = items
	_perception = perception
	_aim = aim
	_stress = stress
	_pathing = pathing
	_squads = squads
	var errs: Array[Error] = [
		register_scorer(STANCE_HOLD, _score_hold), register_scorer(STANCE_ADVANCE, _score_advance),
		register_scorer(STANCE_FLANK, _score_flank), register_scorer(STANCE_RETREAT, _score_retreat),
		register_scorer(STANCE_INVESTIGATE, _score_investigate), register_scorer(STANCE_SURRENDER, _score_surrender),
		register_scorer(STANCE_TRAVEL, _score_travel)]
	for e: Error in errs:
		assert(e == OK, "built-in scorers register once")


func system_id() -> StringName:
	return SYSTEM_ID


func snapshot() -> Dictionary:
	return {"stances": _stances.duplicate(true), "fires": _fires, "scored": _scored}


func attach(sim: SimRoot) -> Error:
	var err: Error = validate_content()
	if err != OK:
		return err
	err = sim.register_system(self)
	if err != OK:
		return err
	return _events.subscribe(ActorSystem.EVENT_REMOVED, _on_removed)


func _on_removed(payload: Dictionary) -> void:
	var actor: int = payload["actor"]
	_stances.erase(actor)


## Where "is this agent on the road" comes from, wired by the assembly.
func set_travel_check(check: Callable) -> void:
	_travelling = check


## A scorer for a stance name: func(ctx: Dictionary) -> int in [0, 1 000 000]. A
## second registration for the same name is refused.
func register_scorer(name: StringName, scorer: Callable) -> Error:
	if _scorers.has(name):
		push_error("StanceSystem: scorer '%s' already registered" % name)
		return ERR_ALREADY_EXISTS
	if not scorer.is_valid():
		push_error("StanceSystem: invalid scorer for '%s'" % name)
		return ERR_INVALID_PARAMETER
	_scorers[name] = scorer
	return OK


func implemented_stances() -> Array[StringName]:
	var names: Array[String] = []
	for key: Variant in _scorers:
		var name: StringName = key
		names.append(String(name))
	names.sort()
	var out: Array[StringName] = []
	for name: String in names:
		out.append(StringName(name))
	return out


## Every profile's stances exist as content and have a scorer; `hold` is always
## implemented (the stance an agent starts in); every route's cells are cells.
func validate_content() -> Error:
	if not _scorers.has(STANCE_HOLD):
		return _content_fail("no scorer for '%s'" % STANCE_HOLD)
	for id: StringName in _content.ids(PerceptionSystem.KIND_AGENT):
		var t: Dictionary = _content.get_entry(PerceptionSystem.KIND_AGENT, id)
		if typeof(t.get("stances")) != TYPE_ARRAY:
			return _content_fail("agent_profile/%s has no stances" % id)
		var stances: Array = t["stances"]
		if stances.is_empty():
			return _content_fail("agent_profile/%s allows no stance" % id)
		for entry: Variant in stances:
			if typeof(entry) != TYPE_DICTIONARY:
				return _content_fail("agent_profile/%s: stance entry shape" % id)
			var e: Dictionary = entry
			if typeof(e.get("stance")) != TYPE_STRING or typeof(e.get("weight")) != TYPE_INT:
				return _content_fail("agent_profile/%s: stance entry fields" % id)
			var name_s: String = e["stance"]
			var name: StringName = StringName(name_s)
			if not _content.has(KIND_STANCE, name):
				return _content_fail("agent_profile/%s: no stance/%s" % [id, name_s])
			if not _scorers.has(name):
				return _content_fail("agent_profile/%s: stance '%s' has no scorer" % [id, name_s])
	for id: StringName in _content.ids(KIND_ROUTE):
		var t: Dictionary = _content.get_entry(KIND_ROUTE, id)
		if typeof(t.get("cells")) != TYPE_ARRAY:
			return _content_fail("patrol_route/%s has no cells" % id)
		var cells: Array = t["cells"]
		if cells.is_empty():
			return _content_fail("patrol_route/%s is empty" % id)
		for c: Variant in cells:
			if not PathingSystem._is_cell(c):
				return _content_fail("patrol_route/%s: a cell is not three ints" % id)
	return OK


func _content_fail(reason: String) -> Error:
	push_error("StanceSystem: %s" % reason)
	return ERR_INVALID_DATA


# ---------------------------------------------------------------- queries

func stance_of(agent: int) -> StringName:
	var rec: Dictionary = _record(agent)
	if rec.is_empty():
		return STANCE_HOLD if _perception.is_agent(agent) else &""
	return rec["stance"]


func since_of(agent: int) -> int:
	var rec: Dictionary = _record(agent)
	if rec.is_empty():
		return 0
	return rec["since"]


func waypoint_of(agent: int) -> int:
	var rec: Dictionary = _record(agent)
	if rec.is_empty():
		return 0
	return rec["waypoint"]


func fire_count() -> int:
	return _fires


func score_count() -> int:
	return _scored


## The stances an agent's profile allows, in profile order, with their weights.
func allowed_stances(agent: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var profile: StringName = _perception.profile_of(agent)
	if profile.is_empty():
		return out
	var t: Dictionary = _content.get_entry(PerceptionSystem.KIND_AGENT, profile)
	var stances: Array = t["stances"]
	for entry: Variant in stances:
		var e: Dictionary = entry
		var name_s: String = e["stance"]
		var weight: int = e["weight"]
		out.append({"stance": StringName(name_s), "weight": weight})
	return out


func _record(agent: int) -> Dictionary:
	var stored: Variant = _stances.get(agent)
	if typeof(stored) != TYPE_DICTIONARY:
		return {}
	return stored


# ---------------------------------------------------------------- scoring

## What the scorers see: the most-aware known contact (visible or remembered), the
## agent's stress state, distances, cover and whether it has a patrol route.
func context_of(agent: int) -> Dictionary:
	var contact: int = _known_contact(agent)
	var ctx: Dictionary = {"known": contact != EntityIds.NONE, "visible": false, "alerted": false, "awareness": 0,
		"distance_mm": 0, "stress": _stress.stress_of(agent), "broken": _stress.is_broken(agent), "routed": _stress.is_routed(agent),
		"in_cover": false, "route": not _route_of(agent).is_empty(), "travelling": _is_travelling(agent)}
	if contact == EntityIds.NONE:
		return ctx
	ctx["visible"] = _perception.sees(agent, contact)
	ctx["alerted"] = _perception.is_alerted(agent, contact)
	ctx["awareness"] = _perception.awareness_of(agent, contact)
	var here: Vector3i = _actors.position_of(agent)
	var there: Vector3i = _actors.position_of(contact) if ctx["visible"] else _perception.last_known(agent, contact)
	ctx["distance_mm"] = PerceptionSystem.distance_mm(here, there)
	ctx["in_cover"] = not _perception.line_of_sight(here, there)
	return ctx


## Picks the stance for `ctx` given the allowed list, the current stance and how long
## it has run: the highest weighted score wins (ties to profile order); a routed
## agent may only retreat or surrender; the winner must beat the current stance by
## HYSTERESIS unless the current stance has become disallowed.
func choose(allowed: Array[Dictionary], ctx: Dictionary, current: StringName, ran: int) -> Dictionary:
	var routed: bool = ctx["routed"]
	ctx["current"] = current
	var best: StringName = &""
	var best_score: int = -1
	var current_score: int = -1
	var current_allowed: bool = false
	for entry: Dictionary in allowed:
		var name: StringName = entry["stance"]
		if routed and name != STANCE_RETREAT and name != STANCE_SURRENDER and _has_escape(allowed):
			continue
		var scorer: Callable = _scorers[name]
		var raw: Variant = scorer.call(ctx)
		var score_v: int = raw
		var weight: int = entry["weight"]
		var score: int = clampi(score_v, 0, 1_000_000) * weight / 1000
		if name == current:
			current_score = score
			current_allowed = true
		if score > best_score:
			best = name
			best_score = score
	if not current_allowed:
		return {"stance": best, "score": best_score, "switched": true}
	if best != current and best_score >= current_score + HYSTERESIS and ran >= MIN_STANCE_TICKS:
		return {"stance": best, "score": best_score, "switched": true}
	return {"stance": current, "score": current_score, "switched": false}


static func _has_escape(allowed: Array[Dictionary]) -> bool:
	for entry: Dictionary in allowed:
		var name: StringName = entry["stance"]
		if name == STANCE_RETREAT or name == STANCE_SURRENDER:
			return true
	return false


func _score_hold(ctx: Dictionary) -> int:
	var known: bool = ctx["known"]
	var stress: int = ctx["stress"]
	return maxi(300_000 + (400_000 if not known else 0) - stress / 4, 0)


func _score_advance(ctx: Dictionary) -> int:
	var alerted: bool = ctx["alerted"]
	if not alerted:
		return 0
	var awareness: int = ctx["awareness"]
	var stress: int = ctx["stress"]
	var distance: int = ctx["distance_mm"]
	return maxi(250_000 + awareness / 2 - stress / 2 - (200_000 if distance <= ENGAGE_CELLS * BuildSystem.CELL else 0), 0)


func _score_flank(ctx: Dictionary) -> int:
	var alerted: bool = ctx["alerted"]
	var visible: bool = ctx["visible"]
	if not alerted or visible:
		return 0
	var awareness: int = ctx["awareness"]
	var stress: int = ctx["stress"]
	return maxi(200_000 + awareness / 2 - stress / 2, 0)


func _score_retreat(ctx: Dictionary) -> int:
	var routed: bool = ctx["routed"]
	var broken: bool = ctx["broken"]
	var stress: int = ctx["stress"]
	if routed:
		return 900_000
	if broken:
		return 600_000 + stress / 4
	return 0


func _score_investigate(ctx: Dictionary) -> int:
	var known: bool = ctx["known"]
	var visible: bool = ctx["visible"]
	var alerted: bool = ctx["alerted"]
	var awareness: int = ctx["awareness"]
	var current: StringName = ctx.get("current", &"")
	if not known or visible or alerted:
		return 0
	# a look is started on real awareness, and once started it is finished while the
	# contact is remembered at all, however faint the awareness has grown
	if awareness < INVESTIGATE_MIN and current != STANCE_INVESTIGATE:
		return 0
	return 500_000 + awareness / 4


## Walking the road while nobody is about. Anything known — seen, heard, remembered —
## stops the walk, and the stance scorers above decide what happens instead; once it is
## forgotten the walk wins back by more than the hysteresis.
func _score_travel(ctx: Dictionary) -> int:
	var travelling: bool = ctx.get("travelling", false)
	var known: bool = ctx["known"]
	if not travelling or known:
		return 0
	return 900_000


func _is_travelling(agent: int) -> bool:
	if not _travelling.is_valid():
		return false
	var on_road: bool = _travelling.call(agent)
	return on_road


func _score_surrender(ctx: Dictionary) -> int:
	var routed: bool = ctx["routed"]
	var visible: bool = ctx["visible"]
	var distance: int = ctx["distance_mm"]
	if routed and visible and distance <= SURRENDER_MM:
		return 1_000_000
	return 0


# ---------------------------------------------------------------- the tick

func tick(sim: SimRoot) -> void:
	var tick_now: int = sim.get_tick()
	for agent: int in _perception.agent_ids():
		if not _actors.is_alive(agent):
			_stances.erase(agent)
			continue
		var rec: Dictionary = _record(agent)
		if rec.is_empty():
			rec = {"stance": _first_stance(agent), "since": tick_now, "score": 0, "waypoint": 0, "goal": [] as Array[int]}
		if tick_now % SCORE_EVERY == agent % SCORE_EVERY:
			_scored += 1
			var current: StringName = rec["stance"]
			var since: int = rec["since"]
			var choice: Dictionary = choose(allowed_stances(agent), context_of(agent), current, tick_now - since)
			var switched: bool = choice["switched"]
			rec["score"] = choice["score"]
			if switched:
				rec["stance"] = choice["stance"]
				rec["since"] = tick_now
				rec["goal"] = [] as Array[int]
				_pathing.cancel(agent)
		_execute(sim, agent, rec)
		_stances[agent] = rec


## A new agent starts in the first stance its profile lists, so a squad hydrated onto a
## road is walking from its first tick rather than standing until its first scoring.
## Every profile before M7 lists hold first, so for them this is the hold it always was.
func _first_stance(agent: int) -> StringName:
	var allowed: Array[Dictionary] = allowed_stances(agent)
	if allowed.is_empty():
		return STANCE_HOLD
	var first: StringName = allowed[0]["stance"]
	return first


func _execute(sim: SimRoot, agent: int, rec: Dictionary) -> void:
	var stance: StringName = rec["stance"]
	var target: int = _aim.target_of(agent)
	if target != EntityIds.NONE:
		var d: Vector3i = _actors.position_of(target) - _actors.position_of(agent)
		_perception.set_facing(agent, facing_toward(Vector2i(d.x, d.z)))
		if FIRING_STANCES.has(stance) and _perception.is_alerted(agent, target) and _weapon_ready(agent, sim.get_tick()):
			var err: Error = sim.submit(SimCommand.new(sim.get_tick() + 1, CombatSystem.COMMAND_FIRE, {"actor": agent, "target": target}))
			assert(err == OK, "the next tick is never late")
			_fires += 1
	var here: Vector3i = BuildSystem.cell_of(_actors.position_of(agent))
	var contact: int = _known_contact(agent)
	var goal: Vector3i = here
	var wants_goal: bool = false
	match stance:
		STANCE_HOLD:
			var route: Array = _route_of(agent)
			if not route.is_empty():
				var waypoint: int = rec["waypoint"]
				goal = PathingSystem._vec(route[waypoint % route.size()])
				if here == goal:
					waypoint = (waypoint + 1) % route.size()
					rec["waypoint"] = waypoint
					goal = PathingSystem._vec(route[waypoint])
				wants_goal = true
		STANCE_ADVANCE:
			if _squads.has_assignment(agent):
				# the squad planner's entry edge: take the door, or cover the window
				goal = _squads.assignment_of(agent)
				wants_goal = goal != here
			elif contact != EntityIds.NONE:
				var there: Vector3i = _contact_cell(agent, contact)
				if PathingSystem._manhattan(here, there) > ENGAGE_CELLS:
					goal = there
					wants_goal = true
		STANCE_FLANK:
			if _squads.has_assignment(agent):
				goal = _squads.assignment_of(agent)
				wants_goal = goal != here
			elif contact != EntityIds.NONE:
				var there: Vector3i = _contact_cell(agent, contact)
				var toward: Vector3i = _dominant(there - here)
				goal = there + Vector3i(-toward.z, 0, toward.x) * FLANK_CELLS
				wants_goal = true
		STANCE_RETREAT:
			if contact != EntityIds.NONE:
				var there: Vector3i = _contact_cell(agent, contact)
				var away: Vector3i = _dominant(here - there)
				if away == Vector3i.ZERO:
					away = Vector3i(1, 0, 0)
				goal = here + away * RETREAT_CELLS
				wants_goal = PathingSystem._manhattan(here, there) < RETREAT_CELLS * 2
		STANCE_INVESTIGATE:
			if contact != EntityIds.NONE:
				goal = _contact_cell(agent, contact)
				wants_goal = goal != here
		_:
			wants_goal = false
	var stored: Array = rec["goal"]
	if wants_goal:
		if stored.is_empty() or PathingSystem._vec(stored) != goal:
			rec["goal"] = PathingSystem._arr(goal)
			if not _pathing.request(agent, goal):
				rec["goal"] = [] as Array[int]
	elif not stored.is_empty():
		rec["goal"] = [] as Array[int]
		_pathing.cancel(agent)


func _weapon_ready(agent: int, tick_now: int) -> bool:
	var weapon: int = _actors.wielded(agent)
	if weapon == EntityIds.NONE:
		return false
	return not _items.is_busy(weapon, tick_now) and _items.chambered(weapon) != EntityIds.NONE


## The visible target if there is one, else the remembered contact the agent is most
## aware of; NONE when nothing is known.
func _known_contact(agent: int) -> int:
	var target: int = _aim.target_of(agent)
	if target != EntityIds.NONE:
		return target
	var best: int = EntityIds.NONE
	var best_aw: int = -1
	for contact: int in _actors.actor_ids():
		if contact == agent or not _perception.has_last_known(agent, contact):
			continue
		var aw: int = _perception.awareness_of(agent, contact)
		if aw > best_aw:
			best = contact
			best_aw = aw
	return best


func _contact_cell(agent: int, contact: int) -> Vector3i:
	if _perception.sees(agent, contact):
		return BuildSystem.cell_of(_actors.position_of(contact))
	return BuildSystem.cell_of(_perception.last_known(agent, contact))


func _route_of(agent: int) -> Array:
	if not _perception.is_agent(agent):
		return []
	var route_s: String = _perception.route_of(agent)
	if route_s.is_empty() or not _content.has(KIND_ROUTE, StringName(route_s)):
		return []
	var t: Dictionary = _content.get_entry(KIND_ROUTE, StringName(route_s))
	return t["cells"]


## The whole degree whose direction best matches `v` (integer trig: the table's dot
## product is scanned, coarse then fine, so no atan2 in the sim).
static func facing_toward(v: Vector2i) -> int:
	if v == Vector2i.ZERO:
		return 0
	var best: int = 0
	var best_dot: int = -2_000_000_000
	for step: int in 45:
		var deg: int = step * 8
		var dot: int = PerceptionSystem.cos_milli(deg) * v.x + PerceptionSystem.sin_milli(deg) * v.y
		if dot > best_dot:
			best = deg
			best_dot = dot
	var coarse: int = best
	for offset: int in range(-8, 9):
		var deg: int = posmod(coarse + offset, 360)
		var dot: int = PerceptionSystem.cos_milli(deg) * v.x + PerceptionSystem.sin_milli(deg) * v.y
		if dot > best_dot:
			best = deg
			best_dot = dot
	return best


## The unit step along the larger horizontal component of `v` (x wins a tie).
static func _dominant(v: Vector3i) -> Vector3i:
	if v.x == 0 and v.z == 0:
		return Vector3i.ZERO
	if absi(v.x) >= absi(v.z):
		return Vector3i(signi(v.x), 0, 0)
	return Vector3i(0, 0, signi(v.z))


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 3 or typeof(state.get("stances")) != TYPE_DICTIONARY or typeof(state.get("fires")) != TYPE_INT or typeof(state.get("scored")) != TYPE_INT:
		return _restore_fail("shape")
	var fires: int = state["fires"]
	var scored: int = state["scored"]
	if fires < 0 or scored < 0:
		return _restore_fail("negative counter")
	var in_all: Dictionary = state["stances"]
	var out: Dictionary = {}
	for key: Variant in in_all:
		if typeof(key) != TYPE_INT or typeof(in_all[key]) != TYPE_DICTIONARY:
			return _restore_fail("agent key")
		var agent: int = key
		if not _perception.is_agent(agent):
			return _restore_fail("agent %d is not an agent" % agent)
		var rec: Dictionary = in_all[key]
		var stance_v: Variant = rec.get("stance")
		if rec.size() != 5 or (typeof(stance_v) != TYPE_STRING_NAME and typeof(stance_v) != TYPE_STRING) or typeof(rec.get("since")) != TYPE_INT \
				or typeof(rec.get("score")) != TYPE_INT or typeof(rec.get("waypoint")) != TYPE_INT or typeof(rec.get("goal")) != TYPE_ARRAY:
			return _restore_fail("agent %d record" % agent)
		var stance_s: String = stance_v
		var stance: StringName = StringName(stance_s)
		if not _scorers.has(stance):
			return _restore_fail("agent %d stance '%s'" % [agent, stance_s])
		var since: int = rec["since"]
		var score: int = rec["score"]
		var waypoint: int = rec["waypoint"]
		var goal_in: Array = rec["goal"]
		if since < 0 or score < 0 or waypoint < 0 or (not goal_in.is_empty() and not PathingSystem._is_cell(goal_in)):
			return _restore_fail("agent %d values" % agent)
		var goal: Array[int] = [] as Array[int]
		if not goal_in.is_empty():
			goal = PathingSystem._arr(PathingSystem._vec(goal_in))
		out[agent] = {"stance": stance, "since": since, "score": score, "waypoint": waypoint, "goal": goal}
	_stances = out
	_fires = fires
	_scored = scored
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("StanceSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
