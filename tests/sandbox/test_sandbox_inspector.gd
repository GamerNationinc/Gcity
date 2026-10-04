extends GcityTest

## M7.6 spec claim 8: the inspector reads sim queries and writes nothing. Every overlay on,
## synced every tick over a running Cold Storage with its guards, against the same sim
## stepped with no inspector: the state hash is the same at every tick, and syncing does
## not change it within a tick either.

const SEED: int = 20261705
const TICKS: int = 300


func _scene() -> Array:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	assert_eq(ContentLoader.load_all(db, "res://sandbox_content"), OK, "and the sandbox's")
	var sim: SimRoot = SandboxAssembly.build(SEED, db)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var player: int = actors.spawn(&"arcade", 0)
	var t: Dictionary = db.get_entry(SiteSystem.KIND_SITE, &"cold_storage")
	var at: int = sim.get_tick() + 1
	sim.submit(SimCommand.new(at, &"land.identify", {"actor": player, "owner": "player"}))
	for p: Variant in t["parcels"]:
		var id_s: String = p
		sim.submit(SimCommand.new(at, &"land.transfer", {"parcel": id_s, "owner": "player"}))
	sim.step()
	assert_true(SimAssembly.sites_of(sim).raise_site(player, &"cold_storage"), "Cold Storage stands")
	# the player in the street in front of the lobby, where the lobby guard looks out
	actors.set_position(player, BuildSystem.cell_centre(SimAssembly.sites_of(sim).cell_of(&"cold_storage", Vector3i(2, 0, -6))) - Vector3i(0, 500, 0))
	return [sim, player]


func test_every_overlay_reads_and_writes_nothing() -> void:
	var a: Array = _scene()
	var b: Array = _scene()
	var watched: SimRoot = a[0]
	var plain: SimRoot = b[0]
	var player: int = a[1]
	var inspector := SandboxInspector.new()
	inspector.call(&"set_all", true)
	var shown: PackedStringArray = inspector.call(&"on_list")
	assert_eq(shown.size(), SandboxInspector.OVERLAYS.size(), "every overlay on")
	var most_labels: int = 0
	for i: int in TICKS:
		var before: String = watched.state_hash()
		inspector.call(&"sync", watched, player)
		assert_eq(watched.state_hash(), before, "syncing changed nothing at tick %d" % watched.get_tick())
		var labels: int = inspector.call(&"label_count")
		most_labels = maxi(most_labels, labels)
		watched.step()
		plain.step()
		if watched.state_hash() != plain.state_hash():
			assert_eq(watched.state_hash(), plain.state_hash(), "the watched sim and the plain one parted at tick %d" % watched.get_tick())
			break
	assert_true(most_labels > 0, "and it drew something (%d labels at most)" % most_labels)
	for overlay: String in SandboxInspector.OVERLAYS:
		var toggled: bool = inspector.call(&"toggle", overlay)
		assert_true(toggled, "%s toggles" % overlay)
	var none: PackedStringArray = inspector.call(&"on_list")
	assert_eq(none.size(), 0, "and toggled, every one is off")
	var bad: bool = inspector.call(&"toggle", "x-ray")
	assert_false(bad, "a name that is not an overlay is refused")
	inspector.free()
