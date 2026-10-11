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
var _player: int = 0
var _drive: RefCounted


func _initialize() -> void:
	var only: PackedStringArray = OS.get_cmdline_user_args()
	var all: Dictionary = {"m6-front": _front, "m6-side": _side, "m6-front-hot": _front_hot, "m6-hack-interrupt": _hack_interrupt}
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
	_drive = Driver.new(_sim, 1)
	# the player: actor 1, on the street by Marlow
	_drive.call("submit", &"actor.spawn", {"profile": "arcade", "range_m": 14})
	_sim.step()
	_player = SimAssembly.actors_of(_sim).actor_ids()[0]
	var plan: Array = plan_of.call()
	var ok: bool = _drive.call("run", plan)
	if not ok:
		print("FAILED %s: %s (player at %s)" % [name, _drive.get("failure"), BuildSystem.cell_of(SimAssembly.actors_of(_sim).position_of(_player))])
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

const SHOOTER: int = 2


## Hit during the hack: someone already in the yard (actor 2, armed with a loaded
## pistol) opens fire while the player works the junction box; the first hit ends the
## hack, its progress is lost and the monitor is never spoofed.
func _hack_interrupt() -> Array:
	var theirs: String = String(ItemSystem.inventory_of(SHOOTER))
	var plan: Array = [["call", func(d: RefCounted) -> bool:
		d.call("submit", &"actor.spawn", {"profile": "arcade", "range_m": 51})
		return true], ["wait", 2]]
	for spec: Array in [["weapon_frame", "g19", 11, 1], ["weapon_part", "g19_mag_15", 12, 1], ["ammo", "9x19_fmj", 13, 15]]:
		plan.append(["call", func(d: RefCounted) -> bool:
			d.call("submit", &"item.spawn", {"kind": spec[0], "template": spec[1], "container": theirs, "seed": spec[2], "count": spec[3]})
			return true])
	plan.append(["wait", 2])
	plan.append(["call", func(d: RefCounted) -> bool:
		var items: ItemSystem = SimAssembly.items_of(_sim)
		var frame: int = 0
		var mag: int = 0
		for id: int in items.items_in(ItemSystem.inventory_of(SHOOTER)):
			var kind: StringName = items.item_kind(id)
			if kind == &"weapon_frame":
				frame = id
			elif kind == &"weapon_part":
				mag = id
			else:
				d.call("submit", &"magazine.load", {"actor": SHOOTER, "magazine": mag, "round": id})
		d.call("submit", &"actor.wield", {"actor": SHOOTER, "weapon": frame})
		return true])
	plan.append(["wait", 2])
	plan.append(["call", func(d: RefCounted) -> bool:
		d.call("submit", &"weapon.reload_tactical", {"actor": SHOOTER, "weapon": _shooter_frame(), "magazine": _shooter_mag()})
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
			d.call("submit", &"weapon.fire", {"actor": SHOOTER, "target": _player})
		return false])
	plan.append(["wait", 40])
	return plan


func _shooter_frame() -> int:
	var items: ItemSystem = SimAssembly.items_of(_sim)
	for id: int in items.items_in(ItemSystem.inventory_of(SHOOTER)):
		if items.item_kind(id) == &"weapon_frame":
			return id
	return EntityIds.NONE


func _shooter_mag() -> int:
	var items: ItemSystem = SimAssembly.items_of(_sim)
	for id: int in items.items_in(ItemSystem.inventory_of(SHOOTER)):
		if items.item_kind(id) == &"weapon_part":
			return id
	return EntityIds.NONE
