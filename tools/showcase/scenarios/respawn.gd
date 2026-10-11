## Showcase for M6 claim 17 (respawn and the city's softening). You own the starter plot
## and carry a pistol, two magazines and some rounds, with 400 credits. On a docklands
## lot (law 500 of 1000) a guard shoots you down. Your body keeps your kit; the city then
## recovers some of it, each item by a coin flip weighted by the district's law (50 %
## here), for 100 credits each, until your money runs out. You wake up at home, whole,
## with your device. Every label is read from the sim each frame.
extends RefCounted

const LOT: Vector3i = Vector3i(2000, 0, -9000)

var _sim: SimRoot
var _you: int = 0
var _guard: int = 0
var _respawn_at: int = -1
var _caption_override: String = ""


func title() -> String:
	return "Gcity M6 claim 17: DEATH IS NOT THE END (the body, the city, home)"


func content(db: ContentDb) -> void:
	var shooter: Dictionary = db.get_entry(&"agent_profile", &"guard_sim").duplicate(true)
	shooter["stances"] = [{"stance": "hold", "weight": 1000}]
	db.add(&"agent_profile", &"showcase_shooter", shooter)


func setup(sim: SimRoot, view: Node3D) -> void:
	_sim = sim
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	SimAssembly.land_of(sim).add_parcel(&"showcase_lot", &"docklands", &"corp", [[0, -12000], [9000, -12000], [9000, -3000], [0, -3000]], -1000, 3000)
	_you = actors.spawn(&"arcade", 0)
	actors.set_position(_you, LOT)
	sim.submit(SimCommand.new(1, &"land.identify", {"actor": _you, "owner": "player"}))
	sim.submit(SimCommand.new(1, &"land.transfer", {"parcel": "starter_plot", "owner": "player"}))
	var mine: String = String(ItemSystem.inventory_of(_you))
	for spec: Array in [["device_frame", "handset", 1], ["weapon_frame", "g19", 2], ["weapon_part", "g19_mag_15", 3], ["weapon_part", "g19_mag_15", 4]]:
		sim.submit(SimCommand.new(1, &"item.spawn", {"kind": spec[0], "template": spec[1], "container": mine, "seed": spec[2], "count": 1}))
	sim.submit(SimCommand.new(1, &"item.spawn", {"kind": "ammo", "template": "9x19_fmj", "container": mine, "seed": 5, "count": 4}))
	_guard = SimAssembly.perception_of(sim).spawn(&"showcase_shooter", BuildSystem.cell_of(LOT + Vector3i(4000, 0, 0)), 180, 1, "")
	var his: String = String(ItemSystem.inventory_of(_guard))
	sim.submit(SimCommand.new(1, &"item.spawn", {"kind": "weapon_frame", "template": "g19", "container": his, "seed": 11, "count": 1}))
	sim.submit(SimCommand.new(1, &"item.spawn", {"kind": "weapon_part", "template": "g19_mag_15", "container": his, "seed": 12, "count": 1}))
	sim.submit(SimCommand.new(1, &"item.spawn", {"kind": "ammo", "template": "9x19_fmj", "container": his, "seed": 13, "count": 15}))
	view.call("name_actor", _you, "You", true)
	view.call("name_actor", _guard, "Guard", false)
	var wallet: WalletSystem = SimAssembly.wallet_of(sim)
	wallet.register_source(&"showcase.savings")
	wallet.credit(_you, 400, &"showcase.savings")
	view.call("slab", Vector3(0, -0.03, -12), Vector2(12.2, 24.2), Color(0.3, 0.32, 0.36))
	view.call("slab", Vector3(0, -0.02, 0), Vector2(12.192, 12.192), Color(0.2, 0.45, 0.25, 0.7))
	view.call("slab", Vector3(0, -0.02, -12), Vector2(9, 9), Color(0.55, 0.15, 0.15, 0.6))
	view.call("pin", "home", Vector3(6, 0.2, 11.5), "YOUR HOME: the starter plot (law 250)", Color(0.6, 1.0, 0.6))
	view.call("pin", "lot", Vector3(4.5, 0.2, -12.4), "DOCKLANDS LOT (law 500 of 1000)", Color(1.0, 0.6, 0.6))
	view.call("place_camera", Vector3(-9, 22, -16), Vector3(4, 0, -3), 17.0)


func before_tick(sim: SimRoot, view: Node3D, tick: int) -> void:
	var items: ItemSystem = SimAssembly.items_of(sim)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	if tick == 3:
		# arm the guard: load his magazine, wield, reload
		var frame: int = 0
		var mag: int = 0
		var rounds: Array[int] = []
		for id: int in items.items_in(ItemSystem.inventory_of(_guard)):
			var kind: StringName = items.item_kind(id)
			if kind == &"weapon_frame":
				frame = id
			elif kind == &"weapon_part":
				mag = id
			else:
				rounds.append(id)
		for r: int in rounds:
			sim.submit(SimCommand.new(tick, &"magazine.load", {"actor": _guard, "magazine": mag, "round": r}))
		sim.submit(SimCommand.new(tick + 1, &"actor.wield", {"actor": _guard, "weapon": frame}))
		sim.submit(SimCommand.new(tick + 1, &"weapon.reload_tactical", {"actor": _guard, "weapon": frame, "magazine": mag}))
		for id: int in items.items_in(ItemSystem.inventory_of(_you)):
			if items.item_kind(id) == &"device_frame":
				sim.submit(SimCommand.new(tick + 1, &"actor.equip_device", {"actor": _you, "device": id}))
	if _respawn_at < 0 and tick > 10 and not actors.is_alive(_you):
		_respawn_at = tick + 120
	if tick == _respawn_at:
		sim.submit(SimCommand.new(tick, ActorSystem.COMMAND_RESPAWN, {"actor": _you}))
	# what you have, what the body has, what home has, and your money
	var wallet: WalletSystem = SimAssembly.wallet_of(sim)
	var feet: Vector3 = Vector3(actors.position_of(_you)) / 1000.0
	view.call("pin", "you", feet + Vector3(0, 3.9, 0), "carrying: %s\ncredits: %d" % [_list(items, ItemSystem.inventory_of(_you)), wallet.balance_of(_you)], Color(0.7, 0.85, 1.0))
	view.call("pin", "base", Vector3(7, 0.3, 4), "YOUR BASE holds: %s" % _list(items, ItemSystem.base_of(_you)), Color(0.75, 1.0, 0.75))


func _list(items: ItemSystem, container: StringName) -> String:
	var names: PackedStringArray = PackedStringArray()
	for id: int in items.items_in(container):
		names.append(String(items.item_template(id)))
	return "nothing" if names.is_empty() else ", ".join(names)


func ticks_per_frame(_tick: int) -> int:
	return 4


func end_tick() -> int:
	return 1200 if _respawn_at < 0 else _respawn_at + 120


func caption(tick: int) -> String:
	var actors: ActorSystem = SimAssembly.actors_of(_sim)
	if _respawn_at < 0:
		return "You are on a docklands lot with your kit and 400 credits. A guard opens fire."
	if tick < _respawn_at:
		return "You are down. Your body keeps your kit. The docklands has some law (500 of 1000), so the city recovers each item with a 50 % chance, at 100 credits each."
	return "You wake up at home, whole, still carrying your device. What the city recovered waits in your base; the rest is still on your body at the docks." if actors.is_alive(_you) else ""
