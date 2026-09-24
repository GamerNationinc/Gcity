## What a contract asks for instead of naming a place (M7 spec claim 8).
##
## Before this, a quest that happened somewhere had to say where, which meant every
## mission was authored against one building at one set of coordinates. A quest now
## carries a **handle**: what the site has to be good for, roughly how far out it is,
## and whether it has to be somewhere the player has not already found. The director
## turns that into an actual place when the contract is accepted (claim 9); the quest
## itself never knows which one, which is what lets the same contract be offered in a
## world it was not written for.
##
## The language is deliberately four fields and no more. A constraint solver is not the
## feature — a fixer saying "an old industrial place, eight to fifteen kilometres out,
## somewhere you haven't been" is.
##
## Nothing here holds state or picks anything. It reads the constraint and answers
## whether a slot satisfies it; which of the satisfying slots gets used, and the record
## that it was, belong to the binder.
class_name SiteConstraint extends RefCounted

const BLOCK: String = "site"


## A quest's site constraint, or empty for a contract that happens wherever it happens.
static func of_quest(content: ContentDb, quest: StringName) -> Dictionary:
	if not content.has(QuestSystem.KIND_QUEST, quest):
		return {}
	var entry: Dictionary = content.get_entry(QuestSystem.KIND_QUEST, quest)
	if not entry.has(BLOCK):
		return {}
	var block: Dictionary = entry[BLOCK]
	return block


## True when a slot is somewhere this contract could happen.
##
## `discovered` is the set of slots the player has already found, which the caller
## owns: this reads it and never writes it, so the same question can be asked of a
## hypothetical as easily as of the save.
static func matches(constraint: Dictionary, content: ContentDb, routes: RouteGraph, slot: int, discovered: Dictionary) -> bool:
	if constraint.is_empty():
		# a contract that asks for nothing is happy anywhere that is a place at all
		return routes.has_slot(slot)
	if not routes.has_slot(slot):
		return false
	var undiscovered: bool = constraint["undiscovered"]
	if undiscovered and discovered.has(slot):
		return false
	var metres: int = routes.slot_metres_from_gate(slot)
	var min_km: int = constraint["min_km"]
	var max_km: int = constraint["max_km"]
	if metres < min_km * 1000 or metres > max_km * 1000:
		return false
	var tags: Array[StringName] = SiteTags.of_slot(content, routes, slot)
	var wanted: Array = constraint["tags_any"]
	for v: Variant in wanted:
		var tag: String = v
		if tags.has(StringName(tag)):
			return true
	return false


## Every slot in a world this contract could happen at, lowest first. The order is the
## graph's, so it is the same everywhere; which one is chosen is the binder's business.
static func slots_matching(constraint: Dictionary, content: ContentDb, routes: RouteGraph, discovered: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for slot: int in routes.slot_ids():
		if matches(constraint, content, routes, slot, discovered):
			out.append(slot)
	return out


## Every constraint asks for something a world could offer. A contract whose range is
## backwards can never bind, and the symptom would be a fixer with a job nobody can
## take and nothing saying why.
static func validate(content: ContentDb) -> Error:
	for quest: StringName in content.ids(QuestSystem.KIND_QUEST):
		var constraint: Dictionary = of_quest(content, quest)
		if constraint.is_empty():
			continue
		var min_km: int = constraint["min_km"]
		var max_km: int = constraint["max_km"]
		if min_km > max_km:
			push_error("quest/%s asks for a site between %d and %d km out" % [quest, min_km, max_km])
			return ERR_INVALID_DATA
		var wanted: Array = constraint["tags_any"]
		if wanted.is_empty():
			push_error("quest/%s asks for a site that is good for nothing in particular" % quest)
			return ERR_INVALID_DATA
	return OK
