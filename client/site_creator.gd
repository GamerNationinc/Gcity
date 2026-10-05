## The creator tool (M7.5 spec claims 14–15): a site built in the game, a piece at a
## time, then written out as a `content/site` file. The view drives it (`--create`);
## this holds what the tool knows that the sim does not — the cursor, the palette, the
## guard posts and terminals not yet raised — and turns the sim's pieces into a site.
##
## Every piece goes in through `build.place` like any other build, so support, land
## rights and the body rule judge it: a site the tool writes is valid because the sim
## placed every piece of it. Guard posts and terminals are markers only until the file
## is raised; the tool never spawns a guard.
class_name SiteCreator extends RefCounted

## The lots the creator builds on, the player's for the session. Cold Storage's lot is
## open ground while nothing raises it, and a shipped site opens where it was authored.
const LOTS: Array[String] = ["cold_storage_lot", "starter_plot", "neighbour_north"]
## Where the cursor starts: the middle of Cold Storage's lot, at street level.
const START: Vector3i = Vector3i(42, 0, 46)
## The two markers at the end of the palette.
const GUARD_POST: StringName = &"guard_post"
const TERMINAL: StringName = &"terminal"
## What a guard post becomes and carries until the tool chooses them (spec, out of scope).
const GUARD_PROFILE: String = "guard_sim"
const GUARD_KIT: Dictionary = {"frame": "g19", "magazine": "g19_mag_15", "ammo": "9x19_fmj", "rounds": 15}
const GUARD_SQUAD: int = 1
const TERMINAL_TEMPLATE: String = "cs_server"
## The schema's limits (tools/content_schemas/site.json).
const MAX_PIECES: int = 2048
const MAX_SPAWNS: int = 64
const MAX_TERMINALS: int = 16
const MAX_REL: int = 100000
const SITE_DIR: String = "user://sites"
## The one file the creator keeps the lot in while you build: Steam ends a game without
## letting it quit, and a build only saved from the menu was lost (Game Mode run, 2026-10-04).
const AUTOSAVE_ID: String = "autosave"
## How often the lot is written there when it has changed: 15 s.
const AUTOSAVE_TICKS: int = 600
## Where a `--demo` build saves and autosaves instead, out of the menu.
const DEMO_DIR: String = "user://demo_sites"
## The piece the palette starts on.
const FIRST_PIECE: StringName = &"foundation_block"
## The four facings round a cell, a quarter turn apart: 0°, 90°, 180°, 270° (the sim's
## facing degrees run from +x towards +z).
const AROUND: Array[String] = ["px", "pz", "nx", "nz"]

var _content: ContentDb
var _palette: Array[StringName] = []
var _index: int = 0
var _cursor: Vector3i = START
## Quarter turns X has added to the facing the camera gives.
var _turn: int = 0
## Each {"cell": Vector3i, "facing": int}, in the order placed.
var _posts: Array[Dictionary] = []
var _terminals: Array[Vector3i] = []


func _init(content: ContentDb) -> void:
	_content = content
	_palette = content.ids(BuildSystem.KIND_PIECE)
	_palette.append(GUARD_POST)
	_palette.append(TERMINAL)
	# start on what goes on bare ground: anything else placed first is refused (Deck test,
	# 2026-10-04: the first A on a concrete block did nothing a player could see)
	select(FIRST_PIECE)


func palette() -> Array[StringName]:
	return _palette.duplicate()


func selected() -> StringName:
	return _palette[_index]


func next_piece() -> void:
	_index = (_index + 1) % _palette.size()


func cursor() -> Vector3i:
	return _cursor


func set_cursor(cell: Vector3i) -> void:
	_cursor = cell


func turn() -> void:
	_turn = (_turn + 1) % AROUND.size()


## Quarter turns from the facing the camera gives, for a scripted build.
func set_turn(turns: int) -> void:
	_turn = posmod(turns, AROUND.size())


func select(name: StringName) -> bool:
	var at: int = _palette.find(name)
	if at < 0:
		return false
	_index = at
	return true


func guard_posts() -> Array[Dictionary]:
	return _posts.duplicate(true)


func terminal_cells() -> Array[Vector3i]:
	return _terminals.duplicate()


static func is_marker(name: StringName) -> bool:
	return name == GUARD_POST or name == TERMINAL


