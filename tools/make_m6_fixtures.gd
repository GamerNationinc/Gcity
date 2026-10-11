## Writes the M6 replay fixtures (spec claim 20) into tests/replay/. Each runs a live sim
## while a FixtureDriver plays a plan, so ids in later commands come from the sim itself;
## a plan that fails is reported and nothing is written for it.
##   godot --headless --path . -s tools/make_m6_fixtures.gd [-- name ...]
## Then `tools/test.sh replay` (or tools/rerecord) gives each hash for "expected_hash".
extends SceneTree

const Driver: GDScript = preload("res://tools/fixture_driver.gd")
const OUT_DIR: String = "res://tests/replay"
const SEED: int = 20261200
const SITE: Vector3i = Vector3i(40, 0, 0)
const QUEST: StringName = &"cold_storage_contract"

var _sim: SimRoot
var _db: ContentDb
var _player: int = 0
var _drive: RefCounted


## `name=value` arguments: plan parameters (the stealth plan's waits), and `probe`,
## which reports the first time a guard is alerted to the player instead of writing.
var _params: Dictionary = {}
var _probe: bool = false
var _first_alert: int = -1
var _alert_where: Vector3i = Vector3i.ZERO


func _param(name: String, default: int) -> int:
	return _params.get(name, default)


func _initialize() -> void:
	var only: PackedStringArray = PackedStringArray()
	for arg: String in OS.get_cmdline_user_args():
		if arg == "probe":
			_probe = true
		elif arg.contains("="):
			var kv: PackedStringArray = arg.split("=")
			_params[kv[0]] = kv[1].to_int()
		else:
			only.append(arg)
	var all: Dictionary = {"m6-front": _front, "m6-side": _side, "m6-front-hot": _front_hot, "m6-hack-interrupt": _hack_interrupt, "m6-death": _death, "m6-city-death": _city_death, "m6-loud": _loud, "m6-fall": _fall, "m6-stealth": _stealth}
	var failed: int = 0
	for name: String in all:
		if not only.is_empty() and not only.has(name):
			continue
		var plan_of: Callable = all[name]
		if not _write(name, plan_of):
			failed += 1
	quit(1 if failed > 0 else 0)


func _write(name: String, plan_of: Callable) -> bool:
	var db := ContentDb.new()
	var err: Error = ContentLoader.load_all(db)
	assert(err == OK, "content")
	_sim = SimAssembly.build(SEED, db)
	_db = db
	_drive = Driver.new(_sim, 1)
	# the player: actor 1, on the street by Marlow
	_drive.call("submit", &"actor.spawn", {"profile": "arcade", "range_m": 14})
	_sim.step()
	_player = SimAssembly.actors_of(_sim).actor_ids()[0]
	var plan: Array = plan_of.call()
	_first_alert = -1
	SimAssembly.combat_of(_sim).events().subscribe(PerceptionSystem.EVENT_ALERTED, func(p: Dictionary) -> void:
		if p["contact"] == _player and _first_alert < 0:
			_first_alert = _sim.get_tick()
			_alert_where = BuildSystem.cell_of(SimAssembly.actors_of(_sim).position_of(_player)) - SITE)
	var ok: bool = _drive.call("run", plan)
	if _probe:
		print("PROBE %s ok=%s first_alert=%d at %s end=%d" % [name, ok, _first_alert, _alert_where, _sim.get_tick()])
		return ok
	if not ok:
		print("FAILED %s: %s (player at %s)" % [name, _drive.get("failure"), BuildSystem.cell_of(SimAssembly.actors_of(_sim).position_of(_player))])
		print("  last shot: %s" % str(SimAssembly.combat_of(_sim).snapshot().get("last")))
		var a: ActorSystem = SimAssembly.actors_of(_sim)
		if a.has_actor(_shooter):
			var items: ItemSystem = SimAssembly.items_of(_sim)
			print("  shooter alive %s at %s wields %d, inventory %s, mag holds %d, chambered %d" % [a.is_alive(_shooter), BuildSystem.cell_of(a.position_of(_shooter)), a.wielded(_shooter),
				str(items.items_in(ItemSystem.inventory_of(_shooter))), items.rounds_in(_shooter_mag()).size() if _shooter_mag() != 0 else -1, items.chambered(_shooter_frame()) if _shooter_frame() != 0 else -1])
		var here: Vector3i = BuildSystem.cell_of(SimAssembly.actors_of(_sim).position_of(_player))
		var b: BuildSystem = SimAssembly.build_of(_sim)
		var east: int = b.cell_piece_at(here + Vector3i(1, 0, 0))
		print("  east of the player: piece %d %s, pieces placed %d, can act %s" % [east, b.template_of(east) if east != 0 else &"", b.piece_ids().size(), SimAssembly.movement_of(_sim).can_act(_player)])
		var cmds: Array = _drive.get("commands")
		for c: Variant in cmds.slice(maxi(0, cmds.size() - 6)):
			print("  ", c)
		return false
	var fixture: Dictionary = _drive.call("fixture", name, SEED, 40)
	var file: FileAccess = FileAccess.open("%s/%s.json" % [OUT_DIR, name], FileAccess.WRITE)
	file.store_string(JSON.stringify(fixture, "\t") + "\n")
	file.close()
	var commands: Array = fixture["commands"]
	print("wrote %s: %d commands, %d ticks" % [name, commands.size(), fixture["ticks"]])
	return true


