## The one combat pipeline under a data-selected profile (design doc §13.1; M1 spec
## claim 11). `weapon.fire` runs the stages the shooter's profile enables, in the
## profile's order. Stage implementations are registered by name; a profile that
## enables a stage with no implementation fails assembly, not the playtest.
##
## M1 implements the arcade stages: hit_roll (a roll against the resolved hit chance
## minus a per-metre falloff, since no space exists yet), damage (the round's resolved
## damage) and routing (the profile's routing table onto the target's health graph).
## Emits `combat.fire` and `combat.hit` on the event bus; progression listens there.
class_name CombatSystem extends SimSystem

const SYSTEM_ID: StringName = &"combat"
const COMMAND_FIRE: StringName = &"weapon.fire"
const EVENT_FIRE: StringName = &"combat.fire"
const EVENT_HIT: StringName = &"combat.hit"
const STAGE_HIT_ROLL: StringName = &"hit_roll"
const STAGE_DAMAGE: StringName = &"damage"
const STAGE_ROUTING: StringName = &"routing"
const STAT_HIT_CHANCE: StringName = &"hit_chance"
const STAT_DAMAGE: StringName = &"damage"
const STAT_CYCLE_TICKS: StringName = &"cycle_ticks"
## The reason recorded on a shot that ran no stages: the shooter could not see the
## target (M4 spec claim 7). "" on any other shot.
const REASON_NO_LOS: String = "no_los"
## hit_chance is in basis points of a percent: this many is 100 %.
const CHANCE_ONE: int = 1_000_000

var _content: ContentDb
var _stats: StatResolver
var _items: ItemSystem
var _actors: ActorSystem
var _events: EventBus
## stage name -> Callable(ctx: Dictionary, sim: SimRoot) -> void
var _stages: Dictionary = {}
var _shots: int = 0
var _hits: int = 0
var _kills: int = 0
## Sum of damage actually applied to targets, milli-hp.
var _damage_dealt: int = 0
var _last: Dictionary = {}
## Callable(shooter: int, target: int) -> bool, set at assembly once perception
## exists (M4 spec claim 7). Unset, every target is in sight, as at M1.
var _sight: Callable = Callable()


func _init(content: ContentDb, stats: StatResolver, items: ItemSystem, actors: ActorSystem, events: EventBus) -> void:
	_content = content
	_stats = stats
	_items = items
	_actors = actors
	_events = events
	var e1: Error = register_stage(STAGE_HIT_ROLL, _stage_hit_roll)
	var e2: Error = register_stage(STAGE_DAMAGE, _stage_damage)
	var e3: Error = register_stage(STAGE_ROUTING, _stage_routing)
	assert(e1 == OK and e2 == OK and e3 == OK, "built-in stages must register")


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


func snapshot() -> Dictionary:
	return {"shots": _shots, "hits": _hits, "kills": _kills, "damage_dealt": _damage_dealt, "last": _last.duplicate(true)}


func events() -> EventBus:
	return _events


## A stage implementation. The name must be a `combat_stage` content id.
## Installs the sight check every shot passes before its stages run. The check
## answers for players and agents alike; its owner decides what "seeing" means.
func set_sight_check(check: Callable) -> void:
	_sight = check


func register_stage(name: StringName, implementation: Callable) -> Error:
	if _stages.has(name):
		push_error("CombatSystem: stage '%s' already registered" % name)
		return ERR_ALREADY_EXISTS
	if not implementation.is_valid():
		push_error("CombatSystem: stage '%s' needs a valid callable" % name)
		return ERR_INVALID_PARAMETER
	_stages[name] = implementation
	return OK


func implemented_stages() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: Variant in _stages:
		var name: StringName = key
		out.append(name)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


func attach(sim: SimRoot) -> Error:
	var err: Error = validate_content()
	if err != OK:
		return err
	err = sim.register_system(self)
	if err != OK:
		return err
	return sim.commands().register(COMMAND_FIRE, _on_fire)


