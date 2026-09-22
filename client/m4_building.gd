## The M4 test building, which is now `content/site/m4_test_building.json` (M6 spec
## claim 3). This is the thin adapter the M4 client, bench and fixture generator keep
## using: the same payloads they always emitted, read from the site file instead of a
## second copy of the layout. New work raises a site with `site.raise` and needs none
## of this.
class_name M4Building extends RefCounted

const SITE: StringName = &"m4_test_building"
## The lobby's south-west interior cell, which the site's `base` also carries.
const BASE: Vector3i = Vector3i(3, 0, 8)
## Where the player stands at the start: on the street, off the door's axis so the
## post inside cannot see it until it steps in front of the door.
const PLAYER_START: Vector3i = Vector3i(2500, 0, 1500)


## The `build.place` payloads of the site's pieces, in the site's own order.
static func commands(actor: int, content: ContentDb) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t: Dictionary = content.get_entry(SiteSystem.KIND_SITE, SITE)
	var base: Vector3i = PathingSystem._vec(t["base"])
	var pieces: Array = t["pieces"]
	for p: Variant in pieces:
		var entry: Dictionary = p
		var rel: Vector3i = PathingSystem._vec(entry["rel"])
		var centre: Vector3i = BuildSystem.cell_centre(base + rel)
		var piece_s: String = entry["piece"]
		var facing: String = entry["facing"]
		out.append({"actor": actor, "piece": piece_s, "x": centre.x, "y": centre.y, "z": centre.z, "facing": facing})
	return out


## The `agent.spawn` payloads of the site's guards, all under one profile (the M4
## client swaps every guard's profile at once).
static func guards(profile: String, content: ContentDb) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t: Dictionary = content.get_entry(SiteSystem.KIND_SITE, SITE)
	var base: Vector3i = PathingSystem._vec(t["base"])
	var spawns: Array = t["spawns"]
	for s: Variant in spawns:
		var spawn: Dictionary = s
		var rel: Vector3i = PathingSystem._vec(spawn["rel"])
		var cell: Vector3i = base + rel
		var facing: int = spawn["facing"]
		var squad: int = spawn["squad"]
		var route: String = spawn["route"]
		out.append({"profile": profile, "cell": [cell.x, cell.y, cell.z], "facing": facing, "squad": squad, "route": route})
	return out
