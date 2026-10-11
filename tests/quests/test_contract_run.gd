extends GcityTest

## M6 spec claim 14: the contract is a quest with a site, a fixer and a score.
## quest.accept needs the fixer within reach, spawns the site and opens a run record;
## the run counts times detected, alarms raised, bodies and traces left from bus events
## only; exfil is leaving the site's exfil polygon carrying the deliverable;
## contract.deliver at the fixer hands it over and pays base x the scoring multiplier.
## Properties (10 000 generated event streams): the counters equal a straightforward
## recount of the stream, and the multiplier never rises when any counter rises.

const SEED: int = 20261043
const SEED_PROPERTY: int = 20261044
const PROPERTY_CASES: int = 10_000
const QUEST: StringName = &"cold_storage_contract"
const SITE: StringName = &"cold_storage"
const FIXER_CELL: Vector3i = Vector3i(14, 0, -3)

var _sim: SimRoot
var _player: int = 0
var _quests: QuestSystem
var _sites: SiteSystem
var _actors: ActorSystem
var _events: EventBus
var _origin: Vector3i


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_quests = SimAssembly.quests_of(_sim)
	_sites = SimAssembly.sites_of(_sim)
	_actors = SimAssembly.actors_of(_sim)
	_events = SimAssembly.combat_of(_sim).events()
	_player = _actors.spawn(&"arcade", 0)
	_origin = _sites.placement_of(SITE)


func _feet(cell: Vector3i) -> Vector3i:
	return BuildSystem.cell_centre(cell) - Vector3i(0, BuildSystem.CELL / 2, 0)


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload))
	_sim.step()
	return _sim.dispatched_count() == before + 1


func _accept() -> bool:
	_actors.set_position(_player, _feet(FIXER_CELL + Vector3i(1, 0, 0)))
	return _do(&"quest.accept", {"actor": _player, "quest": String(QUEST)})


func _counters() -> Dictionary:
	var run: Dictionary = _quests.run_of(_player, QUEST)
	return run["counters"]


## Gets the records out: holds the drive inside the site, then steps outside it.
func _exfil() -> void:
	SimAssembly.items_of(_sim).spawn(&"key_item", &"cold_storage_data", ItemSystem.inventory_of(_player), 77)
	_actors.set_position(_player, _feet(_origin + Vector3i(12, 0, 4)))
	_sim.step()
	_actors.set_position(_player, _feet(_origin + Vector3i(12, 0, 30)))
	_sim.step()


func test_accepting_needs_the_fixer_and_spawns_the_site() -> void:
	_setup()
	_actors.set_position(_player, _feet(FIXER_CELL + Vector3i(10, 0, 0)))
	assert_false(_do(&"quest.accept", {"actor": _player, "quest": String(QUEST)}), "too far from Marlow: refused")
	assert_false(_sites.is_spawned(SITE), "and nothing spawned")
	assert_true(_accept(), "at Marlow: accepted")
	assert_true(_sites.is_spawned(SITE), "Cold Storage stands")
	assert_eq(_sites.origin_of(SITE), _origin, "where the contract puts it")
	assert_eq(_counters(), {"times_detected": 0, "alarms_raised": 0, "bodies": 0, "traces_left": 0}, "a clean run record")
	assert_false(_do(&"quest.accept", {"actor": _player, "quest": String(QUEST)}), "not twice")


