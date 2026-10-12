## A playtest bot: the Cold Storage job by the front route, played through the real
## client (lib/job_bot.gd, lib/plan.gd): the keycard from the yard crate, the front door
## opened with it (the door camera's heat check), through the lobby past its post to
## the hall, up the stairs, the server room's hidden corner, the terminal hacked and
## logged out of, and out the way it came. It waits, as a careful player would, before
## each stretch past the guards; the verdict says whether anyone was alerted.
extends "res://tools/playtest/lib/job_bot.gd"


func _name() -> String:
	return "cold_storage_front"


## The route; cells are the site's, from its placement.
func _route(sim: SimRoot, player: int) -> Array:
	var o: Vector3i = SimAssembly.sites_of(sim).placement_of(&"cold_storage")
	var site: Callable = func(x: int, y: int, z: int) -> Vector3i: return o + Vector3i(x, y, z)
	var items: ItemSystem = SimAssembly.items_of(sim)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var coprocessor: int = EntityIds.NONE
	for id: int in items.items_in(ItemSystem.inventory_of(player)):
		if items.item_template(id) == &"daemon_coprocessor":
			coprocessor = id
	var plan: Array = [
		["kit", &"item.attach", {"actor": player, "weapon": actors.device_of(player), "part": coprocessor}],
		["wait", 3],
		["goto", MARLOW],
		["use", "pz", QuestSystem.COMMAND_ACCEPT],
		["goto", Vector3i(14, 0, -6)],
		["goto", site.call(11, 0, -6)],
		["goto", site.call(11, 0, 1)],
		["use", "nx", CorpseSystem.COMMAND_TAKE],  # the keycard
		["goto", site.call(11, 0, -6)],
		["goto", site.call(2, 0, -6)],
		["goto", site.call(2, 0, -1)],
	]
	var stretches: Array = [
		[  # the front door, the lobby, the hall to the stairs, up, and to the hide
			["use", "pz", BuildSystem.COMMAND_OPEN], ["wait", 3],
			["goto", site.call(2, 0, 1)], ["goto", site.call(3, 0, 1)], ["goto", site.call(5, 0, 1)],
			["goto", site.call(5, 0, 5)], ["goto", site.call(9, 0, 5)],
			["use", "pz", MovementSystem.COMMAND_CLIMB], ["settle"],
			["goto", site.call(9, 1, 5)], ["goto", site.call(9, 1, 4)], ["goto", site.call(7, 1, 4)],
			["goto", site.call(7, 1, 3)], ["goto", site.call(5, 1, 3)],
		],
		[
			["goto", site.call(7, 1, 3)], ["goto", site.call(7, 1, 4)], ["goto", site.call(5, 1, 4)],
			["goto", site.call(5, 1, 5)], ["goto", site.call(4, 1, 5)], ["goto", site.call(4, 1, 7)],
			["goto", site.call(2, 1, 7)],
		],
		[["hack"]],
		[
			["goto", site.call(4, 1, 7)], ["goto", site.call(4, 1, 5)], ["goto", site.call(5, 1, 5)],
			["goto", site.call(5, 1, 4)], ["goto", site.call(7, 1, 4)], ["goto", site.call(7, 1, 3)],
			["goto", site.call(5, 1, 3)],
		],
		[  # down the stairs, back through the hall and the lobby, out of the front door
			["goto", site.call(7, 1, 3)], ["goto", site.call(7, 1, 4)], ["goto", site.call(9, 1, 4)],
			["goto", site.call(9, 1, 6)],
			["use", "pz", MovementSystem.COMMAND_CLIMB], ["settle"],
			["goto", site.call(9, 0, 5)], ["goto", site.call(5, 0, 5)], ["goto", site.call(5, 0, 1)],
			["goto", site.call(3, 0, 1)], ["goto", site.call(2, 0, 1)], ["goto", site.call(2, 0, -1)],
		],
	]
	for stretch: Array in stretches:
		plan.append(["sneak", stretch])
		plan.append_array(stretch)
	plan.append_array([
		["goto", site.call(2, 0, -6)],
		["goto", Vector3i(14, 0, -6)],
		["goto", Vector3i(14, 0, -2)],
		["use", "nz", QuestSystem.COMMAND_DELIVER],
		["wait", 40],
	])
	return plan
