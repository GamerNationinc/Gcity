extends GcityTest

## M6 spec claim 9: a tool is an item (`content/tool/<id>.json`) naming the tool class
## it breaches with, carrying tags and stats like any template: the handheld cutter
## is spawned into an inventory, read back as a tool of class `cutter`, and its noise
## stat resolves through the one resolver.

const SEED: int = 20261130


func _content() -> ContentDb:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	return db


func test_the_handheld_cutter_is_a_tool_of_the_cutter_class() -> void:
	var sim: SimRoot = SimAssembly.build(SEED, _content())
	var items: ItemSystem = SimAssembly.items_of(sim)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var player: int = actors.spawn(&"arcade", 0)
	var inv: StringName = ItemSystem.inventory_of(player)
	var cutter: int = items.spawn(ItemSystem.KIND_TOOL, &"cutter_handheld", inv, 1)
	assert_true(cutter > 0, "spawned into the inventory")
	assert_eq(items.item_kind(cutter), ItemSystem.KIND_TOOL, "a tool")
	assert_eq(items.tool_class_of(cutter), &"cutter", "that cuts")
	assert_true(SimAssembly.stats_of(sim).get_tags(cutter).has(&"tool.cutter"), "tagged")
	assert_true(SimAssembly.stats_of(sim).resolve(cutter, &"noise") > 0, "and loud")
	assert_eq(items.tool_class_of(player), &"", "an actor is not a tool")
	var frame: int = items.spawn(ItemSystem.KIND_FRAME, &"g19", inv, 2)
	assert_eq(items.tool_class_of(frame), &"", "nor is a pistol")
	assert_eq(items.first_tool_of_class(player, &"cutter"), cutter, "found in the inventory by class")
	assert_eq(items.first_tool_of_class(player, &"breacher"), EntityIds.NONE, "no breacher carried")


func test_goods_are_items_read_by_their_tags() -> void:
	var sim: SimRoot = SimAssembly.build(SEED, _content())
	var items: ItemSystem = SimAssembly.items_of(sim)
	var player: int = SimAssembly.actors_of(sim).spawn(&"arcade", 0)
	var drive: int = items.spawn(ItemSystem.KIND_GOODS, &"data_drive", ItemSystem.inventory_of(player), 1)
	assert_true(drive > 0, "a data drive in the inventory")
	assert_eq(items.item_kind(drive), ItemSystem.KIND_GOODS, "goods")
	assert_true(SimAssembly.stats_of(sim).get_tags(drive).has(&"goods.data"), "tagged as data")
	assert_eq(items.tool_class_of(drive), &"", "not a tool")
	var db: ContentDb = _content()
	assert_eq(db.add(ItemSystem.KIND_GOODS, &"zz_bad", {"schema_version": 1, "description": "x", "tags": [], "stats": [{"stat": "no_stat", "value": 1}]}), OK, "added")
	assert_true(SimAssembly.build(SEED, db) == null, "goods with an unknown stat refuse assembly")


func test_the_spawn_command_takes_tools() -> void:
	var sim: SimRoot = SimAssembly.build(SEED, _content())
	var player: int = SimAssembly.actors_of(sim).spawn(&"arcade", 0)
	var inv: String = String(ItemSystem.inventory_of(player))
	sim.submit(SimCommand.new(sim.get_tick() + 1, &"item.spawn", {"kind": "tool", "template": "cutter_handheld", "container": inv, "seed": 3, "count": 1}))
	sim.submit(SimCommand.new(sim.get_tick() + 1, &"item.spawn", {"kind": "tool", "template": "no_such_tool", "container": inv, "seed": 4, "count": 1}))
	sim.step()
	assert_eq(sim.rejected_count(), 1, "the unknown template is refused")
	assert_eq(SimAssembly.items_of(sim).items_in(ItemSystem.inventory_of(player)).size(), 1, "one tool carried")


func test_assembly_refuses_a_tool_with_an_unknown_class_or_stat() -> void:
	for bad: Dictionary in [
		{"schema_version": 1, "description": "x", "tool_class": "no_class", "tags": [], "stats": []},
		{"schema_version": 1, "description": "x", "tool_class": "cutter", "tags": [], "stats": [{"stat": "no_stat", "value": 1}]},
	]:
		var db: ContentDb = _content()
		assert_eq(db.add(ItemSystem.KIND_TOOL, &"zz_bad", bad), OK, "the db takes the shape")
		assert_true(SimAssembly.build(SEED, db) == null, "assembly refuses %s" % [bad])
