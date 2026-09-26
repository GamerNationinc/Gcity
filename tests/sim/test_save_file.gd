extends GcityTest

## M2 spec claims 13–16: save = seed + overlay, `load(save(state))` hashes equal and
## keeps stepping equal, saves are small, and hostile saves fail cleanly.

const SEED: int = 20260926
const PROPERTY_CASES: int = 10_000
const SEED_PROPERTY: int = 20260927
const SEED_FUZZ: int = 20260928
const FUZZ_MUTATIONS: int = 10_000
const FUZZ_DIR: String = "res://tests/fuzz/save_file"
const MAX_SAVE_BYTES: int = 64 * 1024
const M: int = 1000

var _content: ContentDb


func _db() -> ContentDb:
	if _content == null:
		_content = ContentDb.new()
		assert_eq(ContentLoader.load_all(_content), OK, "content loads")
	return _content


func _submit(sim: SimRoot, kind: StringName, payload: Dictionary, at: int = 1) -> void:
	assert_eq(sim.submit(SimCommand.new(sim.get_tick() + at, kind, payload)), OK, "submit %s" % kind)


## A sim with a little of everything: actors, the pistol kit, an owned plot, a
## container with modules, a violation, and commands still queued in the inbox.
func _populated(seed: int = SEED) -> SimRoot:
	var sim: SimRoot = SimAssembly.build(seed, _db())
	_submit(sim, &"actor.spawn", {"profile": "arcade", "range_m": 0})
	_submit(sim, &"actor.spawn", {"profile": "range_dummy", "range_m": 18})
	sim.step()
	_submit(sim, &"item.spawn", {"kind": "weapon_frame", "template": "g19", "container": "inv.1", "seed": 7, "count": 1})
	_submit(sim, &"item.spawn", {"kind": "weapon_part", "template": "g19_mag_15", "container": "inv.1", "seed": 8, "count": 1})
	_submit(sim, &"item.spawn", {"kind": "ammo", "template": "9x19_fmj", "container": "inv.1", "seed": 9, "count": 10})
	_submit(sim, &"land.identify", {"actor": 1, "owner": "player"})
	_submit(sim, &"land.transfer", {"parcel": "starter_plot", "owner": "player"})
	sim.step()
	_submit(sim, &"structure.place", {"actor": 1, "template": "container_20ft", "x": 2 * M, "y": 0, "z": 4 * M, "rotation": 0})
	_submit(sim, &"structure.place", {"actor": 1, "template": "container_20ft", "x": 14 * M, "y": 0, "z": 4 * M, "rotation": 0})
	sim.step()
	var structures: StructureSystem = SimAssembly.structures_of(sim)
	var s: int = structures.structure_ids()[0]
	_submit(sim, &"module.install", {"actor": 1, "structure": s, "template": "power_cell_rack", "col": 0, "row": 0})
	sim.step()
	_submit(sim, &"module.install", {"actor": 1, "structure": s, "template": "work_station", "col": 2, "row": 0})
	_submit(sim, &"actor.wield", {"actor": 1, "weapon": 3})
	sim.step_n(3)
	# leave two commands queued for the future
	_submit(sim, &"module.install", {"actor": 1, "structure": s, "template": "sustainment", "col": 5, "row": 0}, 4)
	_submit(sim, &"land.transfer", {"parcel": "neighbour_east", "owner": "player"}, 6)
	return sim


func _save(sim: SimRoot) -> String:
	var text: String = SaveFile.serialize(sim, _db().digest())
	assert_false(text.is_empty(), "serialize")
	return text


func _load(text: String) -> SimRoot:
	var file: SaveFile = SaveFile.parse(text)
	assert_true(file.is_valid(), "parse: %s" % file.error)
	var sim: SimRoot = SimAssembly.load_save(file, _db())
	assert_true(sim != null, "load")
	return sim


# ---------------------------------------------------------------- round trip

