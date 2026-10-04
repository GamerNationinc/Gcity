extends GcityTest

## M7.6 spec claim 2 and decision 5: the spawn menu lists what the content holds, by kind,
## with nothing listed by hand, so a new file appears with no code; A asks the view to
## spawn the entry under the cursor.

var _asked: Array[Dictionary] = []


func _db() -> ContentDb:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	return db


func _ask(kind: StringName, payload: Dictionary) -> void:
	_asked.append({"kind": kind, "payload": payload})


func test_the_pages_are_the_content() -> void:
	var db: ContentDb = _db()
	var kits: Array[Dictionary] = SandboxApp.kits(db)
	assert_true(kits.has({"frame": "g19", "magazine": "g19_mag_15", "ammo": "9x19_fmj", "rounds": 15}), "the g19 with its magazine full of ball")
	assert_true(kits.has({"frame": "m9", "magazine": "m9_mag_15", "ammo": "9x19_jhp", "rounds": 15}), "the m9 with hollow points")
	for kit: Dictionary in kits:
		assert_ne(kit["ammo"], "access_token", "a token is not a round")
	var agents: Array[Dictionary] = SandboxApp.entries(db, "agents")
	assert_eq(agents.size(), db.ids(PerceptionSystem.KIND_AGENT).size() * (kits.size() + 1), "every profile, unarmed and with every kit")
	var items: Array[Dictionary] = SandboxApp.entries(db, "items")
	var expected: int = 0
	for kind: StringName in SandboxApp.ITEM_KINDS:
		expected += db.ids(kind).size()
	assert_eq(items.size(), expected, "every item template")
	# Q4: a new weapon is a file, and it is on the menu
	var g19: Dictionary = db.get_entry(ItemSystem.KIND_FRAME, &"g19").duplicate(true)
	assert_eq(db.add(ItemSystem.KIND_FRAME, &"g19_test", g19), OK, "a new frame")
	assert_eq(SandboxApp.entries(db, "items").size(), expected + 1, "listed with no code")


func test_a_spawns_the_entry_under_the_cursor() -> void:
	var db: ContentDb = _db()
	var sim: SimRoot = SimAssembly.build(1, db)
	var scene: PackedScene = load("res://client/sandbox/sandbox_app.tscn")
	var app: SandboxApp = scene.instantiate()
	app.bind(_ask, Callable())
	assert_true(app.refresh(sim, 0), "draws")
	assert_true(app.handle(&"device_down", sim, 0), "down")
	assert_true(app.refresh(sim, 0), "the cursor moved")
	assert_true(app.handle(&"device_select", sim, 0), "A")
	var second: Dictionary = SandboxApp.entries(db, "agents")[1].duplicate(true)
	second.erase("label")
	assert_eq(_asked, [{"kind": SandboxApp.KIND_SPAWN, "payload": second}], "asks for the second agent entry, without its label")
	assert_true(app.handle(&"device_right", sim, 0), "the next page")
	assert_true(app.handle(&"device_select", sim, 0), "A")
	var item: Dictionary = _asked[1]["payload"]
	assert_eq(item["spawn"], "item", "an item")
	assert_true(app.handle(&"device_left", sim, 0), "back a page")
	assert_false(app.handle(&"device_back", sim, 0), "B is the shell's")
	app.free()


## Claims 4–5: the trainer page shows each effect's state and asks for the other one.
func test_the_trainer_page_toggles_what_is_on() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	assert_eq(ContentLoader.load_all(db, "res://sandbox_content"), OK, "and the sandbox's")
	var sim: SimRoot = SandboxAssembly.build(1, db)
	var player: int = SimAssembly.actors_of(sim).spawn(&"arcade", 0)
	var page: Array[Dictionary] = SandboxApp.entries(db, "trainer", sim, player)
	assert_eq(page[0]["label"], "god mode: off", "god mode starts off")
	assert_eq(page[0]["on"], true, "and A asks for it on")
	assert_eq(sim.submit(SimCommand.new(sim.get_tick() + 1, SandboxSystem.COMMAND_TRAINER, {"actor": player, "effect": "god", "on": true})), OK, "turned on")
	sim.step()
	page = SandboxApp.entries(db, "trainer", sim, player)
	assert_eq(page[0]["label"], "god mode: ON", "shows on")
	assert_eq(page[0]["on"], false, "and A asks for it off")
	assert_eq(page.size(), SandboxApp.EFFECTS.size() + 2, "the three effects, full health, teleport")
