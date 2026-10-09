extends GcityTest

## M6 spec claim 3: openings (door, window, hatch, ladder, grate) carry an open flag.
## A piece template says how it starts; `opening.open` / `opening.close` need the actor
## in one of the two cells the face separates; a locked piece needs its credential
## carried; a latched one opens only from its inside (an enclosed volume). An open
## horizontal opening holds nobody up, and a piece set into the ground face cuts the
## ground there for good, so a cut grate stays a hole.

const SEED: int = 20261015
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)

var _sim: SimRoot
var _build: BuildSystem
var _actors: ActorSystem
var _items: ItemSystem
var _player: int = 0
var _changes: Array[Dictionary] = []


func _setup(db: ContentDb = null) -> void:
	if db == null:
		db = ContentDb.new()
		assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_build = SimAssembly.build_of(_sim)
	_actors = SimAssembly.actors_of(_sim)
	_items = SimAssembly.items_of(_sim)
	_player = _actors.spawn(&"arcade", 0)
	_actors.set_position(_player, _feet(6, 0, 6))
	var sink: Array[Dictionary] = []
	_changes = sink
	var on_changed: Callable = func(payload: Dictionary) -> void:
		sink.append(payload)
	SimAssembly.combat_of(_sim).events().subscribe(BuildSystem.EVENT_OPENING, on_changed)


func _feet(cx: int, storey: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, storey * BuildSystem.STOREY_MM, cz * M + 500)


func _at(cx: int, cy: int, cz: int) -> Vector3i:
	return FAR + Vector3i(cx * M + 500, cy * M + 500, cz * M + 500)


func _cell(cx: int, cy: int, cz: int) -> Vector3i:
	return BuildSystem.cell_of(_at(cx, cy, cz))


func _do(kind: StringName, payload: Dictionary) -> bool:
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	_sim.step()
	return _sim.dispatched_count() == before + 1


