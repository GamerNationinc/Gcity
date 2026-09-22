## Writes the M5 replay fixtures (spec claim 15) into tests/replay/: the device's own
## command streams, replayed headless against the assembled sim, so what the panes
## submit is proven without a window. Runs a sim while writing so item ids in later
## commands come from the sim itself.
##   godot --headless --path . -s tools/make_m5_fixtures.gd
## Then `tools/test.sh replay` prints each hash to paste into "expected_hash".
extends SceneTree

const OUT_DIR: String = "res://tests/replay"
const M: int = 1000
const SEED: int = 20261150
## On the starter plot, which the player owns: `safe`, so the device may pause.
const ON_PLOT: Vector3i = Vector3i(3 * M, 0, 3 * M)
## On the neighbour's parcel: not safe, so a pause there is a violation.
const OFF_PLOT: Vector3i = Vector3i(18 * M, 0, 6 * M)

var _sim: SimRoot
var _commands: Array = []
var _player: int = 0
var _items: ItemSystem
var _actors: ActorSystem


func _initialize() -> void:
	_inventory()
	_quest()
	_pause()
	quit(0)


## The inventory app's own stream: carry the device, fit the radio module, load a
## magazine round by round, wield, swap it in, then take the module out again.
func _inventory() -> void:
	_begin()
	var inv: StringName = ItemSystem.inventory_of(_player)
	var device: int = _find(inv, ItemSystem.KIND_DEVICE_FRAME)
	var module: int = _find(inv, ItemSystem.KIND_DEVICE_MODULE)
	var pistol: int = _find(inv, ItemSystem.KIND_FRAME)
	var mag: int = _find(inv, ItemSystem.KIND_PART)
	_at(10, &"actor.equip_device", {"actor": _player, "device": device})
	_at(10, &"item.attach", {"actor": _player, "weapon": device, "part": module})
	_step_to(11)
	var tick: int = 12
	for round: int in _items.items_in(inv):
		if _items.item_kind(round) == ItemSystem.KIND_AMMO and _items.rounds_in(mag).size() < 15:
			_at(tick, &"magazine.load", {"actor": _player, "magazine": mag, "round": round})
			_step_to(tick + 1)
			tick += 1
	_at(tick, &"actor.wield", {"actor": _player, "weapon": pistol})
	_at(tick, &"weapon.reload_tactical", {"actor": _player, "weapon": pistol, "magazine": mag})
	_step_to(tick + 1)
	_at(tick + 90, &"item.detach", {"actor": _player, "weapon": device, "socket": "radio"})
	_write("m5-inventory", tick + 120)


## The quests app's stream: accept, put three rounds into a dummy, completed, the
## reward in the inventory; then abandoning it is refused.
func _quest() -> void:
	_begin()
	var inv: StringName = ItemSystem.inventory_of(_player)
	var pistol: int = _find(inv, ItemSystem.KIND_FRAME)
	var mag: int = _find(inv, ItemSystem.KIND_PART)
	var dummy: int = 0
	_at(10, &"actor.spawn", {"profile": "range_dummy", "range_m": 6})
	_step_to(11)
	for id: int in _actors.actor_ids():
		if id != _player:
			dummy = id
	_at(12, &"quest.accept", {"actor": _player, "quest": "first_blood"})
	var tick: int = 13
	for round: int in _items.items_in(inv):
		if _items.item_kind(round) == ItemSystem.KIND_AMMO and _items.rounds_in(mag).size() < 15:
			_at(tick, &"magazine.load", {"actor": _player, "magazine": mag, "round": round})
			_step_to(tick + 1)
			tick += 1
	_at(tick, &"actor.wield", {"actor": _player, "weapon": pistol})
	_at(tick, &"weapon.reload_tactical", {"actor": _player, "weapon": pistol, "magazine": mag})
	_step_to(tick + 1)
	tick += 90
	# the dummy soaks every hit: fire until the objective's three hits land
	for i: int in 30:
		_at(tick, &"weapon.fire", {"actor": _player, "target": dummy})
		_step_to(tick + 1)
		tick += 7
	_at(tick, &"quest.abandon", {"actor": _player, "quest": "first_blood"})
	_write("m5-quest", tick + 10)


