## Authored sites (M6 spec claim 3; design doc §15, §16 M6): a `content/site/` entry
## is the build pieces a place stands on, the agents posted in it and the routes they
## walk, all relative to a base cell. `site.raise {actor, site}` raises one: it places
## every piece in the file's order (which the author keeps supportable) and spawns
## every agent, then records the site as raised so a save knows and a second raise is
## refused. Nothing here generates anything; procgen is M7.
class_name SiteSystem extends SimSystem

const SYSTEM_ID: StringName = &"sites"
const KIND_SITE: StringName = &"site"
const COMMAND_RAISE: StringName = &"site.raise"
const EVENT_RAISED: StringName = &"site.raised"

var _content: ContentDb
var _build: BuildSystem
var _perception: PerceptionSystem
var _actors: ActorSystem
var _events: EventBus
var _terminals: TerminalSystem
var _items: ItemSystem
## site id -> {"pieces": Array[int], "agents": Array[int], "terminals": Array[int],
## "base": [x, y, z]} — the base it was actually raised at, which is the content's own
## unless a contract bound it somewhere (M7 spec claim 10)
var _raised: Dictionary = {}
## The world a bound site is raised into (M7 spec claim 10), wired by the assembly.
var _routes: RouteGraph = null
var _regions: Regions = null
var _land: LandSystem = null
## (quest) -> the slot its handle is bound to, or NONE: the binder's, wired by the assembly
var _slot_of: Callable = Callable()
## How far round a bound site's pieces the ground is levelled, in cells: the street.
const LEVEL_MARGIN: int = 8
## How deep a bound site's lot is filled under it before the fill gives up, in cells.
const FILL_DEPTH: int = 40


func _init(content: ContentDb, build: BuildSystem, perception: PerceptionSystem, actors: ActorSystem, events: EventBus, terminals: TerminalSystem, items: ItemSystem) -> void:
	_content = content
	_build = build
	_perception = perception
	_actors = actors
	_events = events
	_terminals = terminals
	_items = items


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


func snapshot() -> Dictionary:
	return {"raised": _raised.duplicate(true)}


func attach(sim: SimRoot) -> Error:
	var err: Error = validate_content()
	if err != OK:
		return err
	err = sim.register_system(self)
	if err != OK:
		return err
	err = _events.subscribe(ActorSystem.EVENT_REMOVED, _on_removed)
	if err != OK:
		return err
	return sim.commands().register(COMMAND_RAISE, _on_raise)


## Every site names pieces, profiles and routes that exist, and no piece sits twice
## in the same cell and facing (a site that cannot raise itself fails assembly).
func validate_content() -> Error:
	for site: StringName in _content.ids(KIND_SITE):
		var t: Dictionary = _content.get_entry(KIND_SITE, site)
		var seen: Dictionary = {}
		var pieces: Array = t["pieces"]
		for p: Variant in pieces:
			var entry: Dictionary = p
			var facing: String = entry["facing"]
			var rel: Vector3i = PathingSystem._vec(entry["rel"])
			var key: String = "%s|%s" % [BuildSystem.cell_key(rel), facing]
			if seen.has(key):
				return _fail("site/%s places two pieces at %s" % [site, key])
			seen[key] = true
			var piece_s: String = entry["piece"]
			var piece_t: Dictionary = _content.get_entry(BuildSystem.KIND_PIECE, StringName(piece_s))
			var kind_s: String = piece_t["kind"]
			var kind: Dictionary = _content.get_entry(BuildSystem.KIND_PIECE_KIND, StringName(kind_s))
			var occupies: String = kind["occupies"]
			if occupies == "cell" and not facing.is_empty():
				return _fail("site/%s gives a cell piece a facing at %s" % [site, key])
			if occupies == "face" and facing.is_empty():
				return _fail("site/%s gives a face piece no facing at %s" % [site, key])
		var spawns: Array = t["spawns"]
		for s: Variant in spawns:
			var spawn: Dictionary = s
			var route_s: String = spawn["route"]
			if not route_s.is_empty() and not _content.has(PerceptionSystem.KIND_ROUTE, StringName(route_s)):
				return _fail("site/%s: no patrol_route/%s" % [site, route_s])
	return OK


