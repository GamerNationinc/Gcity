extends GcityTest

## M6 spec claims 14 and 16 (ADR-007 C): a death leaves a body with what the actor
## carried, less the share the district's `law_index` impounds; the hands are emptied;
## `actor.died` names the body and the killer. `actor.respawn` brings the dead back,
## whole, at the respawn point of the home `actor.set_home` gave them. Property: no
## item is ever made or lost across deaths, bodies, impounds, takes and respawns.

const SEED: int = 20261230
const SEED_CONSERVATION: int = 20261231
const PROPERTY_CASES: int = 10_000
const M: int = 1000
const FAR_CELL: Vector3i = Vector3i(500, 0, 500)
## A parcel in the corporate core, far from everything else, for a death there.
const CORE_CELL: Vector3i = Vector3i(-500, 0, -500)

var _sim: SimRoot
var _actors: ActorSystem
var _items: ItemSystem
var _loot: LootSystem
var _deaths: DeathSystem
var _player: int = 0
var _died: Array[Dictionary] = []


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var x0: int = CORE_CELL.x * M
	var z0: int = CORE_CELL.z * M
	assert_eq(db.add(&"parcel", &"zz_core_lot", {"schema_version": 1, "description": "A corporate lot.", "district": "corporate_core", "owner": "",
		"footprint": [[x0, z0], [x0 + 20000, z0], [x0 + 20000, z0 + 20000], [x0, z0 + 20000]], "floor_y": -3000, "ceiling_y": 9000}), OK, "a core lot")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_loot = SimAssembly.loot_of(_sim)
	_deaths = SimAssembly.deaths_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, _floor_of(FAR_CELL))
	var died: Array[Dictionary] = []
	_died = died
	SimAssembly.combat_of(_sim).events().subscribe(DeathSystem.EVENT_DIED, func(p: Dictionary) -> void: died.append(p))


static func _floor_of(cell: Vector3i) -> Vector3i:
	return Vector3i(cell.x * M + M / 2, cell.y * M, cell.z * M + M / 2)


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload))
	_sim.step()
	return _sim.dispatched_count() == before + 1


## Kills an actor the way combat does: its fatal node to zero, then the hit event.
func _kill(actor: int, killer: int) -> void:
	_actors.damage_node(actor, &"body", 1_000_000)
	SimAssembly.combat_of(_sim).events().emit(CombatSystem.EVENT_HIT, {"shooter": killer, "weapon": 0, "target": actor, "node": &"body",
		"damage": 1_000_000, "range_m": 1, "tags": [] as Array, "killed": true})


func _kit(actor: int, pieces: int) -> Array[int]:
	var inv: StringName = ItemSystem.inventory_of(actor)
	var out: Array[int] = []
	out.append(_items.spawn(ItemSystem.KIND_FRAME, &"g19", inv, actor * 1000))
	out.append(_items.spawn(ItemSystem.KIND_DEVICE_FRAME, &"handset", inv, actor * 1000 + 1))
	for i: int in pieces - 2:
		out.append(_items.spawn(ItemSystem.KIND_AMMO, &"9x19_fmj", inv, actor * 1000 + 2 + i))
	return out


func _all_placed() -> Array[int]:
	var snap: Dictionary = _items.snapshot()
	var containers: Dictionary = snap["containers"]
	var out: Array[int] = []
	for name: Variant in containers:
		var list: Array = containers[name]
		for v: Variant in list:
			var id: int = v
			out.append(id)
	out.sort()
	return out


func test_a_death_in_the_badlands_leaves_nearly_everything_on_the_body() -> void:
	_setup()
	var kit: Array[int] = _kit(_player, 10)
	_do(&"actor.wield", {"actor": _player, "weapon": kit[0]})
	_do(&"actor.equip_device", {"actor": _player, "device": kit[1]})
	var killer: int = _actors.spawn(&"arcade", 0)
	_kill(_player, killer)
	_sim.step()
	assert_eq(_died.size(), 1, "actor.died")
	var ev: Dictionary = _died[0]
	var who: int = ev["actor"]
	var by: int = ev["killer"]
	var body: int = ev["corpse"]
	var impounded: int = ev["impounded"]
	assert_eq(who, _player, "the player died")
	assert_eq(by, killer, "at the killer's hand")
	var law: int = _law_at(_actors.position_of(_player))
	assert_eq(impounded, 10 * law / 1000, "the badlands' law impounds %d of 10" % (10 * law / 1000))
	assert_eq(_items.items_in(_loot.container_name(body)).size(), 10 - impounded, "the rest is on the body")
	assert_eq(_loot.owner_of(body), _player, "the player's body")
	assert_eq(_loot.position_of(body), _actors.position_of(_player), "where they fell")
	assert_eq(_items.items_in(ItemSystem.inventory_of(_player)).size(), 0, "nothing left in the pockets")
	assert_eq(_actors.wielded(_player), EntityIds.NONE, "hands empty")
	assert_eq(_actors.device_of(_player), EntityIds.NONE, "device gone with the kit")


