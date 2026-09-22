extends GcityTest

## M5 spec claim 9: quests are content with event objectives; accepted and abandoned
## by pause-safe commands; objectives advance from bus events credited to the actor,
## filtered by tags; completion happens exactly once, with the reward granted once.
## Property over 10 000 event streams: counts never exceed their target, completion
## exactly once, the reward once.

const SEED: int = 20261130
const SEED_PROPERTY: int = 20261131
const PROPERTY_CASES: int = 10_000

var _sim: SimRoot
var _actors: ActorSystem
var _items: ItemSystem
var _quests: QuestSystem
var _events: EventBus
var _player: int = 0
var _completed: Array[Dictionary] = []


func _db() -> ContentDb:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	return db


func _setup(db: ContentDb = null) -> void:
	if db == null:
		db = _db()
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_quests = SimAssembly.quests_of(_sim)
	_events = SimAssembly.combat_of(_sim).events()
	_events.subscribe(QuestSystem.EVENT_COMPLETED, _on_completed)
	_player = _actors.spawn(&"arcade", 0)


func _on_completed(payload: Dictionary) -> void:
	_completed.append(payload)


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


func _hit(shooter: int, tags: Array) -> void:
	_events.emit(CombatSystem.EVENT_HIT, {"shooter": shooter, "weapon": 0, "target": 2, "node": &"body", "damage": 1, "range_m": 5, "tags": tags, "killed": false})


func test_accept_and_abandon_contracts() -> void:
	_setup()
	assert_true(_quests.quest_ids().has(&"first_blood") and _quests.quest_ids().has(&"break_ground"), "the quests in content, lexically (%s)" % [_quests.quest_ids()])
	assert_eq(_quests.status_of(_player, &"first_blood"), "", "nothing accepted")
	assert_true(_do(&"quest.accept", {"actor": _player, "quest": "first_blood"}), "accept")
	assert_eq(_quests.status_of(_player, &"first_blood"), "active", "active")
	assert_eq(_quests.progress_of(_player, &"first_blood"), [0] as Array[int], "no progress")
	assert_false(_do(&"quest.accept", {"actor": _player, "quest": "first_blood"}), "not twice")
	assert_false(_do(&"quest.accept", {"actor": _player, "quest": "nothing"}), "unknown quest")
	assert_false(_do(&"quest.accept", {"actor": 99, "quest": "first_blood"}), "unknown actor")
	assert_false(_do(&"quest.accept", {"actor": _player}), "missing quest")
	assert_false(_do(&"quest.abandon", {"actor": _player, "quest": "break_ground"}), "not accepted")
	assert_true(_do(&"quest.abandon", {"actor": _player, "quest": "first_blood"}), "abandon")
	assert_eq(_quests.status_of(_player, &"first_blood"), "", "gone")
	assert_true(_do(&"quest.accept", {"actor": _player, "quest": "first_blood"}), "accepted again from nothing")
	assert_eq(_quests.quests_of(_player), [&"first_blood"] as Array[StringName], "one on the list")
	assert_true(_sim.commands().is_pause_safe(&"quest.accept") and _sim.commands().is_pause_safe(&"quest.abandon"), "both pause-safe")


func test_objectives_advance_from_credited_tagged_events_and_complete_once_with_the_reward() -> void:
	_setup()
	var other: int = _actors.spawn(&"arcade", 5)
	assert_true(_do(&"quest.accept", {"actor": _player, "quest": "first_blood"}), "accept")
	_hit(_player, ["weapon_class.handgun"])
	assert_eq(_quests.progress_of(_player, &"first_blood"), [1] as Array[int], "one hit")
	_hit(_player, ["weapon_class.rifle"])
	assert_eq(_quests.progress_of(_player, &"first_blood"), [1] as Array[int], "a rifle hit does not count")
	_hit(other, ["weapon_class.handgun"])
	assert_eq(_quests.progress_of(_player, &"first_blood"), [1] as Array[int], "another actor's hit does not count")
	var before: int = _items.items_in(ItemSystem.inventory_of(_player)).size()
	_hit(_player, ["weapon_class.handgun"])
	_hit(_player, ["weapon_class.handgun"])
	assert_eq(_quests.status_of(_player, &"first_blood"), "completed", "completed on the third")
	assert_eq(_completed.size(), 1, "one quest.completed")
	assert_eq(_completed[0]["actor"], _player, "for the player")
	assert_eq(_items.items_in(ItemSystem.inventory_of(_player)).size(), before + 15, "fifteen rounds of reward")
	_hit(_player, ["weapon_class.handgun"])
	assert_eq(_quests.progress_of(_player, &"first_blood"), [3] as Array[int], "no further count")
	assert_eq(_items.items_in(ItemSystem.inventory_of(_player)).size(), before + 15, "no further reward")
	assert_false(_do(&"quest.abandon", {"actor": _player, "quest": "first_blood"}), "a completed quest is kept")
	assert_false(_do(&"quest.accept", {"actor": _player, "quest": "first_blood"}), "and not accepted again")
	assert_eq(_quests.completed_count(), 1, "one completion counted")