## Every registered stage name is a content id; every profile enables only implemented stages.
func validate_content() -> Error:
	for name: StringName in _stages:
		if not _content.has(&"combat_stage", name):
			push_error("CombatSystem: implemented stage '%s' has no combat_stage/%s.json" % [name, name])
			return ERR_INVALID_DATA
	for profile: StringName in _content.ids(ActorSystem.KIND_PROFILE):
		var t: Dictionary = _content.get_entry(ActorSystem.KIND_PROFILE, profile)
		var stages: Array = t["stages"]
		var seen: Array[StringName] = []
		for s: Variant in stages:
			var name_s: String = s
			var name: StringName = StringName(name_s)
			if not _stages.has(name):
				push_error("CombatSystem: combat_profile/%s enables stage '%s', which nothing implements" % [profile, name])
				return ERR_INVALID_DATA
			if seen.has(name):
				push_error("CombatSystem: combat_profile/%s enables '%s' twice" % [profile, name])
				return ERR_INVALID_DATA
			seen.append(name)
	return OK


func shots() -> int:
	return _shots


func hits() -> int:
	return _hits


func kills() -> int:
	return _kills


func damage_dealt() -> int:
	return _damage_dealt


## The last shot: {tick, shooter, weapon, target, round, hit, damage, node, chance}.
func last_shot() -> Dictionary:
	return _last.duplicate(true)


## The chance (0..CHANCE_ONE) a shot from `weapon` hits a target at `range_m` under the
## shooter's profile. What the hit_roll stage rolls against; exposed for the HUD.
func hit_chance_at(shooter: int, weapon: int, range_m: int) -> int:
	var t: Dictionary = _actors.profile_data(shooter)
	if t.is_empty():
		return 0
	var falloff: int = t["range_falloff_per_m"]
	return clampi(_stats.resolve(weapon, STAT_HIT_CHANCE) - range_m * falloff, 0, CHANCE_ONE)


# ---------------------------------------------------------------- the command

## {"actor": int, "target": int}: fire the wielded weapon at another living actor.
func _on_fire(sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("target")) != TYPE_INT:
		return false
	var shooter: int = payload["actor"]
	var target: int = payload["target"]
	if shooter == target or not _actors.is_alive(shooter) or not _actors.is_alive(target):
		return false
	var weapon: int = _actors.wielded(shooter)
	if weapon == EntityIds.NONE or _items.is_busy(weapon, sim.get_tick()):
		return false
	var round: int = _items.chambered(weapon)
	if round == EntityIds.NONE:
		return false
	var profile: Dictionary = _actors.profile_data(shooter)
	var ctx: Dictionary = {
		"tick": sim.get_tick(), "shooter": shooter, "weapon": weapon, "round": round, "target": target,
		"range_m": ActorSystem.metres_between(_actors.position_of(shooter), _actors.position_of(target)), "profile": profile, "hit": false, "damage": 0, "applied": 0,
		"node": &"", "chance": 0, "killed": false,
	}
	# A shot at a target the shooter cannot see runs no stage: the round goes, the
	# noise is made, and the miss carries its reason (M4 spec claim 7).
	var reason: String = ""
	if _sight.is_valid() and not _sight.call(shooter, target):
		reason = REASON_NO_LOS
	else:
		var stages: Array = profile["stages"]
		for s: Variant in stages:
			var name_s: String = s
			var name: StringName = StringName(name_s)
			var stage: Callable = _stages[name]
			stage.call(ctx, sim)
	var weapon_tags: Array[StringName] = _stats.get_tags(weapon)
	var tags: Array[String] = []
	for t: StringName in weapon_tags:
		tags.append(String(t))
	var consumed: int = _items.consume_chambered(weapon)
	assert(consumed == round, "the chambered round is the one that was fired")
	_items.chamber_next(weapon)
	var cycle: int = maxi(1, _stats.resolve(weapon, STAT_CYCLE_TICKS) / 1000)
	_items.set_busy(weapon, sim.get_tick() + cycle)
	_shots += 1
	var hit: bool = ctx["hit"]
	if hit:
		_hits += 1
	var killed: bool = ctx["killed"]
	if killed:
		_kills += 1
	var applied: int = ctx["applied"]
	_damage_dealt += applied
	_last = {"tick": ctx["tick"], "shooter": shooter, "weapon": weapon, "target": target, "round": round,
		"hit": hit, "damage": ctx["applied"], "node": ctx["node"], "chance": ctx["chance"], "killed": killed, "reason": reason}
	_events.emit(EVENT_FIRE, {"shooter": shooter, "weapon": weapon, "target": target, "round": round, "tags": tags})
	if hit:
		_events.emit(EVENT_HIT, {"shooter": shooter, "weapon": weapon, "target": target, "node": ctx["node"],
			"damage": ctx["applied"], "range_m": ctx["range_m"], "tags": tags, "killed": killed})
	return true