func _fail(reason: String) -> Error:
	push_error("SiteSystem: %s" % reason)
	return ERR_INVALID_DATA


# ---------------------------------------------------------------- queries

func set_world(routes: RouteGraph, regions: Regions, land: LandSystem, slot_of: Callable) -> void:
	_routes = routes
	_regions = regions
	_land = land
	_slot_of = slot_of


func site_ids() -> Array[StringName]:
	return _content.ids(KIND_SITE)


func is_raised(site: StringName) -> bool:
	return _raised.has(site)


## The pieces a raised site placed, in placement order; empty if it is not raised.
func pieces_of(site: StringName) -> Array[int]:
	var out: Array[int] = []
	if not _raised.has(site):
		return out
	var rec: Dictionary = _raised[site]
	for v: Variant in rec["pieces"]:
		var id: int = v
		out.append(id)
	return out


## The terminals a raised site placed, in placement order.
func terminals_of(site: StringName) -> Array[int]:
	var out: Array[int] = []
	if not _raised.has(site):
		return out
	var rec: Dictionary = _raised[site]
	for v: Variant in rec["terminals"]:
		var id: int = v
		out.append(id)
	return out


func agents_of(site: StringName) -> Array[int]:
	var out: Array[int] = []
	if not _raised.has(site):
		return out
	var rec: Dictionary = _raised[site]
	for v: Variant in rec["agents"]:
		var id: int = v
		out.append(id)
	return out


## Where a site stands: where it was raised, or where its content puts it if it has not
## been raised yet.
func base_of(site: StringName) -> Vector3i:
	if _raised.has(site):
		var rec: Dictionary = _raised[site]
		return PathingSystem._vec(rec["base"])
	if not _content.has(KIND_SITE, site):
		return Vector3i.ZERO
	var t: Dictionary = _content.get_entry(KIND_SITE, site)
	return PathingSystem._vec(t["base"])


## The world cell of a site's relative cell.
func cell_of(site: StringName, rel: Vector3i) -> Vector3i:
	return base_of(site) + rel


# ---------------------------------------------------------------- raising