func test_the_counters_count_their_events_and_only_theirs() -> void:
	_setup()
	assert_true(_accept(), "accepted")
	var other: int = _actors.spawn(&"arcade", 1)
	var guards: Array[int] = _sites.agents_of(SITE)
	var camera: int = EntityIds.NONE
	var guard: int = EntityIds.NONE
	for a: int in guards:
		if SimAssembly.perception_of(_sim).profile_of(a) == &"camera":
			camera = a
		else:
			guard = a
	_events.emit(PerceptionSystem.EVENT_ALERTED, {"observer": guard, "contact": _player, "tick": 1})
	_events.emit(PerceptionSystem.EVENT_ALERTED, {"observer": guard, "contact": other, "tick": 1})
	_events.emit(SquadSystem.EVENT_REPORT, {"squad": 1, "reporter": guard, "contact": _player, "cell": [0, 0, 0], "informed": []})
	_events.emit(CombatSystem.EVENT_HIT, {"shooter": _player, "weapon": 0, "target": guard, "node": &"body", "damage": 1, "range_m": 1, "tags": [], "killed": true})
	_events.emit(CombatSystem.EVENT_HIT, {"shooter": _player, "weapon": 0, "target": camera, "node": &"body", "damage": 1, "range_m": 1, "tags": [], "killed": true})
	_events.emit(CombatSystem.EVENT_HIT, {"shooter": _player, "weapon": 0, "target": other, "node": &"body", "damage": 1, "range_m": 1, "tags": [], "killed": true})
	_events.emit(CombatSystem.EVENT_HIT, {"shooter": _player, "weapon": 0, "target": guard, "node": &"body", "damage": 1, "range_m": 1, "tags": [], "killed": false})
	var pieces: Array[int] = _sites.pieces_of(SITE)
	var build: BuildSystem = SimAssembly.build_of(_sim)
	var wall: int = build.face_piece_at(BuildSystem.face_key(_origin + Vector3i(3, 0, 0), "nz"))
	var window: int = build.face_piece_at(BuildSystem.face_key(_origin + Vector3i(9, 1, 1), "px"))
	assert_true(pieces.has(wall) and pieces.has(window), "a site wall and the maintenance window")
	_events.emit(BuildSystem.EVENT_BREACHED, {"actor": _player, "piece": wall, "removed": [wall]})
	_events.emit(BuildSystem.EVENT_BREACHED, {"actor": _player, "piece": window, "removed": [window]})
	_events.emit(BuildSystem.EVENT_BREACHED, {"piece": wall, "removed": [wall]})
	assert_eq(_counters(), {"times_detected": 1, "alarms_raised": 1, "bodies": 1, "traces_left": 2}, "one of each, the camera and the wall as traces; the window waits for exfil")
	# a login left on the terminal and the forced window both count once at exfil
	var terminal: int = EntityIds.NONE
	for target: int in _sites.targets_of(SITE):
		if SimAssembly.hacks_of(_sim).snapshot()["targets"][target]["target"] == &"cold_storage_terminal":
			terminal = target
	var hacks: HackSystem = SimAssembly.hacks_of(_sim)
	# a login needs a device that holds it (a slot), or the hack system drops it
	var items: ItemSystem = SimAssembly.items_of(_sim)
	var inv: StringName = ItemSystem.inventory_of(_player)
	var device: int = items.spawn(&"device_frame", &"handset", inv, 91)
	var cop: int = items.spawn(&"device_module", &"daemon_coprocessor", inv, 92)
	assert_true(_do(&"actor.equip_device", {"actor": _player, "device": device}), "a device")
	assert_true(_do(&"item.attach", {"actor": _player, "weapon": device, "part": cop}), "with a coprocessor")
	var snap: Dictionary = hacks.snapshot()
	snap["logins"] = {_player: [terminal]}
	var targets: Dictionary = snap["targets"]
	var trec: Dictionary = targets[terminal]
	trec["done"] = true
	assert_eq(hacks.restore(snap), OK, "a login left on the terminal")
	_exfil()
	var run: Dictionary = _quests.run_of(_player, QUEST)
	var out: bool = run["exfil"]
	assert_true(out, "out")
	assert_eq(_counters()["traces_left"], 4, "plus the forced window and the login")
	_events.emit(PerceptionSystem.EVENT_ALERTED, {"observer": guard, "contact": _player, "tick": 1})
	assert_eq(_counters()["times_detected"], 1, "after exfil the run is closed to counting")


func test_a_clean_run_pays_the_full_stealth_rate_and_completes_the_quest() -> void:
	_setup()
	assert_true(_accept(), "accepted")
	var delivered: Array[Dictionary] = []
	_events.subscribe(QuestSystem.EVENT_DELIVERED, func(p: Dictionary) -> void: delivered.append(p))
	assert_false(_do(&"contract.deliver", {"actor": _player, "quest": String(QUEST)}), "nothing to deliver yet: refused")
	_exfil()
	assert_false(_do(&"contract.deliver", {"actor": _player, "quest": String(QUEST)}), "out of Marlow's reach: refused")
	_actors.set_position(_player, _feet(FIXER_CELL + Vector3i(1, 0, 0)))
	assert_true(_do(&"contract.deliver", {"actor": _player, "quest": String(QUEST)}), "delivered")
	assert_eq(SimAssembly.wallet_of(_sim).balance_of(_player), 2000, "1000 base x 2.0 for a ghost run")
	assert_eq(delivered.size(), 1, "contract.delivered")
	assert_eq(delivered[0]["tier"], "ghost", "the ghost tier")
	assert_eq(_quests.status_of(_player, QUEST), QuestSystem.STATUS_COMPLETED, "the quest completes")
	assert_eq(SimAssembly.items_of(_sim).items_in(ItemSystem.fixer_container(&"marlow")).size(), 1, "Marlow has the drive")
	assert_eq(SimAssembly.standing_of(_sim).standing_of(_player, &"notoriety"), 100, "and the player's notoriety rose")
	assert_false(_do(&"contract.deliver", {"actor": _player, "quest": String(QUEST)}), "once")