## The pause stream: a pause off the plot is refused as a violation; back on the plot
## it is accepted, a reload submitted while paused waits, the menu's own commands do
## not, and the resume lets the reload through.
func _pause() -> void:
	_begin()
	var inv: StringName = ItemSystem.inventory_of(_player)
	var device: int = _find(inv, ItemSystem.KIND_DEVICE_FRAME)
	var module: int = _find(inv, ItemSystem.KIND_DEVICE_MODULE)
	var pistol: int = _find(inv, ItemSystem.KIND_FRAME)
	var mag: int = _find(inv, ItemSystem.KIND_PART)
	_at(10, &"actor.equip_device", {"actor": _player, "device": device})
	var tick: int = 11
	for round: int in _items.items_in(inv):
		if _items.item_kind(round) == ItemSystem.KIND_AMMO and _items.rounds_in(mag).size() < 15:
			_at(tick, &"magazine.load", {"actor": _player, "magazine": mag, "round": round})
			_step_to(tick + 1)
			tick += 1
	_at(tick, &"actor.wield", {"actor": _player, "weapon": pistol})
	_step_to(tick + 1)
	tick += 1
	# walk off the plot: 15 m east at 150 mm a tick
	for i: int in 100:
		_at(tick, &"actor.move", {"actor": _player, "dx": 150, "dz": 0})
		_step_to(tick + 1)
		tick += 1
	_at(tick, &"sim.pause", {"actor": _player})  # refused: not safe here
	_step_to(tick + 1)
	tick += 1
	for i: int in 100:
		_at(tick, &"actor.move", {"actor": _player, "dx": -150, "dz": 0})
		_step_to(tick + 1)
		tick += 1
	_at(tick, &"sim.pause", {"actor": _player})  # accepted: home
	_step_to(tick + 1)
	# paused: the menu's commands land on the frozen step, the reload waits for the
	# resume, which the client submits for the same tick when the device is lowered
	_at(tick + 1, &"item.attach", {"actor": _player, "weapon": device, "part": module})
	_at(tick + 1, &"weapon.reload_tactical", {"actor": _player, "weapon": pistol, "magazine": mag})
	_at(tick + 1, &"sim.resume", {"actor": _player})
	_sim.step()
	_sim.step()
	tick = _sim.get_tick()
	# raised again and left raised: every tick from here is frozen, and the queued
	# step never happens
	_at(tick + 1, &"sim.pause", {"actor": _player})
	_sim.step()
	_at(_sim.get_tick() + 1, &"actor.move", {"actor": _player, "dx": 150, "dz": 0})
	_write("m5-pause", tick + 120)


# ---------------------------------------------------------------- the common setup

func _begin() -> void:
	_commands = []
	var db := ContentDb.new()
	var err: Error = ContentLoader.load_all(db)
	assert(err == OK, "content")
	_sim = SimAssembly.build(SEED, db)
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_at(1, &"actor.spawn", {"profile": "arcade", "range_m": 0})
	_sim.step()
	_player = _actors.actor_ids()[0]
	var err2: Error = _actors.set_position(_player, ON_PLOT)
	assert(err2 == OK, "on the plot")
	var inv: String = String(ItemSystem.inventory_of(_player))
	_at(2, &"land.identify", {"actor": _player, "owner": "player"})
	_at(2, &"land.transfer", {"parcel": "starter_plot", "owner": "player"})
	_at(2, &"item.spawn", {"kind": "device_frame", "template": "handset", "container": inv, "seed": 1, "count": 1})
	_at(2, &"item.spawn", {"kind": "device_module", "template": "radio_module", "container": inv, "seed": 2, "count": 1})
	_at(2, &"item.spawn", {"kind": "weapon_frame", "template": "g19", "container": inv, "seed": 3, "count": 1})
	_at(2, &"item.spawn", {"kind": "weapon_part", "template": "g19_mag_15", "container": inv, "seed": 4, "count": 1})
	_at(2, &"item.spawn", {"kind": "ammo", "template": "9x19_fmj", "container": inv, "seed": 100, "count": 20})
	_step_to(3)


func _find(container: StringName, kind: StringName) -> int:
	for id: int in _items.items_in(container):
		if _items.item_kind(id) == kind:
			return id
	return EntityIds.NONE


func _at(tick: int, kind: StringName, payload: Dictionary) -> void:
	_commands.append({"tick": tick, "kind": String(kind), "payload": payload})
	var err: Error = _sim.submit(SimCommand.new(tick, kind, payload))
	assert(err == OK, "submit %s for tick %d at %d" % [kind, tick, _sim.get_tick()])


## Steps until the sim's tick is one before `tick`, so a command submitted for
## `tick` is still in the future (the sim never rewrites the past).
func _step_to(tick: int) -> void:
	while _sim.get_tick() < tick - 1:
		_sim.step()


func _write(name: String, ticks: int) -> void:
	var fixture: Dictionary = {"schema_version": 1, "name": name, "seed": SEED, "ticks": ticks, "commands": _commands, "expected_hash": ""}
	var file: FileAccess = FileAccess.open("%s/%s.json" % [OUT_DIR, name], FileAccess.WRITE)
	assert(file != null, "open %s" % name)
	file.store_string(JSON.stringify(fixture, "\t") + "\n")
	file.close()
	print("wrote %s: %d commands, %d ticks" % [name, _commands.size(), ticks])
