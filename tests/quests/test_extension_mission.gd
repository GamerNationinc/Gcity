extends GcityTest

## The M6 extension exercise (engineering standards §11, gate question Q4): a second
## contract against the same site, with its own machine behind its own door, priced by
## its own sheet, added in content files alone.
##
## What this test is really asserting is the shape of the diff that produced it: six
## new content files, a partition and a terminal in `tools/make_sites.gd`, and nothing
## under `sim/`. If the second contract had needed a line of simulation, the first one
## was not content — it was a special case wearing content's clothes.

const SEED: int = 20261240
const QUEST: StringName = &"cold_storage_returns"
const SITE: StringName = &"cold_storage"
const CURVE: StringName = &"fixer_patient"
## content/quest/cold_storage_returns.json
const NOTES: int = 18
## content/parcel/fixers_office.json
const AT_THE_FIXER: Vector3i = Vector3i(6000, 0, 30000)

var _sim: SimRoot
var _sites: SiteSystem
var _terminals: TerminalSystem
var _actors: ActorSystem
var _items: ItemSystem
var _quests: QuestSystem
var _movement: MovementSystem
var _events: EventBus
var _player: int = 0
var _operator: int = 0


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	_sites = SimAssembly.sites_of(_sim)
	_terminals = SimAssembly.terminals_of(_sim)
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_quests = SimAssembly.quests_of(_sim)
	_movement = SimAssembly.movement_of(_sim)
	_events = SimAssembly.combat_of(_sim).events()
	_operator = _actors.spawn(&"arcade", 0)
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, &"land.identify", {"actor": _operator, "owner": "corp.coldchain"})), OK, "identify")
	_sim.step()
	assert_true(_sites.raise_site(_operator, SITE), "the site stands")
	_player = _actors.spawn(&"arcade", 0)
	# the archive sits where the guards patrol; being shot is the mission fixtures' job
	for guard: int in _sites.agents_of(SITE):
		_actors.wield(guard, EntityIds.NONE)


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


func _at(rel: Vector3i) -> Vector3i:
	var centre: Vector3i = BuildSystem.cell_centre(_sites.cell_of(SITE, rel))
	return Vector3i(centre.x, rel.y * 1000, centre.z)


func _archive() -> int:
	for terminal: int in _sites.terminals_of(SITE):
		if _terminals.template_of(terminal) == &"cs_archive":
			return terminal
	return EntityIds.NONE


func test_the_site_gained_a_second_machine_behind_its_own_door() -> void:
	_setup()
	assert_eq(_sites.terminals_of(SITE).size(), 2, "two machines now")
	var archive: int = _archive()
	assert_true(archive != EntityIds.NONE, "the archive is one of them")
	assert_eq(_terminals.hack_ticks_of(archive), 640, "twice the sit of the server outside it")
	# the door reads the actor, exactly as the lobby's does
	_actors.set_position(_player, _at(Vector3i(2, 1, 10)))
	# a step is 150 mm and a cell is a metre, so one refused move proves nothing: walk
	# at it until either the cell changes or it is plainly not going to
	var got_in: bool = false
	for i: int in 14:
		_movement.move(_player, 0, 150, 0)
		if BuildSystem.cell_of(_actors.position_of(_player)) == _sites.cell_of(SITE, Vector3i(2, 1, 11)):
			got_in = true
			break
	assert_false(got_in, "no token: the archive door is a wall")
	var token: int = _items.spawn(&"ammo", &"archive_token", ItemSystem.inventory_of(_player), 1)
	assert_true(token > 0, "a maintenance token")
	var walked: bool = false
	for i: int in 12:
		if _movement.move(_player, 0, 150, 0):
			walked = true
		if BuildSystem.cell_of(_actors.position_of(_player)) == _sites.cell_of(SITE, Vector3i(2, 1, 11)):
			break
	assert_true(walked, "with it, the door opens")
	assert_eq(BuildSystem.cell_of(_actors.position_of(_player)), _sites.cell_of(SITE, Vector3i(2, 1, 11)), "inside the archive")