func _site(c: Vector3i) -> Vector3i:
	return SITE + c


## The item the sim gave the player of `template`, once spawned.
func _carried(template: StringName) -> int:
	var items: ItemSystem = SimAssembly.items_of(_sim)
	for id: int in items.items_in(ItemSystem.inventory_of(_player)):
		if items.item_template(id) == template:
			return id
	return EntityIds.NONE


## Kit, through commands: a plasma cutter in hand, and a handset with a daemon
## coprocessor carried as the device.
func _kit() -> Array:
	var inv: String = String(ItemSystem.inventory_of(_player))
	var plan: Array = []
	for spec: Array in [["tool", "plasma_cutter", 1], ["device_frame", "handset", 2], ["device_module", "daemon_coprocessor", 3]]:
		plan.append(["call", func(d: RefCounted) -> bool:
			d.call("submit", &"item.spawn", {"kind": spec[0], "template": spec[1], "container": inv, "seed": spec[2], "count": 1})
			return true])
	plan.append(["wait", 2])
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"actor.wield", {"actor": _player, "weapon": _carried(&"plasma_cutter")})
		d.call("submit", &"actor.equip_device", {"actor": _player, "device": _carried(&"handset")})
		return true])
	plan.append(["wait", 2])
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"item.attach", {"actor": _player, "weapon": _carried(&"handset"), "part": _carried(&"daemon_coprocessor")})
		return true])
	plan.append(["wait", 2])
	return plan


## The site's hack target of `kind`.
func _target(kind: StringName) -> int:
	var hacks: HackSystem = SimAssembly.hacks_of(_sim)
	var targets: Dictionary = hacks.snapshot()["targets"]
	for t: int in SimAssembly.sites_of(_sim).targets_of(&"cold_storage"):
		var rec: Dictionary = targets[t]
		if rec["target"] == kind:
			return t
	return EntityIds.NONE


func _accept() -> Array:
	return [
		["walk", [Vector3i(14, 0, -2)]],
		["accept", QUEST],
	]


# ---------------------------------------------------------------- m6-front

## The front route: take the keycard from the yard crate, walk round to the front
## door and open it with the card while heat is low: the door opens and no alarm.
func _front() -> Array:
	var plan: Array = _accept()
	plan.append(["walk", [Vector3i(14, 0, -6), _site(Vector3i(11, 0, -6)), _site(Vector3i(11, 0, 1))]])
	plan.append(["call", _take_card])
	plan.append(["walk", [_site(Vector3i(11, 0, -6)), _site(Vector3i(2, 0, -6)), _site(Vector3i(2, 0, -1))]])
	plan.append(["call", _open_front_door])
	plan.append(["wait", 40])
	return plan


func _take_card(d: RefCounted) -> bool:
	var crate: StringName = SimAssembly.sites_of(_sim).crates_of(&"cold_storage")[0]
	var held: Array[int] = SimAssembly.items_of(_sim).items_in(crate)
	if held.is_empty():
		return _carried(&"cold_storage_keycard") != EntityIds.NONE
	d.call("submit", CorpseSystem.COMMAND_TAKE, {"actor": _player, "from": String(crate), "item": held[0]})
	return false


func _front_door() -> int:
	return SimAssembly.build_of(_sim).face_piece_at(BuildSystem.face_key(_site(Vector3i(2, 0, 0)), "nz"))


func _open_front_door(d: RefCounted) -> bool:
	if SimAssembly.build_of(_sim).is_open(_front_door()):
		return true
	d.call("submit", &"opening.open", {"actor": _player, "piece": _front_door()})
	return false


# ---------------------------------------------------------------- m6-side

## The side route: spoof the window's power monitor from its junction box in the yard,
## mantle onto the crate under the window, cut the window and step in: no alarm.
func _side() -> Array:
	var plan: Array = _kit()
	plan.append_array(_accept())
	plan.append(["walk", [Vector3i(14, 0, -6), _site(Vector3i(11, 0, -6)), _site(Vector3i(11, 0, 1))]])
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"hack.start", {"actor": _player, "target": _target(&"power_monitor_spoof")})
		return true])
	plan.append(["wait", 3])
	plan.append(["call", func(_d: RefCounted) -> bool: return not SimAssembly.hacks_of(_sim).is_hacking(_player)])
	plan.append(["mantle", -1, 0])
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"build.breach", {"actor": _player, "piece": _side_window()})
		return true])
	plan.append(["wait", 3])
	plan.append(["call", func(_d: RefCounted) -> bool: return not SimAssembly.build_of(_sim).is_breaching(_player)])
	plan.append(["walk", [_site(Vector3i(9, 1, 1))]])
	plan.append(["wait", 40])
	return plan


func _side_window() -> int:
	return SimAssembly.build_of(_sim).face_piece_at(BuildSystem.face_key(_site(Vector3i(9, 1, 1)), "px"))


# ---------------------------------------------------------------- m6-front-hot

