extends GcityTest

## M6 spec claim 12: a site's agents patrol routes relative to the site. An agent keeps
## the cell its route is measured from (zero for agent.spawn, the site's origin for
## site.spawn), and walks the route's cells shifted by it. Metamorphic: the same route
## from origin O visits exactly the cells it visits from zero, each moved by O.

const SEED: int = 20261037
const M: int = 1000
const BASE: Vector3i = Vector3i(500, 0, 500)
const SHIFT: Vector3i = Vector3i(20, 0, -7)


func _sim_with_route() -> SimRoot:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	var cells: Array = []
	for c: Vector3i in [BASE, BASE + Vector3i(4, 0, 0), BASE + Vector3i(4, 0, 3), BASE + Vector3i(0, 0, 3)]:
		cells.append([c.x, c.y, c.z])
	assert_eq(db.add(&"patrol_route", &"zz_square", {"schema_version": 1, "description": "test", "cells": cells}), OK, "a square route")
	var watchman: Dictionary = db.get_entry(&"agent_profile", &"guard_sim").duplicate(true)
	watchman["stances"] = [{"stance": "hold", "weight": 1000}]
	assert_eq(db.add(&"agent_profile", &"zz_watchman", watchman), OK, "a guard who only holds")
	var sim: SimRoot = SimAssembly.build(SEED, db)
	assert_true(sim != null, "assembly")
	return sim


## The cells the agent stands in, in order of first visit, over `ticks`.
func _walk(sim: SimRoot, agent: int, ticks: int) -> Array[Vector3i]:
	var seen: Array[Vector3i] = []
	for i: int in ticks:
		sim.step()
		var c: Vector3i = BuildSystem.cell_of(SimAssembly.actors_of(sim).position_of(agent))
		if seen.is_empty() or seen[seen.size() - 1] != c:
			seen.append(c)
	return seen


func test_metamorphic_a_route_from_an_origin_is_the_same_walk_shifted() -> void:
	var a: SimRoot = _sim_with_route()
	var plain: int = SimAssembly.perception_of(a).spawn(&"zz_watchman", BASE, 0, 1, "zz_square")
	assert_eq(SimAssembly.perception_of(a).route_origin_of(plain), Vector3i.ZERO, "agent.spawn's origin is zero")
	var walk_a: Array[Vector3i] = _walk(a, plain, 1200)
	var b: SimRoot = _sim_with_route()
	var shifted: int = SimAssembly.perception_of(b).spawn(&"zz_watchman", BASE + SHIFT, 0, 1, "zz_square", SHIFT)
	assert_eq(SimAssembly.perception_of(b).route_origin_of(shifted), SHIFT, "its origin is kept")
	var walk_b: Array[Vector3i] = _walk(b, shifted, 1200)
	assert_true(walk_a.size() > 12, "the route was walked (%d cells)" % walk_a.size())
	assert_eq(walk_b.size(), walk_a.size(), "the same number of steps")
	var moved: Array[Vector3i] = []
	for c: Vector3i in walk_a:
		moved.append(c + SHIFT)
	assert_eq(walk_b, moved, "every cell moved by the origin")


func test_the_origin_survives_the_restore_and_a_bad_one_is_refused() -> void:
	var a: SimRoot = _sim_with_route()
	var perception: PerceptionSystem = SimAssembly.perception_of(a)
	var agent: int = perception.spawn(&"zz_watchman", BASE + SHIFT, 0, 1, "zz_square", SHIFT)
	var snap: Dictionary = perception.snapshot()
	var b: SimRoot = _sim_with_route()
	assert_eq(SimAssembly.restore_systems(b, a.snapshot()), OK, "restores")
	assert_eq(SimAssembly.perception_of(b).route_origin_of(agent), SHIFT, "kept")
	for bad_origin: Variant in [[1, 2], [1, 2, "3"], [0, 0, 999999999]]:
		var bad: Dictionary = snap.duplicate(true)
		var agents: Dictionary = bad["agents"]
		var rec: Dictionary = agents[agent]
		rec["origin"] = bad_origin
		assert_eq(SimAssembly.perception_of(b).restore(bad), ERR_INVALID_DATA, "origin %s refused" % str(bad_origin))