## "cell", "face" or "marker" for a palette entry.
func occupies(name: StringName) -> String:
	if is_marker(name):
		return "marker"
	var t: Dictionary = _content.get_entry(BuildSystem.KIND_PIECE, name)
	var k: Dictionary = _content.get_entry(BuildSystem.KIND_PIECE_KIND, LandSystem._as_name(t["kind"]))
	var occupies_s: String = k["occupies"]
	return occupies_s


func _horizontal(name: StringName) -> bool:
	var t: Dictionary = _content.get_entry(BuildSystem.KIND_PIECE, name)
	var k: Dictionary = _content.get_entry(BuildSystem.KIND_PIECE_KIND, LandSystem._as_name(t["kind"]))
	var orientation: String = k["orientation"]
	return orientation == "horizontal"


# ---------------------------------------------------------------- the cursor

## A D-pad press as a step on the ground, relative to a camera at `yaw`: up is away
## from the camera along whichever axis it faces most, right is the screen's right.
static func camera_step(yaw: float, dpad: Vector2i) -> Vector2i:
	var forward: Vector2 = Vector2(-sin(yaw), -cos(yaw))
	var right: Vector2 = Vector2(-forward.y, forward.x)
	var ground: Vector2 = right * float(dpad.x) - forward * float(dpad.y)
	if ground.length_squared() < 0.01:
		return Vector2i.ZERO
	if absf(ground.x) >= absf(ground.y):
		return Vector2i(1 if ground.x > 0.0 else -1, 0)
	return Vector2i(0, 1 if ground.y > 0.0 else -1)


func move(step: Vector2i) -> void:
	_cursor += Vector3i(step.x, 0, step.y)


func rise(levels: int) -> void:
	_cursor.y += levels


## The wall face of the cursor cell toward a camera at `yaw`, turned by X.
func wall_facing(yaw: float) -> String:
	var forward: Vector2 = Vector2(-sin(yaw), -cos(yaw))
	var toward: String
	if absf(forward.x) >= absf(forward.y):
		toward = "nx" if forward.x > 0.0 else "px"
	else:
		toward = "nz" if forward.y > 0.0 else "pz"
	return AROUND[(AROUND.find(toward) + _turn) % AROUND.size()]


## The facing a piece of the selected kind takes: none for a cell piece, the cursor
## cell's floor for a horizontal face, the wall toward the camera for a vertical one.
func facing_for(name: StringName, yaw: float) -> String:
	match occupies(name):
		"cell", "marker":
			return ""
		_:
			return "ny" if _horizontal(name) else wall_facing(yaw)


## A guard post looks away from the camera, turned by X: in degrees, as a spawn's facing.
func post_facing(yaw: float) -> int:
	var away: String = AROUND[(AROUND.find(wall_facing(yaw)) + 2) % AROUND.size()]
	return AROUND.find(away) * 90


# ---------------------------------------------------------------- placing

## A press of A: the `build.place` payload for the selected piece at the cursor, or,
## for a marker, the marker put down (replacing one in the same cell) and {}. A guard
## post goes down only where a guard could stand ([method guard_fits]).
func place(actor: int, yaw: float, movement: MovementSystem) -> Dictionary:
	var name: StringName = selected()
	if name == GUARD_POST:
		if guard_fits(movement, _cursor) and _posts.size() < MAX_SPAWNS:
			_drop_marker_at(_cursor)
			_posts.append({"cell": _cursor, "facing": post_facing(yaw)})
		return {}
	if name == TERMINAL:
		_drop_marker_at(_cursor)
		if _terminals.size() < MAX_TERMINALS:
			_terminals.append(_cursor)
		return {}
	var centre: Vector3i = BuildSystem.cell_centre(_cursor)
	return {"actor": actor, "piece": String(name), "x": centre.x, "y": centre.y, "z": centre.z, "facing": facing_for(name, yaw)}


## Why the sim would refuse to place `name` at the cursor with `facing`, in a few words
## a player can act on, or "" if nothing here says it would. Asked before the press is
## sent, so that when the piece does not appear the view can say why rather than leave
## a button that seems to do nothing (Deck test, 2026-10-04). Read-only: the sim alone
## decides; this only explains.
func why_not(sim: SimRoot, actor: int, name: StringName, facing: String) -> String:
	return why_not_at(sim, _content, actor, name, _cursor, facing)


