extends GcityTest

## The agents' side of M6 spec claims 8 and 10. Movement announces every cell change
## as `actor.moved` (steps, climbs, falls), which sensors watch. A lock with a
## `heat_max` still lets a card-carrier through, but flags the door check when the
## passer's heat is over it. A squad takes a report from something that is not a
## member (a sensor) and delivers it on the tick it is made.

const SEED: int = 20261170
const M: int = 1000
const FAR_CELL: Vector3i = Vector3i(500, 0, 500)
const TAG: StringName = &"access.test"

var _sim: SimRoot
var _actors: ActorSystem
var _build: BuildSystem
var _items: ItemSystem
var _movement: MovementSystem
var _perception: PerceptionSystem
var _squads: SquadSystem
var _standing: StandingSystem
var _player: int = 0
var _moved: Array[Dictionary] = []
var _checks: Array[Dictionary] = []
var _reports: Array[Dictionary] = []


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	assert_eq(db.add(&"build_piece", &"zz_front_door", {
		"schema_version": 1, "description": "A card door that minds your heat.", "kind": "door",
		"material": "scrap_steel", "open_cost": 40, "value": 0, "lock": {"requires_tag": String(TAG), "heat_max": 2000},
	}), OK, "a door with a heat limit")
	assert_eq(db.add(ItemSystem.KIND_TOOL, &"zz_card", {
		"schema_version": 1, "description": "Its card.", "tool_class": "cutter", "tags": [String(TAG)], "stats": [],
	}), OK, "its card")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_build = SimAssembly.build_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_movement = SimAssembly.movement_of(_sim)
	_perception = SimAssembly.perception_of(_sim)
	_squads = SimAssembly.squads_of(_sim)
	_standing = SimAssembly.standing_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	var moved: Array[Dictionary] = []
	var checks: Array[Dictionary] = []
	var reports: Array[Dictionary] = []
	_moved = moved
	_checks = checks
	_reports = reports
	var events: EventBus = SimAssembly.combat_of(_sim).events()
	events.subscribe(MovementSystem.EVENT_MOVED, func(p: Dictionary) -> void: moved.append(p))
	events.subscribe(MovementSystem.EVENT_DOOR_CHECK, func(p: Dictionary) -> void: checks.append(p))
	events.subscribe(SquadSystem.EVENT_REPORT, func(p: Dictionary) -> void: reports.append(p))


func _c(x: int, y: int, z: int) -> Vector3i:
	return FAR_CELL + Vector3i(x, y, z)


static func _floor_of(cell: Vector3i) -> Vector3i:
	return Vector3i(cell.x * M + M / 2, cell.y * M, cell.z * M + M / 2)


static func _arr(c: Vector3i) -> Array[int]:
	return [c.x, c.y, c.z] as Array[int]


func test_every_cell_change_is_announced_and_nothing_else_is() -> void:
	_setup()
	_build.place_batch([[&"foundation_block", _c(0, 0, 0), ""], [&"storage_crate", _c(1, 0, 0), ""]] as Array[Array])
	_actors.set_position(_player, _floor_of(_c(2, 0, 0)))
	assert_true(_movement.move(_player, 100, 0), "a step inside the cell")
	assert_eq(_moved.size(), 0, "is no cell change")
	for i: int in 3:
		assert_true(_movement.move(_player, 0, 150), "towards the next cell")
	assert_eq(_moved.size(), 0, "still inside it")
	assert_true(_movement.move(_player, 0, 150), "a step across into the next")
	assert_eq(_moved.size(), 1, "is one")
	var first: Dictionary = _moved[0]
	var who: int = first["actor"]
	var from: Array = first["from"]
	var to: Array = first["to"]
	assert_eq(who, _player, "the player's")
	assert_eq(from, _arr(_c(2, 0, 0)) as Array, "from its cell")
	assert_eq(to, _arr(_c(2, 0, 1)) as Array, "to the next")
	_actors.set_position(_player, _floor_of(_c(2, 0, 0)))
	assert_true(_movement.climb(_player, MovementSystem.DIR_UP, "nx"), "up onto the crate")
	var climbed: Dictionary = _moved[_moved.size() - 1]
	var climbed_to: Array = climbed["to"]
	assert_eq(climbed_to, _arr(_c(1, 1, 0)) as Array, "a climb is a cell change")
	var count: int = _moved.size()
	for i: int in 8:
		_movement.move(_player, 0, 150)
	var fell: Dictionary = _moved[_moved.size() - 1]
	var fell_to: Array = fell["to"]
	assert_eq(_moved.size(), count + 1, "off the crate's side: one change, the fall included")
	assert_eq(fell_to, _arr(_c(1, 0, 1)) as Array, "to where the fall ends")


func test_a_hot_card_carrier_is_let_through_but_flagged() -> void:
	_setup()
	var ids: Array[Array] = [[&"foundation_block", _c(2, 0, -1), ""], [&"foundation_block", _c(2, 0, 1), ""], [&"zz_front_door", _c(2, 0, 0), "px"]]
	assert_eq(_build.place_batch(ids).size(), 3, "the front door")
	_items.spawn(ItemSystem.KIND_TOOL, &"zz_card", ItemSystem.inventory_of(_player), 1)
	_actors.set_position(_player, _floor_of(_c(2, 0, 0)))
	for i: int in 3:
		_movement.move(_player, 150, 0)
	assert_true(_movement.move(_player, 150, 0), "cold: through")
	var cold: Dictionary = _checks[0]
	var cold_passed: bool = cold["passed"]
	var cold_flagged: bool = cold["flagged"]
	assert_true(cold_passed and not cold_flagged, "passed, not flagged")
	_standing.raise(_player, &"heat", 2001)
	for i: int in 5:
		_movement.move(_player, -150, 0)
	var hot: Dictionary = _checks[_checks.size() - 1]
	var hot_passed: bool = hot["passed"]
	var hot_flagged: bool = hot["flagged"]
	assert_true(hot_passed, "hot: still through, the card is good")
	assert_true(hot_flagged, "but flagged: heat over the lock's limit")
	assert_eq(BuildSystem.cell_of(_actors.position_of(_player)), _c(2, 0, 0), "back through")


func test_a_squad_takes_a_report_from_outside_it_on_the_tick() -> void:
	_setup()
	_actors.set_position(_player, _floor_of(_c(0, 0, 0)))
	var a: int = _perception.spawn(&"guard_sim", _c(-30, 0, 0), 180, 7, "")
	var b: int = _perception.spawn(&"guard_sim", _c(-30, 0, 5), 180, 7, "")
	var other: int = _perception.spawn(&"guard_sim", _c(-30, 0, 10), 180, 8, "")
	_squads.report_from_outside(7, _player, _c(0, 0, 0), _sim.get_tick() + 1)
	_sim.step()
	assert_eq(_reports.size(), 1, "one report delivered on the tick")
	var r: Dictionary = _reports[0]
	var reporter: int = r["reporter"]
	var informed: Array = r["informed"]
	assert_eq(reporter, EntityIds.NONE, "from no member")
	assert_eq(informed.size(), 2, "both members told")
	assert_true(_perception.is_alerted(a, _player) and _perception.is_alerted(b, _player), "and alerted")
	assert_false(_perception.is_alerted(other, _player), "the other squad was not")
	assert_eq(_perception.last_known(a, _player), _floor_of(_c(0, 0, 0)), "at the reported cell")
