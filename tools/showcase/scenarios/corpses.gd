## Showcase for M6 claim 16 (a death leaves a corpse). A guard on a private yard
## carries a pistol, a spare magazine and the Cold Storage keycard, and does not hold
## the pistol. You shoot him down. His body stays where he fell, holding everything he
## carried; you walk over and take the keycard and the pistol (the yard is not yours:
## the loot is recorded against you, and the take still happens), then drop your own
## spare magazine on the floor. Every label is read from the sim each frame.
extends RefCounted

const ORIGIN: Vector3i = Vector3i(500000, 0, 500000)

var _sim: SimRoot
var _you: int = 0
var _guard: int = 0
var _pistol: int = 0
var _spare: int = 0
var _step: int = 0
var _wait_until: int = 0
var _path: Array[Vector3i] = [Vector3i(7, 0, 2), Vector3i(7, 0, 3)]


func title() -> String:
	return "Gcity M6 claim 16: A BODY STAYS WHERE IT FELL (and its gear is loot)"


func content(db: ContentDb) -> void:
	var watchman: Dictionary = db.get_entry(&"agent_profile", &"guard_sim").duplicate(true)
	watchman["stances"] = [{"stance": "hold", "weight": 1000}]
	db.add(&"agent_profile", &"showcase_watchman", watchman)


func _feet(cx: int, cz: int) -> Vector3i:
	return ORIGIN + Vector3i(cx * 1000 + 500, 0, cz * 1000 + 500)


func setup(sim: SimRoot, view: Node3D) -> void:
	_sim = sim
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var x0: int = ORIGIN.x
	var z0: int = ORIGIN.z
	SimAssembly.land_of(sim).add_parcel(&"showcase_yard", &"starter_ghetto", &"corp", [[x0 + 5000, z0 - 2000], [x0 + 12000, z0 - 2000], [x0 + 12000, z0 + 6000], [x0 + 5000, z0 + 6000]], -1000, 3000)
	_you = actors.spawn(&"arcade", 0)
	actors.set_position(_you, _feet(0, 2))
	_guard = SimAssembly.perception_of(sim).spawn(&"showcase_watchman", BuildSystem.cell_of(_feet(8, 2)), 0, 1, "")
	var mine: String = String(ItemSystem.inventory_of(_you))
	var his: String = String(ItemSystem.inventory_of(_guard))
	for spec: Array in [["weapon_frame", "g19", mine, 1], ["weapon_part", "g19_mag_15", mine, 2], ["weapon_part", "g19_mag_15", mine, 3],
			["weapon_frame", "g19", his, 4], ["weapon_part", "g19_mag_15", his, 5], ["key_item", "cold_storage_keycard", his, 6]]:
		sim.submit(SimCommand.new(1, &"item.spawn", {"kind": spec[0], "template": spec[1], "container": spec[2], "seed": spec[3], "count": 1}))
	sim.submit(SimCommand.new(1, &"item.spawn", {"kind": "ammo", "template": "9x19_fmj", "container": mine, "seed": 7, "count": 15}))
	view.call("name_actor", _you, "You", true)
	view.call("name_actor", _guard, "Guard", false)
	var o: Vector3 = Vector3(ORIGIN) / 1000.0
	view.call("slab", o + Vector3(-2, -0.02, -2), Vector2(15, 8), Color(0.3, 0.32, 0.36))
	view.call("slab", o + Vector3(5, -0.01, -2), Vector2(7, 8), Color(0.55, 0.15, 0.15, 0.6))
	view.call("pin", "yard", o + Vector3(8.5, 0.2, 6.6), "PRIVATE YARD (owned by Corp)\nlooting here is a crime", Color(1.0, 0.6, 0.6))
	view.call("place_camera", o + Vector3(4, 13, -10), o + Vector3(5, 0, 2), 11.0)


func _go(sim: SimRoot, tick: int, kind: StringName, payload: Dictionary) -> void:
	sim.submit(SimCommand.new(tick, kind, payload))


func before_tick(sim: SimRoot, _view: Node3D, tick: int) -> void:
	var items: ItemSystem = SimAssembly.items_of(sim)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	if tick < _wait_until:
		return
	match _step:
		0:  # load the magazine and the pistol once the kit exists
			if tick < 3:
				return
			var mags: Array[int] = []
			var rounds: Array[int] = []
			for id: int in items.items_in(ItemSystem.inventory_of(_you)):
				var kind: StringName = items.item_kind(id)
				if kind == &"weapon_frame":
					_pistol = id
				elif kind == &"weapon_part":
					mags.append(id)
				else:
					rounds.append(id)
			_spare = mags[1]
			for r: int in rounds:
				_go(sim, tick, &"magazine.load", {"actor": _you, "magazine": mags[0], "round": r})
			_go(sim, tick + 1, &"actor.wield", {"actor": _you, "weapon": _pistol})
			_go(sim, tick + 1, &"weapon.reload_tactical", {"actor": _you, "weapon": _pistol, "magazine": mags[0]})
			_step = 1
			_wait_until = tick + 100
		1:  # fire until he is down
			if not actors.is_alive(_guard):
				_step = 2
				_wait_until = tick + 60
				return
			if not items.is_busy(_pistol, tick + 1):
				_go(sim, tick + 1, CombatSystem.COMMAND_FIRE, {"actor": _you, "target": _guard})
		2:  # walk to the body
			if _path.is_empty():
				_step = 3
				return
			var goal: Vector3i = _feet(_path[0].x, _path[0].z)
			var d: Vector3i = goal - actors.position_of(_you)
			if absi(d.x) + absi(d.z) < 60:
				_path.remove_at(0)
				return
			var speed: int = SimAssembly.movement_of(sim).speed_of(_you)
			var dx: int = clampi(d.x, -speed, speed)
			var dz: int = clampi(d.z, -speed, speed) if dx == 0 else 0
			_go(sim, tick, &"actor.move", {"actor": _you, "dx": dx, "dz": dz})
		3, 4:  # take the keycard, then the pistol
			var body: StringName = SimAssembly.corpses_of(sim).corpse_of(_guard)
			var want: StringName = &"key_item" if _step == 3 else &"weapon_frame"
			for id: int in items.items_in(body):
				if items.item_kind(id) == want:
					_go(sim, tick, CorpseSystem.COMMAND_TAKE, {"actor": _you, "from": String(body), "item": id})
					break
			_step += 1
			_wait_until = tick + 60
		5:  # drop your own spare magazine
			_go(sim, tick, CorpseSystem.COMMAND_DROP, {"actor": _you, "item": _spare})
			_step = 6
			_wait_until = tick + 60


func ticks_per_frame(_tick: int) -> int:
	return 4


func end_tick() -> int:
	return 900 if _step < 6 else _wait_until + 40


func caption(_tick: int) -> String:
	match _step:
		0, 1:
			return "A guard stands in a private yard with a pistol, a spare magazine and the Cold Storage keycard on him. You open fire."
		2:
			return "He is down. His body stays where he fell (dark red slab), and everything he carried is in it."
		3, 4:
			return "You take the keycard and his pistol. It is not your yard, so the looting is recorded against you; it still happens."
	return "You drop your own spare magazine: it lies on the floor in a pile anyone can pick up."