## The same for any cell: the world's build buttons say why too (Deck run, 2026-10-05).
static func why_not_at(sim: SimRoot, content: ContentDb, actor: int, name: StringName, cell: Vector3i, facing: String) -> String:
	var build: BuildSystem = SimAssembly.build_of(sim)
	var slot: String = BuildSystem.cell_key(cell) if facing.is_empty() else BuildSystem.face_key(cell, facing)
	var taken: int = build.cell_piece_at(cell) if facing.is_empty() else build.face_piece_at(slot)
	if taken != EntityIds.NONE:
		return "that spot already has a %s" % build.template_of(taken)
	var rights: Dictionary = SimAssembly.land_of(sim).rights_at(BuildSystem.cell_centre(cell), actor)
	var may_build: bool = rights[&"build"]
	if not may_build:
		return "this is not your land to build on"
	var t: Dictionary = content.get_entry(BuildSystem.KIND_PIECE, name)
	if LandSystem._as_name(t["kind"]) == &"foundation" and not build._on_ground(cell):
		return "a foundation goes on the ground: lower the cursor (L1)"
	if build.would_enclose_a_body(name, cell, facing):
		return "somebody is standing there"
	return "nothing holds it up there: too far from a foundation, build one closer"


## A press of B: the `build.remove` payload for what is under the cursor — a piece in
## the cell, else the wall toward the camera, else the cell's floor — or, where there
## is no piece but a marker, the marker taken away and {}. {} too when there is nothing.
func remove(build: BuildSystem, actor: int, yaw: float) -> Dictionary:
	var id: int = build.cell_piece_at(_cursor)
	if id == EntityIds.NONE:
		id = build.face_piece_at(BuildSystem.face_key(_cursor, wall_facing(yaw)))
	if id == EntityIds.NONE:
		id = build.face_piece_at(BuildSystem.face_key(_cursor, "ny"))
	if id != EntityIds.NONE:
		return {"actor": actor, "piece_id": id}
	_drop_marker_at(_cursor)
	return {}


## Whether a guard of the post's profile could stand at `cell`: the movement system's
## own body and standing rules, since a spawn checks neither and a guard put in a wall
## stays in it.
func guard_fits(movement: MovementSystem, cell: Vector3i) -> bool:
	var t: Dictionary = _content.get_entry(PerceptionSystem.KIND_AGENT, StringName(GUARD_PROFILE))
	var combat_s: String = t["combat_profile"]
	return movement.body_fits(cell, movement.profile_body_cells(StringName(combat_s))) and movement.is_standable(cell)


## Takes away every guard post a build change left without room for a guard, and
## returns their cells so the view can say so.
func prune(movement: MovementSystem) -> Array[Vector3i]:
	var gone: Array[Vector3i] = []
	for i: int in range(_posts.size() - 1, -1, -1):
		var post: Dictionary = _posts[i]
		var at: Vector3i = post["cell"]
		if not guard_fits(movement, at):
			_posts.remove_at(i)
			gone.append(at)
	gone.reverse()
	return gone


func _drop_marker_at(cell: Vector3i) -> void:
	for i: int in range(_posts.size() - 1, -1, -1):
		var post: Dictionary = _posts[i]
		var at: Vector3i = post["cell"]
		if at == cell:
			_posts.remove_at(i)
	_terminals.erase(cell)


# ---------------------------------------------------------------- the site file

## Everything standing in `build`, and the markers, as a `content/site` entry (claim
## 15): relative to the lowest corner, which is the base. Pieces are listed in the
## order the support search settles them, which is an order the sim can place them in
## again: by placement order alone, a piece whose first support was taken away and
## replaced by a later one would be refused. Face pieces are written from the lower
## cell of their face, which names the same face. {} (after an error) past the schema's
## limits, with nothing built, or with a guard post a guard no longer fits.
func to_site(build: BuildSystem, movement: MovementSystem, title: String, description: String) -> Dictionary:
	var problem_: String = unsavable(build, movement)
	if not problem_.is_empty():
		push_error("SiteCreator: %s" % problem_)
		return {}
	var order: Array = build.supported_set().keys()
	var rows: Array[Array] = []
	var low: Vector3i = Vector3i(1 << 30, 1 << 30, 1 << 30)
	for v: Variant in order:
		var id: int = v
		var cell: Vector3i = build.cell_of_piece(id)
		var key: String = build.key_of_piece(id)
		var facing: String = "p" + key.get_slice("|", 1) if key.contains("|") else ""
		rows.append([String(build.template_of(id)), cell, facing])
		low = Vector3i(mini(low.x, cell.x), mini(low.y, cell.y), mini(low.z, cell.z))
	for post: Dictionary in _posts:
		var at: Vector3i = post["cell"]
		low = Vector3i(mini(low.x, at.x), mini(low.y, at.y), mini(low.z, at.z))
	for at: Vector3i in _terminals:
		low = Vector3i(mini(low.x, at.x), mini(low.y, at.y), mini(low.z, at.z))
	var pieces: Array = []
	for row: Array in rows:
		var cell: Vector3i = row[1]
		pieces.append({"piece": row[0], "rel": _rel(cell - low), "facing": row[2]})
	var spawns: Array = []
	for post: Dictionary in _posts:
		var at: Vector3i = post["cell"]
		spawns.append({"profile": GUARD_PROFILE, "rel": _rel(at - low), "facing": post["facing"], "squad": GUARD_SQUAD, "route": "", "kit": GUARD_KIT.duplicate()})
	var terminals: Array = []
	for at: Vector3i in _terminals:
		terminals.append({"terminal": TERMINAL_TEMPLATE, "rel": _rel(at - low)})
	return {
		"schema_version": 1,
		"title": title,
		"description": description,
		"base": _rel(low),
		"parcels": [],
		"pieces": pieces,
		"spawns": spawns,
		"terminals": terminals,
	}


