## A playtest bot (CLAUDE.md §8: the cloud plays first): the Cold Storage job by the
## under route, played through the real client, `world_view.tscn -- --playtest=
## cold_storage_stealth` (tools/playtest.sh). Every move is the view's own stick
## (WorldView.move_step), every action the context button (Interact) or a press on the
## device (DeviceShell, the hacking pane); only the kit-up (fitting the coprocessor)
## is a plain command. Before each stretch past the patrols it waits, as a careful
## player watching them would, until playing the stretch ahead on a copy of the sim,
## through a stand-in view with the same button, device and stick, leaves nobody
## alerted for 420 ticks after (past a guard's 400-tick memory); after 2400 ticks
## without one it goes anyway. The run passes when the job is delivered with the player
## alive; the verdict line gives the pay and whether anyone was alerted.
extends RefCounted

const QUEST: StringName = &"cold_storage_contract"
const MARLOW: Vector3i = Vector3i(14, 0, -3)
const EVERY: int = 10
const PATIENCE: int = 2400
const MARGIN: int = 420
const LIMIT: int = 20000

var _plan: Plan = null
var _alerted: Array[bool] = [false]
var _subscribed: bool = false


func tick(view: Node) -> void:
	var sim: SimRoot = view.call("sim")
	var ready: bool = view.call("is_ready")
	if not ready:
		return
	if not _subscribed:
		_subscribed = true
		var alerted: Array[bool] = _alerted
		var player: int = view.call("player")
		SimAssembly.combat_of(sim).events().subscribe(PerceptionSystem.EVENT_ALERTED, func(p: Dictionary) -> void:
			if p["contact"] == player:
				alerted[0] = true)
		_plan = Plan.new(_route(sim, player))
	if OS.has_environment("PLAYTEST_DEBUG") and sim.get_tick() % 400 == 0:
		var perception: PerceptionSystem = SimAssembly.perception_of(sim)
		var line: String = "  t%d step %d:" % [sim.get_tick(), _plan.step]
		for a: int in SimAssembly.sites_of(sim).agents_of(&"cold_storage"):
			line += "  %d %s %s %s/%s" % [a, BuildSystem.cell_of(SimAssembly.actors_of(sim).position_of(a)) - SimAssembly.sites_of(sim).origin_of(&"cold_storage"),
				SimAssembly.stances_of(sim).stance_of(a), SimAssembly.pathing_of(sim).state_of(a), perception.route_of(a)]
		print(line)
	if sim.get_tick() > LIMIT:
		view.call("finish", "ran past %d ticks at step %d" % [LIMIT, _plan.step], false)
		return
	_plan.tick(view)
	if not _plan.failure.is_empty():
		view.call("finish", _plan.failure, false)
	elif _plan.done():
		var player: int = view.call("player")
		view.call("finish", _verdict(sim, player), _passed(sim, player))


## The loop worked: the job delivered and the player alive. Whether it was a ghost run
## is the verdict's to say (the m6-stealth fixture is the stealth proof).
func _passed(sim: SimRoot, player: int) -> bool:
	return SimAssembly.quests_of(sim).status_of(player, QUEST) == QuestSystem.STATUS_COMPLETED and SimAssembly.actors_of(sim).is_alive(player)


func _verdict(sim: SimRoot, player: int) -> String:
	return "cold_storage_stealth: contract %s, credits %d, anyone alerted %s, tick %d" % [
		SimAssembly.quests_of(sim).status_of(player, QUEST), SimAssembly.wallet_of(sim).balance_of(player), _alerted[0], sim.get_tick()]


