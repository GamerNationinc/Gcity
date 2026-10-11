## Showcase for M6 claim 20's stealth proof: the m6-stealth replay fixture, its recorded
## commands played back through the real sim exactly as the fixture test does. The
## Cold Storage job by the under route with nobody ever alerted: the maintenance key
## from the city's utility box, both grates unlocked (silent, no trace), the basement,
## a wait in the maintenance room for the hall patrols to turn away, the server room's
## one corner that no doorway sees, the hack, back the same way, out, paid the
## full-stealth bonus. The caption says what the player is doing, read from the sim;
## the counters are the contract's own.
extends RefCounted

const FIXTURE: String = "res://tests/replay/m6-stealth.json"
const PLAYER: int = 1

var _fixture: ReplayFixture
var _sim: SimRoot
var _named: bool = false
var _site_named: bool = false
var _paid: String = ""


func _init() -> void:
	_fixture = ReplayFixture.parse(FileAccess.get_file_as_string(FIXTURE))
	assert(_fixture.is_valid(), "stealth_run: %s" % _fixture.error)


func title() -> String:
	return "Gcity M6: THE COLD STORAGE JOB WITHOUT BEING SEEN (fixture m6-stealth)"


func seed() -> int:
	return _fixture.seed


func content(_db: ContentDb) -> void:
	pass


func setup(sim: SimRoot, view: Node3D) -> void:
	_sim = sim
	for c: SimCommand in _fixture.commands:
		sim.submit(c)
	SimAssembly.combat_of(sim).events().subscribe(QuestSystem.EVENT_DELIVERED, _on_delivered)
	view.call("slab", Vector3(28, -0.02, -2), Vector2(56, 24), Color(0.3, 0.32, 0.36))
	view.call("place_camera", Vector3(-6, 18, -16), Vector3(8, 0, -3), 22.0)


func _on_delivered(p: Dictionary) -> void:
	var credits: int = p["credits"]
	var tier: String = p["tier"]
	_paid = "PAID %d credits, the %s rate: twice the base for a job nobody noticed." % [credits, tier]


func before_tick(sim: SimRoot, view: Node3D, tick: int) -> void:
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	if not _named and actors.has_actor(PLAYER):
		_named = true
		view.call("name_actor", PLAYER, "You", true)
	var sites: SiteSystem = SimAssembly.sites_of(sim)
	if not _site_named and sites.is_spawned(&"cold_storage"):
		_site_named = true
		var perception: PerceptionSystem = SimAssembly.perception_of(sim)
		for agent: int in sites.agents_of(&"cold_storage"):
			view.call("name_actor", agent, "Camera" if perception.profile_of(agent) == &"camera" else "Guard", false)
	if tick % 4 == 0 and actors.has_actor(PLAYER):
		var p: Vector3 = Vector3(actors.position_of(PLAYER)) / 1000.0
		var storey: int = BuildSystem.storey_of(actors.position_of(PLAYER))
		view.call("cutaway", storey if sites.is_spawned(&"cold_storage") else 99)
		view.call("place_camera", p + Vector3(-8, 14, -10), p, 17.0)


func ticks_per_frame(_tick: int) -> int:
	return 8


func end_tick() -> int:
	return _fixture.ticks


func caption(_tick: int) -> String:
	if not _paid.is_empty():
		return _paid
	if _sim == null or not SimAssembly.actors_of(_sim).has_actor(PLAYER):
		return "Kit up."
	var line: String = _doing()
	var run: Dictionary = SimAssembly.quests_of(_sim).run_of(PLAYER, &"cold_storage_contract")
	if run.is_empty():
		return line
	var c: Dictionary = run["counters"]
	return "%s\nseen %d   alarms %d   bodies %d   traces %d" % [line, c["times_detected"], c["alarms_raised"], c["bodies"], c["traces_left"]]


## What the player is doing now, in words, read from the sim.
func _doing() -> String:
	var actors: ActorSystem = SimAssembly.actors_of(_sim)
	var items: ItemSystem = SimAssembly.items_of(_sim)
	var hacks: HackSystem = SimAssembly.hacks_of(_sim)
	var quests: QuestSystem = SimAssembly.quests_of(_sim)
	var sites: SiteSystem = SimAssembly.sites_of(_sim)
	if quests.status_of(PLAYER, &"cold_storage_contract").is_empty():
		return "Take the Cold Storage job from Marlow."
	var o: Vector3i = sites.origin_of(&"cold_storage")
	var cell: Vector3i = BuildSystem.cell_of(actors.position_of(PLAYER)) - o
	var has_key: bool = false
	var has_drive: bool = false
	for id: int in items.items_in(ItemSystem.inventory_of(PLAYER)):
		has_key = has_key or items.item_template(id) == &"maintenance_key"
		has_drive = has_drive or items.item_template(id) == &"cold_storage_data"
	var run: Dictionary = quests.run_of(PLAYER, &"cold_storage_contract")
	if not run.is_empty() and run["exfil"]:
		return "Out of the site with the records: back to Marlow."
	if hacks.is_hacking(PLAYER):
		return "Hacking the terminal from the one corner no doorway can see (15 s)."
	if not has_key:
		return "Take the maintenance key from the city's utility box on the pavement."
	if cell.y == 0 and cell.z < 0 and not has_drive:
		return "Unlock the street grate with the key and drop into the city's tunnel: silent, no trace."
	if cell.y == -1:
		if cell.z < 0:
			return "The city's tunnel." if not has_drive else "Back along the tunnel to its hatch, and up to the street."
		return "Cold Storage's basement, behind the desk guard's back." if not has_drive else "Back through the basement."
	if cell.y == 0:
		return "Through the hall to the stairs, when the roamer is upstairs." if not has_drive else "Down to the basement."
	if cell.y == 1 and cell.x >= 5 and cell.z <= 3:
		return "Hiding in the maintenance room (nobody patrols it) until the hall patrols turn away."
	if cell.y == 1 and cell.x >= 5:
		return "Across the hall while both patrols look elsewhere."
	if cell.y == 1:
		return "In the server room." if not has_drive else "The records are on the drive: log out, so no trace is left."
	return "Walking."