## Hot at the front door: take the keycard from the yard crate, then cut the side
## window without spoofing its monitor (an alarm, and the guards it calls see a
## trespasser), drop back into the yard, walk round and open the front door with the
## card while heat is over the door's 300: the door opens, and the lobby camera
## raises the alarm.
func _front_hot() -> Array:
	var plan: Array = _kit()
	plan.append_array(_accept())
	plan.append(["walk", [Vector3i(14, 0, -6), _site(Vector3i(11, 0, -6)), _site(Vector3i(11, 0, 1))]])
	plan.append(["call", _take_card])
	plan.append(["mantle", -1, 0])
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"build.breach", {"actor": _player, "piece": _side_window()})
		return true])
	plan.append(["wait", 3])
	plan.append(["call", func(_d: RefCounted) -> bool: return not SimAssembly.build_of(_sim).is_breaching(_player)])
	plan.append(["walk", [_site(Vector3i(11, 1, 1))]])
	plan.append(["wait", 20])
	plan.append(["walk", [_site(Vector3i(11, 0, -6)), _site(Vector3i(2, 0, -6)), _site(Vector3i(2, 0, -1))]])
	plan.append(["call", _open_front_door])
	plan.append(["wait", 40])
	return plan


# ---------------------------------------------------------------- m6-hack-interrupt

## actor 2's id: actors and items share one id counter, so it is read after spawning
var _shooter: int = 0


## Hit during the hack: someone already in the yard (actor 2, armed with a loaded
## pistol) opens fire while the player works the junction box; the first hit ends the
## hack, its progress is lost and the monitor is never spoofed.
func _hack_interrupt() -> Array:
	var plan: Array = [["call", func(d: RefCounted) -> bool:
		d.call("submit", &"actor.spawn", {"profile": "arcade", "range_m": 51})
		return true], ["wait", 2], ["call", _find_shooter]]
	for spec: Array in [["weapon_frame", "g19", 11, 1], ["weapon_part", "g19_mag_15", 12, 1], ["ammo", "9x19_fmj", 13, 15]]:
		plan.append(["call", func(d: RefCounted) -> bool:
			d.call("submit", &"item.spawn", {"kind": spec[0], "template": spec[1], "container": String(ItemSystem.inventory_of(_shooter)), "seed": spec[2], "count": spec[3]})
			return true])
	plan.append(["wait", 2])
	plan.append(["call", func(d: RefCounted) -> bool:
		var items: ItemSystem = SimAssembly.items_of(_sim)
		var frame: int = 0
		var mag: int = 0
		for id: int in items.items_in(ItemSystem.inventory_of(_shooter)):
			var kind: StringName = items.item_kind(id)
			if kind == &"weapon_frame":
				frame = id
			elif kind == &"weapon_part":
				mag = id
			else:
				d.call("submit", &"magazine.load", {"actor": _shooter, "magazine": mag, "round": id})
		d.call("submit", &"actor.wield", {"actor": _shooter, "weapon": frame})
		return true])
	plan.append(["wait", 2])
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"weapon.reload_tactical", {"actor": _shooter, "weapon": _shooter_frame(), "magazine": _shooter_mag()})
		return true])
	plan.append_array(_kit())
	plan.append_array(_accept())
	plan.append(["walk", [Vector3i(14, 0, -6), _site(Vector3i(11, 0, -6)), _site(Vector3i(11, 0, 1))]])
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"hack.start", {"actor": _player, "target": _target(&"power_monitor_spoof")})
		return true])
	plan.append(["wait", 60])
	plan.append(["call", func(d: RefCounted) -> bool:
		if not SimAssembly.hacks_of(_sim).is_hacking(_player):
			return true
		if not SimAssembly.items_of(_sim).is_busy(_shooter_frame(), _sim.get_tick() + 1):
			d.call("submit", &"weapon.fire", {"actor": _shooter, "target": _player})
		return false])
	plan.append(["wait", 40])
	return plan


func _shooter_frame() -> int:
	var items: ItemSystem = SimAssembly.items_of(_sim)
	for id: int in items.items_in(ItemSystem.inventory_of(_shooter)):
		if items.item_kind(id) == &"weapon_frame":
			return id
	return EntityIds.NONE


func _shooter_mag() -> int:
	var items: ItemSystem = SimAssembly.items_of(_sim)
	for id: int in items.items_in(ItemSystem.inventory_of(_shooter)):
		if items.item_kind(id) == &"weapon_part":
			return id
	return EntityIds.NONE


# ---------------------------------------------------------------- m6-death