func test_a_death_in_the_corporate_core_is_mostly_impounded() -> void:
	_setup()
	_actors.set_position(_player, _floor_of(CORE_CELL + Vector3i(5, 0, 5)))
	var kit: Array[int] = _kit(_player, 20)
	_kill(_player, EntityIds.NONE)
	_sim.step()
	var ev: Dictionary = _died[0]
	var impounded: int = ev["impounded"]
	assert_eq(impounded, 20 * 950 / 1000, "950 of every 1000: 19 of 20")
	assert_eq(_items.items_in(_deaths.impound_of(_player)).size(), 19, "in the impound")
	var body: int = ev["corpse"]
	assert_eq(_items.items_in(_loot.container_name(body)).size(), 1, "one left on the body")
	var all: Array[int] = kit.duplicate()
	all.sort()
	assert_eq(_all_placed().filter(func(i: int) -> bool: return all.has(i)).size(), 20, "all twenty still exist")


func test_an_empty_handed_death_leaves_no_body() -> void:
	_setup()
	_kill(_player, EntityIds.NONE)
	_sim.step()
	var body: int = _died[0]["corpse"]
	assert_eq(body, EntityIds.NONE, "no body to leave")
	assert_eq(_loot.holder_ids().size(), 0, "no holder made")


func test_respawn_brings_the_dead_back_whole_at_home() -> void:
	_setup()
	assert_false(_do(DeathSystem.COMMAND_RESPAWN, {"actor": _player}), "the living do not respawn")
	assert_false(_do(DeathSystem.COMMAND_SET_HOME, {"actor": _player, "site": "nowhere"}), "no such site")
	assert_false(_do(DeathSystem.COMMAND_SET_HOME, {"actor": 99999, "site": "home"}), "no such actor")
	_kill(_player, EntityIds.NONE)
	_sim.step()
	assert_false(_do(DeathSystem.COMMAND_RESPAWN, {"actor": _player}), "no home: nowhere to respawn")
	assert_true(_do(DeathSystem.COMMAND_SET_HOME, {"actor": _player, "site": "home"}), "home set, even dead")
	assert_true(_do(DeathSystem.COMMAND_RESPAWN, {"actor": _player}), "respawned")
	var db: ContentDb = _sim.get_system(&"content")
	assert_true(_actors.is_alive(_player), "alive")
	assert_eq(_actors.health_of(_player), {&"body": 100000}, "whole")
	assert_eq(_actors.position_of(_player), SiteSystem.point_position(db, &"home", &"respawn"), "at home's respawn point")
	assert_false(_do(DeathSystem.COMMAND_RESPAWN, {"actor": _player}), "not twice")
	for payload: Dictionary in [{}, {"actor": "1"}, {"actor": _player, "x": 1}]:
		assert_false(_do(DeathSystem.COMMAND_RESPAWN, payload), "refused: %s" % [payload])


func test_a_quest_stays_active_through_a_death_and_a_respawn() -> void:
	_setup()
	var quests: QuestSystem = SimAssembly.quests_of(_sim)
	assert_true(_do(QuestSystem.COMMAND_ACCEPT, {"actor": _player, "quest": "first_blood"}), "taken on")
	assert_true(_do(DeathSystem.COMMAND_SET_HOME, {"actor": _player, "site": "home"}), "home set")
	_kill(_player, EntityIds.NONE)
	_sim.step()
	assert_eq(quests.status_of(_player, &"first_blood"), QuestSystem.STATUS_ACTIVE, "active while dead")
	assert_true(_do(DeathSystem.COMMAND_RESPAWN, {"actor": _player}), "respawned")
	assert_eq(quests.status_of(_player, &"first_blood"), QuestSystem.STATUS_ACTIVE, "and after")


