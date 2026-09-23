extends GcityTest

## M6 spec claim 8: three standing scalars, not one wanted level. Heat and notoriety
## are raised by content rules on bus events exactly as skill xp is and decay on their
## own clock at a rate the actor's district scales; visible wealth is derived from what
## the actor carries and is recomputed rather than accumulated. Property over 10 000
## generated events: a rule credits the actor its payload names and nobody else, and
## no decay takes a scalar below zero.

const SEED: int = 20261210
const SEED_PROPERTY: int = 20261211
const PROPERTY_CASES: int = 10_000
const HEAT: StringName = &"heat"
const NOTORIETY: StringName = &"notoriety"
const WEALTH: StringName = &"visible_wealth"
## content/standing_rule/heat.json and notoriety.json
const HEAT_PERIOD: int = 40
const HEAT_PER_VIOLATION: int = 200
const HEAT_PER_SIGHTING: int = 50
const HEAT_DECAY: int = 20
const NOTORIETY_PER_CONTRACT: int = 100
## content/parcel/neighbour_east.json, owned by npc.landlord_east
const ON_NEIGHBOUR_EAST: Vector3i = Vector3i(18000, 0, 6000)
## content/parcel/starter_plot.json, in starter_ghetto and owned by nobody
const ON_STARTER_PLOT: Vector3i = Vector3i(6000, 0, 6000)
## outside every parcel, so the wild district answers
const ON_OPEN_GROUND: Vector3i = Vector3i(500000, 0, 500000)

var _sim: SimRoot
var _standing: StandingSystem
var _actors: ActorSystem
var _items: ItemSystem
var _land: LandSystem
var _events: EventBus
var _player: int = 0


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	_standing = SimAssembly.standing_of(_sim)
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_land = SimAssembly.land_of(_sim)
	_events = SimAssembly.combat_of(_sim).events()
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, ON_OPEN_GROUND)


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


func _violate(actor: int) -> void:
	var p: Vector3i = _actors.position_of(actor)
	_events.emit(LandSystem.EVENT_VIOLATION, {"actor": actor, "parcel": _land.parcel_at(p), "right": &"build", "x": p.x, "y": p.y, "z": p.z})


func _seen(contact: int) -> void:
	_events.emit(PerceptionSystem.EVENT_ALERTED, {"observer": 0, "contact": contact, "tick": _sim.get_tick()})


func _completed(actor: int) -> void:
	_events.emit(QuestSystem.EVENT_COMPLETED, {"actor": actor, "quest": &"first_steps"})


## Steps to the next tick the given period fires on, without letting it fire twice.
func _step_to_next(period: int) -> void:
	var now: int = _sim.get_tick()
	var ticks: int = period - (now % period)
	_sim.step_n(ticks)


func test_the_scalars_and_their_rules_come_from_content() -> void:
	_setup()
	assert_eq(_standing.scalars(), [HEAT, NOTORIETY, WEALTH] as Array[StringName], "three scalars, named by their files")
	assert_eq(_standing.standing_of(_player, HEAT), 0, "an actor starts at nothing")
	assert_eq(_standing.standing_of(_player, &"reputation"), 0, "and a scalar nobody defined reads zero")
	assert_eq(_standing.heat_of(_player), 0, "heat")
	assert_eq(_standing.notoriety_of(_player), 0, "notoriety")
	assert_eq(_standing.visible_wealth_of(_player), 0, "visible wealth")
	assert_eq(_standing.snapshot(), {"standing": {}}, "and nobody is in the snapshot until something touches them")


func test_heat_rises_on_a_violation_and_on_being_seen_on_land_that_is_not_yours() -> void:
	_setup()
	_violate(_player)
	assert_eq(_standing.heat_of(_player), HEAT_PER_VIOLATION, "taking a right you do not hold is heat wherever you are")
	# being seen only counts on somebody else's parcel
	_seen(_player)
	assert_eq(_standing.heat_of(_player), HEAT_PER_VIOLATION, "open ground: nobody to object")
	_actors.set_position(_player, ON_STARTER_PLOT)
	_seen(_player)
	assert_eq(_standing.heat_of(_player), HEAT_PER_VIOLATION, "an unclaimed parcel is nobody's either")
	_actors.set_position(_player, ON_NEIGHBOUR_EAST)
	_seen(_player)
	assert_eq(_standing.heat_of(_player), HEAT_PER_VIOLATION + HEAT_PER_SIGHTING, "but the landlord's plot is")
	assert_true(_do(&"land.identify", {"actor": _player, "owner": "npc.landlord_east"}), "unless you are the landlord")
	_seen(_player)
	assert_eq(_standing.heat_of(_player), HEAT_PER_VIOLATION + HEAT_PER_SIGHTING, "your own land costs nothing")
	# the event has to name an actor the sim knows
	_seen(9999)
	_events.emit(LandSystem.EVENT_VIOLATION, {"actor": "not an id"})
	assert_eq(_standing.heat_of(_player), HEAT_PER_VIOLATION + HEAT_PER_SIGHTING, "a payload naming nobody credits nobody")


