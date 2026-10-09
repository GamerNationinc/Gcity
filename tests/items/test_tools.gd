extends GcityTest

## M6 spec claim 4: tools are items. A tool is spawned like any item, carries its tags,
## and answers which tool class it breaches with; nothing else does.

const SEED: int = 20261017

var _sim: SimRoot
var _items: ItemSystem


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_items = SimAssembly.items_of(_sim)


func test_a_tool_is_an_item_with_a_tool_class() -> void:
	_setup()
	var a: int = SimAssembly.actors_of(_sim).spawn(&"arcade", 0)
	var cutter: int = _items.spawn(&"tool", &"plasma_cutter", ItemSystem.inventory_of(a), 1)
	assert_true(cutter > 0, "spawned")
	assert_eq(_items.item_kind(cutter), &"tool", "its kind")
	assert_eq(_items.tool_class_of(cutter), &"cutter", "breaches as a cutter")
	assert_true(_items.carries_tag(a, &"tool.cutter"), "tagged")
	var round: int = _items.spawn(&"ammo", &"9x19_fmj", ItemSystem.inventory_of(a), 2)
	assert_eq(_items.tool_class_of(round), &"", "a round is no tool")
	assert_eq(_items.tool_class_of(999), &"", "nor is nothing")


func test_tools_survive_the_restore() -> void:
	_setup()
	var cutter: int = _items.spawn(&"tool", &"breaching_kit", &"world", 1)
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.items_of(other).restore(_items.snapshot()), OK, "restores")
	assert_eq(SimAssembly.items_of(other).tool_class_of(cutter), &"breacher", "kept")