func test_load_of_save_hashes_equal_and_keeps_stepping_equal() -> void:
	var original: SimRoot = _populated()
	var text: String = _save(original)
	var loaded: SimRoot = _load(text)
	assert_eq(loaded.state_hash(), original.state_hash(), "load(save(state)) == state")
	assert_eq(loaded.get_tick(), original.get_tick(), "tick restored")
	assert_eq(loaded.dispatched_count(), original.dispatched_count(), "dispatch counter restored")
	assert_eq(SimAssembly.structures_of(loaded).power_available(SimAssembly.structures_of(original).structure_ids()[0]), 4700, "budget through the resolver: 3000 + 2500 - 800")
	for _i: int in 10:
		original.step()
		loaded.step()
		assert_eq(loaded.state_hash(), original.state_hash(), "still equal at tick %d (queued commands dispatched on both)" % original.get_tick())
	assert_eq(loaded.rejected_count(), original.rejected_count(), "queued commands had the same fate")
	assert_true(SimAssembly.land_of(loaded).owner_of(&"neighbour_east") == &"player", "the queued transfer landed")
	assert_eq(_save(loaded), _save(original), "saving both again gives the same text")


func test_save_text_is_deterministic_and_small() -> void:
	var sim: SimRoot = _populated()
	var a: String = _save(sim)
	var b: String = _save(sim)
	assert_eq(a, b, "same state, same text")
	assert_true(a.length() < MAX_SAVE_BYTES, "save is %d bytes, under %d" % [a.length(), MAX_SAVE_BYTES])
	assert_true(a.find("\"i:1\"") >= 0, "int keys carry their prefix")


func test_big_integers_and_prefixed_strings_survive() -> void:
	var sim: SimRoot = SimAssembly.build(SEED, _db())
	sim.rng().state = 9223372036854775807
	_submit(sim, &"land.transfer", {"parcel": "str:looks:prefixed", "owner": "int:12"})
	var text: String = _save(sim)
	var loaded: SimRoot = _load(text)
	assert_eq(loaded.rng().state, 9223372036854775807, "64-bit RNG state exact")
	assert_eq(loaded.state_hash(), sim.state_hash(), "inbox payload strings round-trip")


# ---------------------------------------------------------------- hostile input

func test_envelope_and_root_validation() -> void:
	var sim: SimRoot = _populated()
	var text: String = _save(sim)
	var cases: Dictionary[String, Callable] = {
		"wrong schema version": func(e: Dictionary) -> void: e["save_schema_version"] = 2,
		"fractional schema version": func(e: Dictionary) -> void: e["save_schema_version"] = 1.5,
		"missing digest": func(e: Dictionary) -> void: e.erase("content_digest"),
		"short digest": func(e: Dictionary) -> void: e["content_digest"] = "abc",
		"unknown key": func(e: Dictionary) -> void: e["extra"] = 1,
		"snapshot not object": func(e: Dictionary) -> void: e["snapshot"] = [],
		"unprefixed key": func(e: Dictionary) -> void: _snap(e)["tick"] = 1,
		"float value": func(e: Dictionary) -> void: _snap(e)["s:tick"] = 1.5,
		"malformed big int": func(e: Dictionary) -> void: _snap(e)["s:rng_state"] = "int:12abc",
		"small big int": func(e: Dictionary) -> void: _snap(e)["s:rng_state"] = "int:5",
	}
	for name: String in cases:
		var envelope: Dictionary = JSON.parse_string(text)
		var mutate: Callable = cases[name]
		mutate.call(envelope)
		var file: SaveFile = SaveFile.parse(JSON.stringify(envelope))
		assert_false(file.is_valid(), "%s is rejected at parse" % name)
		assert_false(file.error.is_empty(), "%s carries a message" % name)
	var loads: Dictionary[String, Callable] = {
		"digest of other content": func(e: Dictionary) -> void: e["content_digest"] = "0".repeat(64),
		"seed not an int": func(e: Dictionary) -> void: _snap(e)["s:seed"] = "1",
		"negative tick": func(e: Dictionary) -> void: _snap(e)["s:tick"] = -1,
		"inbox in the past": func(e: Dictionary) -> void: _inbox(e)["i:1"] = [{"s:kind": "land.transfer", "s:payload": {}}],
		"inbox unknown kind": func(e: Dictionary) -> void: _inbox(e)["i:99"] = [{"s:kind": "no.such", "s:payload": {}}],
		"inbox entry shape": func(e: Dictionary) -> void: _inbox(e)["i:99"] = [{"s:kind": "land.transfer"}],
		"snapshot missing systems": func(e: Dictionary) -> void: _snap(e).erase("s:systems"),
		"structure with bad rotation": func(e: Dictionary) -> void: _structure(e)["s:rotation"] = 45,
		"parcel overlapping": func(e: Dictionary) -> void:
			var plot: Dictionary = _parcels(e)["s:starter_plot"]
			_parcels(e)["s:dup"] = plot.duplicate(true),
		"actor owner map with unknown actor id type": func(e: Dictionary) -> void: _land(e)["s:actor_owner"] = {"s:x": "player"},
	}
	for name: String in loads:
		var envelope: Dictionary = JSON.parse_string(text)
		var mutate: Callable = loads[name]
		mutate.call(envelope)
		var file: SaveFile = SaveFile.parse(JSON.stringify(envelope))
		assert_true(file.is_valid(), "%s parses (rejection is the loader's)" % name)
		assert_true(SimAssembly.load_save(file, _db()) == null, "%s is rejected at load" % name)


