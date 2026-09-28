## Writes the M7 replay fixtures (spec claim 17) into tests/replay/: a world generated
## from its seed, a contract binding its place, a squad on the road coming in and going
## back out, and a player taking the gate there and back.
##   godot --headless --path . -s tools/make_m7_fixtures.gd
## Then `tools/test.sh replay` prints each hash to paste into "expected_hash".
##
## Every one of them is a command log over the assembled sim, and tests/sim/
## test_m7_fixtures.gd replays each and asks what actually happened in it.
extends SceneTree

const OUT_DIR: String = "res://tests/replay"
const M: int = 1000
const SEED: int = 20261300
## Where the player turns up: `actor.spawn` places on the x axis at z 0, in the city just
## east of the gate.
const SPAWN_RANGE_M: int = 12
## The city side of the gate's opening.
const GATE_IN: Vector3i = Vector3i(500, 0, 500)
## The squad the hydrate fixture sends down the road: unarmed, on foot, at a guard's
## walking pace, so nothing in the fixture is a fight.
const FACTION: String = "faction.scrapline"
const PACE: int = 50
const MEMBERS: int = 3
## Where the player stands to watch the squad go by: out on the levelled apron east of
## the road, inside [HydrationSystem.HYDRATE_MM] of the gate and well beyond anything a
## guard sees (40 m) or hears (60 m).
const WATCH: Vector2i = Vector2i(100 * M, -10 * M)
## How far down the road the seam fixture walks before turning back.
const SEAM_WALK_M: int = 30

var _sim: SimRoot
var _commands: Array = []
var _player: int = 0
var _tick: int = 0
var _actors: ActorSystem
var _movement: MovementSystem
## Set by `--debug` on the command line: prints where the squad's members are as it walks.
var _debug: bool = false


func _initialize() -> void:
	_debug = OS.get_cmdline_user_args().has("--debug")
	_graph()
	_bind()
	_hydrate()
	_seam()
	quit(0)


# ---------------------------------------------------------------- the four runs

## Claim 1, as a replay: nothing but the world. The route graph's snapshot is its seed
## and its world hash, so the fixture's hash is the world's, re-generated every replay.
func _graph() -> void:
	_begin(false)
	_write("m7-graph", 40)


## Claim 9: the contract is taken, and taking it binds a place out in the wilds.
func _bind() -> void:
	_begin(true)
	_command(&"quest.accept", {"actor": _player, "quest": "cold_storage"})
	var binder: SiteBinder = SimAssembly.binder_of(_sim)
	print("    bound slot %d, node %d" % [binder.slot_of(&"cold_storage"), binder.node_of(&"cold_storage")])
	_write("m7-bind", 40)


## Claim 12: a squad leaves the gate for the outskirts while the player watches from the
## apron. It comes in as agents, walks the road itself, and goes back to being a token
## once it is out of range, three strong and further down the road.
func _hydrate() -> void:
	_begin(true)
	_through_the_gate()
	_walk_to_world(Vector3i(WATCH.x, _ground_mm(WATCH), WATCH.y), 2000)
	_command(MacroTokenSystem.COMMAND_SPAWN, {"faction": FACTION, "from": 1, "to": RouteGraph.OUTSKIRTS, "speed": PACE,
		"payload": {"profile": "foot_patrol", "members": MEMBERS}})
	var tokens: MacroTokenSystem = SimAssembly.tokens_of(_sim)
	var hydration: HydrationSystem = SimAssembly.hydration_of(_sim)
	var token: int = tokens.token_ids()[0]
	var came: int = -1
	var went: int = -1
	for i: int in 6000:
		_wait(1)
		if came < 0 and hydration.is_hydrated(token):
			came = _sim.get_tick()
		if _debug and came >= 0 and (_sim.get_tick() - came) % 400 == 1:
			var stances: StanceSystem = SimAssembly.stances_of(_sim)
			for a: int in hydration.members_of(token):
				print("      t%d agent %d at %s stance %s" % [_sim.get_tick(), a, _actors.position_of(a), stances.stance_of(a)])
		if came >= 0 and went < 0 and not hydration.is_hydrated(token):
			went = _sim.get_tick()
			break
	if came < 0 or went < 0:
		push_error("m7-hydrate: the squad came in at %d and went at %d" % [came, went])
	print("    squad in at tick %d, out at tick %d, %d of %d back, leg %d, %d mm along" % [came, went,
		tokens.payload_of(token).get("members", 0), MEMBERS, tokens.leg_of(token), tokens.progress_of(token)])
	_write("m7-hydrate", 200)


## Claim 14: through the gate into the wilds, down the road a way, a cell of ground dug
## out beside it (claim 15's overlay), and back through the gate into the city.
func _seam() -> void:
	_begin(true)
	_through_the_gate()
	var road: Array[Vector2i] = _road_out(SEAM_WALK_M * M)
	for point: Vector2i in road:
		_walk_road(point)
	var here: Vector3i = _actors.position_of(_player)
	var regions: Regions = SimAssembly.regions_of(_sim)
	var beside: Vector3i = BuildSystem.cell_of(here) + Vector3i(1, -1, 0)
	if not regions.is_solid(beside):
		push_error("m7-seam: no ground beside the road at %s to dig" % beside)
	_command(Regions.COMMAND_DIG, {"actor": _player, "cell": [beside.x, beside.y, beside.z]})
	if regions.is_solid(beside):
		push_error("m7-seam: the dig at %s was refused" % beside)
	print("    dug %s" % beside)
	road.reverse()
	for point: Vector2i in road:
		_walk_road(point)
	_walk_road(Vector2i(GATE_IN.x, -GATE_IN.z))
	_command(Regions.COMMAND_ENTER, {"actor": _player, "region": "city"})
	_wait(Regions.LOAD_WINDOW_TICKS + 1)
	var back: Vector3i = _actors.position_of(_player)
	if regions.region_at(back.x, back.z).id() != &"city":
		push_error("m7-seam: the gate did not take the player home (at %s)" % back)
	_walk_to_world(Vector3i(SPAWN_RANGE_M * M, 0, 4 * M))
	_write("m7-seam", 40)


