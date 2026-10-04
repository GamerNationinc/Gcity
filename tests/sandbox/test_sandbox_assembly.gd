extends GcityTest

## M7.6 spec claims 1 and 3, decisions 1 and 2: the sandbox's sim is the game's with one
## system attached last; the game's has no `sandbox.*` command; the release export leaves
## every sandbox folder out; despawn and clear go through the owning systems' own rules,
## conserve kit, and never touch the actor who asks.

const SEED: int = 20261701
const M: int = 1000


func _sandbox() -> SimRoot:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var sim: SimRoot = SandboxAssembly.build(SEED, db)
	assert_true(sim != null, "the sandbox assembles")
	return sim


func _do(sim: SimRoot, kind: StringName, payload: Dictionary) -> bool:
	var before: int = sim.dispatched_count()
	assert_eq(sim.submit(SimCommand.new(sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	sim.step()
	return sim.dispatched_count() == before + 1


## A position `rel` cells from the creator's start, on the lot `--sandbox` gives the player.
func _at(rel: Vector3i) -> Vector3i:
	return Vector3i(42500, 0, 41500) + rel * M


func _cell(rel: Vector3i) -> Array:
	var c: Vector3i = BuildSystem.cell_of(_at(rel))
	return [c.x, rel.y, c.z]


## The player on the creator's lots, theirs, with a guard beside it carrying a pistol.
func _scene(sim: SimRoot) -> Array[int]:
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var player: int = actors.spawn(&"arcade", 0)
	actors.set_position(player, _at(Vector3i.ZERO))
	assert_true(_do(sim, &"land.identify", {"actor": player, "owner": "player"}), "the player is somebody")
	for lot: String in SiteCreator.LOTS:
		assert_true(_do(sim, &"land.transfer", {"parcel": lot, "owner": "player"}), "and owns %s" % lot)
	var guard: int = actors.spawn(&"guard", 0)
	actors.set_position(guard, _at(Vector3i(3, 0, 0)))
	var items: ItemSystem = SimAssembly.items_of(sim)
	items.spawn(&"weapon_frame", &"g19", ItemSystem.inventory_of(guard), 1)
	return [player, guard]


func test_the_game_has_no_sandbox_and_the_sandbox_is_the_game_plus_one_system_last() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var game: SimRoot = SimAssembly.build(SEED, db)
	for kind: StringName in game.commands().kinds():
		assert_false(String(kind).begins_with("sandbox."), "the game's assembly has no %s" % kind)
	assert_false(game.system_ids().has(SandboxSystem.SYSTEM_ID), "nor the system")
	var sim: SimRoot = _sandbox()
	var ids: Array[StringName] = sim.system_ids()
	assert_eq(ids.back(), SandboxSystem.SYSTEM_ID, "the sandbox system is attached last")
	assert_eq(ids.slice(0, ids.size() - 1), game.system_ids(), "after exactly the game's systems, in their order")
	for kind: StringName in [SandboxSystem.COMMAND_DESPAWN, SandboxSystem.COMMAND_CLEAR]:
		assert_true(sim.commands().has(kind), "the sandbox registers %s" % kind)


## Decision 1: the shipped game has no sandbox code to reach. Only a preset named for
## development ("Linux dev", for the Deck run) may keep it.
func test_the_release_export_leaves_every_sandbox_folder_out() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://export_presets.cfg"), OK, "the export presets read")
	var found: bool = false
	for section: String in cfg.get_sections():
		var name: String = cfg.get_value(section, "name", "")
		if not section.ends_with(".options") and cfg.has_section_key(section, "exclude_filter") and not name.ends_with(" dev"):
			found = true
			var filters: PackedStringArray = PackedStringArray()
			var text: String = cfg.get_value(section, "exclude_filter")
			for f: String in text.split(","):
				filters.append(f.strip_edges())
			for folder: String in ["sim/sandbox/*", "client/sandbox/*", "sandbox_content/*"]:
				assert_true(filters.has(folder), "preset %s excludes %s" % [cfg.get_value(section, "name"), folder])
	assert_true(found, "there is a preset to check")


func test_despawn_removes_the_actor_in_the_cell_and_keeps_its_kit() -> void:
	var sim: SimRoot = _sandbox()
	var made: Array[int] = _scene(sim)
	var player: int = made[0]
	var guard: int = made[1]
	var items: ItemSystem = SimAssembly.items_of(sim)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var count: int = items.item_ids().size()
	assert_false(_do(sim, SandboxSystem.COMMAND_DESPAWN, {"actor": player, "cell": _cell(Vector3i(0, 1, 0)), "facing": ""}), "the player's own head: refused")
	assert_true(actors.is_alive(player), "the player stays")
	assert_true(_do(sim, SandboxSystem.COMMAND_DESPAWN, {"actor": player, "cell": _cell(Vector3i(3, 1, 0)), "facing": ""}), "the guard's head is in the cell above its feet")
	assert_false(actors.has_actor(guard), "the guard is gone")
	assert_eq(items.item_ids().size(), count, "nothing made or lost")
	assert_eq(items.items_in(ItemSystem.WORLD).size(), 1, "its pistol is in the world")
	assert_false(_do(sim, SandboxSystem.COMMAND_DESPAWN, {"actor": player, "cell": _cell(Vector3i(3, 0, 1)), "facing": ""}), "an empty cell: nothing to remove")


func test_despawn_removes_a_piece_through_the_build_rules() -> void:
	var sim: SimRoot = _sandbox()
	var player: int = _scene(sim)[0]
	var build: BuildSystem = SimAssembly.build_of(sim)
	var block: int = build.place(player, &"foundation_block", BuildSystem.cell_centre(BuildSystem.cell_of(_at(Vector3i(0, 0, 3)))), "")
	assert_true(block != EntityIds.NONE, "a foundation on the open ground")
	var wall: int = build.place(player, &"wall_panel", BuildSystem.cell_centre(BuildSystem.cell_of(_at(Vector3i(0, 0, 3))) + Vector3i(0, 1, 0)), "px")
	assert_true(wall != EntityIds.NONE, "a wall on it")
	assert_true(_do(sim, SandboxSystem.COMMAND_DESPAWN, {"actor": player, "cell": _cell(Vector3i(0, 1, 3)), "facing": "px"}), "the wall, named by its face")
	assert_false(build.has_piece(wall), "is gone")
	assert_true(_do(sim, SandboxSystem.COMMAND_DESPAWN, {"actor": player, "cell": _cell(Vector3i(0, 0, 3)), "facing": ""}), "the foundation, by its cell")
	assert_false(build.has_piece(block), "is gone")


func test_clear_empties_the_lot_but_the_player() -> void:
	var sim: SimRoot = _sandbox()
	var made: Array[int] = _scene(sim)
	var player: int = made[0]
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var build: BuildSystem = SimAssembly.build_of(sim)
	var extra: int = actors.spawn(&"guard", 0)
	actors.set_position(extra, _at(Vector3i(5, 0, 0)))
	var block: int = build.place(player, &"foundation_block", BuildSystem.cell_centre(BuildSystem.cell_of(_at(Vector3i(0, 0, 3)))), "")
	build.place(player, &"concrete_block", BuildSystem.cell_centre(BuildSystem.cell_of(_at(Vector3i(0, 0, 3))) + Vector3i(0, 1, 0)), "")
	assert_true(block != EntityIds.NONE, "something built")
	assert_true(_do(sim, SandboxSystem.COMMAND_CLEAR, {"actor": player}), "clear")
	assert_eq(actors.actor_ids(), [player] as Array[int], "only the player is left")
	assert_eq(build.piece_ids(), [] as Array[int], "and nothing built")
	assert_eq(SandboxAssembly.sandbox_of(sim).snapshot(), {"removed_actors": 2, "removed_pieces": 2, "spawned": 0, "trainer": {}}, "counted")


## Claim 10's boundary for these two: exact payloads only.
func test_a_malformed_payload_is_refused() -> void:
	var sim: SimRoot = _sandbox()
	var player: int = _scene(sim)[0]
	for payload: Dictionary in [
		{}, {"actor": player}, {"actor": player, "cell": _cell(Vector3i(3, 1, 0))},
		{"actor": player, "cell": [6, 1], "facing": ""}, {"actor": player, "cell": [6, 1, 3.5], "facing": ""},
		{"actor": player, "cell": "6,1,3", "facing": ""}, {"actor": player, "cell": _cell(Vector3i(3, 1, 0)), "facing": "up"},
		{"actor": "1", "cell": _cell(Vector3i(3, 1, 0)), "facing": ""}, {"actor": 999, "cell": _cell(Vector3i(3, 1, 0)), "facing": ""},
		{"actor": player, "cell": _cell(Vector3i(3, 1, 0)), "facing": "", "extra": 1},
	]:
		assert_false(_do(sim, SandboxSystem.COMMAND_DESPAWN, payload), "despawn refuses %s" % payload)
	for payload: Dictionary in [{}, {"actor": "1"}, {"actor": 999}, {"actor": player, "extra": 1}]:
		assert_false(_do(sim, SandboxSystem.COMMAND_CLEAR, payload), "clear refuses %s" % payload)
	assert_eq(SimAssembly.actors_of(sim).actor_ids().size(), 2, "and nothing changed")


## Claim 2: an agent of any profile, armed with a kit, facing where it is told; refused
## where its body does not fit, and for a kit that is not one.
func test_spawn_agent_arms_a_guard_where_its_body_fits() -> void:
	var sim: SimRoot = _sandbox()
	var player: int = _scene(sim)[0]
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var items: ItemSystem = SimAssembly.items_of(sim)
	var kit: Dictionary = {"frame": "g19", "magazine": "g19_mag_15", "ammo": "9x19_fmj", "rounds": 15}
	var before: Array[int] = actors.actor_ids()
	assert_true(_do(sim, SandboxSystem.COMMAND_SPAWN_AGENT, {"actor": player, "profile": "guard_sim", "cell": _cell(Vector3i(0, 0, 4)), "facing": 90, "kit": kit}), "a guard with a pistol")
	var agent: int = actors.actor_ids().back()
	assert_false(before.has(agent), "a new actor")
	var weapon: int = actors.wielded(agent)
	assert_true(weapon != EntityIds.NONE, "holding a weapon")
	assert_eq(items.item_template(weapon), &"g19", "the kit's frame")
	assert_eq(SimAssembly.perception_of(sim).facing_of(agent), 90, "facing where it was told")
	assert_true(_do(sim, SandboxSystem.COMMAND_SPAWN_AGENT, {"actor": player, "profile": "sentry_drone", "cell": _cell(Vector3i(2, 0, 4)), "facing": 0, "kit": {}}), "any profile, unarmed")
	var drone: int = actors.actor_ids().back()
	assert_eq(actors.wielded(drone), EntityIds.NONE, "holding nothing")
	var build: BuildSystem = SimAssembly.build_of(sim)
	build.place(player, &"foundation_block", BuildSystem.cell_centre(BuildSystem.cell_of(_at(Vector3i(4, 0, 4)))), "")
	var count: int = actors.actor_ids().size()
	assert_false(_do(sim, SandboxSystem.COMMAND_SPAWN_AGENT, {"actor": player, "profile": "guard_sim", "cell": _cell(Vector3i(4, 0, 4)), "facing": 0, "kit": {}}), "inside a foundation: refused")
	for bad: Dictionary in [
		{"frame": "g19", "magazine": "g19_mag_15", "ammo": "9x19_fmj"},
		{"frame": "nope", "magazine": "g19_mag_15", "ammo": "9x19_fmj", "rounds": 15},
		{"frame": "g19", "magazine": "g19_mag_15", "ammo": "9x19_fmj", "rounds": 101},
		{"frame": "g19", "magazine": "g19_mag_15", "ammo": "9x19_fmj", "rounds": "15"},
	]:
		assert_false(_do(sim, SandboxSystem.COMMAND_SPAWN_AGENT, {"actor": player, "profile": "guard_sim", "cell": _cell(Vector3i(0, 0, 6)), "facing": 0, "kit": bad}), "kit refused: %s" % bad)
	for payload: Dictionary in [
		{"actor": player, "profile": "nobody", "cell": _cell(Vector3i(0, 0, 6)), "facing": 0, "kit": {}},
		{"actor": player, "profile": "guard_sim", "cell": _cell(Vector3i(0, 0, 6)), "facing": 360, "kit": {}},
		{"actor": 999, "profile": "guard_sim", "cell": _cell(Vector3i(0, 0, 6)), "facing": 0, "kit": {}},
		{"actor": player, "profile": "guard_sim", "cell": _cell(Vector3i(0, 0, 6)), "facing": 0},
	]:
		assert_false(_do(sim, SandboxSystem.COMMAND_SPAWN_AGENT, payload), "refused: %s" % payload)
	assert_eq(actors.actor_ids().size(), count, "and nobody else appeared")
