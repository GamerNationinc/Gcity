## The ground (M7 spec claim 7). **Terrain is a consumer of the route graph, never the
## other way round.**
##
## The graph already said where the roads go. This says what the land under them does,
## and where the land and the road disagree it emits the thing that reconciles them: a
## bridge over a ravine, a cut or a tunnel through rock. The generator may not make a
## corridor it then blocks, so traversability here is arithmetic rather than a search.
##
## Two fields, which is the whole trick:
##
##   - **base**, long and shallow: the lie of the land. Roads follow this and nothing
##     else, so a road's grade is `2 × amplitude ÷ length`, and because no two places in
##     the world sit closer than [RouteGraph.MIN_SPACING_MM], that ratio is a constant
##     the generator cannot exceed. [MAX_GRADE_PERMILLE] is derived from it rather than
##     chosen, so the two can never drift apart.
##   - **relief**, short and deep: ridges, gullies, outcrops. Terrain has this, roads do
##     not. Every ravine and every crag is therefore a disagreement between the two, and
##     the carves are that disagreement written down.
##
## A town stands on flat ground: inside a settlement's reach the land is its anchor's
## base height and nothing else, which is also what keeps a town's sixty-metre streets
## from being the steepest roads in the world.
##
## Integers throughout, no floats anywhere near it: this is state, and state does not
## hold anything whose last bit depends on the machine.
class_name Terrain extends SimSystem

const SYSTEM_ID: StringName = &"terrain"

## Outside the gate the land is levelled to the city's ground for this far, so the road
## leaves the city on the level and the gate is a gate rather than a cliff (M7 design
## note, regions). Every place in the world is further out than this.
const GATE_APRON_MM: int = RouteGraph.MIN_SPACING_MM / 2

## How far the land rises and falls under the roads, in millimetres either way.
const BASE_AMPLITUDE_MM: int = 25_000
## How far apart the base field's lattice points are: long and shallow.
const BASE_LATTICE_MM: int = 8_192_000
## Ridges and gullies, which roads do not follow and so must cross.
const RELIEF_AMPLITUDE_MM: int = 90_000
const RELIEF_LATTICE_MM: int = 1_024_000
## The second, finer octave of relief: half the lattice, a third of the amplitude.
const RELIEF_OCTAVE_MM: int = RELIEF_LATTICE_MM / 4

## The steepest a road can be, in parts per thousand. **Derived, not chosen**: the
## worst case is the full swing of the base field over the shortest an edge can be.
const MAX_GRADE_PERMILLE: int = 2 * BASE_AMPLITUDE_MM * 1000 / RouteGraph.MIN_SPACING_MM

## How far the road may sit off the ground before something has to be built. Below this
## the road simply lies on the land.
const ON_GROUND_MM: int = 3_000
## Ground this far above the road stops being a cutting and becomes a tunnel.
const TUNNEL_MM: int = 25_000
## How many points along an edge the ground is read at when looking for what has to be
## built. A corridor is kilometres long and this is not a survey; it is enough to find
## the ravines and not so many that ten thousand worlds cannot be checked.
const SAMPLES_PER_EDGE: int = 32

## What gets built where the road and the ground disagree.
const CARVE_BRIDGE: StringName = &"bridge"
const CARVE_CUT: StringName = &"cut"
const CARVE_TUNNEL: StringName = &"tunnel"

var _routes: RouteGraph
var _seed: int = 0


func _init(routes: RouteGraph) -> void:
	_routes = routes


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


## The seed and a fingerprint of the land it makes. The graph carries its own hash, and
## terrain is a function of that graph and this seed — but a change to the noise alone
## would move neither, and a save would quietly restore different ground under the same
## roads. The probe is what notices.
func snapshot() -> Dictionary:
	return {"seed": _seed, "ground": terrain_hash()}


func attach(sim: SimRoot) -> Error:
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	generate(sim.get_seed())
	return OK


## Points the land at a world seed. There is nothing to build: the ground is answered
## where it is asked for, from the seed and the place. This is the whole of generation,
## and it exists so the land has the same shape of API as the graph it consumes.
func generate(world_seed: int) -> void:
	_seed = world_seed


# ---------------------------------------------------------------- the ground

## The lie of the land: long, shallow, and the only thing roads follow.
func base_mm(x: int, z: int) -> int:
	return _noise(x, z, BASE_LATTICE_MM, BASE_AMPLITUDE_MM, 1)


## Ridges, gullies and outcrops. Roads do not follow this, which is why there is
## anything to bridge or tunnel through.
func relief_mm(x: int, z: int) -> int:
	var coarse: int = _noise(x, z, RELIEF_LATTICE_MM, RELIEF_AMPLITUDE_MM * 3 / 4, 2)
	var fine: int = _noise(x, z, RELIEF_OCTAVE_MM, RELIEF_AMPLITUDE_MM / 4, 3)
	return coarse + fine


