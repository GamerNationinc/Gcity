extends GcityTest

## M7.6 spec claim 9: a session is a fixture. Random sandbox sessions (spawns, trainer
## toggles, AI holds, teleports, health, despawns, held and single-stepped clocks) are written by the client's own
## writer (`SandboxMode.fixture_text`), parsed by the fixture schema, and replayed twice on
## fresh sandbox sims: each reproduces the hash it recorded.

const SEED: int = 20261709
const CASES: int = 1_000
const STEPS: int = 30
const SITE_CASES: int = 15
const PROFILES: Array[String] = ["guard_sim", "guard_arcade", "foot_patrol"]
const KIT: Dictionary = {"frame": "g19", "magazine": "g19_mag_15", "ammo": "9x19_fmj", "rounds": 15}

var _db: ContentDb


func _content() -> ContentDb:
	if _db == null:
		_db = ContentDb.new()
		assert_eq(ContentLoader.load_all(_db), OK, "content loads")
		assert_eq(ContentLoader.load_all(_db, "res://sandbox_content"), OK, "and the sandbox's")
	return _db


## Submits for the next tick and records it, as the world view does.
func _send(sim: SimRoot, session: Array[Dictionary], kind: StringName, payload: Dictionary) -> void:
	assert_eq(sim.submit(SimCommand.new(sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	session.append({"tick": sim.get_tick() + 1, "kind": String(kind), "payload": payload.duplicate(true)})


func _one(rng: RandomNumberGenerator, case: int, sites: bool = false) -> void:
	var seed: int = rng.randi_range(1, 1 << 30)
	var sim: SimRoot = SandboxAssembly.build(seed, _content())
	var session: Array[Dictionary] = []
	var start: Vector3i = Vector3i(42, 0, 41)
	_send(sim, session, &"actor.spawn", {"profile": "arcade", "range_m": 0})
	sim.step()
	var player: int = SimAssembly.actors_of(sim).actor_ids()[0]
	_send(sim, session, SandboxSystem.COMMAND_TELEPORT, {"actor": player, "cell": [start.x, start.y, start.z]})
	_send(sim, session, &"land.identify", {"actor": player, "owner": "player"})
	for lot: String in SiteCreator.LOTS:
		_send(sim, session, &"land.transfer", {"parcel": lot, "owner": "player"})
	sim.step()
	for step: int in STEPS:
		var cell: Array = [start.x + rng.randi_range(-4, 4), 0, start.z + rng.randi_range(-4, 4)]
		match rng.randi_range(0, 11 if sites else 9):
			0, 1:
				_send(sim, session, SandboxSystem.COMMAND_SPAWN_AGENT, {"actor": player, "profile": PROFILES[rng.randi_range(0, PROFILES.size() - 1)],
					"cell": cell, "facing": rng.randi_range(0, 3) * 90, "kit": KIT if rng.randi_range(0, 1) == 1 else {}})
			2:
				_send(sim, session, SandboxSystem.COMMAND_TRAINER, {"actor": player, "effect": SandboxSystem.TRAINER_EFFECTS[rng.randi_range(0, 2)], "on": rng.randi_range(0, 1) == 1})
			3:
				_send(sim, session, SandboxSystem.COMMAND_AI, {"actor": player, "agent": "all", "effect": SandboxSystem.AI_EFFECTS[rng.randi_range(0, 2)], "on": rng.randi_range(0, 1) == 1})
			4:
				_send(sim, session, SandboxSystem.COMMAND_TELEPORT, {"actor": player, "cell": cell})
			5:
				_send(sim, session, SandboxSystem.COMMAND_DESPAWN, {"actor": player, "cell": [cell[0], 1, cell[2]], "facing": ""})
			6:
				# the device up: the client's clock held, no sim pause; then a single step
				# or several, as the time page gives them
				_send(sim, session, SandboxSystem.COMMAND_SET_HEALTH, {"actor": player, "node": "body", "value": rng.randi_range(1, 100) * 1000})
			7:
				_send(sim, session, &"item.spawn", {"kind": "ammo", "template": "9x19_fmj", "container": String(ItemSystem.inventory_of(player)), "seed": step, "count": 15})
			8:
				_send(sim, session, &"actor.move", {"actor": player, "dx": rng.randi_range(-150, 150), "dz": rng.randi_range(-150, 150)})
			9:
				# gate item 30: a site at the cursor (refused while it stands) ...
				_send(sim, session, SiteSystem.COMMAND_RAISE, {"actor": player, "site": "m4_test_building", "at": [start.x + rng.randi_range(-2, 2), 0, start.z + rng.randi_range(-2, 2)]})
			10:
				# ... and the clear that takes it down, so it raises again
				_send(sim, session, SandboxSystem.COMMAND_CLEAR, {"actor": player})
			_:
				pass
		for i: int in rng.randi_range(1, 4):
			sim.step()
	# the last commands run before the save, as a player's do while the device comes up
	sim.step()
	var why: Array[String] = []
	var text: String = SandboxMode.fixture_text(sim, session, "case-%d" % case, why)
	assert_false(text.is_empty(), "case %d saves: %s" % [case, why])
	var fixture: ReplayFixture = ReplayFixture.parse(text)
	assert_true(fixture.is_valid(), "case %d is a fixture: %s" % [case, fixture.error])
	assert_eq(fixture.assembly, "sandbox", "recorded on the sandbox's assembly")
	for twice: int in 2:
		var hash: String = Replay.run(fixture, SandboxAssembly.build(fixture.seed, _content()))
		if hash != fixture.expected_hash:
			assert_eq(hash, fixture.expected_hash, "case %d (seed %d) replay %d reproduces its hash" % [case, seed, twice + 1])
			return


func test_property_a_saved_session_replays_to_its_hash() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var started: int = Time.get_ticks_msec()
	for case: int in CASES:
		_one(rng, case)
	print("  %d sessions in %d ms" % [CASES, Time.get_ticks_msec() - started])


## Gate item 30 (CEOGG, 2026-10-07: clear un-raises sites): sessions that raise a site,
## clear it away and raise it again replay to their hash. Fewer cases: a site is 197
## pieces and four guards: 15 here (about 4 min); a 100-case run passed on the Deck
## 2026-10-07 (3 663 assertions, 25 min), recorded in the gate.
func test_property_a_session_raising_and_clearing_sites_replays() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 30
	var started: int = Time.get_ticks_msec()
	for case: int in SITE_CASES:
		_one(rng, case, true)
	print("  %d sessions with sites in %d ms" % [SITE_CASES, Time.get_ticks_msec() - started])


## A session with a command still due cannot be a fixture yet, and says why.
func test_a_command_still_due_is_not_saved() -> void:
	var sim: SimRoot = SandboxAssembly.build(SEED, _content())
	var session: Array[Dictionary] = []
	_send(sim, session, &"actor.spawn", {"profile": "arcade", "range_m": 0})
	var why: Array[String] = []
	assert_eq(SandboxMode.fixture_text(sim, session, "early", why), "", "nothing has run")
	sim.step()
	_send(sim, session, &"actor.spawn", {"profile": "arcade", "range_m": 0})
	why.clear()
	assert_eq(SandboxMode.fixture_text(sim, session, "due", why), "", "a spawn still due")
	assert_true(why[0].contains("still due"), "says so: %s" % why[0])