func test_notoriety_rises_when_a_contract_completes_and_fades_far_more_slowly() -> void:
	_setup()
	_completed(_player)
	_completed(_player)
	assert_eq(_standing.notoriety_of(_player), 2 * NOTORIETY_PER_CONTRACT, "two contracts")
	assert_eq(_standing.heat_of(_player), 0, "finishing a job is not heat")
	# heat cools on its own clock long before a name does
	_violate(_player)
	var heat_before: int = _standing.heat_of(_player)
	_step_to_next(HEAT_PERIOD)
	assert_true(_standing.heat_of(_player) < heat_before, "heat has already started to cool")
	assert_eq(_standing.notoriety_of(_player), 2 * NOTORIETY_PER_CONTRACT, "the name has not moved at all")


func test_visible_wealth_is_what_you_are_carrying_recomputed() -> void:
	_setup()
	var inv: StringName = ItemSystem.inventory_of(_player)
	var handset: int = _items.spawn(&"device_frame", &"handset", inv, 1)
	assert_true(handset > 0, "a handset")
	_step_to_next(HEAT_PERIOD)
	assert_eq(_standing.carried_value(_player), 600, "the handset's worth")
	assert_eq(_standing.visible_wealth_of(_player), 600, "and that is what you look worth")
	# a fitted part raises its host's value, so it is counted without being carried loose
	var module: int = _items.spawn(&"device_module", &"daemon_coprocessor", inv, 2)
	_step_to_next(HEAT_PERIOD)
	assert_eq(_standing.visible_wealth_of(_player), 600, "a chip loose in the bag does not show")
	assert_true(_do(&"actor.equip_device", {"actor": _player, "device": handset}), "carried")
	assert_true(_do(&"item.attach", {"actor": _player, "weapon": handset, "part": module}), "fitted")
	_step_to_next(HEAT_PERIOD)
	assert_eq(_standing.visible_wealth_of(_player), 600 + 900, "fitted, it raises what the handset is worth")
	# wealth is derived, so putting it down lowers it rather than decaying
	_items.spawn(&"weapon_frame", &"m9", inv, 3)
	_step_to_next(HEAT_PERIOD)
	assert_eq(_standing.visible_wealth_of(_player), 600 + 900 + 1400, "and a pistol on top")


func test_decay_is_scaled_by_the_district_and_stops_at_zero() -> void:
	_setup()
	# the wild district's law_index is 50, so heat cools at 20 * (1000 - 50) / 1000
	_violate(_player)
	assert_eq(_standing.heat_of(_player), HEAT_PER_VIOLATION, "heat")
	_step_to_next(HEAT_PERIOD)
	assert_eq(_standing.heat_of(_player), HEAT_PER_VIOLATION - 19, "open ground: nobody is looking, so it cools fast")
	# starter_ghetto's is 250, so the same heat cools more slowly there
	_actors.set_position(_player, ON_STARTER_PLOT)
	_step_to_next(HEAT_PERIOD)
	assert_eq(_standing.heat_of(_player), HEAT_PER_VIOLATION - 19 - 15, "in town it cools slower")
	# and it stops at nothing rather than going negative
	_sim.step_n(HEAT_PERIOD * 40)
	assert_eq(_standing.heat_of(_player), 0, "eventually it is gone")
	assert_eq(_standing.snapshot(), {"standing": {}}, "and an actor at zero on everything leaves the snapshot")
	assert_true(_standing.heat_of(_player) >= 0, "never below zero")