## The side route in to the server room for the drive (spoof, mantle, cut the window,
## the terminal upstairs, log out) and back out into the yard.
func _side_for_the_drive() -> Array:
	var plan: Array = []
	plan.append(["walk", [Vector3i(14, 0, -6), _site(Vector3i(11, 0, -6)), _site(Vector3i(11, 0, 1))]])
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"hack.start", {"actor": _player, "target": _target(&"power_monitor_spoof")})
		return true])
	plan.append(["wait", 3])
	plan.append(["call", func(_d: RefCounted) -> bool: return not SimAssembly.hacks_of(_sim).is_hacking(_player)])
	plan.append(["mantle", -1, 0])
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"build.breach", {"actor": _player, "piece": _side_window()})
		return true])
	plan.append(["wait", 3])
	plan.append(["call", func(_d: RefCounted) -> bool: return not SimAssembly.build_of(_sim).is_breaching(_player)])
	# the maintenance room's door is north at x 7; the server room's east at z 5
	plan.append(["walk", [_site(Vector3i(9, 1, 1)), _site(Vector3i(7, 1, 1)), _site(Vector3i(7, 1, 5)), _site(Vector3i(2, 1, 5)), _site(Vector3i(2, 1, 6))]])
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"hack.start", {"actor": _player, "target": _target(&"cold_storage_terminal")})
		return true])
	plan.append(["wait", 3])
	plan.append(["call", func(_d: RefCounted) -> bool: return not SimAssembly.hacks_of(_sim).is_hacking(_player)])
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"hack.logout", {"actor": _player, "target": _target(&"cold_storage_terminal")})
		return true])
	plan.append(["wait", 3])
	plan.append(["walk", [_site(Vector3i(2, 1, 5)), _site(Vector3i(7, 1, 5)), _site(Vector3i(7, 1, 1)), _site(Vector3i(9, 1, 1)), _site(Vector3i(10, 1, 1)), _site(Vector3i(11, 1, 1))]])
	plan.append(["wait", 20])
	return plan


## Death mid-run: with the drive in hand, back out in the yard, the player is shot
## dead by someone waiting there (actor 2); the drive lies in the body. The player
## respawns at home on the starter plot, walks back, takes the drive from their own
## body, leaves the site (the exfil) and delivers it to Marlow.
func _death() -> Array:
	var plan: Array = [["call", func(d: RefCounted) -> bool:
		d.call("submit", &"land.identify", {"actor": _player, "owner": "player"})
		d.call("submit", &"land.transfer", {"parcel": "starter_plot", "owner": "player"})
		return true], ["wait", 2]]
	plan.append_array(_kit())
	plan.append_array(_accept())
	plan.append_array(_side_for_the_drive())
	plan.append(["call", func(_d: RefCounted) -> bool: return _carried(&"cold_storage_data") != EntityIds.NONE])
	plan.append_array(_armed_shooter(51))
	plan.append(["call", func(d: RefCounted) -> bool:
		if not SimAssembly.actors_of(_sim).is_alive(_player):
			return true
		if not SimAssembly.items_of(_sim).is_busy(_shooter_frame(), _sim.get_tick() + 1):
			d.call("submit", &"weapon.fire", {"actor": _shooter, "target": _player})
		return false])
	plan.append(["wait", 40])
	plan.append(["respawn"])
	plan.append(["walk", [Vector3i(1, 0, -1), Vector3i(14, 0, -1), Vector3i(14, 0, -6), _site(Vector3i(11, 0, -6)), _site(Vector3i(11, 0, 0))]])
	plan.append(["call", func(d: RefCounted) -> bool:
		var body: StringName = SimAssembly.corpses_of(_sim).corpse_of(_player)
		var items: ItemSystem = SimAssembly.items_of(_sim)
		for id: int in items.items_in(body):
			if items.item_template(id) == &"cold_storage_data":
				d.call("submit", CorpseSystem.COMMAND_TAKE, {"actor": _player, "from": String(body), "item": id})
				return false
		return _carried(&"cold_storage_data") != EntityIds.NONE])
	plan.append(["walk", [_site(Vector3i(11, 0, -7)), Vector3i(14, 0, -7), Vector3i(14, 0, -2)]])
	plan.append(["deliver", QUEST])
	plan.append(["wait", 40])
	return plan


## Actor 2, spawned `range_m` metres down the street's x axis with a loaded pistol.
func _armed_shooter(range_m: int) -> Array:
	var plan: Array = [["call", func(d: RefCounted) -> bool:
		d.call("submit", &"actor.spawn", {"profile": "arcade", "range_m": range_m})
		return true], ["wait", 2], ["call", _find_shooter]]
	for spec: Array in [["weapon_frame", "g19", 11, 1], ["weapon_part", "g19_mag_15", 12, 1], ["ammo", "9x19_fmj", 13, 15]]:
		plan.append(["call", func(d: RefCounted) -> bool:
			d.call("submit", &"item.spawn", {"kind": spec[0], "template": spec[1], "container": String(ItemSystem.inventory_of(_shooter)), "seed": spec[2], "count": spec[3]})
			return true])
	plan.append(["wait", 2])
	plan.append(["call", func(d: RefCounted) -> bool:
		var items: ItemSystem = SimAssembly.items_of(_sim)
		var mag: int = _shooter_mag()
		for id: int in items.items_in(ItemSystem.inventory_of(_shooter)):
			if items.item_kind(id) == &"ammo":
				d.call("submit", &"magazine.load", {"actor": _shooter, "magazine": mag, "round": id})
		d.call("submit", &"actor.wield", {"actor": _shooter, "weapon": _shooter_frame()})
		return true])
	plan.append(["wait", 2])
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"weapon.reload_tactical", {"actor": _shooter, "weapon": _shooter_frame(), "magazine": _shooter_mag()})
		return true])
	plan.append(["wait", 90])
	return plan


func _find_shooter(_d: RefCounted) -> bool:
	var ids: Array[int] = SimAssembly.actors_of(_sim).actor_ids()
	_shooter = ids[ids.size() - 1]
	return _shooter != _player


