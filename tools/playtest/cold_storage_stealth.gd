## A playtest bot: the Cold Storage job by the under route (the m6-stealth fixture's),
## played through the real client (lib/job_bot.gd, lib/plan.gd): the maintenance key,
## both grates unlocked, the basement, a wait in the maintenance room, the server
## room's hidden corner, the hack and logout, back and out by the tunnel's hatch.
extends "res://tools/playtest/lib/job_bot.gd"


func _name() -> String:
	return "cold_storage_stealth"


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
		["goto", Vector3i(14, 0, -4)],  # a row north of the utility box's
		["goto", site.call(-1, 0, -4)],
		["use", "pz", CorpseSystem.COMMAND_TAKE],
		["goto", site.call(1, 0, -4)],
		["goto", site.call(1, 0, -3)],
		["use", "pz", BuildSystem.COMMAND_OPEN],
		["wait", 30],
		["goto", site.call(4, -1, -3)],
		["goto", site.call(4, -1, -1)],
		["use", "pz", BuildSystem.COMMAND_OPEN],
		["goto", site.call(4, -1, 1)],
		["goto", site.call(3, -1, 1)],
		["goto", site.call(3, -1, 4)],
		["goto", site.call(7, -1, 4)],
	]
	var stretches: Array = [
		[  # up the two stairs into the maintenance room, beside its door
			["use", "pz", MovementSystem.COMMAND_CLIMB], ["settle"],
			["goto", site.call(9, 0, 5)],
			["use", "pz", MovementSystem.COMMAND_CLIMB], ["settle"],
			["goto", site.call(9, 1, 5)], ["goto", site.call(9, 1, 4)], ["goto", site.call(7, 1, 4)],
			["goto", site.call(7, 1, 3)], ["goto", site.call(5, 1, 3)],
		],
		[  # across the hall into the server room's corner no doorway sees
			["goto", site.call(7, 1, 3)], ["goto", site.call(7, 1, 4)], ["goto", site.call(5, 1, 4)],
			["goto", site.call(5, 1, 5)], ["goto", site.call(4, 1, 5)], ["goto", site.call(4, 1, 7)],
			["goto", site.call(2, 1, 7)],
		],
		[["hack"]],
		[  # back to the maintenance room
			["goto", site.call(4, 1, 7)], ["goto", site.call(4, 1, 5)], ["goto", site.call(5, 1, 5)],
			["goto", site.call(5, 1, 4)], ["goto", site.call(7, 1, 4)], ["goto", site.call(7, 1, 3)],
			["goto", site.call(5, 1, 3)],
		],
		[  # down both stairs
			["goto", site.call(7, 1, 3)], ["goto", site.call(7, 1, 4)], ["goto", site.call(9, 1, 4)],
			["goto", site.call(9, 1, 6)],
			["use", "pz", MovementSystem.COMMAND_CLIMB], ["settle"],
			["goto", site.call(7, 0, 5)],
			["use", "pz", MovementSystem.COMMAND_CLIMB], ["settle"],
		],
		[  # through the basement to the tunnel's hatch
			["goto", site.call(3, -1, 4)], ["goto", site.call(3, -1, 1)], ["goto", site.call(4, -1, 1)],
			["goto", site.call(4, -1, -3)], ["goto", site.call(2, -1, -3)],
		],
	]
	for stretch: Array in stretches:
		plan.append(["sneak", stretch])
		plan.append_array(stretch)
	plan.append_array([
		["use", "nx", MovementSystem.COMMAND_CLIMB], ["settle"],
		["goto", site.call(2, 0, -7)],
		["goto", Vector3i(14, 0, -7)],
		["goto", Vector3i(14, 0, -2)],
		["use", "nz", QuestSystem.COMMAND_DELIVER],
		["wait", 40],
	])
	return plan