func test_property_rules_credit_the_named_actor_and_decay_never_goes_below_zero() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	_setup()
	var names: Array[StringName] = [HEAT, NOTORIETY, WEALTH]
	var others: Array[int] = [_player]
	for i: int in 3:
		var a: int = _actors.spawn(&"arcade", 10 + i)
		_actors.set_position(a, ON_NEIGHBOUR_EAST if i == 0 else ON_OPEN_GROUND)
		others.append(a)
	var violations: int = 0
	var credited: int = 0
	var decays: int = 0
	for case: int in PROPERTY_CASES:
		var who: int = others[rng.randi_range(0, others.size() - 1)]
		var before: Dictionary = {}
		for actor: int in others:
			before[actor] = [_standing.heat_of(actor), _standing.notoriety_of(actor), _standing.visible_wealth_of(actor)]
		var scalar_index: int = 0
		var expected: int = 0
		match rng.randi_range(0, 2):
			0:
				_violate(who)
				expected = HEAT_PER_VIOLATION
			1:
				_seen(who)
				scalar_index = 0
				expected = HEAT_PER_SIGHTING if _actors.position_of(who) == ON_NEIGHBOUR_EAST else 0
			_:
				_completed(who)
				scalar_index = 1
				expected = NOTORIETY_PER_CONTRACT
		if expected > 0:
			credited += 1
		for actor: int in others:
			var was_v: Variant = before[actor]
			var was: Array = was_v
			var now: Array[int] = [_standing.heat_of(actor), _standing.notoriety_of(actor), _standing.visible_wealth_of(actor)]
			for i: int in 3:
				var previous: int = was[i]
				var moved: int = now[i] - previous
				var raised: int = expected if actor == who and i == scalar_index else 0
				# a scalar stops at its rule's ceiling, so a credit past it is partly lost
				var ceiling: int = _standing.ceiling_of(names[i])
				var wanted: int = mini(previous + raised, ceiling) - previous
				if moved != wanted:
					violations += 1
					if violations <= 3:
						fail("case %d: actor %d scalar %d moved by %d, wanted %d" % [case, actor, i, moved, wanted])
				if now[i] < 0:
					violations += 1
					if violations <= 3:
						fail("case %d: actor %d scalar %d went below zero: %d" % [case, actor, i, now[i]])
		# let the clock run now and then, so decay is part of the stream
		if case % 25 == 24:
			decays += 1
			var heat_before: int = _standing.heat_of(who)
			_step_to_next(HEAT_PERIOD)
			if _standing.heat_of(who) > heat_before:
				violations += 1
				if violations <= 3:
					fail("case %d: heat rose over a decay" % case)
			for actor: int in others:
				if _standing.heat_of(actor) < 0:
					violations += 1
					if violations <= 3:
						fail("case %d: actor %d fell below zero over a decay" % [case, actor])
	assert_eq(violations, 0, "every rule credited the actor its payload named and nothing fell below zero (%d credits, %d decays)" % [credited, decays])
	assert_true(credited > 4000 and decays > 300, "the stream exercised both (%d credits, %d decays)" % [credited, decays])


func test_restore_round_trip_and_rejections() -> void:
	_setup()
	_violate(_player)
	_completed(_player)
	var snap: Dictionary = _sim.snapshot()
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "restored")
	assert_eq(other.restore_root(snap), OK, "root restored")
	var restored: StandingSystem = SimAssembly.standing_of(other)
	assert_eq(restored.heat_of(_player), HEAT_PER_VIOLATION, "heat carried over")
	assert_eq(restored.notoriety_of(_player), NOTORIETY_PER_CONTRACT, "and the name with it")
	_sim.step()
	other.step()
	assert_eq(other.state_hash(), _sim.state_hash(), "hashes agree")
	var state: Dictionary = _standing.snapshot()
	assert_eq(restored.restore({}), ERR_INVALID_DATA, "empty")
	var bad: Dictionary = state.duplicate(true)
	var all: Dictionary = bad["standing"]
	var rec: Dictionary = all[_player]
	rec[HEAT] = -1
	assert_eq(restored.restore(bad), ERR_INVALID_DATA, "a negative scalar")
	bad = state.duplicate(true)
	all = bad["standing"]
	rec = all[_player]
	rec.erase(HEAT)
	rec["reputation"] = 5
	assert_eq(restored.restore(bad), ERR_INVALID_DATA, "a scalar no content defines")
	bad = state.duplicate(true)
	all = bad["standing"]
	all[9999] = {HEAT: 10}
	assert_eq(restored.restore(bad), ERR_INVALID_DATA, "an actor that is not an actor")
	bad = state.duplicate(true)
	all = bad["standing"]
	all[_player] = {}
	assert_eq(restored.restore(bad), ERR_INVALID_DATA, "an actor at nothing should not be stored at all")
	assert_eq(restored.snapshot(), state, "rejections leave the state untouched")