static func _snap(e: Dictionary) -> Dictionary:
	return e["snapshot"]


static func _inbox(e: Dictionary) -> Dictionary:
	return _snap(e)["s:inbox"]


static func _systems(e: Dictionary) -> Dictionary:
	return _snap(e)["s:systems"]


static func _land(e: Dictionary) -> Dictionary:
	return _systems(e)["s:land"]


static func _parcels(e: Dictionary) -> Dictionary:
	return _land(e)["s:parcels"]


static func _structure(e: Dictionary) -> Dictionary:
	var structures: Dictionary = _systems(e)["s:structures"]
	var records: Dictionary = structures["s:structures"]
	return records["i:15"]


func test_committed_fuzz_corpus_never_loads() -> void:
	var dir: DirAccess = DirAccess.open(FUZZ_DIR)
	assert_true(dir != null, "corpus directory exists")
	if dir == null:
		return
	var files: PackedStringArray = dir.get_files()
	var checked: int = 0
	for file_name: String in files:
		if not file_name.ends_with(".json"):
			continue
		checked += 1
		var file: SaveFile = SaveFile.parse(read_text(FUZZ_DIR.path_join(file_name)))
		if file.is_valid():
			assert_true(SimAssembly.load_save(file, _db()) == null, "%s must be rejected at load" % file_name)
		else:
			assert_false(file.error.is_empty(), "%s carries a message" % file_name)
	assert_true(checked >= 10, "corpus has at least ten files (%d)" % checked)


func test_random_mutations_never_crash_and_accepted_saves_load_consistently() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_FUZZ
	var base: PackedByteArray = _save(_populated()).to_utf8_buffer()
	var accepted: int = 0
	var loaded: int = 0
	var inconsistent: int = 0
	for _i: int in FUZZ_MUTATIONS:
		var bytes: PackedByteArray = base.duplicate()
		for _m: int in rng.randi_range(1, 3):
			var at: int = rng.randi_range(0, bytes.size() - 1)
			match rng.randi_range(0, 2):
				0:
					bytes[at] = rng.randi_range(0x20, 0x7e)
				1:
					bytes.remove_at(at)
				_:
					bytes.insert(at, rng.randi_range(0x20, 0x7e))
		var file: SaveFile = SaveFile.parse(bytes.get_string_from_utf8())
		if not file.is_valid():
			continue
		accepted += 1
		var sim: SimRoot = SimAssembly.load_save(file, _db())
		if sim == null:
			continue
		loaded += 1
		# whatever loaded must be a sim that saves back to a file that loads to the same hash
		var again: SimRoot = SimAssembly.load_save(SaveFile.parse(SaveFile.serialize(sim, _db().digest())), _db())
		if again == null or again.state_hash() != sim.state_hash():
			inconsistent += 1
	assert_eq(inconsistent, 0, "every loaded mutant is itself a consistent save (%d accepted, %d loaded)" % [accepted, loaded])


# ---------------------------------------------------------------- property