# ---------------------------------------------------------------- m6-city-death

## The city's softening and its fee: the m6-death run, paid by Marlow, then back into
## the docklands yard (law 500) carrying the cutter and six rounds, shot dead again.
## This time there are credits: the city returns each item home with probability
## 500 / 1000, drawn from the sim's generator, for 100 credits each.
func _city_death() -> Array:
	var plan: Array = _death()
	plan.pop_back()  # the m6-death tail wait
	var inv: String = String(ItemSystem.inventory_of(_player))
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"item.spawn", {"kind": "ammo", "template": "9x19_fmj", "container": inv, "seed": 21, "count": 6})
		return true])
	plan.append(["wait", 2])
	plan.append(["walk", [Vector3i(14, 0, -6), _site(Vector3i(11, 0, -6)), _site(Vector3i(11, 0, 1))]])
	plan.append(["call", func(d: RefCounted) -> bool:
		if not SimAssembly.actors_of(_sim).is_alive(_player):
			return true
		if not SimAssembly.items_of(_sim).is_busy(_shooter_frame(), _sim.get_tick() + 1):
			d.call("submit", &"weapon.fire", {"actor": _shooter, "target": _player})
		return false])
	plan.append(["wait", 40])
	return plan


# ---------------------------------------------------------------- m6-loud

## Loud: cut through the front door without the card (the lobby camera's alarm), shoot
## the lobby's guard down (a body), up the stairs to the server room for the drive, back
## out the way in, and deliver: a reduced payout and raised heat.
func _loud() -> Array:
	var plan: Array = _kit()
	var inv: String = String(ItemSystem.inventory_of(_player))
	for spec: Array in [["weapon_frame", "g19", 31, 1], ["weapon_part", "g19_mag_15", 32, 1], ["ammo", "9x19_fmj", 33, 15]]:
		plan.append(["call", func(d: RefCounted) -> bool:
			d.call("submit", &"item.spawn", {"kind": spec[0], "template": spec[1], "container": inv, "seed": spec[2], "count": spec[3]})
			return true])
	plan.append(["wait", 2])
	plan.append(["call", func(d: RefCounted) -> bool:
		var mag: int = _carried(&"g19_mag_15")
		var items: ItemSystem = SimAssembly.items_of(_sim)
		for id: int in items.items_in(ItemSystem.inventory_of(_player)):
			if items.item_kind(id) == &"ammo":
				d.call("submit", &"magazine.load", {"actor": _player, "magazine": mag, "round": id})
		return true])
	plan.append(["wait", 2])
	plan.append_array(_accept())
	plan.append(["walk", [Vector3i(14, 0, -2), _site(Vector3i(2, 0, -2)), _site(Vector3i(2, 0, -1))]])
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"build.breach", {"actor": _player, "piece": _front_door()})
		return true])
	plan.append(["wait", 3])
	plan.append(["call", func(_d: RefCounted) -> bool: return not SimAssembly.build_of(_sim).is_breaching(_player)])
	# the pistol, loaded
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"actor.wield", {"actor": _player, "weapon": _carried(&"g19")})
		return true])
	plan.append(["wait", 2])
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"weapon.reload_tactical", {"actor": _player, "weapon": _carried(&"g19"), "magazine": _carried(&"g19_mag_15")})
		return true])
	plan.append(["wait", 90])
	plan.append(["walk", [_site(Vector3i(2, 0, 0))]])
	plan.append(["call", func(d: RefCounted) -> bool:
		var post: int = _lobby_guard()
		if not SimAssembly.actors_of(_sim).is_alive(post):
			return true
		var pistol: int = SimAssembly.actors_of(_sim).wielded(_player)
		if not SimAssembly.items_of(_sim).is_busy(pistol, _sim.get_tick() + 1):
			d.call("submit", &"weapon.fire", {"actor": _player, "target": post})
		return false])
	# the hall, the stairs, the server room
	plan.append(["walk", [_site(Vector3i(2, 0, 1)), _site(Vector3i(5, 0, 1)), _site(Vector3i(5, 0, 5)), _site(Vector3i(9, 0, 5))]])
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"actor.climb", {"actor": _player, "piece": SimAssembly.build_of(_sim).cell_piece_at(_site(Vector3i(9, 0, 6)))})
		return true])
	plan.append(["wait", 3])
	plan.append(["call", func(_d: RefCounted) -> bool: return SimAssembly.movement_of(_sim).can_act(_player)])
	plan.append(["walk", [_site(Vector3i(9, 1, 5)), _site(Vector3i(2, 1, 5)), _site(Vector3i(2, 1, 6))]])
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"hack.start", {"actor": _player, "target": _target(&"cold_storage_terminal")})
		return true])
	plan.append(["wait", 3])
	plan.append(["call", func(_d: RefCounted) -> bool: return not SimAssembly.hacks_of(_sim).is_hacking(_player)])
	plan.append(["call", func(_d: RefCounted) -> bool: return _carried(&"cold_storage_data") != EntityIds.NONE])
	plan.append(["walk", [_site(Vector3i(2, 1, 5)), _site(Vector3i(9, 1, 5)), _site(Vector3i(9, 1, 6))]])
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"actor.climb", {"actor": _player, "piece": SimAssembly.build_of(_sim).cell_piece_at(_site(Vector3i(9, 0, 6)))})
		return true])
	plan.append(["wait", 3])
	plan.append(["call", func(_d: RefCounted) -> bool: return SimAssembly.movement_of(_sim).can_act(_player)])
	plan.append(["walk", [_site(Vector3i(9, 0, 5)), _site(Vector3i(5, 0, 5)), _site(Vector3i(5, 0, 1)), _site(Vector3i(2, 0, 1)), _site(Vector3i(2, 0, -1)), _site(Vector3i(2, 0, -7)), Vector3i(14, 0, -7), Vector3i(14, 0, -2)]])
	plan.append(["deliver", QUEST])
	plan.append(["wait", 40])
	return plan


