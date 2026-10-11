## Showcase for M6 claims 14-15 (the contract, exfil, delivery and pay), and the
## integration of claims 1-13 it rests on: one player takes the Cold Storage job from
## Marlow and does it by the UNDER route through the real sim, every action a command:
## accept, walk to the street grate, cut it and drop into the tunnel, cut the basement
## grate, climb the stairs to storey 1, hack the server-room terminal, log out, climb
## back down, out up the tunnel's access hatch, leave the site, deliver, get paid.
## A step that fails is reported in the feed, never skipped silently.
extends RefCounted

const QUEST: String = "cold_storage_contract"
const FIXER: Vector3i = Vector3i(14, 0, -3)

var _sim: SimRoot
var _view: Node3D
var _player: int = 0
var _o: Vector3i
## [action, arg, label]
var _plan: Array = []
var _step: int = 0
var _started: int = 0
var _issued: bool = false
var _rejected_before: int = 0
var _caption: String = ""
## the waypoint the current walk is heading for
var _wp: int = 0


func title() -> String:
	return "Gcity M6 claims 14-15: THE COLD STORAGE JOB, start to pay"


func content(_db: ContentDb) -> void:
	pass


func setup(sim: SimRoot, view: Node3D) -> void:
	_sim = sim
	_view = view
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var items: ItemSystem = SimAssembly.items_of(sim)
	_o = SimAssembly.sites_of(sim).placement_of(&"cold_storage")
	_player = actors.spawn(&"arcade", 0)
	actors.set_position(_player, _feet(FIXER + Vector3i(1, 0, 0)))
	var inv: String = String(ItemSystem.inventory_of(_player))
	for spec: Array in [["tool", "plasma_cutter", 1], ["device_frame", "handset", 2], ["device_module", "daemon_coprocessor", 3]]:
		sim.submit(SimCommand.new(1, &"item.spawn", {"kind": spec[0], "template": spec[1], "container": inv, "seed": spec[2], "count": 1}))
	view.call("name_actor", _player, "You", true)
	var f: Vector3 = Vector3(FIXER) + Vector3(0.5, 0, 0.5)
	view.call("pin", "marlow", f + Vector3(0, 2.2, 0), "MARLOW (fixer)", Color(1.0, 0.85, 0.4))
	var post: MeshInstance3D = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.3
	mesh.bottom_radius = 0.3
	mesh.height = 1.8
	post.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.75, 0.25)
	post.material_override = mat
	post.position = f + Vector3(0, 0.9, 0)
	view.add_child(post)
	view.call("slab", Vector3(10, -0.02, -10), Vector2(52, 24), Color(0.3, 0.32, 0.36))
	var o: Vector3i = _o
	_plan = [
		["wait", 3, "Kit up: a plasma cutter in hand, a handset with a daemon coprocessor."],
		["kit", 0, ""],
		["accept", 0, "At Marlow: accept the Cold Storage job. Cold Storage appears on the docklands."],
		["walk", [Vector3i(15, 0, -4), Vector3i(o.x + 1, 0, -4), Vector3i(o.x + 1, 0, -3)], "Walk along the street to the city's grate in front of Cold Storage."],
		["breach", ["face", o + Vector3i(1, -1, -3), "py"], "Cut the street grate (10 s, noisy) and drop into the service tunnel."],
		["wait", 30, ""],
		["walk", [o + Vector3i(4, -1, -3), o + Vector3i(4, -1, -1)], "Crawl the tunnel to the grate into Cold Storage's basement."],
		["breach", ["face", o + Vector3i(4, -1, -1), "pz"], "Cut the basement grate (10 s)."],
		["walk", [o + Vector3i(4, -1, 1), o + Vector3i(3, -1, 1), o + Vector3i(3, -1, 4), o + Vector3i(7, -1, 4)], "Through the basement, round the guard's back, to the stairs."],
		["climb", ["cell", o + Vector3i(7, -1, 5)], "Up the stairs into the hall, out of the lobby camera's sight."],
		["walk", [o + Vector3i(9, 0, 5)], ""],
		["climb", ["cell", o + Vector3i(9, 0, 6)], "Up to storey 1."],
		["walk", [o + Vector3i(9, 1, 5), o + Vector3i(2, 1, 5), o + Vector3i(2, 1, 6)], "Along the corridor into the server room."],
		["hack", 0, "Hack the terminal: 15 s standing still while it makes a little noise."],
		["logout", 0, "Log out of the terminal, so it is not left as a trace."],
		["walk", [o + Vector3i(2, 1, 5), o + Vector3i(9, 1, 5), o + Vector3i(9, 1, 6)], "Back the way you came."],
		["climb", ["cell", o + Vector3i(9, 0, 6)], ""],
		["walk", [o + Vector3i(7, 0, 5)], ""],
		["climb", ["cell", o + Vector3i(7, -1, 5)], ""],
		["walk", [o + Vector3i(3, -1, 4), o + Vector3i(3, -1, 1), o + Vector3i(4, -1, 1), o + Vector3i(4, -1, -3), o + Vector3i(2, -1, -3)], "Down to the tunnel and to its access hatch."],
		["climb", ["face", o + Vector3i(2, -1, -3), "py"], "Up the latched hatch to the street: it opens from below only."],
		["walk", [Vector3i(o.x + 2, 0, -7), Vector3i(15, 0, -7), Vector3i(15, 0, -3)], "Off the site with the drive (that is the exfil), and back to Marlow."],
		["deliver", 0, "Hand Marlow the drive. Pay depends on how quiet the job was."],
		["wait", 120, "Done: the job, the pay and the run's record, all from the simulation."],
	]