# ---------------------------------------------------------------- built-in stages

func _stage_hit_roll(ctx: Dictionary, sim: SimRoot) -> void:
	var shooter: int = ctx["shooter"]
	var weapon: int = ctx["weapon"]
	var range_m: int = ctx["range_m"]
	var chance: int = hit_chance_at(shooter, weapon, range_m)
	ctx["chance"] = chance
	var roll: int = sim.rng().randi_range(0, CHANCE_ONE - 1)
	ctx["hit"] = roll < chance


func _stage_damage(ctx: Dictionary, _sim: SimRoot) -> void:
	var hit: bool = ctx["hit"]
	if not hit:
		return
	var round: int = ctx["round"]
	ctx["damage"] = maxi(0, _stats.resolve(round, STAT_DAMAGE))


func _stage_routing(ctx: Dictionary, sim: SimRoot) -> void:
	var hit: bool = ctx["hit"]
	if not hit:
		return
	var profile: Dictionary = ctx["profile"]
	var health: Dictionary = profile["health"]
	var routing: Array = health["routing"]
	var total: int = 0
	for r: Variant in routing:
		var rd: Dictionary = r
		var weight: int = rd["weight"]
		total += weight
	var pick: int = sim.rng().randi_range(1, total)
	var node: StringName = &""
	for r: Variant in routing:
		var rd: Dictionary = r
		var weight: int = rd["weight"]
		pick -= weight
		if pick <= 0:
			var node_s: String = rd["node"]
			node = StringName(node_s)
			break
	var target: int = ctx["target"]
	var damage: int = ctx["damage"]
	var alive_before: bool = _actors.is_alive(target)
	ctx["node"] = node
	ctx["applied"] = _actors.damage_node(target, node, damage)
	ctx["killed"] = alive_before and not _actors.is_alive(target)


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 5 or typeof(state.get("shots")) != TYPE_INT or typeof(state.get("hits")) != TYPE_INT \
			or typeof(state.get("kills")) != TYPE_INT or typeof(state.get("damage_dealt")) != TYPE_INT \
			or typeof(state.get("last")) != TYPE_DICTIONARY:
		push_error("CombatSystem.restore: rejected snapshot: shape")
		return ERR_INVALID_DATA
	var shots: int = state["shots"]
	var hits: int = state["hits"]
	var kills: int = state["kills"]
	var dealt: int = state["damage_dealt"]
	if shots < 0 or hits < 0 or kills < 0 or dealt < 0 or hits > shots or kills > hits:
		push_error("CombatSystem.restore: rejected snapshot: counters")
		return ERR_INVALID_DATA
	var last: Dictionary = state["last"]
	if not last.is_empty():
		for key: String in ["tick", "shooter", "weapon", "target", "round", "damage", "chance"]:
			if typeof(last.get(key)) != TYPE_INT:
				push_error("CombatSystem.restore: rejected snapshot: last.%s" % key)
				return ERR_INVALID_DATA
		if typeof(last.get("hit")) != TYPE_BOOL or typeof(last.get("killed")) != TYPE_BOOL or last.size() != 11:
			push_error("CombatSystem.restore: rejected snapshot: last shape")
			return ERR_INVALID_DATA
		var reason_v: Variant = last.get("reason")
		if typeof(reason_v) != TYPE_STRING or (reason_v != "" and reason_v != REASON_NO_LOS):
			push_error("CombatSystem.restore: rejected snapshot: last.reason")
			return ERR_INVALID_DATA
		var node_v: Variant = last.get("node")
		if typeof(node_v) != TYPE_STRING_NAME and typeof(node_v) != TYPE_STRING:
			push_error("CombatSystem.restore: rejected snapshot: last.node")
			return ERR_INVALID_DATA
	_shots = shots
	_hits = hits
	_kills = kills
	_damage_dealt = dealt
	_last = last.duplicate(true)
	if not _last.is_empty():
		var node_v: Variant = _last["node"]
		var node_s: String = node_v
		_last["node"] = StringName(node_s)
	return OK