func test_a_build_objective_credits_the_builder() -> void:
	_setup()
	var build: BuildSystem = SimAssembly.build_of(_sim)
	_actors.set_position(_player, Vector3i(500 * 1000, 0, 500 * 1000))
	assert_true(_do(&"quest.accept", {"actor": _player, "quest": "break_ground"}), "accept")
	for i: int in 3:
		assert_true(build.place(_player, &"foundation_block", Vector3i(500 * 1000 + i * 1000 + 500, 500, 500 * 1000 + 500), "") > 0, "placed %d" % i)
	assert_eq(_quests.status_of(_player, &"break_ground"), "completed", "three pieces placed")
	assert_eq(_items.items_in(ItemSystem.inventory_of(_player)).size(), 1, "a magazine of reward")
	assert_eq(_items.item_kind(_items.items_in(ItemSystem.inventory_of(_player))[0]), &"weapon_part", "the magazine")


func test_property_counts_are_bounded_and_completion_and_reward_happen_once() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	var violations: int = 0
	var completions: int = 0
	for case: int in PROPERTY_CASES / 50:
		_completed.clear()
		var db: ContentDb = _db()
		var count: int = rng.randi_range(1, 6)
		db.add(&"quest", &"t_quest", {"schema_version": 1, "description": "generated", "title": "t", "text": "t",
			"objectives": [{"description": "a", "event": "combat.hit", "credit": "shooter", "tags_any": ["weapon_class.handgun"], "count": count},
				{"description": "b", "event": "combat.fire", "credit": "shooter", "tags_any": [], "count": rng.randi_range(1, 4)}],
			"reward": [{"kind": "ammo", "template": "9x19_fmj", "count": 2}]})
		_setup(db)
		var other: int = _actors.spawn(&"arcade", 5)
		assert_true(_do(&"quest.accept", {"actor": _player, "quest": "t_quest"}), "accept")
		var t: Dictionary = db.get_entry(&"quest", &"t_quest")
		var objectives: Array = t["objectives"]
		var inv: StringName = ItemSystem.inventory_of(_player)
		var base_items: int = _items.items_in(inv).size()
		for i: int in rng.randi_range(0, 40):
			var who: int = _player if rng.randi_range(0, 3) > 0 else other
			if rng.randi_range(0, 1) == 0:
				var tag_sets: Array = [["weapon_class.handgun"], ["weapon_class.rifle"], []]
				var tags: Array = tag_sets[rng.randi_range(0, 2)]
				_hit(who, tags)
			else:
				_events.emit(CombatSystem.EVENT_FIRE, {"shooter": who, "weapon": 0, "target": 2, "round": 0, "tags": []})
			var progress: Array[int] = _quests.progress_of(_player, &"t_quest")
			for j: int in progress.size():
				var o: Dictionary = objectives[j]
				var limit: int = o["count"]
				if progress[j] > limit or progress[j] < 0:
					violations += 1
		var completed: bool = _quests.status_of(_player, &"t_quest") == "completed"
		var rewarded: int = _items.items_in(inv).size() - base_items
		if completed:
			completions += 1
		if _completed.size() != (1 if completed else 0) or rewarded != (2 if completed else 0) or _quests.completed_count() != (1 if completed else 0):
			violations += 1
			if violations <= 3:
				fail("case %d: completed %s, events %d, reward %d" % [case, completed, _completed.size(), rewarded])
	assert_eq(violations, 0, "counts bounded; completion and reward exactly once")
	assert_true(completions > 30, "enough completions (%d)" % completions)