func test_a_loud_run_still_completes_and_pays_less() -> void:
	_setup()
	assert_true(_accept(), "accepted")
	var guard: int = _sites.agents_of(SITE)[1]
	for i: int in 4:
		_events.emit(SquadSystem.EVENT_REPORT, {"squad": 1, "reporter": guard, "contact": _player, "cell": [0, 0, 0], "informed": []})
	_exfil()
	_actors.set_position(_player, _feet(FIXER_CELL + Vector3i(1, 0, 0)))
	assert_true(_do(&"contract.deliver", {"actor": _player, "quest": String(QUEST)}), "delivered")
	assert_eq(SimAssembly.wallet_of(_sim).balance_of(_player), 500, "four alarms: no tier fits, 1000 x 0.5")
	assert_eq(_quests.status_of(_player, QUEST), QuestSystem.STATUS_COMPLETED, "it still completes")


func test_property_counters_equal_a_recount_and_the_multiplier_is_monotone() -> void:
	_setup()
	assert_true(_accept(), "accepted")
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	var other: int = _actors.spawn(&"arcade", 1)
	var agents: Array[int] = _sites.agents_of(SITE)
	var walls: Array[int] = []
	for id: int in _sites.pieces_of(SITE):
		if SimAssembly.build_of(_sim).kind_of(id) == &"wall":
			walls.append(id)
	var expected: Dictionary[String, int] = {"times_detected": 0, "alarms_raised": 0, "bodies": 0, "traces_left": 0}
	var mismatches: int = 0
	for i: int in PROPERTY_CASES:
		var who: int = _player if rng.randi_range(0, 3) > 0 else other
		match rng.randi_range(0, 3):
			0:
				_events.emit(PerceptionSystem.EVENT_ALERTED, {"observer": agents[0], "contact": who, "tick": i})
				if who == _player:
					expected["times_detected"] += 1
			1:
				_events.emit(SquadSystem.EVENT_REPORT, {"squad": 1, "reporter": agents[0], "contact": who, "cell": [0, 0, 0], "informed": []})
				if who == _player:
					expected["alarms_raised"] += 1
			2:
				var target: int = agents[rng.randi_range(0, agents.size() - 1)] if rng.randi_range(0, 2) > 0 else other
				var killed: bool = rng.randi_range(0, 1) == 0
				_events.emit(CombatSystem.EVENT_HIT, {"shooter": who, "weapon": 0, "target": target, "node": &"body", "damage": 1, "range_m": 1, "tags": [], "killed": killed})
				if who == _player and killed and agents.has(target):
					var key: String = "traces_left" if SimAssembly.perception_of(_sim).profile_of(target) == &"camera" else "bodies"
					expected[key] += 1
			3:
				var wall: int = walls[rng.randi_range(0, walls.size() - 1)]
				_events.emit(BuildSystem.EVENT_BREACHED, {"actor": who, "piece": wall, "removed": [wall]})
				if who == _player:
					expected["traces_left"] += 1
		var got: Dictionary = _counters()
		for k: String in QuestSystem.COUNTERS:
			var n: int = got[k]
			if n != expected[k]:
				mismatches += 1
				break
	assert_eq(mismatches, 0, "the counters always equal the recount")
	# the multiplier never rises when a counter rises
	var content: ContentDb = _sim.get_system(ContentDb.SYSTEM_ID)
	var scoring: Dictionary = content.get_entry(&"quest", QUEST)["scoring"]
	var rises: int = 0
	for i: int in PROPERTY_CASES:
		var c: Dictionary[String, int] = {}
		for k: String in QuestSystem.COUNTERS:
			c[k] = rng.randi_range(0, 8)
		var louder: Dictionary[String, int] = c.duplicate()
		var k2: String = QuestSystem.COUNTERS[rng.randi_range(0, 3)]
		louder[k2] += rng.randi_range(1, 3)
		var a: int = QuestSystem.score(scoring, c)[0]
		var b: int = QuestSystem.score(scoring, louder)[0]
		if b > a:
			rises += 1
	assert_eq(rises, 0, "a louder run never pays more")
