## Site binding (M7 spec claim 9; design doc §5.3). **A contract's handle becomes a
## place once, when it is accepted, and never again.**
##
## A quest names what it needs ([SiteConstraint]); this picks which of the slots that
## satisfy it is the one, stitches a site onto the graph there, and writes the choice
## down. The choice is a function of the world seed, the quest and the slots already
## taken — not of the sim's shared RNG, so it cannot move because some other system drew
## first, and not of the tick, so it cannot move because the contract was taken a
## minute later.
##
## Permanent means permanent: abandoning a contract does not release its place, and
## taking it again returns to the same one. The same save always has the same place,
## which is the whole claim. A bound slot is never offered to a second contract.
##
## The bindings are the overlay a save carries on top of the seed (design doc §5.6): the
## list of which quest bound which slot, in the order they were bound. The site nodes
## are not stored — they are stitched again from that list on restore, and come back
## under the same ids because the order is the same.
class_name SiteBinder extends SimSystem

const SYSTEM_ID: StringName = &"bindings"

var _content: ContentDb
var _routes: RouteGraph
## [[quest id: String, slot: int], ...] in the order they were bound
var _bound: Array = []
## () -> {slot: true} for every slot whose place the player has found (claim 15),
## wired by the assembly to Discovery. Unset, nowhere has been found.
var _found: Callable = Callable()


func _init(content: ContentDb, routes: RouteGraph) -> void:
	_content = content
	_routes = routes


func set_found_check(found: Callable) -> void:
	_found = found


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


func snapshot() -> Dictionary:
	return {"bound": _bound.duplicate(true)}


func attach(sim: SimRoot) -> Error:
	return sim.register_system(self)


# ---------------------------------------------------------------- binding

## Binds a quest's handle to a slot and returns it: the slot it was already bound to if
## it has been, a newly chosen one otherwise, or NONE if the quest names no site or the
## world has nowhere left that will do.
func bind(quest: StringName) -> int:
	var already: int = slot_of(quest)
	if already != EntityIds.NONE:
		return already
	var constraint: Dictionary = SiteConstraint.of_quest(_content, quest)
	if constraint.is_empty():
		return EntityIds.NONE
	var found: Dictionary = {}
	if _found.is_valid():
		found = _found.call()
	var slot: int = pick(constraint, _content, _routes, _taken(), quest, found)
	if slot == EntityIds.NONE:
		return EntityIds.NONE
	_routes.stitch_slot(slot)
	_bound.append([String(quest), slot])
	return slot


## Which slot a contract with this constraint gets, given the slots already taken: one
## of the free matching slots, indexed by a hash of the world seed and the quest. Static
## and free of state so the property can ask it ten thousand times without a sim.
##
## The quest is in the hash so that two contracts asking for the same kind of place do
## not both start from the same end of the list; the seed is, so that the same contract
## lands somewhere different in a different world.
static func pick(constraint: Dictionary, content: ContentDb, routes: RouteGraph, taken: Dictionary, quest: StringName, found: Dictionary = {}) -> int:
	var free: Array[int] = []
	for slot: int in SiteConstraint.slots_matching(constraint, content, routes, found):
		if not taken.has(slot):
			free.append(slot)
	if free.is_empty():
		return EntityIds.NONE
	var digest: String = StateHash.of([routes.world_seed(), String(quest)])
	# fifteen hex digits is sixty bits: positive in a signed int whatever they are
	return free[digest.left(15).hex_to_int() % free.size()]


# ---------------------------------------------------------------- queries

## The slot a quest is bound to, or NONE.
func slot_of(quest: StringName) -> int:
	for v: Variant in _bound:
		var row: Array = v
		var id: String = row[0]
		if StringName(id) == quest:
			return row[1]
	return EntityIds.NONE


## The site node on the graph for a quest's place, or NONE if it is not bound.
func node_of(quest: StringName) -> int:
	var slot: int = slot_of(quest)
	if slot == EntityIds.NONE:
		return EntityIds.NONE
	return _routes.site_node_of(slot)


func is_bound(slot: int) -> bool:
	return _taken().has(slot)


## Quests with a place, in the order they got one.
func bound_quests() -> Array[StringName]:
	var out: Array[StringName] = []
	for v: Variant in _bound:
		var row: Array = v
		var id: String = row[0]
		out.append(StringName(id))
	return out


func _taken() -> Dictionary:
	var out: Dictionary = {}
	for v: Variant in _bound:
		var row: Array = v
		var slot: int = row[1]
		out[slot] = true
	return out


# ---------------------------------------------------------------- restore

## Everything is checked before anything is touched: a rejected save leaves the bindings
## and the graph as they were.
func restore(state: Dictionary) -> Error:
	if state.size() != 1 or typeof(state.get("bound")) != TYPE_ARRAY:
		return _restore_fail("shape")
	var rows: Array = state["bound"]
	var quests: Dictionary = {}
	var slots: Dictionary = {}
	var out: Array = []
	for v: Variant in rows:
		if typeof(v) != TYPE_ARRAY:
			return _restore_fail("binding row")
		var row: Array = v
		if row.size() != 2 or (typeof(row[0]) != TYPE_STRING and typeof(row[0]) != TYPE_STRING_NAME) or typeof(row[1]) != TYPE_INT:
			return _restore_fail("binding row")
		var quest: StringName = StringName(str(row[0]))
		var slot: int = row[1]
		var constraint: Dictionary = SiteConstraint.of_quest(_content, quest)
		if constraint.is_empty():
			return _restore_fail("quest %s names no site" % quest)
		if quests.has(quest):
			return _restore_fail("quest %s is bound twice" % quest)
		if slots.has(slot):
			return _restore_fail("slot %d is bound twice" % slot)
		# checked against nothing found: a place found since it was bound was not found
		# when it was, and the binding stands
		if not SiteConstraint.matches(constraint, _content, _routes, slot, {}):
			return _restore_fail("slot %d is not a place quest %s could have bound" % [slot, quest])
		quests[quest] = true
		slots[slot] = true
		out.append([String(quest), slot])
	_routes.unstitch_all()
	for v: Variant in out:
		var row: Array = v
		var slot: int = row[1]
		_routes.stitch_slot(slot)
	_bound = out
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("SiteBinder.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