func test_restore_round_trip_and_rejections() -> void:
	_setup()
	assert_true(_do(&"quest.accept", {"actor": _player, "quest": "first_blood"}), "accept")
	_hit(_player, ["weapon_class.handgun"])
	var snap: Dictionary = _sim.snapshot()
	var other: SimRoot = SimAssembly.build(SEED, _db())
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "restored")
	assert_eq(other.restore_root(snap), OK, "root restored")
	var quests: QuestSystem = SimAssembly.quests_of(other)
	assert_eq(quests.progress_of(_player, &"first_blood"), [1] as Array[int], "progress carried over")
	assert_eq(other.state_hash(), _sim.state_hash(), "hashes agree")
	var state: Dictionary = _quests.snapshot()
	assert_eq(quests.restore({}), ERR_INVALID_DATA, "empty")
	var bad: Dictionary = state.duplicate(true)
	var all: Dictionary = bad["quests"]
	var table: Dictionary = all[_player]
	var rec: Dictionary = table[&"first_blood"]
	rec["progress"] = [9]
	assert_eq(quests.restore(bad), ERR_INVALID_DATA, "progress past the target")
	bad = state.duplicate(true)
	all = bad["quests"]
	table = all[_player]
	rec = table[&"first_blood"]
	rec["status"] = "completed"
	assert_eq(quests.restore(bad), ERR_INVALID_DATA, "completed with unfinished objectives")
	bad = state.duplicate(true)
	all = bad["quests"]
	table = all[_player]
	table[&"nothing"] = table[&"first_blood"]
	assert_eq(quests.restore(bad), ERR_INVALID_DATA, "an unknown quest")
	assert_eq(quests.snapshot(), state, "rejections leave the state untouched")


## M6 spec claim 9: a contract with a `turn_in` block is not paid when the work is
## done but when it is carried to the fixer, and its money is scaled by the run's
## payout curve.

## content/parcel/fixers_office.json
const AT_THE_FIXER: Vector3i = Vector3i(6000, 0, 30000)
## content/quest/cold_storage.json pays twelve notes at the base rate
const NOTES: int = 12


func _hacked(actor: int) -> void:
	_events.emit(TerminalSystem.EVENT_HACKED, {"actor": actor, "terminal": 1, "template": &"cs_server", "data": 2, "signal": &"signal.data_theft"})


func _exfil(actor: int, tags: Array) -> void:
	_events.emit(MovementSystem.EVENT_LEFT_PARCEL, {"actor": actor, "parcel": &"cold_storage_lot", "tags": tags})


func _accept_and_do_the_work() -> void:
	assert_true(_do(&"quest.accept", {"actor": _player, "quest": "cold_storage"}), "accepted")
	assert_eq(_quests.status_of(_player, &"cold_storage"), QuestSystem.STATUS_ACTIVE, "active")
	_hacked(_player)
	_exfil(_player, ["nothing.useful"])
	assert_eq(_quests.progress_of(_player, &"cold_storage"), [1, 0] as Array[int], "leaving empty-handed is not an exfil")
	_exfil(_player, ["data.cold_storage"])
	assert_eq(_quests.progress_of(_player, &"cold_storage"), [1, 1] as Array[int], "out with the data")


func test_a_contract_is_not_paid_until_it_is_turned_in_at_the_fixer() -> void:
	_setup()
	var inv: StringName = ItemSystem.inventory_of(_player)
	_accept_and_do_the_work()
	assert_eq(_quests.status_of(_player, &"cold_storage"), QuestSystem.STATUS_READY, "the work is done, the job is not")
	assert_eq(_completed.size(), 0, "nothing completed yet")
	assert_eq(_items.credits_in(inv), 0, "and nothing paid")
	# the fixer is a place: you have to be standing in it
	assert_false(_do(&"quest.turn_in", {"actor": _player, "quest": "cold_storage"}), "not at the fixer")
	_actors.set_position(_player, AT_THE_FIXER)
	assert_false(_do(&"quest.turn_in", {"actor": _player, "quest": "nothing"}), "unknown quest")
	assert_false(_do(&"quest.turn_in", {"actor": 99, "quest": "cold_storage"}), "unknown actor")
	assert_false(_do(&"quest.turn_in", {"actor": _player}), "missing quest")
	assert_true(_do(&"quest.turn_in", {"actor": _player, "quest": "cold_storage"}), "turned in")
	assert_eq(_quests.status_of(_player, &"cold_storage"), QuestSystem.STATUS_COMPLETED, "completed")
	assert_eq(_completed.size(), 1, "one quest.completed, emitted at the fixer and not at the site")
	assert_false(_do(&"quest.turn_in", {"actor": _player, "quest": "cold_storage"}), "and only once")
	# a clean run doubles the money; the fixed part of the reward does not move
	assert_eq(_items.credits_in(inv), 2 * NOTES * 100, "a run nobody scored pays the clean bonus")
	var modules: int = 0
	for item: int in _items.items_in(inv):
		if _items.item_template(item) == &"radio_module":
			modules += 1
	assert_eq(modules, 1, "and the fixed module once")