## The lobby's static post: the site spawns its agents in content order, the lobby
## camera first and then this guard.
func _lobby_guard() -> int:
	return SimAssembly.sites_of(_sim).agents_of(&"cold_storage")[1]


# ---------------------------------------------------------------- m6-fall

## The tower on the player's own starter plot, along z = ROW, x left to right (only
## crates can be mantled; a crate stands by a foundation or on one):
##   x 1  crate                  a step up to storey 1
##   x 2  foundation + crate     a step up to storey 2
##   x 3  crate on storey 1      over open air, held by its neighbours: the guard's post
##   x 4  foundation + crate     its other neighbour
##   z = ROW - 1, x 1..3         foundations: a storey-1 walkway beside the guard's crate
##   x 6, x 8  crates            storey-1 blocks with a one-cell gap between them, each
##                               held by a foundation just north of it (z = ROW + 1)
const ROW: int = 5
const TOWER: Array = [
	["foundation_block", 2, 0, 0], ["foundation_block", 4, 0, 0], ["foundation_block", 1, 0, -1], ["foundation_block", 2, 0, -1],
	["foundation_block", 3, 0, -1], ["foundation_block", 6, 0, 1], ["foundation_block", 8, 0, 1],
	["storage_crate", 1, 0, 0], ["storage_crate", 2, 1, 0], ["storage_crate", 4, 1, 0], ["storage_crate", 3, 1, 0],
	["storage_crate", 6, 0, 0], ["storage_crate", 8, 0, 0],
]


## Falls: build the tower, jump the gap between the storey-1 blocks, climb onto the
## walkway, cut the crate out from under a guard standing on it (two storeys down: the
## content's damage), then up onto the storey-2 crate and off its edge (hurt too).
func _fall() -> Array:
	var plan: Array = [["call", func(d: RefCounted) -> bool:
		d.call("submit", &"land.identify", {"actor": _player, "owner": "player"})
		d.call("submit", &"land.transfer", {"parcel": "starter_plot", "owner": "player"})
		return true], ["wait", 2]]
	plan.append_array(_kit())
	for piece: Array in TOWER:
		plan.append(["call", func(d: RefCounted) -> bool:
			var x: int = piece[1]
			var y: int = piece[2]
			var dz: int = piece[3]
			d.call("submit", &"build.place", {"actor": _player, "piece": piece[0], "x": x * 1000 + 500, "y": y * 1000 + 500, "z": (ROW + dz) * 1000 + 500, "facing": ""})
			return true])
		plan.append(["wait", 1])
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"agent.spawn", {"profile": "guard_sim", "cell": [3, 2, ROW], "facing": 0, "squad": 1, "route": ""})
		return true])
	plan.append(["wait", 2])
	# the jump: up onto the x 6 block, across the gap to x 8, and off its far side (one
	# storey: free)
	plan.append(["walk", [Vector3i(14, 0, -1), Vector3i(5, 0, -1), Vector3i(5, 0, ROW)]])
	plan.append(["mantle", 1, 0])
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"actor.jump", {"actor": _player, "dx": 1, "dz": 0})
		return true])
	plan.append(["wait", 3])
	plan.append(["call", func(_d: RefCounted) -> bool: return SimAssembly.movement_of(_sim).can_act(_player)])
	plan.append(["walk", [Vector3i(9, 1, ROW)]])
	plan.append(["wait", 30])
	# round to the west end, up onto the x 1 crate and along the walkway
	plan.append(["walk", [Vector3i(9, 0, ROW - 3), Vector3i(0, 0, ROW - 3), Vector3i(0, 0, ROW)]])
	plan.append(["mantle", 1, 0])
	plan.append(["walk", [Vector3i(1, 1, ROW - 1), Vector3i(3, 1, ROW - 1)]])
	# cut the crate under the guard
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"build.breach", {"actor": _player, "piece": SimAssembly.build_of(_sim).cell_piece_at(Vector3i(3, 1, ROW))})
		return true])
	plan.append(["wait", 3])
	plan.append(["call", func(_d: RefCounted) -> bool: return not SimAssembly.build_of(_sim).is_breaching(_player)])
	plan.append(["wait", 60])
	# up onto the x 2 crate (storey 2) and off its north edge: two storeys down
	plan.append(["walk", [Vector3i(2, 1, ROW - 1)]])
	plan.append(["mantle", 0, 1])
	plan.append(["walk", [Vector3i(2, 2, ROW + 1)]])
	plan.append(["wait", 60])
	return plan


# ---------------------------------------------------------------- m6-stealth