func test_a_save_taken_between_the_death_and_its_body_finishes_the_same_way() -> void:
	_setup()
	_kit(_player, 6)
	_kill(_player, EntityIds.NONE)
	var db: ContentDb = _sim.get_system(&"content")
	var loaded: SimRoot = SimAssembly.load_save(SaveFile.parse(SaveFile.serialize(_sim, db.digest())), db)
	assert_true(loaded != null, "a save with a death pending loads")
	loaded.step()
	_sim.step()
	assert_eq(loaded.state_hash(), _sim.state_hash(), "and settles it the same way")
	var fresh: DeathSystem = SimAssembly.deaths_of(SimAssembly.build(SEED, db))
	for bad: Dictionary in [{}, {"pending": {}, "homes": {}, "deaths": 0}, {"pending": [], "homes": {}, "deaths": -1},
			{"pending": [[1]], "homes": {}, "deaths": 0}, {"pending": [], "homes": {1: "nowhere"}, "deaths": 0},
			{"pending": [], "homes": {}, "deaths": 0, "x": 1}]:
		assert_eq(fresh.restore(bad), ERR_INVALID_DATA, "rejects %s" % [bad])


## ADR-007's verification: over generated streams of kits, deaths (in the badlands and
## the core), takes from bodies and respawns, every item made is placed exactly once,
## and nothing else exists.
func test_property_no_item_is_made_or_lost_across_death_and_recovery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_CONSERVATION
	_setup()
	var actors: Array[int] = [_player, _actors.spawn(&"arcade", 0), _actors.spawn(&"arcade", 0)]
	for a: int in actors:
		_do(DeathSystem.COMMAND_SET_HOME, {"actor": a, "site": "home"})
	var made: Array[int] = []
	var failures: int = 0
	var deaths: int = 0
	var takes: int = 0
	for case: int in PROPERTY_CASES:
		var a: int = actors[rng.randi_range(0, actors.size() - 1)]
		match rng.randi_range(0, 5):
			0:
				if _actors.is_alive(a):
					var item: int = _items.spawn(ItemSystem.KIND_AMMO, &"9x19_fmj", ItemSystem.inventory_of(a), case)
					made.append(item)
			1:
				if _actors.is_alive(a):
					_actors.set_position(a, _floor_of((CORE_CELL if rng.randi_range(0, 1) == 0 else FAR_CELL) + Vector3i(rng.randi_range(0, 5), 0, rng.randi_range(0, 5))))
					_kill(a, actors[rng.randi_range(0, actors.size() - 1)])
					_sim.step()
					deaths += 1
			2, 3:
				var holders: Array[int] = _loot.holder_ids()
				if _actors.is_alive(a) and not holders.is_empty():
					var holder: int = holders[rng.randi_range(0, holders.size() - 1)]
					_actors.set_position(a, _loot.position_of(holder))
					var inside: Array[int] = _items.items_in(_loot.container_name(holder))
					if not inside.is_empty() and _loot.take(a, holder, inside[rng.randi_range(0, inside.size() - 1)]):
						takes += 1
			_:
				if not _actors.is_alive(a):
					_do(DeathSystem.COMMAND_RESPAWN, {"actor": a})
		if case % 50 == 0 or case == PROPERTY_CASES - 1:
			var placed: Array[int] = _all_placed()
			var expected: Array[int] = made.duplicate()
			expected.sort()
			if placed != expected:
				failures += 1
				if failures <= 3:
					fail("case %d: %d placed, %d made" % [case, placed.size(), expected.size()])
	assert_eq(failures, 0, "every item made is placed exactly once, and nothing else")
	assert_true(deaths > 500 and takes > 500, "deaths (%d) and takes (%d) were exercised" % [deaths, takes])


func _law_at(pos: Vector3i) -> int:
	var land: LandSystem = SimAssembly.land_of(_sim)
	var db: ContentDb = _sim.get_system(&"content")
	var district: Dictionary = db.get_entry(&"district", land.district_of(land.parcel_at(pos)))
	return district["law_index"]
