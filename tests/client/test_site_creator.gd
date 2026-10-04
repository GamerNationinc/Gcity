extends GcityTest

## M7.5 spec claims 14–15: the creator tool. A site is built a piece at a time through
## the sim, written out as a `content/site` file, and that file raised by `site.raise`
## stands exactly as it was built.

const SEED: int = 20261410
const SEED_PROPERTY: int = 20261411
const PROPERTY_CASES: int = 1_000
## Commands each generated build is made of.
const PRESSES: int = 40
const M: int = 1000
## The four camera headings the property builds from: the cursor's facings follow them.
const YAWS: Array[float] = [0.0, PI / 2.0, PI, 3.0 * PI / 2.0]


func _db() -> ContentDb:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	return db


## A sim with the creator's lots the player's, as `--create` sets it up.
func _lot(db: ContentDb, seed: int = SEED) -> Array:
	var sim: SimRoot = SimAssembly.build(seed, db)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var player: int = actors.spawn(&"arcade", 0)
	_do(sim, &"land.identify", {"actor": player, "owner": "player"})
	for lot: String in SiteCreator.LOTS:
		_do(sim, &"land.transfer", {"parcel": lot, "owner": "player"})
	return [sim, player]


func _do(sim: SimRoot, kind: StringName, payload: Dictionary) -> bool:
	var before: int = sim.dispatched_count()
	assert_eq(sim.submit(SimCommand.new(sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	sim.step()
	return sim.dispatched_count() == before + 1


func test_the_palette_is_every_build_piece_and_the_two_markers() -> void:
	var db: ContentDb = _db()
	var creator := SiteCreator.new(db)
	var palette: Array[StringName] = creator.palette()
	for id: StringName in db.ids(BuildSystem.KIND_PIECE):
		assert_true(palette.has(id), "the palette has %s" % id)
	assert_eq(palette.size(), db.ids(BuildSystem.KIND_PIECE).size() + 2, "and nothing else but the markers")
	assert_eq(palette[palette.size() - 2], SiteCreator.GUARD_POST, "a guard post")
	assert_eq(palette[palette.size() - 1], SiteCreator.TERMINAL, "and a terminal")
	var first: StringName = creator.selected()
	for i: int in palette.size():
		creator.next_piece()
	assert_eq(creator.selected(), first, "Y goes round the palette and back")


## The D-pad moves the cursor the way the screen shows, at every heading: up is away
## from the camera, right is the screen's right, always a whole cell along one axis.
func test_the_dpad_moves_the_cursor_relative_to_the_camera() -> void:
	# yaw 0 looks along -z: the screen's right is +x
	assert_eq(SiteCreator.camera_step(0.0, Vector2i(0, -1)), Vector2i(0, -1), "up at yaw 0 is -z")
	assert_eq(SiteCreator.camera_step(0.0, Vector2i(1, 0)), Vector2i(1, 0), "right at yaw 0 is +x")
	for yaw: float in [0.0, 0.4, 1.2, 2.0, 3.0, 4.4, 5.9]:
		var up: Vector2i = SiteCreator.camera_step(yaw, Vector2i(0, -1))
		var right: Vector2i = SiteCreator.camera_step(yaw, Vector2i(1, 0))
		assert_eq(absi(up.x) + absi(up.y), 1, "a whole cell along one axis (yaw %.1f)" % yaw)
		assert_eq(SiteCreator.camera_step(yaw, Vector2i(0, 1)), -up, "down is the opposite of up (yaw %.1f)" % yaw)
		assert_eq(SiteCreator.camera_step(yaw, Vector2i(-1, 0)), -right, "left of right (yaw %.1f)" % yaw)
		var forward: Vector2 = Vector2(-sin(yaw), -cos(yaw))
		assert_true(Vector2(up).dot(forward) > 0.0, "up goes away from the camera (yaw %.1f)" % yaw)
	assert_eq(SiteCreator.camera_step(1.0, Vector2i.ZERO), Vector2i.ZERO, "no press, no step")


## A wall goes on the face toward the camera, X turns it a quarter at a time, a floor
## goes under the cursor and a block in it; a guard post looks away from the camera.
func test_a_piece_faces_the_camera_and_x_turns_it() -> void:
	var db: ContentDb = _db()
	var creator := SiteCreator.new(db)
	# yaw 0: the camera stands on the +z side looking along -z
	assert_eq(creator.wall_facing(0.0), "pz", "the wall toward the camera")
	assert_eq(creator.facing_for(&"wall_panel", 0.0), "pz", "a wall panel takes it")
	assert_eq(creator.facing_for(&"floor_panel", 0.0), "ny", "a floor is the cursor cell's floor")
	assert_eq(creator.facing_for(&"foundation_block", 0.0), "", "a block fills the cell")
	assert_eq(creator.post_facing(0.0), 270, "a guard post looks away, along -z")
	creator.turn()
	assert_eq(creator.wall_facing(0.0), "nx", "X turns the wall a quarter")
	assert_eq(creator.post_facing(0.0), 0, "and the post with it, to +x")
	for i: int in 3:
		creator.turn()
	assert_eq(creator.wall_facing(0.0), "pz", "four turns is all the way round")
	assert_eq(creator.wall_facing(PI / 2.0), "px", "looking along -x the camera is on the +x side")


## What A and B do through the sim: a foundation, a wall on it, both judged by the
## build rules (a wall in the air is refused like any other), B taking away the piece
## under the cursor; a guard post only where a guard fits, and gone when its floor is.
func test_a_and_b_place_and_remove_through_the_sim() -> void:
	var db: ContentDb = _db()
	var made: Array = _lot(db)
	var sim: SimRoot = made[0]
	var player: int = made[1]
	var build: BuildSystem = SimAssembly.build_of(sim)
	var movement: MovementSystem = SimAssembly.movement_of(sim)
	var creator := SiteCreator.new(db)
	creator.set_cursor(SiteCreator.START + Vector3i(0, 5, 0))
	_select(creator, &"wall_panel")
	assert_false(_do(sim, &"build.place", creator.place(player, 0.0, movement)), "a wall in the air falls: refused")
	creator.set_cursor(SiteCreator.START)
	_select(creator, &"foundation_block")
	assert_true(_do(sim, &"build.place", creator.place(player, 0.0, movement)), "a foundation on the ground")
	creator.rise(1)
	_select(creator, &"wall_panel")
	assert_true(_do(sim, &"build.place", creator.place(player, 0.0, movement)), "a wall on it")
	assert_ne(build.face_piece_at(BuildSystem.face_key(SiteCreator.START + Vector3i(0, 1, 0), "pz")), EntityIds.NONE, "toward the camera")
	_select(creator, SiteCreator.GUARD_POST)
	assert_eq(creator.place(player, 0.0, movement), {}, "a marker is not a command")
	assert_eq(creator.guard_posts().size(), 1, "a guard post on the foundation")
	creator.rise(-1)
	assert_eq(creator.place(player, 0.0, movement), {}, "and none inside it")
	assert_eq(creator.guard_posts().size(), 1, "still one")
	var remove: Dictionary = creator.remove(build, player, 0.0)
	assert_true(_do(sim, &"build.remove", remove), "B removes the foundation under the cursor")
	assert_eq(build.piece_ids().size(), 0, "and the wall on it falls with it")
	assert_eq(creator.prune(movement), [SiteCreator.START + Vector3i(0, 1, 0)] as Array[Vector3i], "the post had nothing to stand on")
	assert_eq(creator.guard_posts().size(), 0, "and went")
	_select(creator, SiteCreator.TERMINAL)
	creator.place(player, 0.0, movement)
	assert_eq(creator.terminal_cells(), [SiteCreator.START] as Array[Vector3i], "a terminal marker")
	assert_eq(creator.remove(build, player, 0.0), {}, "B on a marker with no piece there")
	assert_eq(creator.terminal_cells().size(), 0, "takes the marker away")


func _select(creator: SiteCreator, name: StringName) -> void:
	for i: int in creator.palette().size():
		if creator.selected() == name:
			return
		creator.next_piece()
	fail("%s is not in the palette" % name)


## Claim 15's round trip: for 1 000 random builds, saving and then raising the file with
## `site.raise` on an empty lot gives the same pieces in the same cells with the same
## facings, and a guard at every post facing its way, and a terminal at every marker.
func test_property_a_saved_site_raises_as_it_was_built() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	var differ: int = 0
	var refused: int = 0
	var empty: int = 0
	var pieces_total: int = 0
	var posts_total: int = 0
	var reordered: int = 0
	for case: int in PROPERTY_CASES:
		var db: ContentDb = _db()
		var made: Array = _lot(db, SEED_PROPERTY + case)
		var sim: SimRoot = made[0]
		var player: int = made[1]
		var build: BuildSystem = SimAssembly.build_of(sim)
		var movement: MovementSystem = SimAssembly.movement_of(sim)
		var creator := SiteCreator.new(db)
		_random_build(rng, sim, player, creator)
		if build.piece_ids().is_empty():
			empty += 1
			continue
		var site: Dictionary = creator.to_site(build, movement, "Case %d" % case, "A generated build.")
		var settled: Array = build.supported_set().keys()
		var built: Array = build.piece_ids()
		if settled != built:
			reordered += 1
		var want: Dictionary = _standing(build)
		pieces_total += want.size()
		posts_total += creator.guard_posts().size()
		# into a fresh content set, and raised on an empty lot like any shipped site
		var db2: ContentDb = _db()
		assert_eq(db2.add(SiteSystem.KIND_SITE, &"created", site), OK, "the site is content") if case == 0 else db2.add(SiteSystem.KIND_SITE, &"created", site)
		var raised: Array = _lot(db2, SEED_PROPERTY + case)
		var sim2: SimRoot = raised[0]
		if sim2 == null or not _do(sim2, &"site.raise", {"actor": raised[1], "site": "created"}):
			refused += 1
			if refused <= 3:
				fail("case %d: the saved site would not raise" % case)
			continue
		var got: Dictionary = _standing(SimAssembly.build_of(sim2))
		var posts: Array[String] = []
		for post: Dictionary in creator.guard_posts():
			posts.append("%s@%d" % [post["cell"], post["facing"]])
		var guards: Array[String] = []
		var actors2: ActorSystem = SimAssembly.actors_of(sim2)
		var perception2: PerceptionSystem = SimAssembly.perception_of(sim2)
		for agent: int in SimAssembly.sites_of(sim2).agents_of(&"created"):
			guards.append("%s@%d" % [BuildSystem.cell_of(actors2.position_of(agent)), perception2.facing_of(agent)])
		posts.sort()
		guards.sort()
		var terminals: Array[String] = []
		for at: Vector3i in creator.terminal_cells():
			terminals.append(str(at))
		var placed: Array[String] = []
		var terminals2: TerminalSystem = SimAssembly.terminals_of(sim2)
		for id: int in SimAssembly.sites_of(sim2).terminals_of(&"created"):
			placed.append(str(BuildSystem.cell_of(terminals2.position_of(id))))
		terminals.sort()
		placed.sort()
		if got != want or posts != guards or terminals != placed:
			differ += 1
			if differ <= 3:
				fail("case %d: raised %d pieces of %d, guards %s for posts %s, terminals %s for %s" % [case, got.size(), want.size(), guards, posts, placed, terminals])
	assert_eq(refused, 0, "every saved site raises (%d cases)" % PROPERTY_CASES)
	assert_eq(differ, 0, "as it was built: the same pieces, cells and facings, guards and terminals")
	assert_true(pieces_total > PROPERTY_CASES * 5, "and the builds are builds (%d pieces, %d guard posts, %d empty)" % [pieces_total, posts_total, empty])
	assert_true(posts_total > PROPERTY_CASES / 4, "with guard posts in them (%d)" % posts_total)
	assert_true(reordered > 0, "and some only stand in an order other than the one they were built in (%d)" % reordered)


## Every standing piece as "template at slot" -> true: the slot is its cell or its face.
func _standing(build: BuildSystem) -> Dictionary:
	var out: Dictionary = {}
	for id: int in build.piece_ids():
		out["%s@%s" % [build.template_of(id), build.key_of_piece(id)]] = true
	return out


## Presses as a player would make them in a small box on the lot: mostly placing, some
## removing, the cursor wandering, the camera turning, X and Y pressed; and after every
## build change the posts the change left without room pruned, as the view does.
func _random_build(rng: RandomNumberGenerator, sim: SimRoot, player: int, creator: SiteCreator) -> void:
	var build: BuildSystem = SimAssembly.build_of(sim)
	var movement: MovementSystem = SimAssembly.movement_of(sim)
	var size: int = creator.palette().size()
	for press: int in PRESSES:
		var yaw: float = YAWS[rng.randi_range(0, YAWS.size() - 1)]
		creator.set_cursor(SiteCreator.START + Vector3i(rng.randi_range(-2, 2), rng.randi_range(0, 4), rng.randi_range(-2, 2)))
		for i: int in rng.randi_range(0, size - 1):
			creator.next_piece()
		if rng.randi_range(0, 3) == 0:
			creator.turn()
		# the first presses build a footing, so most builds are more than a foundation
		if press < 6:
			creator.set_cursor(Vector3i(creator.cursor().x, 0, creator.cursor().z))
			_select(creator, &"foundation_block")
		if rng.randi_range(0, 4) == 0 and press >= 6:
			var remove: Dictionary = creator.remove(build, player, yaw)
			if not remove.is_empty():
				_do(sim, &"build.remove", remove)
		else:
			var place: Dictionary = creator.place(player, yaw, movement)
			if not place.is_empty():
				_do(sim, &"build.place", place)
		creator.prune(movement)


## A file from `user://` is untrusted: anything that is not a site this content can
## build is refused with a reason, and opening refuses it rather than half-building it.
func test_a_file_that_is_not_a_site_is_refused_with_a_reason() -> void:
	var db: ContentDb = _db()
	var good: Dictionary = db.get_entry(SiteSystem.KIND_SITE, &"m4_test_building").duplicate(true)
	assert_eq(SiteCreator.problem(good, db), "", "a shipped site opens")
	var cases: Dictionary[String, Callable] = {
		"no pieces key": func(s: Dictionary) -> void: s.erase("pieces"),
		"version 2": func(s: Dictionary) -> void: s["schema_version"] = 2,
		"base of two": func(s: Dictionary) -> void: s["base"] = [1, 2],
		"base out of range": func(s: Dictionary) -> void: s["base"] = [0, 0, SiteCreator.MAX_REL + 1],
		"no pieces": func(s: Dictionary) -> void: s["pieces"] = [],
		"an unknown piece": func(s: Dictionary) -> void: s["pieces"] = [{"piece": "nope", "rel": [0, 0, 0], "facing": ""}],
		"a bad facing": func(s: Dictionary) -> void: s["pieces"] = [{"piece": "wall_panel", "rel": [0, 0, 0], "facing": "up"}],
		"a float cell": func(s: Dictionary) -> void: s["pieces"] = [{"piece": "wall_panel", "rel": [0, 0.5, 0], "facing": "px"}],
		"a piece not an object": func(s: Dictionary) -> void: s["pieces"] = ["wall_panel"],
		"a spawn facing 400": func(s: Dictionary) -> void: s["spawns"] = [{"profile": "guard_sim", "rel": [0, 0, 0], "facing": 400, "squad": 1, "route": ""}],
		"a terminal not an object": func(s: Dictionary) -> void: s["terminals"] = [3],
		"too many pieces": func(s: Dictionary) -> void: s["pieces"] = range(SiteCreator.MAX_PIECES + 1).map(func(_i: int) -> Dictionary: return {"piece": "wall_panel", "rel": [0, 0, 0], "facing": "px"}),
	}
	var creator := SiteCreator.new(db)
	for name: String in cases:
		var bad: Dictionary = good.duplicate(true)
		var mutate: Callable = cases[name]
		mutate.call(bad)
		assert_false(SiteCreator.problem(bad, db).is_empty(), "%s is refused with a reason" % name)
		assert_eq(creator.open(bad, 1), [] as Array[Dictionary], "and %s does not open" % name)


## A saved site goes to `user://sites/<id>.json`, the id from the date and time, reads
## back the same, opens with its guard posts and terminals as markers, and is listed
## before the shipped sites.
func test_a_site_saves_reads_back_and_reopens() -> void:
	var db: ContentDb = _db()
	assert_eq(SiteCreator.site_id({"year": 2026, "month": 10, "day": 3, "hour": 9, "minute": 5, "second": 7}), "site_20261003_090507", "the id is the time")
	var site: Dictionary = db.get_entry(SiteSystem.KIND_SITE, &"cold_storage").duplicate(true)
	var dir: String = "user://test_sites"
	var path: String = SiteCreator.save(site, "site_20261003_090507", dir)
	assert_eq(path, dir.path_join("site_20261003_090507.json"), "saved where it says")
	var back: Dictionary = SiteCreator.read(path)
	assert_eq(StateHash.of(back), StateHash.of(site), "and reads back the same, numbers whole")
	var listed: Array[String] = SiteCreator.openable(dir)
	assert_eq(listed[0], path, "the player's own sites come first")
	assert_true(listed.has("res://content/site/cold_storage.json"), "then the shipped ones")
	var creator := SiteCreator.new(db)
	var commands: Array[Dictionary] = creator.open(back, 7)
	var pieces: Array = site["pieces"]
	var spawns: Array = site["spawns"]
	var terminals: Array = site["terminals"]
	assert_eq(commands.size(), pieces.size(), "a command for every piece")
	assert_eq(commands[0]["actor"], 7, "placed by whoever opened it")
	assert_eq(creator.guard_posts().size(), spawns.size(), "its guards as posts")
	assert_eq(creator.terminal_cells().size(), terminals.size(), "its terminals as markers")
	assert_eq(creator.cursor(), Vector3i(40, 0, 40), "and the cursor at its base")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(dir)


## A shipped site opened in the creator stands as it does when raised, and saved again
## it is the same site: Cold Storage, whole, round the tool and back.
func test_cold_storage_opens_in_the_creator_and_saves_as_itself() -> void:
	var db: ContentDb = _db()
	var made: Array = _lot(db)
	var sim: SimRoot = made[0]
	var player: int = made[1]
	var creator := SiteCreator.new(db)
	var site: Dictionary = db.get_entry(SiteSystem.KIND_SITE, &"cold_storage")
	var refused: int = 0
	for command: Dictionary in creator.open(site, player):
		if not _do(sim, &"build.place", command):
			refused += 1
	assert_eq(refused, 0, "every piece of it is placed")
	var build: BuildSystem = SimAssembly.build_of(sim)
	var pieces: Array = site["pieces"]
	assert_eq(build.piece_ids().size(), pieces.size(), "all %d" % pieces.size())
	assert_eq(creator.prune(SimAssembly.movement_of(sim)), [] as Array[Vector3i], "every guard post has room")
	var again: Dictionary = creator.to_site(build, SimAssembly.movement_of(sim), "Cold Storage", "again")
	# its authored base is not its lowest corner: saved again, it is based there instead
	assert_eq(SiteCreator._vec(again["base"]), Vector3i(38, 0, 34), "based at its lowest corner")
	var a: Dictionary = {}
	for v: Variant in site["pieces"]:
		var entry: Dictionary = v
		a[_slot(SiteCreator._vec(site["base"]), entry)] = true
	var b: Dictionary = {}
	for v: Variant in again["pieces"]:
		var entry: Dictionary = v
		b[_slot(SiteCreator._vec(again["base"]), entry)] = true
	assert_eq(b, a, "and the same pieces in the same places")
	var spawns: Array = again["spawns"]
	var terminals: Array = again["terminals"]
	assert_eq(spawns.size(), 4, "its four guards")
	assert_eq(terminals.size(), 2, "its two terminals")


## A piece entry as the slot it takes in the world, so a face written from either side
## and a site written from another base compare equal.
func _slot(base: Vector3i, entry: Dictionary) -> String:
	var cell: Vector3i = base + SiteCreator._vec(entry["rel"])
	var facing: String = entry["facing"]
	return "%s@%s" % [entry["piece"], BuildSystem.cell_key(cell) if facing.is_empty() else BuildSystem.face_key(cell, facing)]


## Deck test, 2026-10-04: the first press of A did nothing anyone could see. The palette
## starts on the piece that goes on bare ground, and a press the sim would refuse comes
## with a reason a player can act on.
func test_the_palette_starts_on_a_foundation_and_a_refusal_has_a_reason() -> void:
	var db: ContentDb = _db()
	var made: Array = _lot(db)
	var sim: SimRoot = made[0]
	var player: int = made[1]
	var movement: MovementSystem = SimAssembly.movement_of(sim)
	var creator := SiteCreator.new(db)
	assert_eq(creator.selected(), &"foundation_block", "the palette starts on a foundation")
	assert_eq(creator.why_not(sim, player, &"foundation_block", ""), "nothing holds it up there: too far from a foundation, build one closer", "the fallback, asked of a fine spot")
	assert_true(_do(sim, &"build.place", creator.place(player, 0.0, movement)), "and the first A places it")
	assert_true(creator.why_not(sim, player, &"foundation_block", "").contains("already has a foundation_block"), "the same spot again: taken")
	creator.rise(2)
	assert_true(creator.why_not(sim, player, &"foundation_block", "").contains("goes on the ground"), "a foundation up in the air")
	assert_true(creator.why_not(sim, player, &"wall_panel", "pz").contains("nothing holds it up"), "a wall two levels over nothing")
	# the fixer's office is somebody else's
	creator.set_cursor(Vector3i(6, 0, 30))
	assert_true(creator.why_not(sim, player, &"foundation_block", "").contains("not your land"), "somebody else's lot")
	assert_false(_do(sim, &"build.place", creator.place(player, 0.0, movement)), "and the sim agrees")


## Deck test, 2026-10-04 ("always ensure buttons are functioning correctly"): every
## control the creator prompts for is bound to exactly the Deck button the spec gives
## it (claim 14), each to a different button, with no keyboard key (CLAUDE.md §10).
func test_every_creator_control_is_on_its_own_deck_button() -> void:
	var expected: Dictionary = {
		&"create_up": JOY_BUTTON_DPAD_UP, &"create_down": JOY_BUTTON_DPAD_DOWN,
		&"create_left": JOY_BUTTON_DPAD_LEFT, &"create_right": JOY_BUTTON_DPAD_RIGHT,
		&"create_raise": JOY_BUTTON_RIGHT_SHOULDER, &"create_lower": JOY_BUTTON_LEFT_SHOULDER,
		&"create_place": JOY_BUTTON_A, &"create_remove": JOY_BUTTON_B,
		&"create_turn": JOY_BUTTON_X, &"create_next": JOY_BUTTON_Y,
	}
	var used: Dictionary = {}
	for action: StringName in expected:
		assert_true(InputMap.has_action(action), "%s exists" % action)
		var buttons: Array[int] = []
		for event: InputEvent in InputMap.action_get_events(action):
			assert_false(event is InputEventKey, "%s has no keyboard key" % action)
			if event is InputEventJoypadButton:
				var b: InputEventJoypadButton = event
				buttons.append(b.button_index)
		assert_eq(buttons, [expected[action]] as Array[int], "%s is on its one button" % action)
		assert_false(used.has(expected[action]), "and no other creator control shares it")
		used[expected[action]] = action
	for action: String in WorldView.CREATOR_ACTIONS:
		assert_true(expected.has(StringName(action)), "%s, handled by the view, is pinned here" % action)
	# the menu is the device button, the same View the rest of the game raises the device with
	var view: Array[int] = []
	for event: InputEvent in InputMap.action_get_events(&"world_device"):
		if event is InputEventJoypadButton:
			var b: InputEventJoypadButton = event
			view.append(b.button_index)
	assert_eq(view, [JOY_BUTTON_BACK] as Array[int], "the menu opens with View")
	assert_false(used.has(JOY_BUTTON_BACK), "which no creator control uses")
	# and with Start, where a player looks for a menu (Deck run, 2026-10-04: Start did nothing)
	var start: Array[int] = []
	for event: InputEvent in InputMap.action_get_events(&"create_menu"):
		assert_false(event is InputEventKey, "create_menu has no keyboard key")
		if event is InputEventJoypadButton:
			var b: InputEventJoypadButton = event
			start.append(b.button_index)
	assert_eq(start, [JOY_BUTTON_START] as Array[int], "the menu opens with Start too")
	assert_false(used.has(JOY_BUTTON_START), "which no creator control uses")
