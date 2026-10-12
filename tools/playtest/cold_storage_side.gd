## A playtest bot: the Cold Storage job by the side route (the m6-side fixture's, then
## on to the terminal), played through the real client (lib/job_bot.gd, lib/plan.gd):
## the junction box in the yard hacked from the hacking pane so the window's power
## monitor sees a steady circuit, onto the yard crate (the context button's mantle),
## the window cut with a plasma cutter, in to the maintenance room, the server room's
## hidden corner, the terminal hacked and logged out of, back out of the window, a drop
## to the yard, off the site and delivered.
extends "res://tools/playtest/lib/job_bot.gd"


func _name() -> String:
	return "cold_storage_side"


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
	var inv: String = String(ItemSystem.inventory_of(player))
	var plan: Array = [
		["kit", &"item.attach", {"actor": player, "weapon": actors.device_of(player), "part": coprocessor}],
		["kit", &"item.spawn", {"kind": "tool", "template": "plasma_cutter", "container": inv, "seed": 9001, "count": 1}],
		["wait", 3],
		["wield", &"plasma_cutter"],
		["wait", 3],
		["goto", MARLOW],
		["use", "pz", QuestSystem.COMMAND_ACCEPT],
		["goto", Vector3i(14, 0, -6)],
		["goto", site.call(11, 0, -6)],
		["goto", site.call(11, 0, 1)],
		["hack_in"],  # the junction box: the monitor now sees a steady circuit
		["use", "nx", CorpseSystem.COMMAND_TAKE],  # the yard crate's keycard: the button offers it first
	]
	var stretches: Array = [
		[  # onto the crate, the window cut, in, and to the maintenance room's hide
			["use", "nx", MovementSystem.COMMAND_MANTLE], ["settle"],
			["use", "nx", BuildSystem.COMMAND_BREACH], ["cut"],
			["goto", site.call(9, 1, 1)], ["goto", site.call(5, 1, 1)], ["goto", site.call(5, 1, 3)],
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
		[  # out of the window, over the crate and down to the yard
			["goto", site.call(5, 1, 1)], ["goto", site.call(9, 1, 1)], ["goto", site.call(10, 1, 1)],
			["goto", site.call(11, 0, 1)], ["settle"],
		],
	]
	for stretch: Array in stretches:
		plan.append(["sneak", stretch])
		plan.append_array(stretch)
	plan.append_array([
		["logout"],  # the junction box: no terminal left logged in
		["goto", site.call(11, 0, -6)],
		["goto", Vector3i(14, 0, -6)],
		["goto", Vector3i(14, 0, -2)],
		["use", "nz", QuestSystem.COMMAND_DELIVER],
		["wait", 40],
	])
	return plan