func test_the_payout_is_scaled_by_the_run_that_earned_it() -> void:
	_setup()
	var inv: StringName = ItemSystem.inventory_of(_player)
	var score: RunScoreSystem = SimAssembly.score_of(_sim)
	var perception: PerceptionSystem = SimAssembly.perception_of(_sim)
	var guard: int = perception.spawn(&"guard_sim", BuildSystem.cell_of(Vector3i(400000, 0, 400000)), 0, 1, "")
	assert_true(_do(&"run.begin", {"actor": _player}), "the run starts with the contract")
	_accept_and_do_the_work()
	# a loud run: two sightings and a body, priced by content/payout_curve/fixer_standard
	_events.emit(PerceptionSystem.EVENT_ALERTED, {"observer": guard, "contact": _player, "tick": _sim.get_tick()})
	_events.emit(PerceptionSystem.EVENT_ALERTED, {"observer": guard, "contact": _player, "tick": _sim.get_tick()})
	_events.emit(CombatSystem.EVENT_HIT, {"shooter": _player, "weapon": 0, "target": guard, "node": &"body", "damage": 1, "range_m": 5, "tags": [], "killed": true})
	assert_true(_do(&"run.end", {"actor": _player}), "and ends when you hand it over")
	var multiplier: int = score.multiplier(_player, &"fixer_standard")
	assert_eq(multiplier, 1000 - 2 * 100 - 400, "two sightings and a body, the body still standing")
	_actors.set_position(_player, AT_THE_FIXER)
	assert_true(_do(&"quest.turn_in", {"actor": _player, "quest": "cold_storage"}), "turned in")
	assert_eq(_items.credits_in(inv), NOTES * multiplier / 1000 * 100, "the payout is the contract's notes scaled by the run")
	assert_true(_items.credits_in(inv) < 2 * NOTES * 100, "and less than a clean run would have paid")


func test_a_ready_contract_survives_the_round_trip() -> void:
	_setup()
	_accept_and_do_the_work()
	assert_eq(_quests.status_of(_player, &"cold_storage"), QuestSystem.STATUS_READY, "ready")
	var snap: Dictionary = _sim.snapshot()
	var other: SimRoot = SimAssembly.build(SEED, _db())
	assert_eq(SimAssembly.restore_systems(other, snap), OK, "restored")
	assert_eq(other.restore_root(snap), OK, "root restored")
	var quests: QuestSystem = SimAssembly.quests_of(other)
	assert_eq(quests.status_of(_player, &"cold_storage"), QuestSystem.STATUS_READY, "still waiting to be handed over")
	_sim.step()
	other.step()
	assert_eq(other.state_hash(), _sim.state_hash(), "hashes agree")
	# a status that disagrees with the work, and a `ready` on a quest with no turn-in
	var state: Dictionary = _quests.snapshot()
	var bad: Dictionary = state.duplicate(true)
	var all: Dictionary = bad["quests"]
	var table: Dictionary = all[_player]
	table[&"cold_storage"] = {"status": QuestSystem.STATUS_ACTIVE, "progress": [1, 1]}
	assert_eq(quests.restore(bad), ERR_INVALID_DATA, "active, but the work is done")
	bad = state.duplicate(true)
	all = bad["quests"]
	table = all[_player]
	table[&"first_blood"] = {"status": QuestSystem.STATUS_READY, "progress": [1]}
	assert_eq(quests.restore(bad), ERR_INVALID_DATA, "ready, on a quest with nothing to turn in")
	assert_eq(quests.snapshot(), state, "rejections leave the state untouched")
