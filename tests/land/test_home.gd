extends GcityTest

## M6 spec claim 17 (respawn and city softening), the land side: an authored parcel may
## declare a spawn point; an actor's home is the first parcel (by id) owned by its
## owner tag that declares one; a position's law index is its district's. Assumption
## recorded for CEOGG: the starter plot is the player's home (design doc §8.1).

const SEED: int = 20261160

var _sim: SimRoot
var _land: LandSystem
var _player: int = 0


func _setup(db: ContentDb = null) -> void:
	if db == null:
		db = ContentDb.new()
		assert_eq(ContentLoader.load_all(db), OK, "content")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_land = SimAssembly.land_of(_sim)
	_player = SimAssembly.actors_of(_sim).spawn(&"arcade", 0)


func _do(kind: StringName, payload: Dictionary) -> void:
	_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload))
	_sim.step()


func test_home_is_the_owned_parcel_with_a_spawn_point() -> void:
	_setup()
	assert_false(_land.has_home(_player), "nobody's home before owning a plot")
	_do(&"land.identify", {"actor": _player, "owner": "player"})
	assert_false(_land.has_home(_player), "a tag owns nothing yet")
	_do(&"land.transfer", {"parcel": "neighbour_north", "owner": "player"})
	assert_false(_land.has_home(_player), "a parcel without a spawn point is not a home")
	_do(&"land.transfer", {"parcel": "starter_plot", "owner": "player"})
	assert_true(_land.has_home(_player), "the starter plot is")
	var spawn: Vector3i = _land.home_spawn_of(_player)
	assert_eq(_land.parcel_at(spawn), &"starter_plot", "its spawn point lies inside it")
	_do(&"land.transfer", {"parcel": "starter_plot", "owner": ""})
	assert_false(_land.has_home(_player), "sold: no home")


func test_law_index_is_the_districts() -> void:
	_setup()
	var plot: Dictionary = _land.parcel(&"starter_plot")
	var poly: Array = plot["footprint"]
	var corner: Array = poly[0]
	var cx: int = corner[0]
	var cz: int = corner[1]
	assert_eq(_land.parcel_at(Vector3i(cx + 10, 0, cz + 10)), &"starter_plot", "a point in the plot")
	assert_eq(_land.law_index_at(Vector3i(cx + 10, 0, cz + 10)), 250, "the starter ghetto's 250")
	assert_eq(_land.law_index_at(Vector3i(-50_000_000, 0, -50_000_000)), 50, "unparcelled land is the wild district's (badlands, 50)")


func test_a_spawn_point_outside_its_parcel_is_refused() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	var plot: Dictionary = db.get_entry(&"parcel", &"starter_plot").duplicate(true)
	plot["spawn"] = [99_999, 0, 500]
	db.add(&"parcel", &"zz_bad_home", plot)
	assert_eq(SimAssembly.build(SEED, db), null, "rejected at assembly")
