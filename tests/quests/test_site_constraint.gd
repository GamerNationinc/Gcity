extends GcityTest

## M7 spec claim 8: a quest names a handle, not a place.
##
## The whole point is that the same contract works in a world it was not written for,
## so the tests build worlds the constraint was not written against and ask what it
## matches there. A test that asserted a constraint matches one hand-picked slot would
## be testing the slot.

const SEED: int = 20261250
const MATCH_SEEDS: int = 40

var _db: ContentDb
var _routes: RouteGraph


func _setup(world: int = SEED) -> void:
	_db = ContentDb.new()
	assert_eq(ContentLoader.load_all(_db), OK, "content loads")
	_routes = RouteGraph.new()
	_routes.set_kits(SettlementKits.prepared(_db))
	_routes.generate(world)


## Constraints are content, so they are built the way content builds them.
func _asking(tags: Array, min_km: int, max_km: int, undiscovered: bool = false) -> Dictionary:
	return {"tags_any": tags, "min_km": min_km, "max_km": max_km, "undiscovered": undiscovered}


func test_a_contract_that_asks_for_nothing_is_happy_anywhere() -> void:
	_setup()
	assert_true(_routes.slot_count() > 0, "the world offers places")
	for slot: int in _routes.slot_ids():
		assert_true(SiteConstraint.matches({}, _db, _routes, slot, {}), "slot %d will do" % slot)
	assert_false(SiteConstraint.matches({}, _db, _routes, 99999, {}), "but something that is not a place will not")
	assert_eq(SiteConstraint.slots_matching({}, _db, _routes, {}), _routes.slot_ids(), "so every slot is on offer")


func test_how_far_out_the_contract_wants_it() -> void:
	_setup()
	var anywhere: Array[int] = SiteConstraint.slots_matching(_asking(["ruin"], 0, 100), _db, _routes, {})
	assert_eq(anywhere, _routes.slot_ids(), "the whole world is within a hundred kilometres")
	# the bounds are exact rather than rounded: a place 19.4 km out is not somewhere
	# "at most 19 km" away, so the band that holds it runs from 19 to 20
	for slot: int in anywhere:
		var metres: int = _routes.slot_metres_from_gate(slot)
		var nearest_km: int = metres / 1000
		var furthest_km: int = (metres + 999) / 1000
		assert_true(SiteConstraint.matches(_asking(["ruin"], nearest_km, furthest_km), _db, _routes, slot, {}),
			"slot %d is %d m out, inside %d to %d km" % [slot, metres, nearest_km, furthest_km])
		assert_false(SiteConstraint.matches(_asking(["ruin"], furthest_km + 1, 100), _db, _routes, slot, {}),
			"and is not further out than it is")
		if nearest_km > 0:
			assert_false(SiteConstraint.matches(_asking(["ruin"], 0, nearest_km - 1), _db, _routes, slot, {}),
				"nor nearer in")
	assert_true(SiteConstraint.slots_matching(_asking(["ruin"], 90, 100), _db, _routes, {}).is_empty(),
		"and nothing is ninety kilometres out in a sixty kilometre world")


## `tags_any` is any, not all: a fixer asking for an industrial or corporate place will
## take either.
func test_what_the_contract_wants_it_to_be() -> void:
	_setup()
	var industrial: Array[int] = SiteConstraint.slots_matching(_asking(["industrial"], 0, 100), _db, _routes, {})
	var corp: Array[int] = SiteConstraint.slots_matching(_asking(["corp"], 0, 100), _db, _routes, {})
	var either: Array[int] = SiteConstraint.slots_matching(_asking(["industrial", "corp"], 0, 100), _db, _routes, {})
	assert_false(industrial.is_empty(), "the world has industrial places (%d)" % industrial.size())
	assert_false(corp.is_empty(), "and corporate ones (%d)" % corp.size())
	for slot: int in industrial:
		assert_true(either.has(slot), "an industrial slot satisfies asking for either")
	for slot: int in corp:
		assert_true(either.has(slot), "and so does a corporate one")
	assert_true(either.size() >= maxi(industrial.size(), corp.size()), "so either is at least as wide as one")
	# and the tags select rather than letting everything through: `ruin` fits every slot
	# by design, so anything narrower than it has to be narrower than the whole world
	var everywhere: Array[int] = SiteConstraint.slots_matching(_asking(["ruin"], 0, 100), _db, _routes, {})
	assert_eq(everywhere, _routes.slot_ids(), "a ruin can be anywhere")
	assert_true(either.size() < everywhere.size(), "but industrial or corporate is not everywhere (%d of %d)" % [
		either.size(), everywhere.size()])


func test_somewhere_you_have_not_been() -> void:
	_setup()
	var open: Array[int] = SiteConstraint.slots_matching(_asking(["ruin"], 0, 100, true), _db, _routes, {})
	assert_eq(open, _routes.slot_ids(), "with nothing found yet, everywhere is new")
	var found: Dictionary = {}
	for slot: int in open:
		found[slot] = true
	assert_true(SiteConstraint.slots_matching(_asking(["ruin"], 0, 100, true), _db, _routes, found).is_empty(),
		"once it is all found, a contract wanting somewhere new has nowhere to go")
	assert_eq(SiteConstraint.slots_matching(_asking(["ruin"], 0, 100, false), _db, _routes, found), _routes.slot_ids(),
		"but one that does not care still has the lot")
	var one: Dictionary = {open[0]: true}
	var rest: Array[int] = SiteConstraint.slots_matching(_asking(["ruin"], 0, 100, true), _db, _routes, one)
	assert_eq(rest.size(), open.size() - 1, "and finding one place rules out exactly that one")
	assert_false(rest.has(open[0]), "namely that one")


