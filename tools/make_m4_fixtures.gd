## Writes the M4 replay fixtures (spec claim 14) into tests/replay/: the building
## from M4Building, four armed guards, and one scripted player per scenario. Runs a
## sim while writing so that item ids in later commands come from the sim itself.
##   godot --headless --path . -s tools/make_m4_fixtures.gd
## Then `tools/test.sh replay` prints each hash to paste into "expected_hash".
extends SceneTree

const OUT_DIR: String = "res://tests/replay"
const M: int = 1000
## A hide the player built on the street round the origin: a screen east of it and a
## stub south, so a guard walking up to where it last saw the player looks at blocks
## (the game's own answer to being seen); open to the north and west.
const HIDE: Array[Vector3i] = [Vector3i(2, 0, 0), Vector3i(1, 0, 1), Vector3i(1, 0, 2), Vector3i(1, 0, 3), Vector3i(1, 0, 4), Vector3i(0, 0, -1), Vector3i(0, 0, -2)]
## A closed one-cell pillbox round the origin: fire from it and nobody can look in.
const PILLBOX: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

var _sim: SimRoot
var _commands: Array = []


func _initialize() -> void:
	_write("m4-detect", "guard_sim", 20, _detect_walk(), 160)
	_write("m4-arcade", "guard_arcade", 20, _detect_walk(), 160)
	_write("m4-break-contact", "guard_sim", 0, _break_contact_walk(), 520, HIDE)
	_write("m4-noise", "guard_sim", 0, _noise_walk(), 560, PILLBOX)
	_write("m4-radio", "guard_sim", 20, _detect_walk(), 120)
	_write("m4-radio-off", "guard_mute", 20, _detect_walk(), 120)
	quit(0)


## A fixture: the common setup with the player spawned `range_m` down the street,
## then `moves` (an array of [dx, dz] or ["fire"] per tick from the first play
## tick), then `tail` ticks of standing still.
func _write(name: String, profile: String, range_m: int, moves: Array, tail: int, cover: Array[Vector3i] = []) -> void:
	_commands = []
	var db := ContentDb.new()
	var err: Error = ContentLoader.load_all(db)
	assert(err == OK, "content")
	_sim = SimAssembly.build(20261100, db)
	var actors: ActorSystem = SimAssembly.actors_of(_sim)
	var items: ItemSystem = SimAssembly.items_of(_sim)
	# 20 m down the street is behind the lobby's east wall from every guard's point of
	# view; the origin is behind its west wall
	_at(1, &"actor.spawn", {"profile": "arcade", "range_m": range_m})
	_step()
	var player: int = actors.actor_ids()[0]
	_at(2, &"land.identify", {"actor": player, "owner": "player"})
	_at(2, &"land.transfer", {"parcel": "starter_plot", "owner": "player"})
	_at(2, &"land.transfer", {"parcel": "neighbour_north", "owner": "player"})
	for c: Dictionary in M4Building.commands(player, db):
		_at(2, &"build.place", c)
	for g: Dictionary in M4Building.guards(profile, db):
		_at(2, &"agent.spawn", g)
	for cell: Vector3i in cover:
		var c: Vector3i = BuildSystem.cell_centre(cell)
		_at(2, &"build.place", {"actor": player, "piece": "foundation_block", "x": c.x, "y": c.y, "z": c.z, "facing": ""})
	_kit(2, player, 1, 2, 30)
	_step()
	var guards: Array[int] = []
	for id: int in actors.actor_ids():
		if id != player:
			guards.append(id)
	for i: int in guards.size():
		_kit(3, guards[i], 10 + i * 100, 11 + i * 100, 15)
	_step()
	var pistol: int = _load_mags(4, items, player)
	for g: int in guards:
		_load_mags(4, items, g)
	_step()
	_at(5, &"actor.wield", {"actor": player, "weapon": pistol})
	_at(5, &"weapon.reload_tactical", {"actor": player, "weapon": pistol, "magazine": _mags(items, player)[0]})
	for g: int in guards:
		var frame: int = _frame(items, g)
		_at(5, &"actor.wield", {"actor": g, "weapon": frame})
		_at(5, &"weapon.reload_tactical", {"actor": g, "weapon": frame, "magazine": _mags(items, g)[0]})
	_step()
	# the reload keeps every pistol busy for 80 ticks; play starts after that
	var play: int = 90
	for i: int in moves.size():
		var m: Array = moves[i]
		if m[0] is String:
			_at(play + i, &"weapon.fire", {"actor": player, "target": guards[0]})
		else:
			var dx: int = m[0]
			var dz: int = m[1]
			if dx != 0 or dz != 0:  # [0, 0] is a tick of standing still: no command
				_at(play + i, &"actor.move", {"actor": player, "dx": dx, "dz": dz})
	var fixture: Dictionary = {
		"schema_version": 1, "name": name, "seed": 20261100, "ticks": play + moves.size() + tail,
		"commands": _commands, "expected_hash": "",
	}
	var file: FileAccess = FileAccess.open("%s/%s.json" % [OUT_DIR, name], FileAccess.WRITE)
	assert(file != null, "open %s" % name)
	file.store_string(JSON.stringify(fixture, "\t") + "\n")
	file.close()
	print("wrote %s: %d commands, %d ticks" % [name, _commands.size(), fixture["ticks"]])