## Places every piece and spawns every agent. `actor` is the builder the pieces are
## placed as, so the land authority's rights apply exactly as they would to a player.
## Returns false without touching anything if the site is unknown or already raised.
##
## With a quest (M7 spec claim 10), the site is raised where that contract's handle is
## bound rather than where its content puts it: the building, its guards, its terminals
## and its lot all move together to the slot, on the ground there, and the ground round
## it is levelled first so the slab sits on something. Nothing in the site's content
## changes; only where it goes.
func raise_site(actor: int, site: StringName, quest: StringName = &"") -> bool:
	if not _content.has(KIND_SITE, site) or _raised.has(site) or not _actors.has_actor(actor):
		return false
	var t: Dictionary = _content.get_entry(KIND_SITE, site)
	var authored: Vector3i = PathingSystem._vec(t["base"])
	var base: Vector3i = authored
	if not quest.is_empty():
		if not _slot_of.is_valid():
			return false
		var slot: int = _slot_of.call(quest)
		if slot == EntityIds.NONE:
			return false
		var at: Vector2i = _routes.slot_position(slot)
		base = Vector3i(Terrain._floor_div(at.x, BuildSystem.CELL), _regions.standing_cell_y(at.x, at.y), Terrain._floor_div(at.y, BuildSystem.CELL))
		var offset: Vector3i = (base - authored) * BuildSystem.CELL
		var parcels: Array = t["parcels"]
		for v: Variant in parcels:
			var parcel_s: String = v
			if _land.move_parcel(StringName(parcel_s), offset) != OK:
				push_error("SiteSystem: could not move %s's lot %s to where its contract put it" % [site, parcel_s])
				return false
		_level(base, t)
	var placed: Array[int] = []
	var pieces: Array = t["pieces"]
	for p: Variant in pieces:
		var entry: Dictionary = p
		var rel: Vector3i = PathingSystem._vec(entry["rel"])
		var facing: String = entry["facing"]
		var piece_s: String = entry["piece"]
		var id: int = _build.place(actor, StringName(piece_s), BuildSystem.cell_centre(base + rel), facing)
		if id != EntityIds.NONE:
			placed.append(id)
	var agents: Array[int] = []
	var spawns: Array = t["spawns"]
	for s: Variant in spawns:
		var spawn: Dictionary = s
		var rel: Vector3i = PathingSystem._vec(spawn["rel"])
		var profile_s: String = spawn["profile"]
		var facing: int = spawn["facing"]
		var squad: int = spawn["squad"]
		var route: String = spawn["route"]
		var agent: int = _perception.spawn(StringName(profile_s), base + rel, facing, squad, route, "", base - authored)
		if agent != EntityIds.NONE:
			agents.append(agent)
			_hand_out_kit(agent, spawn)
	var terminals: Array[int] = []
	var terminal_entries: Array = t["terminals"]
	for e: Variant in terminal_entries:
		var entry: Dictionary = e
		var rel: Vector3i = PathingSystem._vec(entry["rel"])
		var template_s: String = entry["terminal"]
		var centre: Vector3i = BuildSystem.cell_centre(base + rel)
		# at the level the site stands on: a site raised on ground above the city's (claim 10)
		# has its terminals up there with it
		var id: int = _terminals.place(StringName(template_s), Vector3i(centre.x, (base.y + rel.y) * BuildSystem.CELL, centre.z))
		if id != EntityIds.NONE:
			terminals.append(id)
	_raised[site] = {"pieces": placed, "agents": agents, "terminals": terminals, "base": [base.x, base.y, base.z]}
	_events.emit(EVENT_RAISED, {"site": site, "pieces": placed.size(), "agents": agents.size(), "terminals": terminals.size()})
	return true


## Gives a spawn its kit, if it has one. A guard with nothing in its hands cannot
## defend anything, so what the guard is holding is part of the site rather than
## something whoever raised it has to remember (M6 spec claim 4).
func _hand_out_kit(agent: int, spawn: Dictionary) -> void:
	if not spawn.has("kit"):
		return
	var kit: Dictionary = spawn["kit"]
	var frame_s: String = kit["frame"]
	var magazine_s: String = kit["magazine"]
	var ammo_s: String = kit["ammo"]
	var rounds: int = kit["rounds"]
	var weapon: int = _items.arm(agent, StringName(frame_s), StringName(magazine_s), StringName(ammo_s), rounds, agent * 1000)
	if weapon == EntityIds.NONE:
		push_error("SiteSystem: could not arm agent %d with %s" % [agent, frame_s])
		return
	if not _actors.wield(agent, weapon):
		push_error("SiteSystem: agent %d would not hold %s" % [agent, frame_s])


## Levels the ground a bound site stands on: over its pieces and a street's width round
## them, air from the base up and ground from the base down, filled as far as it has to
## go. Where the region's ground is not the site's to change (the city), nothing is.
func _level(base: Vector3i, t: Dictionary) -> void:
	var lo: Vector3i = Vector3i(1 << 30, 1 << 30, 1 << 30)
	var hi: Vector3i = -lo
	for p: Variant in t["pieces"]:
		var entry: Dictionary = p
		var rel: Vector3i = PathingSystem._vec(entry["rel"])
		lo = Vector3i(mini(lo.x, rel.x), mini(lo.y, rel.y), mini(lo.z, rel.z))
		hi = Vector3i(maxi(hi.x, rel.x), maxi(hi.y, rel.y), maxi(hi.z, rel.z))
	for x: int in range(base.x + lo.x - LEVEL_MARGIN, base.x + hi.x + LEVEL_MARGIN + 1):
		for z: int in range(base.z + lo.z - LEVEL_MARGIN, base.z + hi.z + LEVEL_MARGIN + 1):
			for y: int in range(base.y, base.y + hi.y + 3):
				var cell: Vector3i = Vector3i(x, y, z)
				if _regions.is_solid(cell):
					_regions.set_ground(cell, false)
			for d: int in range(1, FILL_DEPTH + 1):
				var cell: Vector3i = Vector3i(x, base.y - d, z)
				if _regions.is_solid(cell):
					break
				_regions.set_ground(cell, true)


