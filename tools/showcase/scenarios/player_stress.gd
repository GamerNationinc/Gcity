## Showcase for M6 claim 18: the player has a stress profile, like any guard. A
## shooter fires four real rounds: two at a board just behind You (near misses), two
## at You. Each shot raises your stress; your own pistol's chance to hit, read from
## the sim's stat resolver every frame, drops with it; then you calm down and it comes
## back. Nothing here is drawn from the scenario's own numbers: the label above You is
## StressSystem.stress_of and CombatSystem.hit_chance_at.
extends RefCounted

const ORIGIN: Vector3i = Vector3i(500000, 0, 500000)
## [tick, target name]
const SHOTS: Array = [[120, "board"], [160, "board"], [200, "you"], [240, "you"]]

var _sim: SimRoot
var _view: Node3D
var _you: int = 0
var _shooter: int = 0
var _board: int = 0
var _your_pistol: int = 0
var _shooter_pistol: int = 0


func title() -> String:
	return "Gcity M6 claim 18: YOUR NERVES (stress spoils your aim)"


func content(_db: ContentDb) -> void:
	pass


func _feet(cx: int, cz: int) -> Vector3i:
	return ORIGIN + Vector3i(cx * 1000 + 500, 0, cz * 1000 + 500)


func setup(sim: SimRoot, view: Node3D) -> void:
	_sim = sim
	_view = view
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	_you = actors.spawn(&"arcade", 10)
	_shooter = actors.spawn(&"arcade", 0)
	_board = actors.spawn(&"range_dummy", 14)
	actors.set_position(_shooter, _feet(0, 0))
	actors.set_position(_you, _feet(10, 0))
	actors.set_position(_board, _feet(14, 1))
	var you_inv: String = String(ItemSystem.inventory_of(_you))
	var shooter_inv: String = String(ItemSystem.inventory_of(_shooter))
	sim.submit(SimCommand.new(1, &"item.spawn", {"kind": "weapon_frame", "template": "g19", "container": you_inv, "seed": 1, "count": 1}))
	sim.submit(SimCommand.new(1, &"item.spawn", {"kind": "weapon_frame", "template": "g19", "container": shooter_inv, "seed": 2, "count": 1}))
	sim.submit(SimCommand.new(1, &"item.spawn", {"kind": "weapon_part", "template": "g19_mag_15", "container": shooter_inv, "seed": 3, "count": 1}))
	sim.submit(SimCommand.new(1, &"item.spawn", {"kind": "ammo", "template": "9x19_fmj", "container": shooter_inv, "seed": 4, "count": 4}))
	view.call("name_actor", _you, "You", true)
	view.call("name_actor", _shooter, "Shooter", false)
	view.call("name_actor", _board, "Target board", false)
	var bus: EventBus = SimAssembly.combat_of(sim).events()
	bus.subscribe(CombatSystem.EVENT_FIRE, _on_fire)
	bus.subscribe(CombatSystem.EVENT_HIT, _on_hit)
	var o: Vector3 = Vector3(ORIGIN) / 1000.0
	view.call("slab", o + Vector3(-2, -0.02, -3), Vector2(19, 7), Color(0.3, 0.32, 0.36))
	view.call("place_camera", o + Vector3(7, 14, -12), o + Vector3(8, 0, 0.5), 13.0)


func _on_fire(p: Dictionary) -> void:
	var target: int = p["target"]
	if target == _you:
		_view.call("note", "Shooter fired at You", 1)
	else:
		_view.call("note", "Shooter fired at the board behind You: a near miss for You", 1)


func _on_hit(p: Dictionary) -> void:
	var target: int = p["target"]
	if target == _you:
		_view.call("note", "  ...and HIT You", 2)


func before_tick(sim: SimRoot, view: Node3D, tick: int) -> void:
	var items: ItemSystem = SimAssembly.items_of(sim)
	if tick == 3:
		for id: int in items.items_in(ItemSystem.inventory_of(_you)):
			_your_pistol = id
		var mag: int = 0
		var rounds: Array[int] = []
		for id: int in items.items_in(ItemSystem.inventory_of(_shooter)):
			var kind: StringName = items.item_kind(id)
			if kind == &"weapon_frame":
				_shooter_pistol = id
			elif kind == &"weapon_part":
				mag = id
			else:
				rounds.append(id)
		for r: int in rounds:
			sim.submit(SimCommand.new(tick, &"magazine.load", {"actor": _shooter, "magazine": mag, "round": r}))
		sim.submit(SimCommand.new(tick + 1, &"actor.wield", {"actor": _you, "weapon": _your_pistol}))
		sim.submit(SimCommand.new(tick + 1, &"actor.wield", {"actor": _shooter, "weapon": _shooter_pistol}))
		sim.submit(SimCommand.new(tick + 1, &"weapon.reload_tactical", {"actor": _shooter, "weapon": _shooter_pistol, "magazine": mag}))
	for shot: Array in SHOTS:
		var at: int = shot[0]
		if tick == at:
			var who: String = shot[1]
			sim.submit(SimCommand.new(tick, CombatSystem.COMMAND_FIRE, {"actor": _shooter, "target": _you if who == "you" else _board}))
	if _your_pistol == 0:
		return
	var stress: int = SimAssembly.stress_of(sim).stress_of(_you)
	var chance: int = SimAssembly.combat_of(sim).hit_chance_at(_you, _your_pistol, 10)
	var health: Dictionary = SimAssembly.actors_of(sim).health_of(_you)
	var hp: int = health.get(&"body", 0)
	var colour: Color = Color(0.5, 0.9, 0.5) if stress == 0 else (Color(1.0, 0.75, 0.3) if stress < 300000 else Color(1.0, 0.4, 0.35))
	var feet: Vector3 = Vector3(SimAssembly.actors_of(sim).position_of(_you)) / 1000.0
	view.call("pin", "you", feet + Vector3(0, 3.9, 0), "YOUR STRESS %d %%\nyour chance to hit at 10 m: %d %%\nhealth %d %%" % [stress / 10000, chance / 10000, hp / 1000], colour)


func ticks_per_frame(tick: int) -> int:
	return 4 if tick < 300 else 8


func end_tick() -> int:
	return 700


func caption(tick: int) -> String:
	if tick < 110:
		return "You stand on a range with a pistol: calm, a 60 % chance to hit a target 10 m away. The Shooter has four rounds."
	if tick < 190:
		return "Two shots at the board just behind you: they pass within 1.5 m of you. Near misses rattle you: stress up, your aim worse."
	if tick < 280:
		return "Two shots at you. Every shot at you rattles you, hit or miss (a hit would rattle you twice as much). Your chance to hit drops further."
	return "The shooting stops and you calm down: stress drains away in a few seconds and your aim comes back to 60 %. Guards work the same way."