## Walks west along the street from the spawn to stand in front of the door, where
## the lobby post can see it; the door's line of sight opens about 7 m before that.
func _detect_walk() -> Array:
	var out: Array = []
	for i: int in 100:
		out.append([-150, 0])
	return out


## From the hide north round the screen and east into the post's line of sight
## through the door for a moment, then straight back into the hide, where no guard
## could see the player at the start, before anyone comes to look.
func _break_contact_walk() -> Array:
	var out: Array = []
	for i: int in 34:
		out.append([0, 150])
	for i: int in 33:
		out.append([150, 0])
	for i: int in 6:
		out.append([0, 0])   # a moment in view: enough to be worth a look, not an alert
	for i: int in 33:
		out.append([-150, 0])
	for i: int in 34:
		out.append([0, -150])
	return out


## From the pillbox, one shot at the post through the lobby's walls: heard, not
## seen, and nobody who comes to look can see in.
func _noise_walk() -> Array:
	return [["fire"]]


func _at(tick: int, kind: StringName, payload: Dictionary) -> void:
	_commands.append({"tick": tick, "kind": String(kind), "payload": payload})
	var err: Error = _sim.submit(SimCommand.new(tick, kind, payload))
	assert(err == OK, "submit")


func _step() -> void:
	_sim.step()


func _kit(tick: int, actor: int, frame_seed: int, mag_seed: int, rounds: int) -> void:
	var inv: String = String(ItemSystem.inventory_of(actor))
	_at(tick, &"item.spawn", {"kind": "weapon_frame", "template": "g19", "container": inv, "seed": frame_seed, "count": 1})
	_at(tick, &"item.spawn", {"kind": "weapon_part", "template": "g19_mag_15", "container": inv, "seed": mag_seed, "count": rounds / 15})
	_at(tick, &"item.spawn", {"kind": "ammo", "template": "9x19_fmj", "container": inv, "seed": 100 + frame_seed, "count": rounds})


func _load_mags(tick: int, items: ItemSystem, actor: int) -> int:
	var frame: int = 0
	var mags: Array[int] = []
	var rounds: Array[int] = []
	for id: int in items.items_in(ItemSystem.inventory_of(actor)):
		if items.item_kind(id) == &"weapon_frame":
			frame = id
		elif items.item_kind(id) == &"weapon_part":
			mags.append(id)
		else:
			rounds.append(id)
	for m: int in mags.size():
		for i: int in 15:
			var index: int = m * 15 + i
			if index < rounds.size():
				_at(tick, &"magazine.load", {"actor": actor, "magazine": mags[m], "round": rounds[index]})
	return frame


func _mags(items: ItemSystem, actor: int) -> Array[int]:
	var out: Array[int] = []
	for id: int in items.items_in(ItemSystem.inventory_of(actor)):
		if items.item_kind(id) == &"weapon_part":
			out.append(id)
	return out


func _frame(items: ItemSystem, actor: int) -> int:
	for id: int in items.items_in(ItemSystem.inventory_of(actor)):
		if items.item_kind(id) == &"weapon_frame":
			return id
	return 0