## The claim the milestone rests on: a contract written against no world in particular
## finds somewhere in worlds it was never written for.
func test_a_contract_finds_somewhere_in_worlds_it_was_not_written_for() -> void:
	_setup()
	var asking: Dictionary = _asking(["industrial", "ruin"], 2, 40)
	var found: int = 0
	var empty: int = 0
	for i: int in MATCH_SEEDS:
		_routes.generate(SEED + i)
		var slots: Array[int] = SiteConstraint.slots_matching(asking, _db, _routes, {})
		if slots.is_empty():
			empty += 1
		else:
			found += 1
		for slot: int in slots:
			var km: int = _routes.slot_metres_from_gate(slot) / 1000
			assert_true(km >= 2 and km <= 40, "slot %d is where it was asked for (%d km)" % [slot, km])
	assert_eq(empty, 0, "every one of %d worlds had somewhere for it" % MATCH_SEEDS)
	assert_true(found == MATCH_SEEDS, "and that is what makes a contract portable")


func test_a_quest_reads_its_own_constraint() -> void:
	_setup()
	var sim: SimRoot = SimAssembly.build(SEED, _db)
	var quests: QuestSystem = SimAssembly.quests_of(sim)
	# claim 10: Cold Storage names a handle; every other contract still says where it is
	for quest: StringName in quests.quest_ids():
		if quest == &"cold_storage":
			assert_eq(quests.site_of(quest)["max_km"], 3, "Cold Storage asks for somewhere close")
		else:
			assert_eq(quests.site_of(quest), {}, "quest/%s still says where it happens" % quest)
	var db := ContentDb.new()
	assert_eq(db.add(QuestSystem.KIND_QUEST, &"a_job", {
		"schema_version": 1, "title": "A job", "description": "x", "text": "x",
		"objectives": [], "reward": [],
		"site": {"tags_any": ["industrial"], "min_km": 8, "max_km": 15, "undiscovered": true},
	}), OK, "a contract with a handle")
	var block: Dictionary = SiteConstraint.of_quest(db, &"a_job")
	assert_eq(block["min_km"], 8, "read back as it was written")
	assert_eq(block["max_km"], 15, "both ends")
	assert_eq(block["undiscovered"], true, "and somewhere new")
	assert_eq(SiteConstraint.of_quest(db, &"not_a_quest"), {}, "and a quest that is not one asks nothing")


## A contract whose range is backwards can never bind, and the symptom would be a fixer
## with a job nobody can take and nothing saying why.
func test_a_contract_that_could_never_bind_fails_assembly() -> void:
	_setup()
	assert_eq(SiteConstraint.validate(_db), OK, "the contracts the game ships are all bindable")
	var backwards := ContentDb.new()
	assert_eq(backwards.add(QuestSystem.KIND_QUEST, &"impossible", {
		"schema_version": 1, "title": "x", "description": "x", "text": "x",
		"objectives": [], "reward": [],
		"site": {"tags_any": ["ruin"], "min_km": 20, "max_km": 5, "undiscovered": false},
	}), OK, "the entry is well formed")
	assert_eq(SiteConstraint.validate(backwards), ERR_INVALID_DATA, "but asks for nowhere")
	var nothing := ContentDb.new()
	assert_eq(nothing.add(QuestSystem.KIND_QUEST, &"vague", {
		"schema_version": 1, "title": "x", "description": "x", "text": "x",
		"objectives": [], "reward": [],
		"site": {"tags_any": [], "min_km": 0, "max_km": 20, "undiscovered": false},
	}), OK, "the entry is well formed")
	assert_eq(SiteConstraint.validate(nothing), ERR_INVALID_DATA, "and this one asks for nothing in particular")


## The outskirts (CEOGG, 2026-09-24): Cold Storage, the first contract, asks for an
## industrial or corporate place within three kilometres, and every world has one — the
## outskirts point of interest a kilometre or two south of the gate, on scrub. Over ten
## thousand worlds the first job always has somewhere to happen, and it is always a
## short walk out.
func test_property_the_first_contract_can_happen_in_every_world() -> void:
	_setup()
	var constraint: Dictionary = SiteConstraint.of_quest(_db, &"cold_storage")
	assert_eq(constraint["max_km"], 3, "Cold Storage asks for somewhere close")
	var nowhere: int = 0
	var far: int = 0
	for i: int in 10_000:
		_routes.generate(SEED + 1000 + i)
		var slots: Array[int] = SiteConstraint.slots_matching(constraint, _db, _routes, {})
		if slots.is_empty():
			nowhere += 1
			if nowhere <= 3:
				fail("seed %d has nowhere for the first contract" % (SEED + 1000 + i))
			continue
		for slot: int in slots:
			if _routes.slot_metres_from_gate(slot) > 3000:
				far += 1
		var outskirts: int = EntityIds.NONE
		for slot: int in _routes.slot_ids():
			if _routes.slot_node(slot) == RouteGraph.OUTSKIRTS:
				outskirts = slot
		if not slots.has(outskirts):
			nowhere += 1
			if nowhere <= 3:
				fail("seed %d: the outskirts is not somewhere the first contract fits" % (SEED + 1000 + i))
	assert_eq(nowhere, 0, "every one of 10 000 worlds has somewhere for the first contract")
	assert_eq(far, 0, "and all of it within three kilometres")