func _feet(c: Vector3i) -> Vector3i:
	return BuildSystem.cell_centre(c) - Vector3i(0, BuildSystem.CELL / 2, 0)


func _here() -> Vector3i:
	return BuildSystem.cell_of(SimAssembly.actors_of(_sim).position_of(_player))


func _piece(spec: Array) -> int:
	var build: BuildSystem = SimAssembly.build_of(_sim)
	var kind: String = spec[0]
	var cell: Vector3i = spec[1]
	if kind == "cell":
		return build.cell_piece_at(cell)
	var facing: String = spec[2]
	return build.face_piece_at(BuildSystem.face_key(cell, facing))


func _terminal() -> int:
	var hacks: HackSystem = SimAssembly.hacks_of(_sim)
	for t: int in SimAssembly.sites_of(_sim).targets_of(&"cold_storage"):
		var rec: Dictionary = hacks.snapshot()["targets"][t]
		if rec["target"] == &"cold_storage_terminal":
			return t
	return EntityIds.NONE


func _submit(tick: int, kind: StringName, payload: Dictionary) -> void:
	_rejected_before = _sim.rejected_count()
	_sim.submit(SimCommand.new(tick, kind, payload))


func before_tick(sim: SimRoot, view: Node3D, tick: int) -> void:
	_follow(view, tick)
	if _step >= _plan.size():
		return
	var step: Array = _plan[_step]
	var action: String = step[0]
	var label: String = step[2]
	if not _issued:
		_issued = true
		_started = tick
		_wp = 0
		print("step %d at tick %d: %s %s, player at %s" % [_step, tick, action, str(step[1]), _here() - _o])
		if not label.is_empty():
			_caption = label
		_issue(action, step[1], tick)
		return
	if sim.rejected_count() > _rejected_before:
		print("  refused at tick %d: %s, player at %s" % [tick, action, _here() - _o])
		view.call("note", "the sim REFUSED: %s" % action, 0)
		_rejected_before = sim.rejected_count()
	if _done(action, step[1], tick):
		_step += 1
		_issued = false
	elif tick - _started > 1200:
		view.call("note", "stuck on: %s (moving on)" % action, 0)
		_step += 1
		_issued = false


