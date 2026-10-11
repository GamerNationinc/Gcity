## The one context button (M6 spec claim 19): what pressing it would do where the
## player stands, facing `facing` ("px", "nx", "pz" or "nz"), as {"label", "kind",
## "payload"}, or {} for nothing. In order: the fixer in reach (take the contract, or
## deliver it), a body, pile or crate in reach with something in it (take the first
## thing), the face ahead, then the floor underfoot (cut it with a wielded tool, else
## open or close an opening: a grate or hatch below), something to climb here or ahead. Reads the sim only; the caller submits.
class_name Interact extends RefCounted

const UP: Vector3i = Vector3i(0, 1, 0)


static func choose(sim: SimRoot, player: int, facing: String) -> Dictionary:
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	if not actors.is_alive(player):
		return {}
	var choice: Dictionary = _fixer(sim, player)
	if choice.is_empty():
		choice = _take(sim, player)
	if choice.is_empty():
		choice = _ahead(sim, player, facing)
	if choice.is_empty():
		choice = _ahead(sim, player, "ny")
	if choice.is_empty():
		choice = _climb(sim, player, facing)
	return choice


static func _name(id: StringName) -> String:
	return String(id).replace("_", " ")


static func _fixer(sim: SimRoot, player: int) -> Dictionary:
	var content: ContentDb = sim.get_system(&"content")
	var quests: QuestSystem = SimAssembly.quests_of(sim)
	for fixer: StringName in content.ids(QuestSystem.KIND_FIXER):
		if not quests.near_fixer(player, fixer):
			continue
		var f: Dictionary = content.get_entry(QuestSystem.KIND_FIXER, fixer)
		var who: String = f["name"]
		for quest: StringName in quests.quest_ids():
			var t: Dictionary = content.get_entry(QuestSystem.KIND_QUEST, quest)
			var giver_v: Variant = t.get("giver", "")
			var giver: String = giver_v if typeof(giver_v) == TYPE_STRING else ""
			if giver != String(fixer):
				continue
			var status: String = quests.status_of(player, quest)
			if status.is_empty():
				return {"label": "take %s's contract: %s" % [who, t["title"]], "kind": QuestSystem.COMMAND_ACCEPT, "payload": {"actor": player, "quest": String(quest)}}
			var run: Dictionary = quests.run_of(player, quest)
			var deliver: String = t["deliver"]
			if status == QuestSystem.STATUS_ACTIVE and not run.is_empty() and run["exfil"] and _carried(sim, player, StringName(deliver)):
				return {"label": "deliver %s to %s" % [_name(StringName(deliver)), who], "kind": QuestSystem.COMMAND_DELIVER, "payload": {"actor": player, "quest": String(quest)}}
	return {}


static func _carried(sim: SimRoot, player: int, template: StringName) -> bool:
	var items: ItemSystem = SimAssembly.items_of(sim)
	for id: int in items.items_in(ItemSystem.inventory_of(player)):
		if items.item_template(id) == template:
			return true
	return false


static func _take(sim: SimRoot, player: int) -> Dictionary:
	var corpses: CorpseSystem = SimAssembly.corpses_of(sim)
	var items: ItemSystem = SimAssembly.items_of(sim)
	for place: StringName in corpses.place_ids():
		if not corpses.in_reach(player, place):
			continue
		var held: Array[int] = items.items_in(place)
		if held.is_empty():
			continue
		var what: String = String(place).get_slice(".", 0)
		return {"label": "take %s from the %s" % [_name(items.item_template(held[0])), "body" if what == "corpse" else what], "kind": CorpseSystem.COMMAND_TAKE, "payload": {"actor": player, "from": String(place), "item": held[0]}}
	return {}


static func _ahead(sim: SimRoot, player: int, facing: String) -> Dictionary:
	var build: BuildSystem = SimAssembly.build_of(sim)
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var items: ItemSystem = SimAssembly.items_of(sim)
	var here: Vector3i = BuildSystem.cell_of(actors.position_of(player))
	var id: int = build.face_piece_at(BuildSystem.face_key(here, facing))
	if id == EntityIds.NONE:
		return {}
	var name: String = _name(build.template_of(id))
	var opening: bool = build.is_opening(id)
	if facing == "ny" and not opening:
		return {}  # underfoot, only a grate or hatch is offered: not every floor
	var wielded: int = actors.wielded(player)
	if wielded != EntityIds.NONE and items.item_kind(wielded) == ItemSystem.KIND_TOOL and not (opening and build.is_open(id)):
		return {"label": "cut %s with the %s" % [name, _name(items.item_template(wielded))], "kind": BuildSystem.COMMAND_BREACH, "payload": {"actor": player, "piece": id}}
	if not opening:
		return {}
	if build.is_open(id):
		return {"label": "close %s" % name, "kind": BuildSystem.COMMAND_CLOSE, "payload": {"actor": player, "piece": id}}
	return {"label": "open %s" % name, "kind": BuildSystem.COMMAND_OPEN, "payload": {"actor": player, "piece": id}}


static func _climb(sim: SimRoot, player: int, facing: String) -> Dictionary:
	var build: BuildSystem = SimAssembly.build_of(sim)
	var movement: MovementSystem = SimAssembly.movement_of(sim)
	var here: Vector3i = BuildSystem.cell_of(SimAssembly.actors_of(sim).position_of(player))
	var ahead: Vector3i = here + _step(facing)
	var candidates: Array[int] = [build.cell_piece_at(ahead), build.cell_piece_at(here - UP), build.cell_piece_at(here),
		build.face_piece_at(BuildSystem.face_key(here, "py")), build.face_piece_at(BuildSystem.face_key(here, "ny"))]
	for id: int in candidates:
		if id != EntityIds.NONE and not movement.climb_destination(here, id).is_empty():
			return {"label": "climb %s" % _name(build.template_of(id)), "kind": MovementSystem.COMMAND_CLIMB, "payload": {"actor": player, "piece": id}}
	return {}


static func _step(facing: String) -> Vector3i:
	match facing:
		"px":
			return Vector3i(1, 0, 0)
		"nx":
			return Vector3i(-1, 0, 0)
		"pz":
			return Vector3i(0, 0, 1)
	return Vector3i(0, 0, -1)
