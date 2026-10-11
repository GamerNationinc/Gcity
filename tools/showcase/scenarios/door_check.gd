## Showcase for M6 claim 10 (credentials and the heat check). Two players carry the
## Cold Storage keycard. Cara (heat 0) opens the front door: it opens, nothing else
## happens. Dex arrives already hot (heat 400 from earlier alarms): the door opens for
## him too, but the lobby camera reports him and a guard round the back hears of it by
## radio. Everything goes through commands (actor.move, opening.open/close).
extends RefCounted

const ORIGIN: Vector3i = Vector3i(500000, 0, 500000)

var _cara: int = 0
var _dex: int = 0
var _guard: int = 0
var _door: int = 0
## [actor, action, arg]: "walk" to a cell [x, z], "open", "close", "wait" ticks
var _plan: Array = []
var _wait_until: int = 0
var _phase: int = 0


func title() -> String:
	return "Gcity M6 claim 10: KEYCARD DOOR that checks your HEAT"


func content(db: ContentDb) -> void:
	# a guard who holds his post facing away: he can only learn of anyone by radio
	var watchman: Dictionary = db.get_entry(&"agent_profile", &"guard_sim").duplicate(true)
	watchman["stances"] = [{"stance": "hold", "weight": 1000}]
	db.add(&"agent_profile", &"showcase_watchman", watchman)


func _feet(cx: int, cz: int) -> Vector3i:
	return ORIGIN + Vector3i(cx * 1000 + 500, 0, cz * 1000 + 500)


func _at(cx: int, cy: int, cz: int) -> Vector3i:
	return ORIGIN + Vector3i(cx * 1000 + 500, cy * 1000 + 500, cz * 1000 + 500)


func setup(sim: SimRoot, view: Node3D) -> void:
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var build: BuildSystem = SimAssembly.build_of(sim)
	var items: ItemSystem = SimAssembly.items_of(sim)
	_cara = actors.spawn(&"arcade", 0)
	_dex = actors.spawn(&"arcade", 1)
	actors.set_position(_cara, _feet(3, -2))
	actors.set_position(_dex, _feet(3, 3))
	# the lobby: one room, foundations on three sides, a roof, the front door to the east
	for c: Vector3i in [Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		build.place(_cara, &"foundation_block", _at(c.x, c.y, c.z), "")
	build.place(_cara, &"floor_panel", _at(0, 0, 0), "py")
	_door = build.place(_cara, &"cold_storage_door", _at(0, 0, 0), "px")
	SimAssembly.sensors_of(sim).install(&"door_camera", _door, 1)
	for a: int in [_cara, _dex]:
		items.spawn(&"key_item", &"cold_storage_keycard", ItemSystem.inventory_of(a), a)
	_guard = SimAssembly.perception_of(sim).spawn(&"showcase_watchman", BuildSystem.cell_of(_feet(-2, 7)), 90, 1, "")
	view.call("name_actor", _cara, "Cara", true)
	view.call("name_actor", _dex, "Dex", true)
	view.call("name_actor", _guard, "Guard round the back", false)
	# Dex's earlier trouble: two alarms on a previous job put his heat at 400
	for i: int in 2:
		SimAssembly.combat_of(sim).events().emit(SensorSystem.EVENT_ALARM, {"sensor": &"an earlier job", "piece": 0, "squad": 0, "actor": _dex})
	var o: Vector3 = Vector3(float(ORIGIN.x) / 1000.0, 0.0, float(ORIGIN.z) / 1000.0)
	view.call("slab", o + Vector3(-3, 0, -5), Vector2(20, 11), Color(0.3, 0.32, 0.36))
	view.call("pin", "door", o + Vector3(0.3, 4.0, -1.5), "COLD STORAGE FRONT DOOR\nkeycard lock; tells the camera\nif your HEAT is over 300", Color(1.0, 0.85, 0.6))
	view.call("pin", "camera", o + Vector3(-1.2, 1.6, 1.8), "lobby (camera inside)", Color(0.8, 0.9, 1.0))
	view.call("place_camera", o + Vector3(9, 11, -11), o + Vector3(3, 0, 0.5), 15.0)
	_plan = [
		[_cara, "wait", 40], [_cara, "walk", [1, -2]], [_cara, "walk", [1, 0]], [_cara, "open", 0], [_cara, "wait", 60],
		[_cara, "close", 0], [_cara, "walk", [1, -2]], [_cara, "walk", [3, -3]], [_cara, "phase", 1],
		[_dex, "walk", [1, 3]], [_dex, "walk", [1, 0]], [_dex, "open", 0], [_dex, "phase", 2], [_dex, "wait", 160], [_dex, "phase", 3],
	]


func before_tick(sim: SimRoot, _view: Node3D, tick: int) -> void:
	if _plan.is_empty() or tick < _wait_until:
		return
	var step: Array = _plan[0]
	var actor: int = step[0]
	var action: String = step[1]
	match action:
		"wait":
			var n: int = step[2]
			_wait_until = tick + n
			_plan.remove_at(0)
		"phase":
			var p: int = step[2]
			_phase = p
			_plan.remove_at(0)
		"open", "close":
			sim.submit(SimCommand.new(tick, &"opening.open" if action == "open" else &"opening.close", {"actor": actor, "piece": _door}))
			_plan.remove_at(0)
		"walk":
			var cell: Array = step[2]
			var cx: int = cell[0]
			var cz: int = cell[1]
			var goal: Vector3i = _feet(cx, cz)
			var here: Vector3i = SimAssembly.actors_of(sim).position_of(actor)
			var d: Vector3i = goal - here
			if absi(d.x) + absi(d.z) < 60:
				_plan.remove_at(0)
				return
			var speed: int = SimAssembly.movement_of(sim).speed_of(actor)
			var dx: int = clampi(d.x, -speed, speed)
			var dz: int = clampi(d.z, -speed, speed) if dx == 0 else 0
			sim.submit(SimCommand.new(tick, &"actor.move", {"actor": actor, "dx": dx, "dz": dz}))


func ticks_per_frame(_tick: int) -> int:
	return 4


func end_tick() -> int:
	return 640


func caption(_tick: int) -> String:
	match _phase:
		0:
			return "Cara and Dex both carry the Cold Storage keycard. Cara has HEAT 0. She opens the front door with her card: it opens, and nothing else happens."
		1:
			return "Dex carries the same card, but he arrives with HEAT 400 from earlier trouble. The door's limit is 300."
		2:
			return "The card still works and the door opens for Dex, but the lobby camera reports him: an alarm, +200 HEAT, and half a second later the guard round the back knows about him by radio (red)."
	return "Same card, same door: being 'hot' does not lock you out, it makes the door give you away."
