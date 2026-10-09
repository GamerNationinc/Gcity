extends GcityTest

## M6 spec claim 3 (locks) and 10 (credentials): an actor carries a tag when an item
## directly in its inventory has it. Only the inventory counts: a tag on a round inside
## a magazine, or on a part in a socket, is not carried for this purpose.

const SEED: int = 20261014

var _sim: SimRoot
var _items: ItemSystem
var _actors: ActorSystem


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_items = SimAssembly.items_of(_sim)
	_actors = SimAssembly.actors_of(_sim)


func test_an_actor_carries_the_tags_of_the_items_in_its_inventory() -> void:
	_setup()
	var a: int = _actors.spawn(&"arcade", 0)
	var b: int = _actors.spawn(&"arcade", 1)
	assert_false(_items.carries_tag(a, &"ammo"), "an empty inventory carries nothing")
	var round: int = _items.spawn(&"ammo", &"9x19_fmj", ItemSystem.inventory_of(a), 1)
	assert_true(round > 0, "a round")
	assert_true(_items.carries_tag(a, &"ammo"), "the round's tag is carried")
	assert_false(_items.carries_tag(b, &"ammo"), "by its holder only")
	assert_false(_items.carries_tag(a, &"cold_storage_keycard"), "not a tag nobody has")
	assert_false(_items.carries_tag(99, &"ammo"), "nor by an unknown actor")


func test_a_tag_inside_a_magazine_is_not_carried() -> void:
	_setup()
	var a: int = _actors.spawn(&"arcade", 0)
	var inv: StringName = ItemSystem.inventory_of(a)
	var mag: int = _items.spawn(&"weapon_part", &"g19_mag_15", inv, 2)
	var round: int = _items.spawn(&"ammo", &"9x19_fmj", inv, 3)
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, &"magazine.load", {"actor": a, "magazine": mag, "round": round})), OK, "submit")
	_sim.step()
	assert_eq(_items.container_of(round), ItemSystem.magazine_container(mag), "the round is in the magazine")
	assert_false(_items.carries_tag(a, &"ammo"), "so its tag is not carried")
