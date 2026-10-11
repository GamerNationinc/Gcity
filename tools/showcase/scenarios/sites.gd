## Showcase for M6 claim 12 (a site is content). The ground starts empty. One command,
## site.spawn, raises the whole M4 test building with its four guards on their patrols.
## A second site, a small outpost written only as data in this scenario, appears in one
## step with its parcel, a dug shaft under a street grate, an alarm on its window, a
## hack target, a guard on a route and an exit zone. Asking for it again is refused.
extends RefCounted

const OUTPOST: Vector3i = Vector3i(30, 0, 8)

var _phase: int = 0
## the sim's rejected-command count before each spawn request, to report what happened
var _rejected_before: int = -1


func title() -> String:
	return "Gcity M6 claim 12: A WHOLE PLACE FROM ONE CONTENT FILE"


func content(db: ContentDb) -> void:
	db.add(&"patrol_route", &"showcase_outpost_loop", {"schema_version": 1, "description": "showcase", "cells": [[1, 0, 3], [5, 0, 3], [5, 0, -2], [1, 0, -2]]})
	var pieces: Array = []
	for c: Array in [[-1, 0, 0], [0, 0, 1], [0, 0, -1], [3, 0, 0]]:
		pieces.append({"piece": "foundation_block", "cell": c, "facing": "", "sensor": "", "squad": 0})
	pieces.append({"piece": "floor_panel", "cell": [0, 0, 0], "facing": "py", "sensor": "", "squad": 0})
	pieces.append({"piece": "window_frame", "cell": [0, 0, 0], "facing": "px", "sensor": "power_monitor", "squad": 1})
	pieces.append({"piece": "street_grate", "cell": [2, -1, 0], "facing": "py", "sensor": "", "squad": 0})
	pieces.append({"piece": "storage_crate", "cell": [0, 0, 2], "facing": "", "sensor": "", "squad": 0})
	db.add(&"site", &"showcase_outpost", {"schema_version": 1, "description": "A small outpost, written only as data for the showcase.",
		"district": "starter_ghetto", "owner": "outpost_co",
		"parcels": [{"id": "lot", "footprint": [[-2, -3], [7, -3], [7, 5], [-2, 5]], "floor": -1, "ceiling": 3, "district": "", "owner": ""}],
		"excavate": [[2, -1, 0]], "pieces": pieces,
		"agents": [{"profile": "guard_sim", "cell": [1, 0, 3], "facing": 0, "squad": 1, "route": "showcase_outpost_loop"}],
		"hack_targets": [{"target": "power_monitor_spoof", "cell": [1, 0, -1], "piece": 5}],
		"placement": [0, 0, 0], "exfil": [[8, -3], [11, -3], [11, 5], [8, 5]]})


func setup(_sim: SimRoot, view: Node3D) -> void:
	var o: Vector3 = Vector3(19, 0, 10)
	view.call("slab", Vector3(-2, 0, -2), Vector2(46, 24), Color(0.3, 0.32, 0.36))
	view.call("place_camera", o + Vector3(-12, 24, -22), o, 32.0)
	view.call("pin", "m4", Vector3(7, 0.3, 5.5), "site 1: the M4 test building", Color(0.9, 0.9, 1.0))
	view.call("pin", "outpost", Vector3(OUTPOST.x + 2, 0.3, OUTPOST.z - 5.5), "site 2: an outpost (data only)", Color(0.9, 0.9, 1.0))


func before_tick(sim: SimRoot, view: Node3D, tick: int) -> void:
	if _rejected_before >= 0:
		# the request went in last tick: say what the sim did with it, not what we hoped
		if sim.rejected_count() > _rejected_before:
			view.call("note", "site.spawn REFUSED by the sim; nothing changed", 1)
		_rejected_before = -1
	var request: Dictionary = {}
	match tick:
		40:
			request = {"site": "m4_test_building", "origin": [0, 0, 0]}
			_phase = 1
		160:
			request = {"site": "showcase_outpost", "origin": [OUTPOST.x, OUTPOST.y, OUTPOST.z]}
			_phase = 2
		320:
			request = {"site": "showcase_outpost", "origin": [OUTPOST.x + 3, 0, OUTPOST.z]}
			view.call("note", "asking for the outpost a second time...", 1)
			_phase = 3
	if not request.is_empty():
		_rejected_before = sim.rejected_count()
		sim.submit(SimCommand.new(tick, &"site.spawn", request))


func ticks_per_frame(_tick: int) -> int:
	return 4


func end_tick() -> int:
	return 640


func caption(_tick: int) -> String:
	match _phase:
		0:
			return "Empty ground. Everything that is about to appear is written in content files, not code."
		1:
			return "One command, site.spawn \"m4_test_building\": 93 building pieces and 4 guards on their patrol routes appear at once."
		2:
			return "A second site, an outpost: its land parcel, a dug shaft under a street grate, an alarm on its window, a hack target, a guard and an EXIT ZONE, all from data."
	return "Asking for the outpost again is refused, and nothing changes: a site exists once. Cold Storage (next) is built exactly this way."