## The route, as steps (see Plan); cells are the site's, from its placement.
func _route(sim: SimRoot, player: int) -> Array:
	var o: Vector3i = SimAssembly.sites_of(sim).placement_of(&"cold_storage")
	var site: Callable = func(x: int, y: int, z: int) -> Vector3i: return o + Vector3i(x, y, z)
	var items: ItemSystem = SimAssembly.items_of(sim)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var coprocessor: int = EntityIds.NONE
	for id: int in items.items_in(ItemSystem.inventory_of(player)):
		if items.item_template(id) == &"daemon_coprocessor":
			coprocessor = id
	var plan: Array = [
		["kit", &"item.attach", {"actor": player, "weapon": actors.device_of(player), "part": coprocessor}],
		["wait", 3],
		["goto", MARLOW],
		["use", "pz", QuestSystem.COMMAND_ACCEPT],
		["goto", Vector3i(14, 0, -4)],  # a row north of the utility box's
		["goto", site.call(-1, 0, -4)],
		["use", "pz", CorpseSystem.COMMAND_TAKE],
		["goto", site.call(1, 0, -4)],
		["goto", site.call(1, 0, -3)],
		["use", "pz", BuildSystem.COMMAND_OPEN],
		["wait", 30],
		["goto", site.call(4, -1, -3)],
		["goto", site.call(4, -1, -1)],
		["use", "pz", BuildSystem.COMMAND_OPEN],
		["goto", site.call(4, -1, 1)],
		["goto", site.call(3, -1, 1)],
		["goto", site.call(3, -1, 4)],
		["goto", site.call(7, -1, 4)],
	]
	var stretches: Array = [
		[  # up the two stairs into the maintenance room, beside its door
			["use", "pz", MovementSystem.COMMAND_CLIMB], ["settle"],
			["goto", site.call(9, 0, 5)],
			["use", "pz", MovementSystem.COMMAND_CLIMB], ["settle"],
			["goto", site.call(9, 1, 5)], ["goto", site.call(9, 1, 4)], ["goto", site.call(7, 1, 4)],
			["goto", site.call(7, 1, 3)], ["goto", site.call(5, 1, 3)],
		],
		[  # across the hall into the server room's corner no doorway sees
			["goto", site.call(7, 1, 3)], ["goto", site.call(7, 1, 4)], ["goto", site.call(5, 1, 4)],
			["goto", site.call(5, 1, 5)], ["goto", site.call(4, 1, 5)], ["goto", site.call(4, 1, 7)],
			["goto", site.call(2, 1, 7)],
		],
		[["hack"]],
		[  # back to the maintenance room
			["goto", site.call(4, 1, 7)], ["goto", site.call(4, 1, 5)], ["goto", site.call(5, 1, 5)],
			["goto", site.call(5, 1, 4)], ["goto", site.call(7, 1, 4)], ["goto", site.call(7, 1, 3)],
			["goto", site.call(5, 1, 3)],
		],
		[  # down both stairs
			["goto", site.call(7, 1, 3)], ["goto", site.call(7, 1, 4)], ["goto", site.call(9, 1, 4)],
			["goto", site.call(9, 1, 6)],
			["use", "pz", MovementSystem.COMMAND_CLIMB], ["settle"],
			["goto", site.call(7, 0, 5)],
			["use", "pz", MovementSystem.COMMAND_CLIMB], ["settle"],
		],
		[  # through the basement to the tunnel's hatch
			["goto", site.call(3, -1, 4)], ["goto", site.call(3, -1, 1)], ["goto", site.call(4, -1, 1)],
			["goto", site.call(4, -1, -3)], ["goto", site.call(2, -1, -3)],
		],
	]
	for stretch: Array in stretches:
		plan.append(["sneak", stretch])
		plan.append_array(stretch)
	plan.append_array([
		["use", "nx", MovementSystem.COMMAND_CLIMB], ["settle"],
		["goto", site.call(2, 0, -7)],
		["goto", Vector3i(14, 0, -7)],
		["goto", Vector3i(14, 0, -2)],
		["use", "nz", QuestSystem.COMMAND_DELIVER],
		["wait", 40],
	])
	return plan