## Generated sims (random seed, random command streams over every M1 and M2 command
## kind, random tick counts): load(save(state)) hashes equal, and both keep hashing
## equal while stepping the same further commands.
func test_property_round_trip_over_generated_sims() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_PROPERTY
	var mismatches: int = 0
	var later_mismatches: int = 0
	var cases: int = 0
	var db: ContentDb = _db()
	while cases < PROPERTY_CASES:
		cases += 1
		var sim: SimRoot = SimAssembly.build(rng.randi(), db)
		_random_commands(sim, rng, rng.randi_range(0, 8))
		sim.step_n(rng.randi_range(0, 6))
		var file: SaveFile = SaveFile.parse(SaveFile.serialize(sim, db.digest()))
		var loaded: SimRoot = SimAssembly.load_save(file, db)
		if loaded == null or loaded.state_hash() != sim.state_hash():
			mismatches += 1
			if mismatches <= 3:
				fail("case %d: %s" % [cases, file.error if not file.is_valid() else "hash mismatch after load"])
			continue
		var more: int = rng.randi_range(1, 4)
		var stream: Array = _command_stream(rng, more)
		_apply_stream(sim, stream)
		_apply_stream(loaded, stream)
		sim.step_n(more)
		loaded.step_n(more)
		if loaded.state_hash() != sim.state_hash():
			later_mismatches += 1
	assert_eq(mismatches, 0, "every generated sim round-trips (%d cases)" % cases)
	assert_eq(later_mismatches, 0, "and keeps stepping identically")


func _random_commands(sim: SimRoot, rng: RandomNumberGenerator, count: int) -> void:
	_apply_stream(sim, _command_stream(rng, count))


func _apply_stream(sim: SimRoot, stream: Array) -> void:
	for entry: Array in stream:
		var at: int = entry[0]
		var kind: StringName = entry[1]
		var payload: Dictionary = entry[2]
		sim.submit(SimCommand.new(sim.get_tick() + at, kind, payload))


