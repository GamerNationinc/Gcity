## Save migrations (M6 spec claim 21). Version 1 saves (M2 to M5) predate the M6
## systems and fields; M6 only added state, so a version-1 snapshot becomes a
## version-2 one by filling in what is missing:
## - every system, and every top-level key of a system, that the old snapshot lacks is
##   taken from a freshly built sim over the current content (so it is empty);
## - an old build piece gets no facing and its template's starting open state, as if
##   placed now;
## - an old agent's home facing is the facing it has, and its route origin the world
##   origin, as every agent's was before sites.
## The result is then restored like any save, so every system still validates it.
class_name SaveMigration extends RefCounted


## The version-2 snapshot for a version-1 one, built against `fresh` (a new sim over
## the current content and the save's seed). The input is not changed.
static func v1_to_v2(old: Dictionary, fresh: SimRoot, content: ContentDb) -> Dictionary:
	var snapshot: Dictionary = old.duplicate(true)
	var systems_v: Variant = snapshot.get("systems")
	if typeof(systems_v) != TYPE_DICTIONARY:
		return snapshot  # restore refuses it
	var systems: Dictionary = systems_v
	var current: Dictionary = fresh.snapshot()["systems"]
	for id: Variant in current:
		var now: Dictionary = current[id]
		if not systems.has(id):
			systems[id] = now.duplicate(true)
			continue
		if typeof(systems[id]) != TYPE_DICTIONARY:
			continue
		var state: Dictionary = systems[id]
		for key: Variant in now:
			if not state.has(key):
				state[key] = _copy(now[key])
	_pieces(systems, content)
	_agents(systems)
	return snapshot


static func _copy(v: Variant) -> Variant:
	if typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v
		return d.duplicate(true)
	if typeof(v) == TYPE_ARRAY:
		var a: Array = v
		return a.duplicate(true)
	return v


static func _pieces(systems: Dictionary, content: ContentDb) -> void:
	var build_v: Variant = systems.get(BuildSystem.SYSTEM_ID)
	if typeof(build_v) != TYPE_DICTIONARY:
		return
	var build: Dictionary = build_v
	var pieces_v: Variant = build.get("pieces")
	if typeof(pieces_v) != TYPE_DICTIONARY:
		return
	var pieces: Dictionary = pieces_v
	for k: Variant in pieces:
		if typeof(pieces[k]) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = pieces[k]
		if not rec.has("facing"):
			rec["facing"] = ""
		if not rec.has("open"):
			var template_v: Variant = rec.get("template")
			var starts_open: bool = false
			if (typeof(template_v) == TYPE_STRING or typeof(template_v) == TYPE_STRING_NAME):
				var template: String = template_v
				if content.has(&"build_piece", StringName(template)):
					var t: Dictionary = content.get_entry(&"build_piece", StringName(template))
					starts_open = t["starts_open"]
			rec["open"] = starts_open


static func _agents(systems: Dictionary) -> void:
	var perception_v: Variant = systems.get(PerceptionSystem.SYSTEM_ID)
	if typeof(perception_v) != TYPE_DICTIONARY:
		return
	var perception: Dictionary = perception_v
	var agents_v: Variant = perception.get("agents")
	if typeof(agents_v) != TYPE_DICTIONARY:
		return
	var agents: Dictionary = agents_v
	for k: Variant in agents:
		if typeof(agents[k]) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = agents[k]
		if not rec.has("home") and typeof(rec.get("facing")) == TYPE_INT:
			rec["home"] = rec["facing"]
		if not rec.has("origin"):
			rec["origin"] = [0, 0, 0] as Array[int]