static func _rel(v: Vector3i) -> Array:
	return [v.x, v.y, v.z]


## Opens a site file to keep working on it: the `build.place` payloads that raise its
## pieces where its base puts them, in its own order, with its guard posts and
## terminals as markers and the cursor at its base. Checked first (`problem`): [] for a
## file that is not a site this content can build.
func open(site: Dictionary, actor: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var wrong: String = problem(site, _content)
	if not wrong.is_empty():
		push_error("SiteCreator: cannot open the site: %s" % wrong)
		return out
	var base: Vector3i = _vec(site["base"])
	_posts = []
	_terminals = []
	for v: Variant in site["pieces"]:
		var entry: Dictionary = v
		var centre: Vector3i = BuildSystem.cell_centre(base + _vec(entry["rel"]))
		out.append({"actor": actor, "piece": entry["piece"], "x": centre.x, "y": centre.y, "z": centre.z, "facing": entry["facing"]})
	for v: Variant in site["spawns"]:
		var spawn: Dictionary = v
		var facing: int = spawn["facing"]
		_posts.append({"cell": base + _vec(spawn["rel"]), "facing": facing})
	for v: Variant in site["terminals"]:
		var entry: Dictionary = v
		_terminals.append(base + _vec(entry["rel"]))
	_cursor = base
	return out


## Why a dictionary is not a site this content can open, or "" if it is. A file from
## `user://` is untrusted (standards §5.1): the shape the schema gives, checked here
## since the schema's validator runs in Python, not in the game.
static func problem(site: Dictionary, content: ContentDb) -> String:
	for key: String in ["schema_version", "title", "description", "base", "parcels", "pieces", "spawns", "terminals"]:
		if not site.has(key):
			return "no '%s'" % key
	if typeof(site["schema_version"]) != TYPE_INT or site["schema_version"] != 1:
		return "schema_version must be 1"
	if not _is_cell(site["base"]):
		return "base must be three whole numbers within %d" % MAX_REL
	for key: String in ["pieces", "spawns", "terminals"]:
		if typeof(site[key]) != TYPE_ARRAY:
			return "'%s' must be a list" % key
	var pieces: Array = site["pieces"]
	var spawns: Array = site["spawns"]
	var terminals: Array = site["terminals"]
	if pieces.is_empty() or pieces.size() > MAX_PIECES or spawns.size() > MAX_SPAWNS or terminals.size() > MAX_TERMINALS:
		return "%d pieces, %d spawns, %d terminals: past the schema's limits" % [pieces.size(), spawns.size(), terminals.size()]
	for v: Variant in pieces:
		if typeof(v) != TYPE_DICTIONARY:
			return "a piece is not an object"
		var entry: Dictionary = v
		if typeof(entry.get("piece")) != TYPE_STRING or not content.has(BuildSystem.KIND_PIECE, StringName(str(entry["piece"]))):
			return "a piece names no build piece: %s" % entry.get("piece")
		if not _is_cell(entry.get("rel")) or typeof(entry.get("facing")) != TYPE_STRING:
			return "piece %s has no cell or facing" % entry["piece"]
		var facing: String = entry["facing"]
		if not facing.is_empty() and not BuildSystem.FACINGS.has(facing):
			return "piece %s faces '%s'" % [entry["piece"], facing]
	for v: Variant in spawns:
		if typeof(v) != TYPE_DICTIONARY:
			return "a spawn is not an object"
		var spawn: Dictionary = v
		if not _is_cell(spawn.get("rel")) or typeof(spawn.get("facing")) != TYPE_INT or spawn["facing"] < 0 or spawn["facing"] > 359:
			return "a spawn has no cell or facing"
	for v: Variant in terminals:
		if typeof(v) != TYPE_DICTIONARY:
			return "a terminal is not an object"
		var terminal: Dictionary = v
		if not _is_cell(terminal.get("rel")):
			return "a terminal has no cell"
	return ""


static func _is_cell(v: Variant) -> bool:
	if typeof(v) != TYPE_ARRAY:
		return false
	var a: Array = v
	if a.size() != 3:
		return false
	for n: Variant in a:
		if typeof(n) != TYPE_INT:
			return false
		var i: int = n
		if absi(i) > MAX_REL:
			return false
	return true


static func _vec(v: Variant) -> Vector3i:
	var a: Array = v
	var x: int = a[0]
	var y: int = a[1]
	var z: int = a[2]
	return Vector3i(x, y, z)


# ---------------------------------------------------------------- files

## The id a site saved now gets: the date and time, which is also its file name.
static func site_id(when: Dictionary) -> String:
	return "site_%04d%02d%02d_%02d%02d%02d" % [when["year"], when["month"], when["day"], when["hour"], when["minute"], when["second"]]


## Writes a site to `<dir>/<id>.json`. The path, or "" after an error.
static func save(site: Dictionary, id: String, dir: String = SITE_DIR) -> String:
	var err: Error = DirAccess.make_dir_recursive_absolute(dir)
	if err != OK:
		push_error("SiteCreator: cannot make %s: %s" % [dir, error_string(err)])
		return ""
	var path: String = dir.path_join(id + ".json")
	# written beside it and renamed over it: a game ended mid-write leaves the old file whole
	var part: String = path + ".part"
	var handle: FileAccess = FileAccess.open(part, FileAccess.WRITE)
	if handle == null:
		push_error("SiteCreator: cannot write %s: %s" % [part, error_string(FileAccess.get_open_error())])
		return ""
	handle.store_string(JSON.stringify(site, "\t", true) + "\n")
	handle.close()
	err = DirAccess.rename_absolute(part, path)
	if err != OK:
		push_error("SiteCreator: cannot rename %s to %s: %s" % [part, path, error_string(err)])
		return ""
	return path


## Why what stands on the lot cannot be saved as a site, or "" when it can.
func unsavable(build: BuildSystem, movement: MovementSystem) -> String:
	var count: int = build.supported_set().size()
	if count == 0:
		return "nothing built"
	if count > MAX_PIECES:
		return "%d pieces, a site holds %d at most" % [count, MAX_PIECES]
	for post: Dictionary in _posts:
		var at: Vector3i = post["cell"]
		if not guard_fits(movement, at):
			return "the guard post at %s has no room for a guard" % at
	return ""


## Reads a site file: the entry with its numbers whole again, or {} after an error.
static func read(path: String) -> Dictionary:
	var handle: FileAccess = FileAccess.open(path, FileAccess.READ)
	if handle == null:
		push_error("SiteCreator: cannot read %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return {}
	var json: JSON = JSON.new()
	if json.parse(handle.get_as_text()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_error("SiteCreator: %s is not a JSON object" % path)
		return {}
	var site: Dictionary = json.data
	JsonNumbers.normalise(site)
	return site


## The sites the creator can open: the autosave, the player's own newest first, then the
## shipped ones.
static func openable(dir: String = SITE_DIR) -> Array[String]:
	var out: Array[String] = []
	var own: PackedStringArray = DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray()
	var mine: Array[String] = []
	for file: String in own:
		if file.ends_with(".json"):
			mine.append(dir.path_join(file))
	mine.sort()
	mine.reverse()
	var autosave: String = dir.path_join(AUTOSAVE_ID + ".json")
	if mine.has(autosave):
		mine.erase(autosave)
		out.append(autosave)
	out.append_array(mine)
	for file: String in DirAccess.get_files_at(ContentLoader.CONTENT_ROOT.path_join(String(SiteSystem.KIND_SITE))):
		if file.ends_with(".json"):
			out.append(ContentLoader.CONTENT_ROOT.path_join(String(SiteSystem.KIND_SITE)).path_join(file))
	return out