## A list of steps run one a tick against a view: the game client (WorldView) or the
## look ahead's stand-in (Standin), which answer the same calls.
##   ["goto", cell]          the stick, one axis at a time (x first), to the cell centre
##   ["use", facing, kind]   face, then the context button, which must offer `kind`
##   ["settle"]              until the player can act again (after a climb)
##   ["hack"]                raise the device, open the hacking pane, start the first
##                           target; when done, log out and lower the device
##   ["kit", kind, payload]  a plain command (kit-up only)
##   ["wait", ticks]
##   ["sneak", steps]        wait until the steps look safe (see the file's head)
class Plan extends RefCounted:
	var steps: Array = []
	var step: int = 0
	var failure: String = ""
	var _started: int = -1
	var _phase: int = 0
	var _last_pos: Vector3i = Vector3i.ZERO
	var _still: int = 0

	func _init(p_steps: Array) -> void:
		steps = p_steps

	func done() -> bool:
		return step >= steps.size()

	func tick(view: Object) -> void:
		if done() or not failure.is_empty():
			return
		var sim: SimRoot = view.call("sim")
		if _started < 0:
			_started = sim.get_tick()
			_phase = 0
		var s: Array = steps[step]
		var action: String = s[0]
		var finished: bool = false
		match action:
			"goto":
				var cell: Vector3i = s[1]
				finished = _goto(view, cell)
			"use":
				var facing: String = s[1]
				var kind: StringName = s[2]
				finished = _use(view, facing, kind)
			"settle":
				var player: int = view.call("player")
				finished = sim.get_tick() - _started > 2 and SimAssembly.movement_of(sim).can_act(player)
			"hack":
				finished = _hack(view)
			"kit":
				view.call("submit", s[1], s[2])
				finished = true
			"wait":
				var n: int = s[1]
				finished = sim.get_tick() - _started >= n
			"sneak":
				var stretch: Array = s[1]
				finished = _sneak(view, stretch)
		if finished:
			step += 1
			_started = -1

	func _goto(view: Object, cell: Vector3i) -> bool:
		var sim: SimRoot = view.call("sim")
		var player: int = view.call("player")
		if not SimAssembly.movement_of(sim).can_act(player):
			return false
		var feet: Vector3i = BuildSystem.cell_centre(cell) - Vector3i(0, BuildSystem.CELL / 2, 0)
		var at: Vector3i = SimAssembly.actors_of(sim).position_of(player)
		var d: Vector3i = feet - at
		if absi(d.x) + absi(d.z) < 60:
			return true
		# a walk that stops moving is a bumped wall: say where, rather than wait forever
		_still = _still + 1 if at == _last_pos else 0
		_last_pos = at
		if _still > 40:
			failure = "step %d: stuck at %s walking to %s" % [step, BuildSystem.cell_of(at), cell]
			return false
		var speed: int = SimAssembly.movement_of(sim).speed_of(player)
		var along_x: bool = absi(d.x) >= 30
		var distance: int = absi(d.x) if along_x else absi(d.z)
		view.call("face", ("px" if d.x > 0 else "nx") if along_x else ("pz" if d.z > 0 else "nz"))
		view.call("stick", Vector2(0.0, -minf(1.0, float(distance) / float(speed))))
		return false

	func _use(view: Object, facing: String, kind: StringName) -> bool:
		var sim: SimRoot = view.call("sim")
		var player: int = view.call("player")
		if _phase == 0:
			if not SimAssembly.movement_of(sim).can_act(player):
				return false
			view.call("face", facing)
			var choice: Dictionary = Interact.choose(sim, player, facing)
			if choice.get("kind", &"") != kind:
				failure = "step %d: the button offers %s, not %s" % [step, str(choice.get("label", "nothing")), kind]
				return false
			view.call("press", "interact")
			_phase = 1
			return false
		return sim.get_tick() - _started > 2

	func _hack(view: Object) -> bool:
		var sim: SimRoot = view.call("sim")
		var player: int = view.call("player")
		var hacks: HackSystem = SimAssembly.hacks_of(sim)
		match _phase:
			0:
				view.call("press", "device")
				_phase = 1
			1:
				var app: StringName = view.call("open_app")
				if app == &"hacking":
					view.call("press", "device:device_select")
					_phase = 2
				else:
					view.call("press", "device:device_next_app")
			2:
				if not hacks.is_hacking(player) and not hacks.logins_of(player).is_empty():
					view.call("press", "device:device_select")
					_phase = 3
				elif not hacks.is_hacking(player) and sim.get_tick() - _started > 20:
					failure = "step %d: the hack stopped without completing" % step
			3:
				if hacks.logins_of(player).is_empty():
					view.call("press", "device")
					return true
		return false

	func _sneak(view: Object, stretch: Array) -> bool:
		var sim: SimRoot = view.call("sim")
		var waited: int = sim.get_tick() - _started
		if waited > PATIENCE:
			# as a player would in the end: go anyway, and let the counters say so
			print("PLAYTEST note: step %d found no safe moment in %d ticks; going anyway" % [step, PATIENCE])
			return true
		if waited % EVERY != 0:
			return false
		var player: int = view.call("player")
		var yaw: float = view.call("yaw")
		var raised: bool = view.call("device_raised")
		return Standin.safe(sim, player, yaw, raised, stretch)