func _issue(action: String, arg: Variant, tick: int) -> void:
	var items: ItemSystem = SimAssembly.items_of(_sim)
	match action:
		"kit":
			var inv: Array[int] = items.items_in(ItemSystem.inventory_of(_player))
			for id: int in inv:
				var kind: StringName = items.item_kind(id)
				if kind == ItemSystem.KIND_TOOL:
					_submit(tick, &"actor.wield", {"actor": _player, "weapon": id})
				elif kind == ItemSystem.KIND_DEVICE_FRAME:
					_submit(tick, &"actor.equip_device", {"actor": _player, "device": id})
		"accept":
			_submit(tick, &"quest.accept", {"actor": _player, "quest": QUEST})
		"breach":
			var spec_b: Array = arg
			_submit(tick, &"build.breach", {"actor": _player, "piece": _piece(spec_b)})
		"climb":
			var spec_c: Array = arg
			_submit(tick, &"actor.climb", {"actor": _player, "piece": _piece(spec_c)})
		"hack":
			_submit(tick, &"hack.start", {"actor": _player, "target": _terminal()})
		"logout":
			_submit(tick, &"hack.logout", {"actor": _player, "target": _terminal()})
		"deliver":
			_submit(tick, &"contract.deliver", {"actor": _player, "quest": QUEST})


func _done(action: String, arg: Variant, tick: int) -> bool:
	var items: ItemSystem = SimAssembly.items_of(_sim)
	match action:
		"kit":
			# attach the coprocessor once the device is carried
			var device: int = SimAssembly.actors_of(_sim).device_of(_player)
			if device == EntityIds.NONE:
				return false
			if not SimAssembly.hacks_of(_sim).capacity(_player) >= 2:
				for id: int in items.items_in(ItemSystem.inventory_of(_player)):
					if items.item_kind(id) == ItemSystem.KIND_DEVICE_MODULE:
						_submit(tick, &"item.attach", {"actor": _player, "weapon": device, "part": id})
				return false
			return true
		"accept":
			return SimAssembly.sites_of(_sim).is_spawned(&"cold_storage")
		"wait":
			var n: int = arg
			return tick - _started >= n
		"walk":
			var cells: Array = arg
			return _walk(cells, tick)
		"breach":
			return not SimAssembly.build_of(_sim).is_breaching(_player) and tick - _started > 2 and SimAssembly.movement_of(_sim).can_act(_player)
		"climb":
			return tick - _started > 2 and SimAssembly.movement_of(_sim).can_act(_player)
		"hack":
			return tick - _started > 2 and not SimAssembly.hacks_of(_sim).is_hacking(_player)
		"logout", "deliver":
			return tick - _started > 2
	return true


## Walks the cells in order along straight lines, one axis at a time; true when done.
func _walk(cells: Array, tick: int) -> bool:
	if not SimAssembly.movement_of(_sim).can_act(_player):
		return false
	var actors: ActorSystem = SimAssembly.actors_of(_sim)
	while _wp < cells.size():
		var goal_cell: Vector3i = cells[_wp]
		var d: Vector3i = _feet(goal_cell) - actors.position_of(_player)
		if absi(d.x) + absi(d.z) < 60:
			_wp += 1
			continue
		var speed: int = SimAssembly.movement_of(_sim).speed_of(_player)
		var dx: int = clampi(d.x, -speed, speed)
		var dz: int = clampi(d.z, -speed, speed) if dx == 0 else 0
		_submit(tick, &"actor.move", {"actor": _player, "dx": dx, "dz": dz})
		return false
	return true


func _follow(view: Node3D, tick: int) -> void:
	if tick % 4 != 0:
		return
	var p: Vector3 = Vector3(SimAssembly.actors_of(_sim).position_of(_player)) / 1000.0
	var storey: int = _here().y
	view.call("cutaway", storey if SimAssembly.sites_of(_sim).is_spawned(&"cold_storage") else 99)
	view.call("place_camera", p + Vector3(-9, 13, -11), p, 18.0)


func ticks_per_frame(_tick: int) -> int:
	if _step < _plan.size():
		var step: Array = _plan[_step]
		var action: String = step[0]
		if action == "breach" or action == "hack":
			return 40
	return 8


func end_tick() -> int:
	return 9000 if _step < _plan.size() else _started + 125


func caption(_tick: int) -> String:
	return _caption
