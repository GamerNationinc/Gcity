extends GcityTest

## M6 spec claim 12: a site's pieces go in through BuildSystem.spawn_batch: excavation
## first, then every piece in order with no rights check, support checked once for the
## whole set, one build.changed. All or nothing: any piece that does not fit leaves the
## build, the excavation and the id counter exactly as they were. Oracle: the M4 building
## spawned as one batch is the same build as the M4 building placed piece by piece.

const SEED: int = 20261034
const M: int = 1000
const FAR: Vector3i = Vector3i(500 * M, 0, 500 * M)

var _sim: SimRoot
var _build: BuildSystem
var _actors: ActorSystem
var _changes: Array[Dictionary] = []


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_build = SimAssembly.build_of(_sim)
	_actors = SimAssembly.actors_of(_sim)
	var sink: Array[Dictionary] = []
	_changes = sink
	SimAssembly.combat_of(_sim).events().subscribe(BuildSystem.EVENT_CHANGED, func(p: Dictionary) -> void: sink.append(p))


func _cell(cx: int, cy: int, cz: int) -> Vector3i:
	return BuildSystem.cell_of(FAR) + Vector3i(cx, cy, cz)


func _e(piece: StringName, c: Vector3i, facing: String) -> Dictionary:
	return {"piece": piece, "cell": c, "facing": facing}


## A shed over a dug cellar: foundations, a roof, a hatch down to the cellar, a ladder.
func _shed() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: Vector3i in [Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		out.append(_e(&"foundation_block", _cell(d.x, d.y, d.z), ""))
	out.append(_e(&"floor_panel", _cell(0, 0, 0), "py"))
	out.append(_e(&"street_grate", _cell(0, -1, 0), "py"))
	return out


## The player owns the M4 building's two parcels, as the M4 fixtures set up.
func _own(player: int) -> void:
	var at: int = _sim.get_tick() + 1
	_sim.submit(SimCommand.new(at, &"land.identify", {"actor": player, "owner": "player"}))
	_sim.submit(SimCommand.new(at, &"land.transfer", {"parcel": "starter_plot", "owner": "player"}))
	_sim.submit(SimCommand.new(at, &"land.transfer", {"parcel": "neighbour_north", "owner": "player"}))
	_sim.step()


func _state() -> String:
	return StateHash.of({"build": _build.snapshot(), "entities": SimAssembly.entities_of(_sim).snapshot()})


func test_a_batch_places_everything_with_one_change_and_no_rights() -> void:
	_setup()
	var cellar: Array[Vector3i] = [_cell(0, -1, 0)]
	var ids: Array[int] = _build.spawn_batch(cellar, _shed())
	assert_eq(ids.size(), 6, "six pieces")
	for i: int in ids.size() - 1:
		assert_eq(ids[i + 1], ids[i] + 1, "ids in entry order")
	assert_eq(_changes.size(), 1, "one build.changed")
	assert_eq(_changes[0]["added"], ids, "naming every piece")
	assert_eq(_changes[0]["actor"], EntityIds.NONE, "raised by nobody")
	assert_false(_build.is_solid(_cell(0, -1, 0)), "the cellar is dug")
	assert_eq(_build.template_of(ids[5]), &"street_grate", "the grate is in the ground face")
	assert_eq(SimAssembly.land_of(_sim).violation_count(), 0, "no rights asked, none violated")


func test_a_batch_that_does_not_fit_changes_nothing() -> void:
	_setup()
	var player: int = _actors.spawn(&"arcade", 0)
	_actors.set_position(player, FAR + Vector3i(-20 * M, 0, -20 * M))
	assert_true(_build.place(player, &"foundation_block", FAR + Vector3i(3 * M + 500, 500, 500), "") > 0, "a foundation already there")
	var before: String = _state()
	var cellar: Array[Vector3i] = [_cell(0, -1, 0)]
	var cases: Array = []
	var taken: Array[Dictionary] = _shed()
	taken.append(_e(&"foundation_block", _cell(3, 0, 0), ""))
	cases.append(["a taken cell", taken])
	var floating: Array[Dictionary] = _shed()
	floating.append(_e(&"floor_panel", _cell(0, 2, 9), "py"))
	cases.append(["an unsupported piece", floating])
	var bad_facing: Array[Dictionary] = _shed()
	bad_facing.append(_e(&"wall_panel", _cell(0, 0, 0), "py"))
	cases.append(["a wall laid flat", bad_facing])
	var unknown: Array[Dictionary] = _shed()
	unknown.append(_e(&"zz_nothing", _cell(0, 0, 0), ""))
	cases.append(["an unknown piece", unknown])
	for c: Array in cases:
		var what: String = c[0]
		var entries: Array[Dictionary] = c[1]
		assert_eq(_build.spawn_batch(cellar, entries), [] as Array[int], "%s: refused" % what)
		assert_eq(_state(), before, "%s: nothing changed, not even an id" % what)
		assert_true(_build.is_solid(_cell(0, -1, 0)), "%s: the cellar is undug" % what)
	_actors.set_position(player, FAR + Vector3i(-1 * M + 500, 0, 500))
	assert_eq(_build.spawn_batch(cellar, _shed()), [] as Array[int], "an actor standing in a cell: refused")
	assert_eq(_state(), before, "nothing changed")
	assert_eq(_build.spawn_batch([Vector3i(0, 0, 0)] as Array[Vector3i], _shed()), [] as Array[int], "digging above ground: refused")
	assert_eq(_changes.size(), 1, "only the first foundation's change")


func test_oracle_the_m4_building_as_one_batch_equals_it_placed_piece_by_piece() -> void:
	_setup()
	var player: int = _actors.spawn(&"arcade", 0)
	_actors.set_position(player, M4Building.PLAYER_START)
	_own(player)
	var entries: Array[Dictionary] = []
	for c: Dictionary in M4Building.commands(player):
		var x: int = c["x"]
		var y: int = c["y"]
		var z: int = c["z"]
		var piece: String = c["piece"]
		var facing: String = c["facing"]
		entries.append(_e(StringName(piece), BuildSystem.cell_of(Vector3i(x, y, z)), facing))
	var ids: Array[int] = _build.spawn_batch([] as Array[Vector3i], entries)
	assert_eq(ids.size(), entries.size(), "the whole building in one batch")
	var batched: Dictionary = _build.snapshot()
	_setup()
	player = _actors.spawn(&"arcade", 0)
	_actors.set_position(player, M4Building.PLAYER_START)
	_own(player)
	for c: Dictionary in M4Building.commands(player):
		var x2: int = c["x"]
		var y2: int = c["y"]
		var z2: int = c["z"]
		var piece2: String = c["piece"]
		var facing2: String = c["facing"]
		assert_true(_build.place(player, StringName(piece2), Vector3i(x2, y2, z2), facing2) > 0, "placed %s" % piece2)
	assert_eq(StateHash.of(_build.snapshot()), StateHash.of(batched), "the same build either way")
