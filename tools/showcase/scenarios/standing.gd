## Showcase for M6 claim 11 (heat). A guard watches a private yard. Alice is seen on
## the public street (no heat); Bob is seen inside the yard (witnessed trespass, +100),
## then opens a shed window wired to a power monitor (alarm, +200). Fast-forward shows
## heat cooling 50 every 1000 ticks and stopping at zero.
extends RefCounted

const ORIGIN: Vector3i = Vector3i(500000, 0, 500000)
const SHED: Vector3i = Vector3i(5, 0, 6)

var _alice: int = 0
var _bob: int = 0
var _guard: int = 0
var _window: int = 0
var _bob_path: Array[Vector3i] = [Vector3i(3, 0, 8), Vector3i(6, 0, 8), Vector3i(6, 0, 6)]
var _opened: bool = false


func title() -> String:
	return "Gcity M6 claim 11: HEAT (how hot the city is on you)"


func content(db: ContentDb) -> void:
	var district: Dictionary = db.get_entry(&"district", &"starter_ghetto").duplicate(true)
	var rights: Dictionary = district["rights"]
	var other: Dictionary = rights["other"]
	other["enter"] = false
	db.add(&"district", &"showcase_private", district)
	# a watchman who holds his post (the M4 guard's other stances would walk him off it)
	var watchman: Dictionary = db.get_entry(&"agent_profile", &"guard_sim").duplicate(true)
	watchman["stances"] = [{"stance": "hold", "weight": 1000}]
	db.add(&"agent_profile", &"showcase_watchman", watchman)
	# a shed window that opens from outside
	var window: Dictionary = db.get_entry(&"build_piece", &"window_frame").duplicate(true)
	window["latched"] = false
	db.add(&"build_piece", &"showcase_shed_window", window)


func _feet(cx: int, cz: int) -> Vector3i:
	return ORIGIN + Vector3i(cx * 1000 + 500, 0, cz * 1000 + 500)


func _at(c: Vector3i) -> Vector3i:
	return ORIGIN + Vector3i(c.x * 1000 + 500, c.y * 1000 + 500, c.z * 1000 + 500)


func setup(sim: SimRoot, view: Node3D) -> void:
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var build: BuildSystem = SimAssembly.build_of(sim)
	var land: LandSystem = SimAssembly.land_of(sim)
	var x0: int = ORIGIN.x
	var z0: int = ORIGIN.z
	_alice = actors.spawn(&"arcade", 0)
	_bob = actors.spawn(&"arcade", 1)
	actors.set_position(_alice, _feet(-3, 3))
	actors.set_position(_bob, _feet(-20, -20))
	# the shed, built before the yard was sold: closed, a window east wired to a power monitor
	for d: Vector3i in [Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(-1, 0, 0)]:
		build.place(_alice, &"foundation_block", _at(SHED + d), "")
	build.place(_alice, &"floor_panel", _at(SHED), "py")
	_window = build.place(_alice, &"showcase_shed_window", _at(SHED), "px")
	land.add_parcel(&"showcase_yard", &"showcase_private", &"corp", [[x0, z0], [x0 + 10000, z0], [x0 + 10000, z0 + 10000], [x0, z0 + 10000]], -1000, 3000)
	actors.set_position(_bob, _feet(3, 3))
	var perception: PerceptionSystem = SimAssembly.perception_of(sim)
	_guard = perception.spawn(&"showcase_watchman", BuildSystem.cell_of(_feet(9, 2)), 180, 1, "")
	SimAssembly.sensors_of(sim).install(&"power_monitor", _window, 1)
	view.call("name_actor", _alice, "Alice", true)
	view.call("name_actor", _bob, "Bob", true)
	view.call("name_actor", _guard, "Guard", false)
	var o: Vector3 = Vector3(float(x0) / 1000.0, 0.0, float(z0) / 1000.0)
	view.call("slab", o + Vector3(-8, 0, -2), Vector2(8, 14), Color(0.3, 0.32, 0.36))
	view.call("slab", o, Vector2(10, 10), Color(0.55, 0.15, 0.15, 0.6))
	view.call("pin", "street", o + Vector3(-4, 0.2, 9.5), "PUBLIC STREET\nanyone may stand here", Color(0.85, 0.85, 0.9))
	view.call("pin", "yard", o + Vector3(5, 0.2, 10.5), "PRIVATE YARD (owned by Corp)\nno entry for outsiders", Color(1.0, 0.6, 0.6))
	view.call("pin", "shed", o + Vector3(4.5, 2.9, 6.5), "shed (window has\na power monitor)", Color(0.7, 0.9, 1.0))
	view.call("place_camera", o + Vector3(17, 15, -7), o + Vector3(3, 0, 5), 18.0)


func before_tick(sim: SimRoot, _view: Node3D, tick: int) -> void:
	if tick < 220:
		return
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	if not _bob_path.is_empty():
		var goal: Vector3i = _feet(_bob_path[0].x, _bob_path[0].z)
		var here: Vector3i = actors.position_of(_bob)
		var d: Vector3i = goal - here
		if absi(d.x) + absi(d.z) < 60:
			_bob_path.remove_at(0)
			return
		var speed: int = SimAssembly.movement_of(sim).speed_of(_bob)
		var dx: int = clampi(d.x, -speed, speed)
		var dz: int = clampi(d.z, -speed, speed) if dx == 0 else 0
		sim.submit(SimCommand.new(tick, &"actor.move", {"actor": _bob, "dx": dx, "dz": dz}))
		return
	if not _opened:
		_opened = true
		sim.submit(SimCommand.new(tick, &"opening.open", {"actor": _bob, "piece": _window}))


func ticks_per_frame(tick: int) -> int:
	return 4 if tick < 560 else 100


func end_tick() -> int:
	return 8800


func caption(tick: int) -> String:
	if tick < 50:
		return "A guard (green = has not noticed anyone yet) watches a private yard. Alice stands on the public street. Bob has climbed into the yard."
	if tick < 220:
		return "The guard spots both (red). Alice is only on the public street, so her HEAT stays 0. Bob is caught trespassing: his HEAT goes up by 100 each time he is spotted inside."
	if tick < 560:
		return "Bob sneaks round to the shed and opens its window. A power monitor on the window raises an alarm against him: another 200 HEAT (orange bar)."
	return "Fast-forward: heat cools by itself, 50 points every 25 seconds of game time, and stops at zero. (Notoriety, earned by finishing contracts, never cools.)"
