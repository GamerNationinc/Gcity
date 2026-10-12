## The step runner the playtest bots share (tools/playtest/*.gd), and the look ahead's
## stand-in view. Not a bot itself: tools/test.sh runs only tools/playtest/*.gd.
## A list of steps run one a tick against a view: the game client (WorldView) or the
## look ahead's stand-in (Standin), which answer the same calls.
##   ["goto", cell]          the stick, one axis at a time (x first), to the cell centre
##   ["use", facing, kind]   face, then the context button, which must offer `kind`
##   ["settle"]              until the player can act again (after a climb)
##   ["hack"]                raise the device, open the hacking pane, start the first
##                           target; when done, log out and lower the device
##   ["hack_in"] / ["logout"] the two halves: hack and stay logged in; log out
##   ["cut"]                 until the cut the button started is done
##   ["wield", template]     kit-up: wield a carried item
##   ["kit", kind, payload]  a plain command (kit-up only)
##   ["wait", ticks]
##   ["sneak", steps]        wait until the steps look safe (see the file's head)
class_name PlaytestPlan extends RefCounted

const EVERY: int = 10
const PATIENCE: int = 2400
const MARGIN: int = 420

var steps: Array = []
var step: int = 0
var failure: String = ""
var _started: int = -1
var _phase: int = 0
## the hack step: the logins held while it ran, and whether it ran
var _held: int = 0
var _ran: bool = false
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
		_held = 0
		_ran = false
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
		"cut":
			var cutter: int = view.call("player")
			finished = sim.get_tick() - _started > 2 and not SimAssembly.build_of(sim).is_breaching(cutter) \
				and SimAssembly.movement_of(sim).can_act(cutter)
		"settle":
			var player: int = view.call("player")
			finished = sim.get_tick() - _started > 2 and SimAssembly.movement_of(sim).can_act(player)
		"hack":
			finished = _hack(view)
		"hack_in":
			finished = _hack_in(view)
		"logout":
			finished = _logout(view)
		"wield":
			var template: StringName = s[1]
			finished = _wield(view, template)
		"kit":
			view.call("submit", s[1], s[2])
			finished = true
		"wait":
			var n: int = s[1]
			finished = sim.get_tick() - _started >= n
		"sneak":
			var stretch: Array = s[1]
			finished = _sneak(view, stretch)
		_:
			failure = "step %d: no such step '%s'" % [step, action]
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
			if hacks.is_hacking(player):
				_ran = true
				_held = hacks.logins_of(player).size()
			elif _ran and hacks.logins_of(player).size() > _held:
				# done, one login more: log out of it (the pane's first row is the
				# lowest id; the terminal's is lower than the junction box's)
				view.call("press", "device:device_select")
				_phase = 3
			elif _ran:
				failure = "step %d: the hack was interrupted" % step
			elif sim.get_tick() - _started > 20:
				failure = "step %d: the hack never started" % step
		3:
			if hacks.logins_of(player).size() <= _held:
				view.call("press", "device")
				return true
	return false

## Raise the device, open the hacking pane, start the first target listed and, once
## it is done (logged in, holding its effect), lower the device.
func _hack_in(view: Object) -> bool:
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
				view.call("press", "device")
				return true
			elif not hacks.is_hacking(player) and sim.get_tick() - _started > 20:
				failure = "step %d: the hack stopped without completing" % step
	return false


## Raise the device, open the hacking pane and log out of the first target listed (the
## one held), then lower the device.
func _logout(view: Object) -> bool:
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
			if hacks.logins_of(player).is_empty():
				view.call("press", "device")
				return true
			if sim.get_tick() - _started > 40:
				failure = "step %d: the logout did not take" % step
	return false


## Kit-up: wield the carried item of `template` (a plain command).
func _wield(view: Object, template: StringName) -> bool:
	var sim: SimRoot = view.call("sim")
	var player: int = view.call("player")
	var items: ItemSystem = SimAssembly.items_of(sim)
	for id: int in items.items_in(ItemSystem.inventory_of(player)):
		if items.item_template(id) == template:
			view.call("submit", &"actor.wield", {"actor": player, "weapon": id})
			return true
	failure = "step %d: no %s carried" % [step, template]
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
		var plan := PlaytestPlan.new(stretch.duplicate())
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

	func step(plan: PlaytestPlan) -> void:
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
