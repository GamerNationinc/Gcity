extends GcityTest

## The G4 extension exercise (standards §11): a third agent profile with its own
## perception, aim and stress profiles and a second patrol route, content only. This
## test names no profile: it walks whatever content/ holds, so a fourth profile is
## covered the day its file lands.

const SEED: int = 20261090
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)
const NEVER: int = 100_000

var _sim: SimRoot
var _actors: ActorSystem
var _perception: PerceptionSystem
var _stances: StanceSystem
var _player: int = 0


func _db() -> ContentDb:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	return db


func _setup() -> void:
	_sim = SimAssembly.build(SEED, _db())
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_perception = SimAssembly.perception_of(_sim)
	_stances = SimAssembly.stances_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, FAR + Vector3i(-100 * M, 0, -100 * M))


func _cell(cx: int, cz: int) -> Vector3i:
	return BuildSystem.cell_of(FAR) + Vector3i(cx, 0, cz)


func _at(cx: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, 0, cz * M + 500)


func test_every_agent_profile_spawns_and_every_route_is_walkable() -> void:
	_setup()
	var db: ContentDb = _sim.get_system(&"content")
	var profiles: Array[StringName] = db.ids(&"agent_profile")
	var routes: Array[StringName] = db.ids(&"patrol_route")
	assert_true(profiles.size() >= 4, "at least four agent profiles (%d)" % profiles.size())
	assert_true(routes.size() >= 4, "at least four patrol routes (%d)" % routes.size())
	var i: int = 0
	for profile: StringName in profiles:
		var agent: int = _perception.spawn(profile, _cell(i * 3, 0), 0, 1, "")
		assert_true(agent > 0, "agent_profile/%s spawns" % profile)
		assert_true(_stances.allowed_stances(agent).size() >= 1, "%s allows a stance" % profile)
		for entry: Dictionary in _stances.allowed_stances(agent):
			var name: StringName = entry["stance"]
			assert_true(_stances.implemented_stances().has(name), "%s's stance %s has a scorer" % [profile, name])
		assert_true(_perception.perception_of(agent).size() > 0 and SimAssembly.aim_of(_sim).aim_profile_of(agent).size() > 0 and SimAssembly.stress_of(_sim).stress_profile_of(agent).size() > 0, "%s binds all three profiles" % profile)
		i += 1
	_sim.step_n(10)
	assert_eq(_sim.rejected_count(), 0, "nothing rejected")
	# every route's cells are cells an agent can be sent to (a spawn on each route works)
	for route: StringName in routes:
		var t: Dictionary = db.get_entry(&"patrol_route", route)
		var cells: Array = t["cells"]
		var first: Vector3i = PathingSystem._vec(cells[0])
		assert_true(_perception.spawn(profiles[0], first, 0, 2, String(route)) > 0, "patrol_route/%s takes an agent" % route)


func test_metamorphic_relations_hold_for_every_profile() -> void:
	# reduced perception never lowers time to alert: for every profile, a copy with a
	# narrower cone and shorter range alerts no sooner than the original
	var db: ContentDb = _db()
	var profiles: Array[StringName] = db.ids(&"agent_profile")
	var checked: int = 0
	for profile: StringName in profiles:
		var t: Dictionary = db.get_entry(&"agent_profile", profile)
		var perception_s: String = t["perception_profile"]
		var p: Dictionary = db.get_entry(&"perception_profile", StringName(perception_s)).duplicate(true)
		var fov: int = p["fov_deg"]
		var range_mm: int = p["sight_range_mm"]
		var gain: int = p["gain_per_tick"]
		p["fov_deg"] = maxi(fov / 2, 1)
		p["sight_range_mm"] = maxi(range_mm / 2, 1)
		p["gain_per_tick"] = gain / 2
		var less: ContentDb = _db()
		less.add(&"perception_profile", &"t_less", p)
		var agent: Dictionary = t.duplicate(true)
		agent["perception_profile"] = "t_less"
		less.add(&"agent_profile", &"t_less", agent)
		var times: Array[int] = []
		for variant: int in 2:
			var sim: SimRoot = SimAssembly.build(SEED, less)
			var actors: ActorSystem = SimAssembly.actors_of(sim)
			var perception: PerceptionSystem = SimAssembly.perception_of(sim)
			var player: int = actors.spawn(&"arcade", 0)
			actors.set_position(player, _at(8, 0))
			var guard: int = perception.spawn(profile if variant == 0 else &"t_less", _cell(0, 0), 0, 1, "")
			var when: int = NEVER
			for i: int in 200:
				sim.step()
				if perception.is_alerted(guard, player):
					when = i + 1
					break
			times.append(when)
		assert_true(times[1] >= times[0], "%s: reduced perception never alerts sooner (%d vs %d)" % [profile, times[0], times[1]])
		checked += 1
	assert_true(checked >= 4, "every profile checked (%d)" % checked)