## The look ahead's view: a copy of the sim restored from a snapshot, the same context
## button, a real DeviceShell with the same panes, and the stick turned into the move
## the client would make (WorldView.move_step), stepped one tick a call.
class Standin extends RefCounted:
	var _sim: SimRoot
	var _player: int
	var _yaw: float
	var _raised: bool
	var _input: Vector2 = Vector2.ZERO
	var _shell: DeviceShell

	static func safe(real: SimRoot, player: int, yaw: float, raised: bool, stretch: Array) -> bool:
		var content: ContentDb = real.get_system(&"content")
		var copy: SimRoot = SimAssembly.build(real.get_seed(), content)
		var snap: Dictionary = real.snapshot()
		if SimAssembly.restore_systems(copy, snap) != OK or copy.restore_root(snap) != OK:
			push_error("playtest: the look-ahead copy did not restore")
			return false
		var seen: Array[bool] = [false]
		var by: Array[int] = [0]
		SimAssembly.combat_of(copy).events().subscribe(PerceptionSystem.EVENT_ALERTED, func(p: Dictionary) -> void:
			if p["contact"] == player and not seen[0]:
				seen[0] = true
				by[0] = p["observer"])
		var standin := Standin.new(copy, player, yaw, raised)
		var plan := Plan.new(stretch.duplicate())
		var ticks: int = 0
		while not plan.done() and plan.failure.is_empty() and not seen[0] and ticks < 3000:
			standin.step(plan)
			ticks += 1
		var ok: bool = plan.done() and plan.failure.is_empty()
		for i: int in MARGIN:
			if seen[0]:
				break
			copy.step()
		standin.free_shell()
		if OS.has_environment("PLAYTEST_DEBUG"):
			var o: int = by[0]
			print("  look at %d: done %s, %s, seen %s at tick %d, player at %s, by %d (%s) at %s in %s" % [real.get_tick(), plan.done(), plan.failure, seen[0], copy.get_tick(),
				BuildSystem.cell_of(SimAssembly.actors_of(copy).position_of(player)), o, SimAssembly.actors_of(copy).profile_of(o) if o != 0 else &"",
				BuildSystem.cell_of(SimAssembly.actors_of(copy).position_of(o)) if o != 0 else Vector3i.ZERO, SimAssembly.stances_of(copy).stance_of(o) if o != 0 else &""])
		return ok and not seen[0]

	func _init(p_sim: SimRoot, p_player: int, p_yaw: float, p_raised: bool) -> void:
		_sim = p_sim
		_player = p_player
		_yaw = p_yaw
		_raised = p_raised
		_shell = DeviceShell.new()
		var content: ContentDb = p_sim.get_system(&"content")
		_shell.setup(content, _submit_now, InputGlyphs.new())
		for app: String in ["inventory", "map", "quests", "comms", "notes", "drone", "hacking"]:
			var scene: PackedScene = load("res://client/device/apps/%s_app.tscn" % app)
			_shell.register_view(StringName(app), scene)

	func free_shell() -> void:
		_shell.free()

	func step(plan: Plan) -> void:
		_input = Vector2.ZERO
		plan.tick(self)
		if not _raised and _input.length_squared() >= 0.01 and SimAssembly.actors_of(_sim).is_alive(_player):
			var m: Vector2i = WorldView.move_step(_yaw, _input, SimAssembly.movement_of(_sim).speed_of(_player))
			if m != Vector2i.ZERO:
				_submit_now(&"actor.move", {"actor": _player, "dx": m.x, "dz": m.y})
		_sim.step()

	func _submit_now(kind: StringName, payload: Dictionary) -> void:
		_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload))

	func sim() -> SimRoot:
		return _sim

	func player() -> int:
		return _player

	func yaw() -> float:
		return _yaw

	func face(facing: String) -> void:
		_yaw = WorldView.yaw_of(facing)

	func stick(input: Vector2) -> void:
		_input = input

	func device_raised() -> bool:
		return _raised

	func open_app() -> StringName:
		return _shell.open_app()

	func submit(kind: StringName, payload: Dictionary) -> void:
		_submit_now(kind, payload)

	func press(action: String) -> void:
		if action == "interact":
			var choice: Dictionary = Interact.choose(_sim, _player, WorldView.facing_of_yaw(_yaw))
			if not choice.is_empty():
				var kind: StringName = choice["kind"]
				var payload: Dictionary = choice["payload"]
				_submit_now(kind, payload)
		elif action == "device":
			_raised = not _raised
			_shell.refresh(_sim, _player)
		elif action.begins_with("device:"):
			_shell.refresh(_sim, _player)
			_shell.handle(StringName(action.trim_prefix("device:")), _sim, _player)
