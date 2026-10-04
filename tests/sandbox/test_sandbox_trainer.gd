extends GcityTest

## M7.6 spec claims 4–5 and decision 3: god mode, infinite ammo and fly are modifiers on
## rules the owning systems read at their neutral value; each is proven the way the spec
## says. Teleport and health act through the owning systems' own checks.

const SEED: int = 20261702
const M: int = 1000


## The game's content and the sandbox's, as `--sandbox` loads them.
func _sandbox() -> SimRoot:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	assert_eq(ContentLoader.load_all(db, "res://sandbox_content"), OK, "and the sandbox's")
	var sim: SimRoot = SandboxAssembly.build(SEED, db)
	assert_true(sim != null, "the sandbox assembles")
	return sim


func _do(sim: SimRoot, kind: StringName, payload: Dictionary) -> bool:
	var before: int = sim.dispatched_count()
	assert_eq(sim.submit(SimCommand.new(sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	sim.step()
	return sim.dispatched_count() == before + 1


func _at(rel: Vector3i) -> Vector3i:
	return Vector3i(42500, 0, 41500) + rel * M


func _cell(rel: Vector3i) -> Vector3i:
	return BuildSystem.cell_of(_at(rel))


## The player on the creator's lots, which are theirs.
func _player(sim: SimRoot) -> int:
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var player: int = actors.spawn(&"arcade", 0)
	actors.set_position(player, _at(Vector3i.ZERO))
	assert_true(_do(sim, &"land.identify", {"actor": player, "owner": "player"}), "the player is somebody")
	for lot: String in SiteCreator.LOTS:
		assert_true(_do(sim, &"land.transfer", {"parcel": lot, "owner": "player"}), "and owns %s" % lot)
	return player


## `actor` holding a loaded g19.
func _arm(sim: SimRoot, actor: int) -> int:
	var weapon: int = SimAssembly.items_of(sim).arm(actor, &"g19", &"g19_mag_15", &"9x19_fmj", 15, actor * 100)
	assert_true(weapon != EntityIds.NONE and SimAssembly.actors_of(sim).wield(actor, weapon), "armed")
	return weapon


## Fires `shots` times, each once the weapon is ready. Returns the shots the sim took.
func _fire(sim: SimRoot, shooter: int, target: int, weapon: int, shots: int) -> int:
	var items: ItemSystem = SimAssembly.items_of(sim)
	var taken: int = 0
	for i: int in shots:
		for wait: int in 40:
			if not items.is_busy(weapon, sim.get_tick() + 1):
				break
			sim.step()
		if _do(sim, CombatSystem.COMMAND_FIRE, {"actor": shooter, "target": target}):
			taken += 1
	return taken


func test_god_mode_takes_a_full_magazine_and_nothing_else() -> void:
	var sim: SimRoot = _sandbox()
	var player: int = _player(sim)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var guard: int = actors.spawn(&"guard", 0)
	actors.set_position(guard, _at(Vector3i(2, 0, 0)))
	var weapon: int = _arm(sim, guard)
	var before: Dictionary = actors.health_of(player)
	assert_true(_do(sim, SandboxSystem.COMMAND_TRAINER, {"actor": player, "effect": "god", "on": true}), "god mode on")
	assert_eq(_fire(sim, guard, player, weapon, 15), 15, "a full magazine fired at the player")
	assert_true(SimAssembly.combat_of(sim).hits() > 0, "and some of it hit")
	assert_eq(actors.health_of(player), before, "the player's health is unchanged")
	assert_true(_do(sim, SandboxSystem.COMMAND_TRAINER, {"actor": player, "effect": "god", "on": false}), "god mode off")
	assert_eq(actors.damage_taken(player), ActorSystem.PER_MILLE, "and every hit counts again")
	assert_false(_do(sim, SandboxSystem.COMMAND_TRAINER, {"actor": player, "effect": "god", "on": false}), "off twice: refused")


func test_infinite_ammo_resolves_a_hundred_shots_from_a_full_magazine() -> void:
	var sim: SimRoot = _sandbox()
	var player: int = _player(sim)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var items: ItemSystem = SimAssembly.items_of(sim)
	var target: int = actors.spawn(&"range_dummy", 0)
	actors.set_position(target, _at(Vector3i(3, 0, 0)))
	assert_true(_do(sim, SandboxSystem.COMMAND_TRAINER, {"actor": target, "effect": "god", "on": true}), "a target that stays up")
	var weapon: int = _arm(sim, player)
	var loaded: int = items.rounds_in(items.magazine_of(weapon)).size()
	var chambered: int = items.chambered(weapon)
	assert_true(_do(sim, SandboxSystem.COMMAND_TRAINER, {"actor": player, "effect": "ammo", "on": true}), "infinite ammo on")
	var shots_before: int = SimAssembly.combat_of(sim).shots()
	assert_eq(_fire(sim, player, target, weapon, 100), 100, "a hundred-round burst")
	assert_eq(SimAssembly.combat_of(sim).shots() - shots_before, 100, "every shot resolved")
	assert_eq(items.rounds_in(items.magazine_of(weapon)).size(), loaded, "the magazine is still full")
	assert_eq(items.chambered(weapon), chambered, "and the same round in the chamber")
	assert_true(_do(sim, SandboxSystem.COMMAND_TRAINER, {"actor": player, "effect": "ammo", "on": false}), "off")
	assert_eq(_fire(sim, player, target, weapon, 1), 1, "one more shot")
	assert_eq(items.rounds_in(items.magazine_of(weapon)).size(), loaded - 1, "takes a round again")


func test_flying_a_step_off_a_roof_does_not_fall() -> void:
	var sim: SimRoot = _sandbox()
	var player: int = _player(sim)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var movement: MovementSystem = SimAssembly.movement_of(sim)
	var build: BuildSystem = SimAssembly.build_of(sim)
	# a roof two levels up: a foundation, a block, and the player on it
	var at: Vector3i = _cell(Vector3i(0, 0, 3))
	assert_true(build.place(player, &"foundation_block", BuildSystem.cell_centre(at), "") != EntityIds.NONE, "a foundation")
	assert_true(build.place(player, &"concrete_block", BuildSystem.cell_centre(at + Vector3i(0, 1, 0)), "") != EntityIds.NONE, "a block on it")
	assert_true(_do(sim, SandboxSystem.COMMAND_TELEPORT, {"actor": player, "cell": [at.x, 2, at.z]}), "onto the roof")
	assert_true(_do(sim, SandboxSystem.COMMAND_TRAINER, {"actor": player, "effect": "fly", "on": true}), "fly on")
	for i: int in 8:
		movement.move(player, 150, 0)
	assert_eq(BuildSystem.cell_of(actors.position_of(player)).x, at.x + 1, "a step off the edge")
	sim.step_n(20)
	assert_eq(BuildSystem.cell_of(actors.position_of(player)).y, 2, "and no fall")
	assert_true(movement.move(player, 0, 0, 1), "up a level with no flight to climb")
	assert_true(movement.move(player, 0, 0, -1), "and down again")
	assert_true(movement.move(player, 0, 0, -1), "down beside the block, in the air")
	for i: int in 8:
		movement.move(player, -150, 0)
	assert_eq(BuildSystem.cell_of(actors.position_of(player)).x, at.x + 1, "but never into the block")
	assert_true(movement.actor_fits(player, BuildSystem.cell_of(actors.position_of(player))), "the body fits where it is (M7.5 claim 2)")
	assert_true(_do(sim, SandboxSystem.COMMAND_TRAINER, {"actor": player, "effect": "fly", "on": false}), "fly off")
	sim.step_n(20)
	assert_eq(BuildSystem.cell_of(actors.position_of(player)).y, 0, "gravity has the player again")


func test_teleport_and_health_go_through_the_owning_rules() -> void:
	var sim: SimRoot = _sandbox()
	var player: int = _player(sim)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var build: BuildSystem = SimAssembly.build_of(sim)
	var block: Vector3i = _cell(Vector3i(4, 0, 4))
	build.place(player, &"foundation_block", BuildSystem.cell_centre(block), "")
	assert_false(_do(sim, SandboxSystem.COMMAND_TELEPORT, {"actor": player, "cell": [block.x, block.y, block.z]}), "into a foundation: refused")
	var free: Vector3i = _cell(Vector3i(6, 0, 6))
	assert_true(_do(sim, SandboxSystem.COMMAND_TELEPORT, {"actor": player, "cell": [free.x, free.y, free.z]}), "to open ground")
	assert_eq(BuildSystem.cell_of(actors.position_of(player)), free, "is there")
	var health: Dictionary = actors.health_of(player)
	var node: StringName = health.keys()[0]
	var most: int = actors.max_health(player, node)
	assert_true(_do(sim, SandboxSystem.COMMAND_SET_HEALTH, {"actor": player, "node": String(node), "value": most / 2}), "half health")
	assert_eq(actors.health_of(player)[node], most / 2, "set")
	assert_false(_do(sim, SandboxSystem.COMMAND_SET_HEALTH, {"actor": player, "node": String(node), "value": most + 1}), "over the most: refused")
	assert_false(_do(sim, SandboxSystem.COMMAND_SET_HEALTH, {"actor": player, "node": "nope", "value": 1}), "no such node: refused")
	assert_true(_do(sim, SandboxSystem.COMMAND_SET_HEALTH, {"actor": player, "node": String(node), "value": 0}), "to nothing")
	assert_false(actors.is_alive(player), "dead, as damage would leave it")
	assert_true(_do(sim, &"actor.respawn", {"actor": player}), "the revive is the game's respawn")
	assert_true(actors.is_alive(player), "back")


## Decision 3: in the game's own content none of the three stats exists, and the rules
## behave exactly as before; the trainer has nothing to turn.
func test_the_game_registers_none_of_the_trainer_stats() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var sim: SimRoot = SandboxAssembly.build(SEED, db)
	var stats: StatResolver = SimAssembly.stats_of(sim)
	for stat: StringName in [ActorSystem.STAT_DAMAGE_TAKEN, CombatSystem.STAT_ROUNDS_PER_SHOT, MovementSystem.STAT_GRAVITY]:
		assert_false(stats.has_stat(stat), "%s is the sandbox's, not the game's" % stat)
	var player: int = _player(sim)
	assert_eq(SimAssembly.actors_of(sim).damage_taken(player), ActorSystem.PER_MILLE, "every hit counts")
	assert_eq(SimAssembly.combat_of(sim).rounds_per_shot(player), 1, "every shot takes a round")
	assert_true(SimAssembly.movement_of(sim).has_gravity(player), "gravity holds")
	assert_false(_do(sim, SandboxSystem.COMMAND_TRAINER, {"actor": player, "effect": "god", "on": true}), "and the trainer is refused")