## Full stealth by the under route (G6's stealth-scoring proof): the maintenance key from
## the city's utility box on the pavement, the street grate unlocked underfoot (a drop
## into the tunnel), the basement grate unlocked, through the basement behind its desk
## guard, up the stairs into the maintenance room (which nobody patrols) to wait, across
## the hall to the server room's north-west corner
## (out of sight of the doorway to the west room), the terminal hacked and logged out
## of, back the same way by the maintenance room and out by the tunnel's hatch, off the site, and delivered:
## nobody alerted, no alarm, no body, no trace, the full-stealth bonus paid. Before each
## stretch upstairs the player waits until going on is safe (_sneak: a look ahead on a
## copy of the sim), as a careful player watching the patrols would.
func _stealth() -> Array:
	var plan: Array = _kit()
	plan.append_array(_accept())
	plan.append(["walk", [Vector3i(14, 0, -4), _site(Vector3i(-1, 0, -4))]])
	plan.append(["call", func(d: RefCounted) -> bool:
		if _carried(&"maintenance_key") != EntityIds.NONE:
			return true
		var box: StringName = SimAssembly.sites_of(_sim).crates_of(&"cold_storage")[1]
		var held: Array[int] = SimAssembly.items_of(_sim).items_in(box)
		d.call("submit", CorpseSystem.COMMAND_TAKE, {"actor": _player, "from": String(box), "item": held[0]})
		return false])
	plan.append(["walk", [_site(Vector3i(1, 0, -4)), _site(Vector3i(1, 0, -3))]])
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"opening.open", {"actor": _player, "piece": _face(Vector3i(1, -1, -3), "py")})
		return true])
	plan.append(["wait", 30])
	plan.append(["walk", [_site(Vector3i(4, -1, -3)), _site(Vector3i(4, -1, -1))]])
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"opening.open", {"actor": _player, "piece": _face(Vector3i(4, -1, -1), "pz")})
		return true])
	plan.append(["wait", 3])
	plan.append(["walk", [_site(Vector3i(4, -1, 1)), _site(Vector3i(3, -1, 1)), _site(Vector3i(3, -1, 4)), _site(Vector3i(7, -1, 4))]])
	# the hack spot: within the terminal's reach, out of every line through the west
	# room's doorway and the hall's door
	var hx: int = _param("hx", 2)
	var hz: int = _param("hz", 7)
	# the hide: in the maintenance room, which nobody patrols, against the hall wall
	# beside the door, where no line through the doorway from the hall reaches
	var hide: Vector3i = _site(Vector3i(_param("mx", 5), 1, _param("mz", 3)))
	var stairs_up: Array = [
		["climb", _site(Vector3i(7, -1, 5)), "cell"],
		["walk", [_site(Vector3i(9, 0, 5))]],
		["climb", _site(Vector3i(9, 0, 6)), "cell"],
		["walk", [_site(Vector3i(9, 1, 5)), _site(Vector3i(9, 1, 4)), _site(Vector3i(7, 1, 4)), _site(Vector3i(7, 1, 3)), hide]],
	]
	var to_server: Array = [
		["walk", [_site(Vector3i(7, 1, hide.z - SITE.z)), _site(Vector3i(7, 1, 4)), _site(Vector3i(5, 1, 4)), _site(Vector3i(5, 1, 5)), _site(Vector3i(4, 1, 5)), _site(Vector3i(4, 1, hz)), _site(Vector3i(hx, 1, hz))]],
	]
	var work: Array = [
		["call", func(d: RefCounted) -> bool:
			d.call("submit", &"hack.start", {"actor": _player, "target": _target(&"cold_storage_terminal")})
			return true],
		["wait", 3],
		["call", func(_d: RefCounted) -> bool: return not SimAssembly.hacks_of(_sim).is_hacking(_player)],
		["call", func(d: RefCounted) -> bool:
			d.call("submit", &"hack.logout", {"actor": _player, "target": _target(&"cold_storage_terminal")})
			return true],
		["wait", 3],
	]
	var to_hide: Array = [
		["walk", [_site(Vector3i(4, 1, hz)), _site(Vector3i(4, 1, 5)), _site(Vector3i(5, 1, 5)), _site(Vector3i(5, 1, 4)), _site(Vector3i(7, 1, 4)), _site(Vector3i(7, 1, 3)), hide]],
	]
	var stairs_down: Array = [
		["walk", [_site(Vector3i(7, 1, hide.z - SITE.z)), _site(Vector3i(7, 1, 4)), _site(Vector3i(9, 1, 4)), _site(Vector3i(9, 1, 6))]],
		["climb", _site(Vector3i(9, 0, 6)), "cell"],
		["walk", [_site(Vector3i(7, 0, 5))]],
		["climb", _site(Vector3i(7, -1, 5)), "cell"],
	]
	var basement: Array = [
		["walk", [_site(Vector3i(3, -1, 4)), _site(Vector3i(3, -1, 1)), _site(Vector3i(4, -1, 1)), _site(Vector3i(4, -1, -3)), _site(Vector3i(2, -1, -3))]],
	]
	for stretch: Array in [stairs_up, to_server, work, to_hide, stairs_down, basement]:
		var steps: Array = _expand(stretch)
		plan.append(_sneak(steps, _param("margin", 420)))
		plan.append_array(steps)
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"actor.climb", {"actor": _player, "piece": _face(Vector3i(2, -1, -3), "py")})
		return true])
	plan.append(["wait", 3])
	plan.append(["call", func(_d: RefCounted) -> bool: return SimAssembly.movement_of(_sim).can_act(_player)])
	plan.append(["walk", [_site(Vector3i(2, 0, -7)), Vector3i(14, 0, -7), Vector3i(14, 0, -2)]])
	plan.append(["deliver", QUEST])
	plan.append(["wait", 40])
	return plan