# ---------------------------------------------------------------- the setup

func _begin(with_player: bool) -> void:
	_commands = []
	_tick = 0
	var db := ContentDb.new()
	var err: Error = ContentLoader.load_all(db)
	assert(err == OK, "content")
	_sim = SimAssembly.build(SEED, db)
	_actors = SimAssembly.actors_of(_sim)
	_movement = SimAssembly.movement_of(_sim)
	if not with_player:
		return
	_command(&"actor.spawn", {"profile": "arcade", "range_m": SPAWN_RANGE_M})
	_player = _actors.actor_ids()[0]


## From the spawn to the gate and through it, waiting out the load window.
func _through_the_gate() -> void:
	_walk_to_world(GATE_IN)
	_command(Regions.COMMAND_ENTER, {"actor": _player, "region": "wilds"})
	_wait(Regions.LOAD_WINDOW_TICKS + 1)
	var here: Vector3i = _actors.position_of(_player)
	if SimAssembly.regions_of(_sim).region_at(here.x, here.z).id() != &"wilds":
		push_error("the gate did not take the player into the wilds (at %s)" % here)


## The standing height of the wild ground at a point, in millimetres.
func _ground_mm(point: Vector2i) -> int:
	return SimAssembly.regions_of(_sim).standing_cell_y(point.x, point.y) * BuildSystem.CELL


## Points two metres apart along the road from the gate toward the outskirts, as far as
## `length` millimetres.
func _road_out(length: int) -> Array[Vector2i]:
	var routes: RouteGraph = SimAssembly.routes_of(_sim)
	var terrain: Terrain = SimAssembly.terrain_of(_sim)
	var path: Array[int] = routes.path_between(1, RouteGraph.OUTSKIRTS)
	var id: int = routes.edge_between(path[0], path[1])
	var rec: Dictionary = routes.edge(id)
	var edge_length: int = rec["length"]
	var first: int = rec["a"]
	var forward: bool = first == path[0]
	var out: Array[Vector2i] = []
	var along: int = 2 * M
	while along <= mini(length, edge_length):
		out.append(terrain.road_at(id, along if forward else edge_length - along))
		along += 2 * M
	return out


# ---------------------------------------------------------------- driving

## One command on the next tick, then one step, so the log reads as it was played.
func _command(kind: StringName, payload: Dictionary) -> void:
	_tick = _sim.get_tick() + 1
	_commands.append({"tick": _tick, "kind": String(kind), "payload": payload})
	var err: Error = _sim.submit(SimCommand.new(_tick, kind, payload))
	assert(err == OK, "submit %s for tick %d" % [kind, _tick])
	_sim.step()


func _wait(ticks: int) -> void:
	for i: int in ticks:
		_sim.step()


## Walks to a world position, one axis at a time, and says so if it cannot.
func _walk_to_world(target: Vector3i, budget: int = 600) -> void:
	var speed: int = _movement.speed_of(_player)
	for i: int in budget:
		var here: Vector3i = _actors.position_of(_player)
		var dx: int = clampi(target.x - here.x, -speed, speed)
		var dz: int = clampi(target.z - here.z, -speed, speed)
		if dx == 0 and dz == 0:
			return
		if dx != 0:
			dz = 0
		_command(&"actor.move", {"actor": _player, "dx": dx, "dz": dz, "dy": 0})
		if _actors.position_of(_player) == here:
			push_error("walking to %s stalled at %s" % [target, here])
			return
	push_error("could not walk to %s, stuck at %s" % [target, _actors.position_of(_player)])


## One step of the road at a time, straight at the next point.
func _walk_road(point: Vector2i) -> void:
	var speed: int = _movement.speed_of(_player)
	for i: int in 200:
		var here: Vector3i = _actors.position_of(_player)
		var dx: int = clampi(point.x - here.x, -speed, speed)
		var dz: int = clampi(point.y - here.z, -speed, speed)
		if dx == 0 and dz == 0:
			return
		_command(&"actor.move", {"actor": _player, "dx": dx, "dz": dz, "dy": 0})
		if _actors.position_of(_player) == here:
			push_error("the road to %s is blocked at %s" % [point, here])
			return
	push_error("could not reach %s along the road" % point)


# ---------------------------------------------------------------- writing

func _write(name: String, tail: int) -> void:
	var ticks: int = _sim.get_tick() + tail
	var fixture: Dictionary = {"schema_version": 1, "name": name, "seed": SEED, "ticks": ticks, "commands": _commands, "expected_hash": ""}
	var file: FileAccess = FileAccess.open("%s/%s.json" % [OUT_DIR, name], FileAccess.WRITE)
	assert(file != null, "open %s" % name)
	file.store_string(JSON.stringify(fixture, "\t") + "\n")
	file.close()
	print("wrote %s: %d commands, %d ticks" % [name, _commands.size(), ticks])