## {"actor": int, "site": string} or {"actor": int, "site": string, "quest": string}: the
## second raises it where that contract's handle is bound (M7 spec claim 10)
func _on_raise(_sim: SimRoot, payload: Dictionary) -> bool:
	var sized: bool = payload.size() == 2 or (payload.size() == 3 and typeof(payload.get("quest")) == TYPE_STRING)
	if not sized or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("site")) != TYPE_STRING:
		return false
	var actor: int = payload["actor"]
	var site_s: String = payload["site"]
	var quest_s: String = payload.get("quest", "")
	if payload.size() == 3 and quest_s.is_empty():
		return false
	return raise_site(actor, StringName(site_s), StringName(quest_s))


## A site's guard who is removed is no longer the site's (M7 spec claim 12).
func _on_removed(payload: Dictionary) -> void:
	var actor: int = payload["actor"]
	for key: Variant in _raised:
		var rec: Dictionary = _raised[key]
		var agents: Array = rec["agents"]
		agents.erase(actor)


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 1 or typeof(state.get("raised")) != TYPE_DICTIONARY:
		return _restore_fail("shape")
	var in_all: Dictionary = state["raised"]
	var out: Dictionary = {}
	for key: Variant in in_all:
		if (typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME) or typeof(in_all[key]) != TYPE_DICTIONARY:
			return _restore_fail("site key")
		var site: StringName = StringName(str(key))
		if not _content.has(KIND_SITE, site):
			return _restore_fail("unknown site %s" % site)
		var rec: Dictionary = in_all[key]
		if rec.size() != 4 or typeof(rec.get("pieces")) != TYPE_ARRAY or typeof(rec.get("agents")) != TYPE_ARRAY \
				or typeof(rec.get("base")) != TYPE_ARRAY \
				or typeof(rec.get("terminals")) != TYPE_ARRAY:
			return _restore_fail("site %s record" % site)
		var pieces: Array[int] = []
		for v: Variant in rec["pieces"]:
			if typeof(v) != TYPE_INT:
				return _restore_fail("site %s piece id" % site)
			var id: int = v
			if not _build.has_piece(id):
				return _restore_fail("site %s names a piece that is not standing" % site)
			pieces.append(id)
		var agents: Array[int] = []
		for v: Variant in rec["agents"]:
			if typeof(v) != TYPE_INT:
				return _restore_fail("site %s agent id" % site)
			var id: int = v
			if not _perception.is_agent(id):
				return _restore_fail("site %s names an agent that does not exist" % site)
			agents.append(id)
		var terminals: Array[int] = []
		for v: Variant in rec["terminals"]:
			if typeof(v) != TYPE_INT:
				return _restore_fail("site %s terminal id" % site)
			var id: int = v
			if not _terminals.has_terminal(id):
				return _restore_fail("site %s names a terminal that does not exist" % site)
			terminals.append(id)
		var base_in: Array = rec["base"]
		if base_in.size() != 3:
			return _restore_fail("site %s base" % site)
		for v: Variant in base_in:
			if typeof(v) != TYPE_INT:
				return _restore_fail("site %s base" % site)
			var n: int = v
			if absi(n) > BuildSystem.MAX_CELL:
				return _restore_fail("site %s base" % site)
		out[site] = {"pieces": pieces, "agents": agents, "terminals": terminals, "base": base_in.duplicate()}
	_raised = out
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("SiteSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