## Expands ["climb", cell, "cell"] (a climb of the cell piece at a world cell, found when
## the step runs, followed by waiting for footing) into driver steps.
func _expand(stretch: Array) -> Array:
	var out: Array = []
	for step: Array in stretch:
		if step[0] == "climb" and step.size() == 3:
			var cell: Vector3i = step[1]
			out.append(["call", func(d: RefCounted) -> bool:
				d.call("submit", &"actor.climb", {"actor": _player, "piece": SimAssembly.build_of(_sim).cell_piece_at(cell)})
				return true])
			out.append(["wait", 3])
			out.append(["call", func(_d: RefCounted) -> bool: return SimAssembly.movement_of(_sim).can_act(_player)])
		else:
			out.append(step)
	return out


func _face(site_cell: Vector3i, facing: String) -> int:
	return SimAssembly.build_of(_sim).face_piece_at(BuildSystem.face_key(_site(site_cell), facing))



# ---------------------------------------------------------------- looking ahead

## A step that waits, as a careful player would, until going on is safe: it plays
## `segment` (the steps that follow it in the plan) and `margin` more ticks on a copy of
## the sim restored from a snapshot, and lets the plan go on only if nobody became
## alerted to the player there. The plan's margin outlasts a guard's memory (400 ticks),
## so a guard who glimpsed the player and comes looking is part of the look. Waiting
## records no command, so the fixture is an
## ordinary replay. Gives up (failing the plan) after `patience` ticks.
func _sneak(segment: Array, margin: int, patience: int = -1) -> Array:
	if patience < 0:
		patience = _param("patience", 5000)
	var since: Array[int] = [-1]
	var every: int = _param("every", 10)
	return ["call", func(_d: RefCounted) -> bool:
		if since[0] < 0:
			since[0] = _sim.get_tick()
		if _sim.get_tick() - since[0] > patience:
			push_warning("make_m6_fixtures: no safe moment by tick %d; going on regardless" % _sim.get_tick())
			return true  # the following steps run regardless; the fixture test will fail loudly
		if (_sim.get_tick() - since[0]) % every != 0:
			return false
		if _safe(segment, margin):
			print("SNEAK safe at tick %d after %d" % [_sim.get_tick(), _sim.get_tick() - since[0]])
			return true
		return false, patience + 40]


func _safe(segment: Array, margin: int) -> bool:
	var real: SimRoot = _sim
	var snap: Dictionary = real.snapshot()
	var copy: SimRoot = SimAssembly.build(SEED, _db)
	if SimAssembly.restore_systems(copy, snap) != OK or copy.restore_root(snap) != OK:
		push_error("make_m6_fixtures: the lookahead copy did not restore")
		return true
	var seen: Array[bool] = [false]
	var start: int = real.get_tick()
	SimAssembly.combat_of(copy).events().subscribe(PerceptionSystem.EVENT_ALERTED, func(p: Dictionary) -> void:
		if p["contact"] == _player and not seen[0]:
			seen[0] = true
			if OS.has_environment("SNEAK_DEBUG"):
				var o: int = p["observer"]
				var a: ActorSystem = SimAssembly.actors_of(_sim)  # the copy, via the member: no captured sim, no cycle
				var at: int = p["tick"]
				print("  seen +%d by %d %s at %s from %s facing %d stance %s" % [at - start, o, a.profile_of(o), a.position_of(_player) / BuildSystem.CELL - SITE, a.position_of(o) / 100, SimAssembly.perception_of(_sim).facing_of(o), SimAssembly.stances_of(_sim).stance_of(o)]))
	if OS.has_environment("SNEAK_DEBUG"):
		var pr: PerceptionSystem = SimAssembly.perception_of(real)
		for agent: int in pr.agent_ids():
			if pr.awareness_of(agent, _player) > 0 or pr.has_last_known(agent, _player):
				print("  before t%d: %d aw=%d alerted=%s mem=%d" % [real.get_tick(), agent, pr.awareness_of(agent, _player), pr.is_alerted(agent, _player), pr.memory_of(agent, _player)])
	_sim = copy
	var look: RefCounted = Driver.new(copy, _player)
	var done: bool = look.call("run", segment.duplicate(), 3000)
	if OS.has_environment("SNEAK_DEBUG"):
		print("  look t%d (%d ms): done=%s after %d ticks %s at %s" % [real.get_tick(), Time.get_ticks_msec(), done, copy.get_tick() - real.get_tick(), look.get("failure"), SimAssembly.actors_of(copy).position_of(_player) / BuildSystem.CELL - SITE])
	for i: int in margin:
		if seen[0]:
			break
		copy.step()
	_sim = real
	return done and not seen[0]