## What the ground does at a position, in millimetres above the world's datum.
##
## Flat inside a town: a settlement stands on ground someone levelled, which is both how
## towns are and what keeps a town's short streets from being the steepest roads there
## are.
func ground_mm(x: int, z: int) -> int:
	if RouteGraph._length_mm(0, 0, x, z) <= GATE_APRON_MM:
		return 0
	var anchor: int = town_under(x, z)
	if anchor != EntityIds.NONE:
		var at: Vector2i = _routes.position_of(anchor)
		return base_mm(at.x, at.y)
	return base_mm(x, z) + relief_mm(x, z)


## The town whose levelled ground covers a position, or NONE.
func town_under(x: int, z: int) -> int:
	for anchor: int in _routes.town_ids():
		var at: Vector2i = _routes.position_of(anchor)
		if RouteGraph._length_mm(at.x, at.y, x, z) <= SettlementKits.MAX_REACH_MM:
			return anchor
	return EntityIds.NONE


## How high the road stands where it meets a place. The base field, or the town's
## levelled ground when the place is part of one.
func node_height_mm(node: int) -> int:
	if not _routes.has_node(node) or _routes.kind_of(node) == RouteGraph.KIND_GATE:
		return 0
	var town: int = _routes.node_town(node)
	var at: Vector2i = _routes.position_of(town if town != EntityIds.NONE else node)
	return base_mm(at.x, at.y)


# ---------------------------------------------------------------- the roads

## How high the road runs, that far along an edge. A straight line between the two
## places it joins: roads do not follow the relief, they cross it.
func road_mm(edge_id: int, at_mm: int) -> int:
	var rec: Dictionary = _routes.edge(edge_id)
	if rec.is_empty():
		return 0
	var a: int = rec["a"]
	var b: int = rec["b"]
	var length: int = rec["length"]
	var from: int = node_height_mm(a)
	var to: int = node_height_mm(b)
	if length <= 0:
		return from
	var along: int = clampi(at_mm, 0, length)
	return from + (to - from) * along / length


## Where the road is, that far along an edge.
func road_at(edge_id: int, at_mm: int) -> Vector2i:
	var rec: Dictionary = _routes.edge(edge_id)
	if rec.is_empty():
		return Vector2i.ZERO
	var a: int = rec["a"]
	var b: int = rec["b"]
	var length: int = rec["length"]
	var from: Vector2i = _routes.position_of(a)
	var to: Vector2i = _routes.position_of(b)
	if length <= 0:
		return from
	var along: int = clampi(at_mm, 0, length)
	return Vector2i(
		from.x + (to.x - from.x) * along / length,
		from.y + (to.y - from.y) * along / length)


## How steep a road is, in parts per thousand. Never more than [MAX_GRADE_PERMILLE],
## and that is arithmetic rather than a promise: the rise is at most the base field's
## full swing and the run is at least the closest two places in a world may be.
func grade_permille(edge_id: int) -> int:
	var rec: Dictionary = _routes.edge(edge_id)
	if rec.is_empty():
		return 0
	var a: int = rec["a"]
	var b: int = rec["b"]
	var length: int = rec["length"]
	if length <= 0:
		return 0
	return absi(node_height_mm(b) - node_height_mm(a)) * 1000 / length


