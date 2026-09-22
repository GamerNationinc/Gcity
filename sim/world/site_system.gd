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
## site id -> {"pieces": Array[int], "agents": Array[int], "terminals": Array[int]}
var _raised: Dictionary = {}


func _init(content: ContentDb, build: BuildSystem, perception: PerceptionSystem, actors: ActorSystem, events: EventBus, terminals: TerminalSystem) -> void:
	_content = content
	_build = build
	_perception = perception
	_actors = actors
	_events = events
	_terminals = terminals


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


func base_of(site: StringName) -> Vector3i:
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
func raise_site(actor: int, site: StringName) -> bool:
	if not _content.has(KIND_SITE, site) or _raised.has(site) or not _actors.has_actor(actor):
		return false
	var t: Dictionary = _content.get_entry(KIND_SITE, site)
	var base: Vector3i = PathingSystem._vec(t["base"])
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
		var agent: int = _perception.spawn(StringName(profile_s), base + rel, facing, squad, route)
		if agent != EntityIds.NONE:
			agents.append(agent)
	var terminals: Array[int] = []
	var terminal_entries: Array = t["terminals"]
	for e: Variant in terminal_entries:
		var entry: Dictionary = e
		var rel: Vector3i = PathingSystem._vec(entry["rel"])
		var template_s: String = entry["terminal"]
		var centre: Vector3i = BuildSystem.cell_centre(base + rel)
		var id: int = _terminals.place(StringName(template_s), Vector3i(centre.x, rel.y * BuildSystem.CELL, centre.z))
		if id != EntityIds.NONE:
			terminals.append(id)
	_raised[site] = {"pieces": placed, "agents": agents, "terminals": terminals}
	_events.emit(EVENT_RAISED, {"site": site, "pieces": placed.size(), "agents": agents.size(), "terminals": terminals.size()})
	return true


## {"actor": int, "site": string}
func _on_raise(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("site")) != TYPE_STRING:
		return false
	var actor: int = payload["actor"]
	var site_s: String = payload["site"]
	return raise_site(actor, StringName(site_s))


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
		if rec.size() != 3 or typeof(rec.get("pieces")) != TYPE_ARRAY or typeof(rec.get("agents")) != TYPE_ARRAY \
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
		out[site] = {"pieces": pieces, "agents": agents, "terminals": terminals}
	_raised = out
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("SiteSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
