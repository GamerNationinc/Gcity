## Readying a firearm from what you carry, in one press (CEOGG's 2026-10-05 sandbox run:
## "no reload button for the firearm automatically if it's in inventory ... can't load
## and fire"). The best fitting magazine you carry is filled from your loose rounds and
## swapped in, which chambers a round. Only item commands the M5 inventory already sends
## (`magazine.load`, `weapon.reload_tactical`), so the sim, saves and replays are unchanged.
class_name WeaponReady extends RefCounted


## The first firearm `actor` carries, or 0.
static func first_firearm(items: ItemSystem, actor: int) -> int:
	for id: int in items.items_in(ItemSystem.inventory_of(actor)):
		if items.item_kind(id) == ItemSystem.KIND_FRAME:
			return id
	return EntityIds.NONE


## {"commands": [[kind, payload], ...], "say": what happened or why not}. No commands
## when there is nothing to do: the weapon is already loaded, or nothing fits it.
static func plan(sim: SimRoot, actor: int, weapon: int) -> Dictionary:
	var items: ItemSystem = SimAssembly.items_of(sim)
	var content: ContentDb = sim.get_system(&"content")
	var name: String = String(items.item_template(weapon))
	var frame: Dictionary = content.get_entry(ItemSystem.KIND_FRAME, items.item_template(weapon))
	var calibre: String = frame["calibre"]
	var socket: StringName = items.magazine_socket_of(weapon)
	var in_gun: int = items.magazine_of(weapon)
	var room_in_gun: bool = in_gun == EntityIds.NONE or items.rounds_in(in_gun).size() < items.capacity_of(ItemSystem.magazine_container(in_gun))
	# the fitting magazine you carry with the most rounds
	var best: int = EntityIds.NONE
	var best_rounds: int = -1
	var loose: Array[int] = []
	for id: int in items.items_in(ItemSystem.inventory_of(actor)):
		var kind: StringName = items.item_kind(id)
		if kind == ItemSystem.KIND_AMMO:
			var round_t: Dictionary = content.get_entry(kind, items.item_template(id))
			if round_t["calibre"] == calibre:
				loose.append(id)
		elif kind == ItemSystem.KIND_PART and items.capacity_of(ItemSystem.magazine_container(id)) > 0:
			var mag_t: Dictionary = content.get_entry(kind, items.item_template(id))
			var mag_socket: String = mag_t["socket"]
			var fits: Array = mag_t["fits"]
			if mag_t["calibre"] == calibre and StringName(mag_socket) == socket and fits.has(name) and items.rounds_in(id).size() > best_rounds:
				best = id
				best_rounds = items.rounds_in(id).size()
	if best == EntityIds.NONE:
		if in_gun != EntityIds.NONE and not items.rounds_in(in_gun).is_empty():
			return {"commands": [], "say": "%s: no spare magazine; %d in this one" % [name, items.rounds_in(in_gun).size()]}
		return {"commands": [], "say": "%s: no magazine for it in your pockets (the Spawn app's items page has one)" % name}
	var commands: Array = []
	var room: int = items.capacity_of(ItemSystem.magazine_container(best)) - best_rounds
	var loading: int = mini(room, loose.size())
	for i: int in loading:
		commands.append([&"magazine.load", {"actor": actor, "magazine": best, "round": loose[i]}])
	var total: int = best_rounds + loading
	if total == 0:
		return {"commands": [], "say": "%s: no %s rounds to load (the Spawn app's items page has some)" % [name, calibre]}
	if items.chambered(weapon) != EntityIds.NONE and not room_in_gun and loading == 0:
		return {"commands": [], "say": "%s is loaded" % name}
	commands.append([&"weapon.reload_tactical", {"actor": actor, "weapon": weapon, "magazine": best}])
	return {"commands": commands, "say": "%s: %s%d-round magazine in, round chambered" % [name, "loaded %d rounds, " % loading if loading > 0 else "", total]}


## Why a pull of the trigger at `tick` would be refused while the gun is busy, or "":
## after the 18:18 run four pulls during a reload were refused with nothing said.
static func busy_reason(items: ItemSystem, weapon: int, tick: int, reloading: bool) -> String:
	if not items.is_busy(weapon, tick):
		return ""
	var left: float = float(items.busy_until(weapon) - tick) / float(SimRoot.TICK_HZ)
	return "%s: %s, %.1f s" % [items.item_template(weapon), "reloading" if reloading else "cycling", left]

