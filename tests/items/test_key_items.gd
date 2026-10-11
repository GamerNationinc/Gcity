extends GcityTest

## M6 spec claim 10: an item template may carry a credential tag. Key items are the
## kind for such things: spawned like any item, carried by tag, kept across a restore.
## M6 ships `cold_storage_keycard`, the tag the Cold Storage front door's lock names.

const SEED: int = 20261032

var _sim: SimRoot
var _items: ItemSystem


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_items = SimAssembly.items_of(_sim)


func test_the_keycard_is_a_carried_credential() -> void:
	_setup()
	var a: int = SimAssembly.actors_of(_sim).spawn(&"arcade", 0)
	assert_false(_items.carries_tag(a, &"cold_storage_keycard"), "not before it is held")
	var before: int = _sim.dispatched_count()
	_sim.submit(SimCommand.new(1, &"item.spawn", {"kind": "key_item", "template": "cold_storage_keycard", "container": String(ItemSystem.inventory_of(a)), "seed": 1, "count": 1}))
	_sim.step()
	assert_eq(_sim.dispatched_count(), before + 1, "item.spawn accepts the key_item kind")
	var held: Array[int] = _items.items_in(ItemSystem.inventory_of(a))
	assert_eq(held.size(), 1, "one card")
	assert_eq(_items.item_kind(held[0]), &"key_item", "its kind")
	assert_true(_items.carries_tag(a, &"cold_storage_keycard"), "the lock's tag is carried")
	assert_true(_items.carries_tag(a, &"credential"), "and it is a credential")
	assert_eq(_items.tool_class_of(held[0]), &"", "it is no tool")


func test_a_key_item_survives_the_restore() -> void:
	_setup()
	var card: int = _items.spawn(&"key_item", &"cold_storage_keycard", &"world", 1)
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	var other: SimRoot = SimAssembly.build(SEED, db)
	assert_eq(SimAssembly.items_of(other).restore(_items.snapshot()), OK, "restores")
	assert_eq(SimAssembly.items_of(other).item_template(card), &"cold_storage_keycard", "kept")
