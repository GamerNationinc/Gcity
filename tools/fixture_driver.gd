## Drives one actor through a plan of steps against a live sim and records every
## command it submits with its tick, so the run can be written as a replay fixture
## (M6 spec claim 20). Each step reads the sim and submits at most a few commands per
## tick; a step that the sim refuses, or that does not finish within its patience, is
## reported and the plan stops: a fixture never records a run that silently failed.
##
## Steps (an Array each, first element the action):
##   ["wait", ticks]
##   ["walk", [cells...]]            cell centres in order, one axis at a time
##   ["breach", piece]               cut a piece with the wielded tool, until it is gone
##   ["climb", piece]                use a ladder or stairs piece
##   ["open", piece]
##   ["take", place, item]           item.take; `place` a StringName, `item` an id
##   ["hack", target] / ["logout", target]
##   ["deliver", quest] / ["accept", quest]
##   ["wield", item] / ["equip", device] / ["attach", device, module]
##   ["respawn"]
##   ["call", Callable]              runs Callable(driver) -> bool once a tick until true
extends RefCounted

const PATIENCE: int = 2400

var sim: SimRoot
var actor: int = 0
var commands: Array = []
var failure: String = ""
var _plan: Array = []
var _step: int = 0
var _issued: bool = false
var _started: int = 0
var _waypoint: int = 0
var _rejected_before: int = 0


func _init(p_sim: SimRoot, p_actor: int) -> void:
	sim = p_sim
	actor = p_actor


## Submits a command for the next tick and records it.
func submit(kind: StringName, payload: Dictionary) -> void:
	var tick: int = sim.get_tick() + 1
	commands.append({"tick": tick, "kind": String(kind), "payload": payload})
	var err: Error = sim.submit(SimCommand.new(tick, kind, payload))
	assert(err == OK, "the next tick is never late")


## Runs the plan to its end (or to a failure), stepping the sim. True when every step
## finished.
func run(plan: Array) -> bool:
	_plan = plan
	_step = 0
	_issued = false
	while _step < _plan.size() and failure.is_empty():
		_tick()
		sim.step()
	return failure.is_empty()


func _tick() -> void:
	var step: Array = _plan[_step]
	var action: String = step[0]
	if not _issued:
		_issued = true
		_started = sim.get_tick()
		_waypoint = 0
		_rejected_before = sim.rejected_count()
		_issue(action, step)
		return
	if sim.rejected_count() > _rejected_before and action != "walk":
		failure = "step %d (%s) was refused at tick %d" % [_step, action, sim.get_tick()]
		return
	if _done(action, step):
		_step += 1
		_issued = false
	elif sim.get_tick() - _started > PATIENCE:
		failure = "step %d (%s) did not finish in %d ticks" % [_step, action, PATIENCE]


func _issue(action: String, step: Array) -> void:
	match action:
		"breach":
			submit(&"build.breach", {"actor": actor, "piece": step[1]})
		"climb":
			submit(&"actor.climb", {"actor": actor, "piece": step[1]})
		"open":
			submit(&"opening.open", {"actor": actor, "piece": step[1]})
		"take":
			var place: StringName = step[1]
			submit(CorpseSystem.COMMAND_TAKE, {"actor": actor, "from": String(place), "item": step[2]})
		"hack":
			submit(&"hack.start", {"actor": actor, "target": step[1]})
		"logout":
			submit(&"hack.logout", {"actor": actor, "target": step[1]})
		"deliver":
			var delivered: StringName = step[1]
			submit(&"contract.deliver", {"actor": actor, "quest": String(delivered)})
		"accept":
			var accepted: StringName = step[1]
			submit(&"quest.accept", {"actor": actor, "quest": String(accepted)})
		"wield":
			submit(&"actor.wield", {"actor": actor, "weapon": step[1]})
		"equip":
			submit(&"actor.equip_device", {"actor": actor, "device": step[1]})
		"attach":
			submit(&"item.attach", {"actor": actor, "weapon": step[1], "part": step[2]})
		"respawn":
			submit(ActorSystem.COMMAND_RESPAWN, {"actor": actor})


func _done(action: String, step: Array) -> bool:
	var settled: bool = sim.get_tick() - _started > 2 and SimAssembly.movement_of(sim).can_act(actor)
	match action:
		"wait":
			var n: int = step[1]
			return sim.get_tick() - _started >= n
		"walk":
			var cells: Array = step[1]
			return _walk(cells)
		"breach":
			var piece: int = step[1]
			return settled and not SimAssembly.build_of(sim).is_breaching(actor) and not SimAssembly.build_of(sim).has_piece(piece)
		"hack":
			return sim.get_tick() - _started > 2 and not SimAssembly.hacks_of(sim).is_hacking(actor)
		"call":
			var f: Callable = step[1]
			return f.call(self)
	return settled


func _walk(cells: Array) -> bool:
	if not SimAssembly.movement_of(sim).can_act(actor):
		return false
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	while _waypoint < cells.size():
		var cell: Vector3i = cells[_waypoint]
		var feet: Vector3i = BuildSystem.cell_centre(cell) - Vector3i(0, BuildSystem.CELL / 2, 0)
		var d: Vector3i = feet - actors.position_of(actor)
		if absi(d.x) + absi(d.z) < 60:
			_waypoint += 1
			continue
		var speed: int = SimAssembly.movement_of(sim).speed_of(actor)
		var dx: int = clampi(d.x, -speed, speed)
		var dz: int = clampi(d.z, -speed, speed) if dx == 0 else 0
		submit(&"actor.move", {"actor": actor, "dx": dx, "dz": dz})
		return false
	return true


## The fixture dictionary for these commands, `tail` ticks past the last.
func fixture(name: String, seed: int, tail: int) -> Dictionary:
	return {"schema_version": 1, "name": name, "seed": seed, "ticks": sim.get_tick() + tail, "commands": commands, "expected_hash": ""}