## A one-cell room at (0, 0, 0): foundations west, north and south, a roof, and the
## given piece in its east wall. Returns that piece.
func _room(piece: StringName) -> int:
	for c: Vector3i in [Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		assert_true(_build.place(_player, &"foundation_block", _at(c.x, c.y, c.z), "") > 0, "foundation %s" % c)
	assert_true(_build.place(_player, &"floor_panel", _at(0, 0, 0), "py") > 0, "roof")
	var id: int = _build.place(_player, piece, _at(0, 0, 0), "px")
	assert_true(id > 0, "%s in the east wall" % piece)
	return id


func test_templates_say_how_openings_start() -> void:
	_setup()
	var door: int = _room(&"door_frame")
	assert_true(_build.is_open(door), "a door frame is an open doorway")
	_setup()
	var w: int = _room(&"window_frame")
	assert_false(_build.is_open(w), "a window starts closed")
	assert_false(_build.is_open(_build.cell_piece_at(_cell(-1, 0, 0))), "a solid piece is never open")


func test_open_and_close_need_the_actor_at_the_face() -> void:
	_setup()
	var door: int = _room(&"door_frame")
	assert_false(_do(&"opening.close", {"actor": _player, "piece": door}), "not from across the street")
	_actors.set_position(_player, _feet(1, 0, 0))
	assert_true(_do(&"opening.close", {"actor": _player, "piece": door}), "closed from outside, at the door")
	assert_false(_build.is_open(door), "closed")
	assert_eq(_changes.back(), {"piece": door, "open": false, "actor": _player}, "the event")
	assert_false(_do(&"opening.close", {"actor": _player, "piece": door}), "already closed")
	assert_true(_do(&"opening.open", {"actor": _player, "piece": door}), "and opened again: a door frame is not latched")
	var wall: int = _build.cell_piece_at(_cell(-1, 0, 0))
	assert_false(_do(&"opening.open", {"actor": _player, "piece": wall}), "a foundation is not an opening")


func test_a_latched_window_opens_only_from_inside() -> void:
	_setup()
	var window: int = _room(&"window_frame")
	_actors.set_position(_player, _feet(1, 0, 0))
	assert_false(_do(&"opening.open", {"actor": _player, "piece": window}), "not from the street")
	_actors.set_position(_player, _feet(0, 0, 0))
	assert_true(_do(&"opening.open", {"actor": _player, "piece": window}), "from the room")
	assert_true(_build.is_open(window), "open")


func test_a_locked_door_needs_its_credential() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	var t: Dictionary = db.get_entry(&"build_piece", &"door_frame").duplicate(true)
	t["starts_open"] = false
	t["lock"] = "ammo"
	assert_eq(db.add(&"build_piece", &"zz_locked_door", t), OK, "a door locked to anyone carrying ammo")
	_setup(db)
	var door: int = _room(&"zz_locked_door")
	_actors.set_position(_player, _feet(0, 0, 0))
	assert_false(_do(&"opening.open", {"actor": _player, "piece": door}), "no credential, even from inside")
	assert_true(_items.spawn(&"ammo", &"9x19_fmj", ItemSystem.inventory_of(_player), 1) > 0, "a round")
	assert_true(_do(&"opening.open", {"actor": _player, "piece": door}), "the credential opens it")


func test_an_open_hatch_holds_nobody_up() -> void:
	_setup()
	assert_true(_build.place(_player, &"foundation_block", _at(0, 0, 1), "") > 0, "foundation")
	var hatch: int = _build.place(_player, &"roof_hatch", _at(0, 0, 0), "py")
	assert_true(hatch > 0, "hatch")
	assert_true(_build.is_standable(_cell(0, 1, 0)), "closed: stood on")
	_actors.set_position(_player, _feet(0, 0, 0))
	assert_true(_do(&"opening.open", {"actor": _player, "piece": hatch}), "opened from below")
	assert_false(_build.is_standable(_cell(0, 1, 0)), "open: a hole")


func test_a_grate_in_the_ground_is_locked_and_cutting_it_leaves_a_hole() -> void:
	_setup()
	assert_true(_build.place(_player, &"foundation_block", _at(1, 0, 0), "") > 0, "foundation")
	var grate: int = _build.place(_player, &"street_grate", _at(0, -1, 0), "py")
	assert_true(grate > 0, "a grate set into the ground face")
	assert_true(_build.is_standable(_cell(0, 0, 0)), "walk on the closed grate")
	_actors.set_position(_player, _feet(0, 0, 0))
	assert_false(_do(&"opening.open", {"actor": _player, "piece": grate}), "maintenance-locked")
	_actors.set_position(_player, _feet(4, 0, 4))
	assert_false(_build.breach(grate).is_empty(), "cut out")
	assert_false(_build.is_standable(_cell(0, 0, 0)), "the ground there is a hole now")
	assert_true(_build.is_standable(_cell(0, -1, 0)), "onto the bedrock below")
	assert_true(_build.is_standable(_cell(2, 0, 0)), "the ground elsewhere is untouched")


func test_open_flags_and_holes_survive_a_restore_and_bad_ones_are_rejected() -> void:
	_setup()
	var door: int = _room(&"door_frame")
	assert_true(_build.place(_player, &"foundation_block", _at(3, 0, 0), "") > 0, "foundation")
	var grate: int = _build.place(_player, &"street_grate", _at(2, -1, 0), "py")
	assert_false(_build.breach(grate).is_empty(), "a hole")
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	var other: BuildSystem = SimAssembly.build_of(SimAssembly.build(SEED, db))
	assert_eq(other.restore(_build.snapshot()), OK, "restores")
	assert_true(other.is_open(door), "open flag kept")
	assert_false(other.is_standable(_cell(2, 0, 0)), "hole kept")
	var bad: Dictionary = _build.snapshot().duplicate(true)
	var pieces: Dictionary = bad["pieces"]
	var wall: int = _build.cell_piece_at(_cell(-1, 0, 0))
	var rec: Dictionary = pieces[wall]
	rec["open"] = true
	assert_eq(other.restore(bad), ERR_INVALID_DATA, "an open foundation is rejected")
	var bad_holes: Dictionary = _build.snapshot().duplicate(true)
	bad_holes["holes"] = ["0,0,0|x"]
	assert_eq(other.restore(bad_holes), ERR_INVALID_DATA, "a hole that is not a ground face is rejected")