## [ticks ahead, kind, payload] triples: mostly valid commands, some that will be
## rejected, so the counters, inbox and every system get exercised.
func _command_stream(rng: RandomNumberGenerator, count: int) -> Array:
	var out: Array = []
	for _i: int in count:
		var at: int = rng.randi_range(1, 3)
		match rng.randi_range(0, 22):
			0:
				if rng.randi_range(0, 3) == 0:
					# M6 claim 3: at a site's named point
					out.append([at, &"actor.spawn", {"profile": "arcade", "site": ["home", "m4_building", "nowhere"][rng.randi_range(0, 2)], "point": ["player_start", "respawn", "nowhere"][rng.randi_range(0, 2)]}])
				else:
					out.append([at, &"actor.spawn", {"profile": "arcade", "range_m": rng.randi_range(0, 20)}])
			10:
				# M4 claim 15: agents, with their perception, aim, stress, paths, stances and squads
				out.append([at, &"agent.spawn", {"profile": ["guard_sim", "guard_arcade", "guard_mute", "nobody"][rng.randi_range(0, 3)], "cell": [rng.randi_range(0, 12), 0, rng.randi_range(0, 12)],
					"facing": rng.randi_range(0, 359), "squad": rng.randi_range(0, 2), "route": ["", "lobby_round", "wing_patrol", "nowhere"][rng.randi_range(0, 3)]}])
			11:
				out.append([at, &"agent.set_profile", {"agent": rng.randi_range(1, 6), "profile": ["guard_sim", "guard_arcade", "nobody"][rng.randi_range(0, 2)]}])
			12:
				# M3 claim 11: build and raid commands
				out.append([at, &"build.place", {"actor": rng.randi_range(1, 3), "piece": ["foundation_block", "wall_panel", "door_frame", "storage_crate", "ladder"][rng.randi_range(0, 4)],
					"x": rng.randi_range(0, 12) * M + 500, "y": 500, "z": rng.randi_range(0, 12) * M + 500, "facing": ["", "px", "nz", "py"][rng.randi_range(0, 3)]}])
			13:
				out.append([at, &"build.remove", {"actor": rng.randi_range(1, 3), "piece_id": rng.randi_range(1, 20)}])
			14:
				out.append([at, &"raid.spawn", {"tool": ["cutter", "nothing"][rng.randi_range(0, 1)]}])
			15:
				if rng.randi_range(0, 3) == 0:
					# M6 claim 6: climbs, mostly refused on flat ground
					out.append([at, &"actor.climb", {"actor": rng.randi_range(1, 6), "dir": ["up", "down"][rng.randi_range(0, 1)], "facing": ["px", "nx", "pz", "nz"][rng.randi_range(0, 3)]}])
				else:
					out.append([at, &"actor.move", {"actor": rng.randi_range(1, 6), "dx": rng.randi_range(-150, 150), "dz": rng.randi_range(-150, 150)}])
			16:
				# M5 claim 16: the device, its bays, quests and the pause
				out.append([at, &"item.spawn", {"kind": ["device_frame", "device_module"][rng.randi_range(0, 1)], "template": ["handset", "radio_module", "nothing"][rng.randi_range(0, 2)], "container": "inv.%d" % rng.randi_range(1, 3), "seed": rng.randi(), "count": 1}])
			17:
				out.append([at, &"actor.equip_device", {"actor": rng.randi_range(1, 3), "device": rng.randi_range(0, 14)}])
			18:
				out.append([at, &"item.attach", {"actor": rng.randi_range(1, 3), "weapon": rng.randi_range(1, 14), "part": rng.randi_range(1, 14)}])
			19:
				out.append([at, &"item.detach", {"actor": rng.randi_range(1, 3), "weapon": rng.randi_range(1, 14), "socket": ["radio", "coprocessor", "barrel", "nothing"][rng.randi_range(0, 3)]}])
			20:
				out.append([at, &"quest.accept" if rng.randi_range(0, 1) == 0 else &"quest.abandon", {"actor": rng.randi_range(1, 3), "quest": ["first_blood", "break_ground", "nothing"][rng.randi_range(0, 2)]}])
			21:
				out.append([at, &"sim.pause" if rng.randi_range(0, 1) == 0 else &"sim.resume", {"actor": rng.randi_range(1, 3)}])
			22:
				# M6 claim 2: a whole site at once, and the refusals of a second raise
				out.append([at, &"site.raise", {"site": ["home", "m4_building", "nowhere"][rng.randi_range(0, 2)]}])
			1:
				out.append([at, &"item.spawn", {"kind": "weapon_frame", "template": "g19", "container": "inv.%d" % rng.randi_range(1, 3), "seed": rng.randi(), "count": 1}])
			2:
				out.append([at, &"item.spawn", {"kind": "ammo", "template": "9x19_jhp", "container": "inv.%d" % rng.randi_range(1, 3), "seed": rng.randi(), "count": rng.randi_range(1, 5)}])
			3:
				out.append([at, &"land.identify", {"actor": rng.randi_range(1, 3), "owner": ["player", "faction.scrapline", ""][rng.randi_range(0, 2)]}])
			4:
				out.append([at, &"land.transfer", {"parcel": ["starter_plot", "neighbour_east", "nowhere"][rng.randi_range(0, 2)], "owner": ["player", "", "npc.x"][rng.randi_range(0, 2)]}])
			5:
				out.append([at, &"structure.place", {"actor": rng.randi_range(1, 3), "template": "container_20ft", "x": rng.randi_range(0, 20) * M, "y": 0, "z": rng.randi_range(0, 20) * M, "rotation": [0, 90, 180, 270][rng.randi_range(0, 3)]}])
			6:
				out.append([at, &"module.install", {"actor": rng.randi_range(1, 3), "structure": rng.randi_range(1, 12), "template": ["power_cell_rack", "work_station", "sustainment"][rng.randi_range(0, 2)], "col": rng.randi_range(0, 8), "row": rng.randi_range(0, 2)}])
			7:
				out.append([at, &"module.remove", {"actor": rng.randi_range(1, 3), "structure": rng.randi_range(1, 12), "module": rng.randi_range(1, 20)}])
			8:
				out.append([at, &"actor.wield", {"actor": rng.randi_range(1, 3), "weapon": rng.randi_range(0, 12)}])
			_:
				out.append([at, &"weapon.fire", {"shooter": rng.randi_range(1, 3), "target": rng.randi_range(1, 3)}])
	return out