## What has to be built along an edge for the road to be a road: the spans where the
## land and the road disagree, in the order they are met.
##
## Ground below the road is a bridge; ground above it is a cutting, or a tunnel once
## there is enough of it overhead to go through rather than take the top off.
func carves_on(edge_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rec: Dictionary = _routes.edge(edge_id)
	if rec.is_empty():
		return out
	var length: int = rec["length"]
	var open_kind: StringName = &""
	var open_from: int = 0
	var deepest: int = 0
	var previous: int = 0
	for i: int in SAMPLES_PER_EDGE + 1:
		var at: int = length * i / SAMPLES_PER_EDGE
		var where: Vector2i = road_at(edge_id, at)
		var over: int = ground_mm(where.x, where.y) - road_mm(edge_id, at)
		var kind: StringName = _carve_for(over)
		if kind != open_kind:
			if open_kind != &"":
				out.append({"kind": open_kind, "from": open_from, "to": at, "depth": deepest})
			open_kind = kind
			# the land started disagreeing somewhere between the last reading and this
			# one, so the span begins back there rather than at the first point that
			# noticed. A bridge starts at the bank, not out over the gap — and a span
			# that only shows up in the final reading still has somewhere to be.
			open_from = previous
			deepest = 0
		deepest = maxi(deepest, absi(over))
		previous = at
	if open_kind != &"":
		out.append({"kind": open_kind, "from": open_from, "to": length, "depth": deepest})
	return out


static func _carve_for(over_mm: int) -> StringName:
	if over_mm > TUNNEL_MM:
		return CARVE_TUNNEL
	if over_mm > ON_GROUND_MM:
		return CARVE_CUT
	if over_mm < -ON_GROUND_MM:
		return CARVE_BRIDGE
	return &""


## True when an edge of the graph can actually be walked in the terrain it produced
## (M7 spec claim 7).
##
## Two halves, and both matter. The grade is the one that could fail, and cannot: it is
## bounded by the arithmetic above. The second is that every place the road is off the
## ground has something built there — true by construction, since that is what a carve
## *is*, but checked here so a bug in stitching the spans together would show up as an
## untraversable edge rather than as a hole in the world nobody looked at.
func is_traversable(edge_id: int) -> bool:
	var rec: Dictionary = _routes.edge(edge_id)
	if rec.is_empty():
		return false
	if grade_permille(edge_id) > MAX_GRADE_PERMILLE:
		return false
	var length: int = rec["length"]
	var carves: Array[Dictionary] = carves_on(edge_id)
	for i: int in SAMPLES_PER_EDGE + 1:
		var at: int = length * i / SAMPLES_PER_EDGE
		var where: Vector2i = road_at(edge_id, at)
		var over: int = ground_mm(where.x, where.y) - road_mm(edge_id, at)
		if _carve_for(over) == &"":
			continue
		if not _covered(carves, at):
			return false
	return true


static func _covered(carves: Array[Dictionary], at: int) -> bool:
	for carve: Dictionary in carves:
		var from: int = carve["from"]
		var to: int = carve["to"]
		if at >= from and at <= to:
			return true
	return false


## A fingerprint of the land, over a fixed ring of places around the city gate. Small on
## purpose: it exists to notice that the ground changed, not to describe it.
func terrain_hash() -> String:
	var probes: Array = []
	for i: int in 16:
		var x: int = (i % 4 - 2) * 3_000_000 + 500_000
		var z: int = (i / 4 - 2) * 3_000_000 + 500_000
		probes.append([x, z, ground_mm(x, z)])
	return StateHash.of({"seed": _seed, "probes": probes})


# ---------------------------------------------------------------- the noise

## Value noise on an integer lattice, interpolated with an integer smoothstep.
##
## A lattice point's value comes from hashing its coordinates with the world seed, so
## the land is a function of the seed and the place, in any order, on any machine.
func _noise(x: int, z: int, lattice: int, amplitude: int, salt: int) -> int:
	var gx: int = _floor_div(x, lattice)
	var gz: int = _floor_div(z, lattice)
	var fx: int = _smooth((x - gx * lattice) * 1000 / lattice)
	var fz: int = _smooth((z - gz * lattice) * 1000 / lattice)
	var top: int = _mix(_lattice(gx, gz, salt), _lattice(gx + 1, gz, salt), fx)
	var bottom: int = _mix(_lattice(gx, gz + 1, salt), _lattice(gx + 1, gz + 1, salt), fx)
	return _mix(top, bottom, fz) * amplitude / 1000


## The value at one lattice point, in thousandths either side of zero.
func _lattice(gx: int, gz: int, salt: int) -> int:
	var h: int = _seed * 374761393 + gx * 668265263 + gz * 2246822519 + salt * 3266489917
	h &= 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	h = (h ^ (h >> 16)) & 0x7FFFFFFF
	return h % 2001 - 1000


## Thousandths, eased at both ends: `t²(3 - 2t)`, which keeps the land smooth where one
## lattice cell meets the next instead of creasing along every boundary.
static func _smooth(t: int) -> int:
	var clamped: int = clampi(t, 0, 1000)
	return clamped * clamped * (3000 - 2 * clamped) / 1_000_000


static func _mix(a: int, b: int, t: int) -> int:
	return a + (b - a) * t / 1000


## Floor division that floors for negative numbers too. GDScript's `/` truncates toward
## zero, which would make the lattice cell at -1 the same as the one at 0 and put a
## seam through the origin.
static func _floor_div(value: int, by: int) -> int:
	if value < 0:
		return -((-value + by - 1) / by)
	return value / by


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 2 or typeof(state.get("seed")) != TYPE_INT or typeof(state.get("ground")) != TYPE_STRING:
		push_error("Terrain.restore: snapshot must be {\"seed\": int, \"ground\": String}")
		return ERR_INVALID_DATA
	var world: int = state["seed"]
	var claimed: String = state["ground"]
	var was: int = _seed
	generate(world)
	if terrain_hash() != claimed:
		push_error("Terrain.restore: seed %d now makes different ground (%s, save says %s)" % [
			world, terrain_hash().left(12), claimed.left(12)])
		generate(was)
		return ERR_INVALID_DATA
	return OK
