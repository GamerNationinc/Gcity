## A Cold Storage job bot's common part (CLAUDE.md §8: the cloud plays first): played
## through the real client, `world_view.tscn -- --playtest=<bot>` (tools/playtest.sh).
## A bot extends this and gives its route (_route) and name (_name). Every move is the view's own stick
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
const LIMIT: int = 20000

var _plan: PlaytestPlan = null
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
		_plan = PlaytestPlan.new(_route(sim, player))
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
	return "%s: contract %s, credits %d, anyone alerted %s, tick %d" % [_name(),
		SimAssembly.quests_of(sim).status_of(player, QUEST), SimAssembly.wallet_of(sim).balance_of(player), _alerted[0], sim.get_tick()]


## The bot's route, as PlaytestPlan steps.
func _route(_sim: SimRoot, _player: int) -> Array:
	assert(false, "a job bot gives its route")
	return []


func _name() -> String:
	return "job"