func test_the_second_contract_is_paid_by_its_own_sheet() -> void:
	_setup()
	var inv: StringName = ItemSystem.inventory_of(_player)
	assert_true(_quests.quest_ids().has(QUEST), "the contract is on record")
	var terms: Dictionary = _quests.turn_in_of(QUEST)
	assert_eq(terms["curve"], "fixer_patient", "priced by its own sheet, not the standard one")
	assert_eq(terms["notes"], NOTES, "and its own number of notes")
	assert_true(_do(&"quest.accept", {"actor": _player, "quest": String(QUEST)}), "accepted")
	assert_true(_do(&"run.begin", {"actor": _player}), "the run starts")
	# in through the archive door and hack the machine behind it
	assert_true(_items.spawn(&"ammo", &"archive_token", inv, 1) > 0, "a token")
	var handset: int = _items.spawn(&"device_frame", &"handset", inv, 2)
	var module: int = _items.spawn(&"device_module", &"daemon_coprocessor", inv, 3)
	assert_true(_do(&"actor.equip_device", {"actor": _player, "device": handset}), "carried")
	assert_true(_do(&"item.attach", {"actor": _player, "weapon": handset, "part": module}), "fitted")
	var archive: int = _archive()
	_actors.set_position(_player, _terminals.position_of(archive))
	assert_true(_do(&"terminal.hack_start", {"actor": _player, "terminal": archive}), "hacking the archive")
	_sim.step_n(_terminals.hack_ticks_of(archive) + 2)
	assert_eq(_quests.progress_of(_player, QUEST)[0], 1, "the machine is done")
	var carried: bool = false
	for item: int in _items.items_in(inv):
		if _items.item_template(item) == &"archive_data":
			carried = true
	assert_true(carried, "and the archive is in the bag")
	# the exfil objective reads what is being carried, which is the only thing that
	# tells the two contracts apart: the data only comes off this machine
	_events.emit(MovementSystem.EVENT_LEFT_PARCEL, {"actor": _player, "parcel": &"cold_storage_lot", "tags": ["nothing.useful"]})
	assert_eq(_quests.progress_of(_player, QUEST)[1], 0, "leaving empty-handed is not an exfil")
	_events.emit(MovementSystem.EVENT_LEFT_PARCEL, {"actor": _player, "parcel": &"cold_storage_lot", "tags": ["data.archive"]})
	assert_eq(_quests.status_of(_player, QUEST), QuestSystem.STATUS_READY, "the work is done")
	assert_true(_do(&"run.end", {"actor": _player}), "the run ends")
	_actors.set_position(_player, AT_THE_FIXER)
	assert_true(_do(&"quest.turn_in", {"actor": _player, "quest": String(QUEST)}), "handed in")
	assert_eq(_quests.status_of(_player, QUEST), QuestSystem.STATUS_COMPLETED, "completed")
	# the machine was left switched on, which this sheet barely minds: 1200 less 40,
	# where the standard sheet would take 150 for the same untidiness
	var score: RunScoreSystem = SimAssembly.score_of(_sim)
	assert_eq(score.counters(_player)[3], 1, "one trace: the archive was never wiped")
	assert_eq(score.multiplier(_player, CURVE), 1200 - 40, "the patient sheet hardly notices")
	assert_eq(score.multiplier(_player, &"fixer_standard"), 1000 - 150, "the standard one minds more")
	assert_eq(_items.credits_in(inv), NOTES * 1160 / 1000 * 100, "eighteen notes at the patient rate")


func test_the_two_sheets_disagree_about_what_a_run_was_worth() -> void:
	_setup()
	var score: RunScoreSystem = SimAssembly.score_of(_sim)
	assert_true(_do(&"run.begin", {"actor": _player}), "a run")
	var perception: PerceptionSystem = SimAssembly.perception_of(_sim)
	var guard: int = _sites.agents_of(SITE)[0]
	var victim: int = _actors.spawn(&"arcade", 0)
	# one body, one trace: the standard sheet and the patient one price these apart
	_events.emit(CombatSystem.EVENT_HIT, {"shooter": _player, "weapon": 0, "target": victim, "node": &"body", "damage": 1, "range_m": 5, "tags": [], "killed": true})
	_actors.damage_node(victim, &"body", 999999)
	assert_eq(score.counters(_player)[2], 1, "a body")
	assert_eq(score.counters(_player)[3], 1, "left where it fell")
	assert_eq(score.multiplier(_player, &"fixer_standard"), 1000 - 400 - 150, "the standard sheet")
	assert_eq(score.multiplier(_player, CURVE), 1200 - 500 - 40, "the patient one: dearer for the body, almost free for the mess")
	assert_true(perception.is_alerted(guard, _player) == false, "nobody saw any of this")
