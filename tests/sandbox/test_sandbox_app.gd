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


## Claim 3 on the Deck (gate items 3 and 6, CEOGG 2026-10-07): the reset page is last, so
## every other page keeps its place; each entry sends its command or says why it does not.
func test_the_reset_page_removes_and_clears_or_says_why_not() -> void:
	assert_eq(SandboxApp.PAGES.back(), "reset", "the last page")
	assert_eq(SandboxApp.PAGES.slice(0, 8), ["agents", "items", "sites", "trainer", "ai", "time", "inspect", "record"] as Array[String], "the others where they were")
	var db: ContentDb = _db()
	var spawns: Array = SandboxApp.entries(db, "reset").map(func(e: Dictionary) -> Variant: return e["spawn"])
	assert_eq(spawns, ["despawn", "clear"], "remove and clear")
	var sim: SimRoot = SandboxAssembly.build(1, db)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var player: int = actors.spawn(&"arcade", 0)
	var here: Vector3i = Vector3i(42, 0, 41)
	actors.set_position(player, BuildSystem.cell_centre(here) - Vector3i(0, BuildSystem.CELL / 2, 0))
	var empty: Dictionary = SandboxMode.reset_request(sim, player, here + Vector3i(4, 0, 0), "clear")
	assert_eq(empty, {"say": "the lot is already clear"}, "nothing to clear: said, nothing sent")
	assert_false(SandboxMode.reset_request(sim, player, here, "despawn").has("command"), "the player under the cursor: refused")
	var me: String = SandboxMode.reset_request(sim, player, here, "despawn")["say"]
	assert_true(me.contains("that is you"), "and said")
	var nobody: Dictionary = SandboxMode.reset_request(sim, player, here + Vector3i(4, 0, 0), "despawn")
	assert_false(nobody.has("command"), "an empty cell: nothing sent")
	var why: String = nobody["say"]
	assert_true(why.begins_with("nothing to remove"), "and said why")
	var guard: int = actors.spawn(&"guard", 0)
	actors.set_position(guard, BuildSystem.cell_centre(here + Vector3i(2, 0, 0)) - Vector3i(0, BuildSystem.CELL / 2, 0))
	var take: Dictionary = SandboxMode.reset_request(sim, player, here + Vector3i(2, 0, 0), "despawn")
	assert_eq(take.get("command"), SandboxSystem.COMMAND_DESPAWN, "a guard under the cursor: removed")
	var clear: Dictionary = SandboxMode.reset_request(sim, player, here, "clear")
	assert_eq(clear.get("command"), SandboxSystem.COMMAND_CLEAR, "someone on the lot: cleared")
	assert_eq(clear.get("payload"), {"actor": player}, "for the player")
	var said: String = clear["say"]
	assert_true(said.contains("1 people"), "counting who goes")


## Item 30, found on the 2026-10-07 demo run: a site raised a level above the ground put
## up its guards and none of its 197 pieces, and the HUD only said "raising". Now what the
## raise and the clear came to is said once their tick has run.
func test_a_raise_and_a_clear_say_what_they_came_to() -> void:
	var db: ContentDb = _db()
	var sim: SimRoot = SandboxAssembly.build(1, db)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var player: int = actors.spawn(&"arcade", 0)
	var tick: int = sim.get_tick() + 1
	sim.submit(SimCommand.new(tick, &"land.identify", {"actor": player, "owner": "player"}))
	for lot: String in SiteCreator.LOTS:
		sim.submit(SimCommand.new(tick, &"land.transfer", {"parcel": lot, "owner": "player"}))
	sim.step()
	var at: Vector3i = Vector3i(41, 0, 41)
	var cmd: Dictionary = {"actor": player, "site": "m4_test_building", "at": [at.x, at.y, at.z]}
	var not_yet: String = SandboxMode.raise_result(sim, &"m4_test_building", at)
	assert_true(not_yet.contains("not raised"), "before the sim has it: refused, said")
	sim.submit(SimCommand.new(sim.get_tick() + 1, SiteSystem.COMMAND_RAISE, cmd))
	sim.step()
	var whole: String = SandboxMode.raise_result(sim, &"m4_test_building", at)
	assert_true(whole.begins_with("m4_test_building stands at"), "on the ground: whole (%s)" % whole)
	var before: int = SandboxAssembly.sandbox_of(sim).snapshot()["lowered_sites"]
	sim.submit(SimCommand.new(sim.get_tick() + 1, SandboxSystem.COMMAND_CLEAR, {"actor": player}))
	sim.step()
	assert_eq(SandboxMode.clear_result(sim, before), "cleared: 1 sites came down", "the clear counted")
	var up: Vector3i = at + Vector3i(0, 1, 0)
	sim.submit(SimCommand.new(sim.get_tick() + 1, SiteSystem.COMMAND_RAISE, {"actor": player, "site": "m4_test_building", "at": [up.x, up.y, up.z]}))
	sim.step()
	var part: String = SandboxMode.raise_result(sim, &"m4_test_building", up)
	assert_true(part.contains("only partly stands"), "a level up: said to stand only in part (%s)" % part)
