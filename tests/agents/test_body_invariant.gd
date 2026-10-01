extends GcityTest

## M7.5 spec claim 2, the body invariant: over 10 000 generated steps of building,
## walking, climbing and falling, no live actor ever has ground or a cell piece in any
## of its body cells, or a solid floor between two of them, and no accepted step ever
## crossed a face that was solid at any row of the body. Two-cell actors, from a
## profile the test adds, since the shipped profiles are one cell until claim 6.

const SEED: int = 20261320
const PROPERTY_CASES: int = 10_000
const STEPS_PER_ARENA: int = 100
const M: int = 1000
const TALL: StringName = &"tall_test"
const ARENA: int = 6
const PIECES: Array[StringName] = [&"foundation_block", &"wall_panel", &"door_frame", &"window_frame", &"floor_panel", &"roof_hatch", &"stair_flight", &"storage_crate"]
const SIDES: Array[String] = ["px", "nx", "pz", "nz", "py", "ny"]

var _sim: SimRoot
var _actors: ActorSystem
var _movement: MovementSystem
var _build: BuildSystem
var _builder: int = 0


func _setup() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content loads")
	var tall: Dictionary = db.get_entry(ActorSystem.KIND_PROFILE, &"arcade").duplicate(true)
	tall["body_cells"] = 2
	assert_eq(db.add(ActorSystem.KIND_PROFILE, TALL, tall), OK, "a two-cell profile")
	_sim = SimAssembly.build(SEED, db)
	assert_true(_sim != null, "assembly")
	_actors = SimAssembly.actors_of(_sim)
	_movement = SimAssembly.movement_of(_sim)
	_build = SimAssembly.build_of(_sim)
	_builder = _actors.spawn(&"arcade", 0)


## "cell" or "face": what a piece template takes up, from its kind.
func _occupies(piece: StringName) -> String:
	var db: ContentDb = _sim.get_system(&"content")
	var t: Dictionary = db.get_entry(BuildSystem.KIND_PIECE, piece)
	var kind_s: String = t["kind"]
	var k: Dictionary = db.get_entry(BuildSystem.KIND_PIECE_KIND, StringName(kind_s))
	var occupies: String = k["occupies"]
	return occupies


## The first rule the actor breaks, or "" when its body is where a body may be.
func _broken(actor: int) -> String:
	var feet: Vector3i = BuildSystem.cell_of(_actors.position_of(actor))
	var height: int = _movement.body_cells(actor)
	for row: int in height:
		var cell: Vector3i = feet + Vector3i(0, row, 0)
		if _build.cell_piece_at(cell) != EntityIds.NONE:
			return "a piece in body row %d at %s" % [row, cell]
		if row > 0:
			var floor_piece: int = _build.face_piece_at(BuildSystem.face_key(cell, "ny"))
			if floor_piece != EntityIds.NONE:
				var kind: Dictionary = _build.kind_data(floor_piece)
				var passable: bool = kind["passable"]
				if not passable:
					return "a solid floor inside the body at %s" % cell
	return ""


## Whether every face between `from` and `to` (one cell apart on x or z) is open or
## passable at every row of a body `height` tall.
func _crossing_open(actor: int, from: Vector3i, to: Vector3i, height: int) -> bool:
	var d: Vector3i = to - from
	var facing: String = "px" if d.x > 0 else ("nx" if d.x < 0 else ("pz" if d.z > 0 else "nz"))
	for row: int in height:
		var piece: int = _build.face_piece_at(BuildSystem.face_key(from + Vector3i(0, row, 0), facing))
		if piece != EntityIds.NONE and not _movement.passes(actor, piece):
			return false
	return true


func test_no_body_is_ever_inside_anything() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var failures: Array[String] = []
	var accepted: int = 0
	var placed: int = 0
	var refused_on_a_body: int = 0
	for arena: int in PROPERTY_CASES / STEPS_PER_ARENA:
		# a fresh sim per arena: the portal graph floods the bounding box of everything
		# built, so arenas side by side in one sim would make one enormous region
		_setup()
		var origin: Vector3i = Vector3i(0, 0, 600)
		var walker: int = _actors.spawn(TALL, 0)
		_actors.set_position(walker, (origin + Vector3i(ARENA / 2, 0, ARENA / 2)) * M + Vector3i(500, 0, 500))
		# something to build from: foundations on a third of the ground, never the walker's cell
		for x: int in ARENA + 1:
			for z: int in ARENA + 1:
				if rng.randi_range(0, 2) == 0 and Vector2i(x, z) != Vector2i(ARENA / 2, ARENA / 2):
					if _build.place(_builder, &"foundation_block", BuildSystem.cell_centre(origin + Vector3i(x, 0, z)), "") != EntityIds.NONE:
						placed += 1
		for step: int in STEPS_PER_ARENA:
			var roll: int = rng.randi_range(0, 9)
			if roll < 4:
				# build something somewhere in the arena, often right where the walker is
				var cell: Vector3i = origin + Vector3i(rng.randi_range(0, ARENA), rng.randi_range(0, 3), rng.randi_range(0, ARENA))
				if rng.randi_range(0, 2) == 0:
					cell = BuildSystem.cell_of(_actors.position_of(walker)) + Vector3i(0, rng.randi_range(0, 1), 0)
				var piece: StringName = PIECES[rng.randi_range(0, PIECES.size() - 1)]
				var facing: String = "" if _occupies(piece) == "cell" else SIDES[rng.randi_range(0, SIDES.size() - 1)]
				var id: int = _build.place(_builder, piece, BuildSystem.cell_centre(cell), facing)
				if id != EntityIds.NONE:
					placed += 1
				elif _build.would_enclose_a_body(piece, cell, facing):
					refused_on_a_body += 1
			else:
				var before: Vector3i = _actors.position_of(walker)
				var speed: int = _movement.speed_of(walker)
				var dy: int = rng.randi_range(-1, 1) if roll == 9 else 0
				var dx: int = rng.randi_range(-speed, speed)
				var dz: int = rng.randi_range(-speed, speed)
				if _movement.move(walker, dx, dz, dy):
					accepted += 1
					var a: Vector3i = BuildSystem.cell_of(before)
					var b: Vector3i = BuildSystem.cell_of(_actors.position_of(walker))
					a.y = b.y
					var mid: Vector3i = Vector3i(b.x, a.y, a.z)
					for pair: Array in [[a, mid], [mid, b]]:
						var p: Vector3i = pair[0]
						var q: Vector3i = pair[1]
						if p != q and not _crossing_open(walker, p, q, 2):
							failures.append("arena %d step %d: crossed a solid face %s -> %s" % [arena, step, p, q])
			_sim.step()  # gravity
			var broken: String = _broken(walker)
			if not broken.is_empty():
				failures.append("arena %d step %d: %s" % [arena, step, broken])
			if failures.size() > 5:
				break
		if failures.size() > 5:
			break
	assert_eq(failures, [] as Array[String], "the body invariant holds (%d moves, %d pieces placed, %d refused for a body)" % [accepted, placed, refused_on_a_body])
	assert_true(accepted > 1000 and placed > 500, "the property exercised moves and builds (%d, %d)" % [accepted, placed])
	assert_true(refused_on_a_body > 0, "some placements were refused because a body was there (%d)" % refused_on_a_body)
