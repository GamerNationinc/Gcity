extends GcityTest

## M6 spec claim 19: interacting is one context button that names its target. The
## client picks, in order: the fixer in reach (take the contract, or deliver), a body,
## pile or crate in reach with something in it (take), the face ahead (cut it with a
## wielded tool, else open or close it), something to climb; and the command it names
## is one the sim accepts.

const SEED: int = 20261190
const O: Vector3i = Vector3i(40, 0, 0)

var _sim: SimRoot
var _actors: ActorSystem
var _player: int = 0


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	_sim = SimAssembly.build(SEED, db)
	_actors = SimAssembly.actors_of(_sim)
	assert_true(SimAssembly.sites_of(_sim).spawn(&"cold_storage", O), "Cold Storage")
	_player = _actors.spawn(&"arcade", 0)


func _stand(cell: Vector3i) -> void:
	_actors.set_position(_player, BuildSystem.cell_centre(cell) - Vector3i(0, BuildSystem.CELL / 2, 0))


## Runs the chosen command and reports whether the sim accepted it.
func _accepted(choice: Dictionary) -> bool:
	var kind: StringName = choice["kind"]
	var payload: Dictionary = choice["payload"]
	var before: int = _sim.dispatched_count()
	assert_eq(_sim.submit(SimCommand.new(_sim.get_tick() + 1, kind, payload)), OK, "submit")
	_sim.step()
	return _sim.dispatched_count() > before


func test_at_the_fixer_the_button_takes_the_contract() -> void:
	_setup()
	_stand(Vector3i(14, 0, -3))
	var choice: Dictionary = Interact.choose(_sim, _player, "pz")
	assert_eq(choice.get("kind"), QuestSystem.COMMAND_ACCEPT, "accept")
	assert_true(_label(choice).contains("Marlow"), "named: %s" % choice.get("label"))
	assert_true(_accepted(choice), "the sim takes it")
	assert_eq(Interact.choose(_sim, _player, "pz"), {}, "an open contract with nothing to deliver offers nothing here")


func test_at_the_yard_crate_the_button_takes_the_keycard() -> void:
	_setup()
	_stand(O + Vector3i(10, 0, 1))
	var choice: Dictionary = Interact.choose(_sim, _player, "nx")
	assert_eq(choice.get("kind"), CorpseSystem.COMMAND_TAKE, "take")
	assert_true(_label(choice).contains("cold storage keycard") and _label(choice).contains("crate"), "named: %s" % choice.get("label"))
	assert_true(_accepted(choice), "the sim takes it")
	assert_true(SimAssembly.items_of(_sim).carries_tag(_player, &"cold_storage_keycard") or _carries(&"cold_storage_keycard"), "carried")


func _label(choice: Dictionary) -> String:
	var label: String = choice.get("label", "")
	return label


func _carries(template: StringName) -> bool:
	var items: ItemSystem = SimAssembly.items_of(_sim)
	for id: int in items.items_in(ItemSystem.inventory_of(_player)):
		if items.item_template(id) == template:
			return true
	return false


func test_facing_a_door_the_button_opens_it_and_a_cutter_cuts_it() -> void:
	_setup()
	_stand(O + Vector3i(2, 0, -1))
	var choice: Dictionary = Interact.choose(_sim, _player, "pz")
	assert_eq(choice.get("kind"), BuildSystem.COMMAND_OPEN, "facing the front door: open")
	assert_true(_label(choice).begins_with("open cold storage door"), "named: %s" % choice.get("label"))
	assert_eq(Interact.choose(_sim, _player, "nz"), {}, "facing the street: nothing")
	var cutter: int = SimAssembly.items_of(_sim).spawn(&"tool", &"plasma_cutter", ItemSystem.inventory_of(_player), 1)
	assert_true(_accepted({"kind": &"actor.wield", "payload": {"actor": _player, "weapon": cutter}}), "wielded")
	choice = Interact.choose(_sim, _player, "pz")
	assert_eq(choice.get("kind"), BuildSystem.COMMAND_BREACH, "with a cutter, the door is cut")
	assert_true(_label(choice).begins_with("cut cold storage door"), "named: %s" % choice.get("label"))
	assert_true(_accepted(choice), "the sim takes it")


func test_at_the_stairs_the_button_climbs() -> void:
	_setup()
	_stand(O + Vector3i(9, 0, 5))
	var choice: Dictionary = Interact.choose(_sim, _player, "pz")
	assert_eq(choice.get("kind"), MovementSystem.COMMAND_CLIMB, "climb")
	assert_true(_label(choice).begins_with("climb"), "named: %s" % choice.get("label"))
	assert_true(_accepted(choice), "the sim takes it")


func test_nothing_in_reach_offers_nothing() -> void:
	_setup()
	_stand(Vector3i(0, 0, 30))
	assert_eq(Interact.choose(_sim, _player, "pz"), {}, "nothing")
