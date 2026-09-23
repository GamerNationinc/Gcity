## What a generated site slot is good for (M7 spec claim 5).
##
## A tag is **not** written onto a slot when the world is generated. Each
## `content/site_tag/` entry declares where it belongs — which biomes, which kinds of
## graph node — and a slot carries every tag whose declaration it matches. The tag list
## is therefore a reading over the slot, not a field of it.
##
## That is a deliberate choice and it is what claim 5 costs least: the world hash covers
## the slots (where they are, what ground they are on), not the tags derived from them,
## so adding a fifth tag is one new file that gives the tag to every slot it fits
## without moving a single existing world. Writing tags at generation would instead make
## every saved world disagree with the generator the moment content grew — the Q4
## extension exercise would fail on its first run.
##
## An empty `biomes` or `node_kinds` means "anywhere": `ruin` uses both, which is what
## guarantees every slot carries at least one tag and so can always be bound.
class_name SiteTags extends RefCounted

const KIND: StringName = &"site_tag"


## Every tag that fits this ground and this kind of place, lexically sorted.
static func matching(content: ContentDb, biome: StringName, node_kind: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for tag: StringName in content.ids(KIND):
		if _fits(content.get_entry(KIND, tag), biome, node_kind):
			out.append(tag)
	return out


## True when a tag names this biome and this node kind, where naming nothing is naming
## everything.
static func _fits(entry: Dictionary, biome: StringName, node_kind: StringName) -> bool:
	if entry.is_empty():
		return false
	var biomes: Array = entry["biomes"]
	if not biomes.is_empty() and not _holds(biomes, biome):
		return false
	var kinds: Array = entry["node_kinds"]
	return kinds.is_empty() or _holds(kinds, node_kind)


static func _holds(list: Array, wanted: StringName) -> bool:
	for v: Variant in list:
		var text: String = v
		if StringName(text) == wanted:
			return true
	return false


## Every tag names a biome the world has and a node kind the graph has. A typo here
## would be a tag that silently never applies, which is the kind of dead content that
## only shows up when a contract cannot find anywhere to happen.
static func validate(content: ContentDb) -> Error:
	for tag: StringName in content.ids(KIND):
		var entry: Dictionary = content.get_entry(KIND, tag)
		var biomes: Array = entry["biomes"]
		for v: Variant in biomes:
			var text: String = v
			if not RouteGraph.BIOMES.has(StringName(text)):
				push_error("site_tag/%s names biome '%s', which no ground is" % [tag, text])
				return ERR_INVALID_DATA
		var kinds: Array = entry["node_kinds"]
		for v: Variant in kinds:
			var text: String = v
			if not RouteGraph.KINDS.has(StringName(text)):
				push_error("site_tag/%s names node kind '%s', which no place is" % [tag, text])
				return ERR_INVALID_DATA
	return OK


## The tags a slot carries, which is the pair of readings the graph already holds: the
## ground it sits on and the kind of place it hangs off.
static func of_slot(content: ContentDb, routes: RouteGraph, slot: int) -> Array[StringName]:
	if not routes.has_slot(slot):
		return [] as Array[StringName]
	return matching(content, routes.slot_biome(slot), routes.kind_of(routes.slot_node(slot)))
