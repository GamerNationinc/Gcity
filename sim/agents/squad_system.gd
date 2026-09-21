## Squads coordinate on the portal graph and report by radio, not telepathy (design
## doc §14.5; M4 spec claim 11). A squad is the set of agents sharing a squad id.
## When a member is alerted to a contact, and its profile has a radio, a report
## `squad.report {squad, contact, cell}` reaches the other living members after the
## reporter's `radio_latency_ticks`: each learns the contact's cell as a last-known
## position and rises to its own alert threshold, so it acts. Reports in flight are
## state. The planner then assigns each member outside the contact's volume a
## distinct entry edge of that volume, cheapest first in member order, so one takes
## the door while another covers the window; the stance layer walks to the cell
## outside the assigned edge. No radio, no report: killing or jamming the radio is
## the minimal form of the §7.4 signal machinery this grows into.
class_name SquadSystem extends SimSystem

const SYSTEM_ID: StringName = &"squads"
const EVENT_REPORT: StringName = &"squad.report"
const TOOL: StringName = &"cutter"

var _content: ContentDb
var _actors: ActorSystem
var _perception: PerceptionSystem
var _portals: PortalGraph
var _build: BuildSystem
var _events: EventBus
## [{"due": tick, "squad": int, "reporter": int, "contact": int, "cell": [x, y, z]}] in due, then submission order
var _reports: Array = []
## agent -> [x, y, z]: the cell outside the entry edge the planner assigned
var _assignments: Dictionary = {}
var _delivered: int = 0
## Set by build.changed: every assignment is re-planned on the next tick.
var _replan: bool = false


func _init(content: ContentDb, actors: ActorSystem, perception: PerceptionSystem, portals: PortalGraph, build: BuildSystem, events: EventBus) -> void:
	_content = content
	_actors = actors
	_perception = perception
	_portals = portals
	_build = build
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func snapshot() -> Dictionary:
	return {"reports": _reports.duplicate(true), "assignments": _assignments.duplicate(true), "delivered": _delivered, "replan": _replan}


func attach(sim: SimRoot) -> Error:
	var err: Error = validate_content()
	if err != OK:
		return err
	err = sim.register_system(self)
	if err != OK:
		return err
	err = _events.subscribe(PerceptionSystem.EVENT_ALERTED, _on_alerted)
	if err != OK:
		return err
	return _events.subscribe(BuildSystem.EVENT_CHANGED, _on_build_changed)


func validate_content() -> Error:
	for id: StringName in _content.ids(PerceptionSystem.KIND_AGENT):
		var t: Dictionary = _content.get_entry(PerceptionSystem.KIND_AGENT, id)
		if typeof(t.get("radio")) != TYPE_BOOL or typeof(t.get("radio_latency_ticks")) != TYPE_INT:
			push_error("SquadSystem: agent_profile/%s needs radio and radio_latency_ticks" % id)
			return ERR_INVALID_DATA
	return OK


# ---------------------------------------------------------------- queries

func has_radio(agent: int) -> bool:
	var profile: StringName = _perception.profile_of(agent)
	if profile.is_empty():
		return false
	var t: Dictionary = _content.get_entry(PerceptionSystem.KIND_AGENT, profile)
	return t["radio"]


func radio_latency(agent: int) -> int:
	var profile: StringName = _perception.profile_of(agent)
	if profile.is_empty():
		return 0
	var t: Dictionary = _content.get_entry(PerceptionSystem.KIND_AGENT, profile)
	return t["radio_latency_ticks"]


func pending_count() -> int:
	return _reports.size()


func delivered_count() -> int:
	return _delivered


func has_assignment(agent: int) -> bool:
	return _assignments.has(agent)


func assignment_of(agent: int) -> Vector3i:
	if not _assignments.has(agent):
		return Vector3i.ZERO
	return PathingSystem._vec(_assignments[agent])


## Living members of a squad in id order.
func members_of(squad: int) -> Array[int]:
	var out: Array[int] = []
	if squad <= 0:
		return out
	for agent: int in _perception.agent_ids():
		if _perception.squad_of(agent) == squad and _actors.is_alive(agent):
			out.append(agent)
	return out


# ---------------------------------------------------------------- events

func _on_alerted(payload: Dictionary) -> void:
	var observer: int = payload["observer"]
	var contact: int = payload["contact"]
	var tick_now: int = payload["tick"]
	var squad: int = _perception.squad_of(observer)
	if squad <= 0 or not has_radio(observer):
		return
	var cell: Vector3i = BuildSystem.cell_of(_actors.position_of(contact))
	_reports.append({"due": tick_now + radio_latency(observer), "squad": squad, "reporter": observer, "contact": contact, "cell": PathingSystem._arr(cell)})


func _on_build_changed(_payload: Dictionary) -> void:
	_replan = true


# ---------------------------------------------------------------- the tick

func tick(sim: SimRoot) -> void:
	var tick_now: int = sim.get_tick()
	# delivery alerts receivers, whose alerts append new reports: take the list first
	var pending: Array = _reports
	_reports = []
	var kept: Array = []
	var touched: Dictionary = {}
	for r: Variant in pending:
		var report: Dictionary = r
		var due: int = report["due"]
		if due > tick_now:
			kept.append(report)
			continue
		_deliver(report, tick_now)
		touched[report["squad"]] = true
	kept.append_array(_reports)
	_reports = kept
	if _replan:
		for agent: int in _assignments.keys():
			touched[_perception.squad_of(agent)] = true
		_replan = false
	for squad: Variant in touched:
		var id: int = squad
		_plan(id)
	for agent: int in _assignments.keys():
		if not _actors.is_alive(agent):
			_assignments.erase(agent)


func _deliver(report: Dictionary, tick_now: int) -> void:
	var squad: int = report["squad"]
	var reporter: int = report["reporter"]
	var contact: int = report["contact"]
	var cell: Vector3i = PathingSystem._vec(report["cell"])
	if not _actors.is_alive(contact):
		return
	var informed: Array[int] = []
	for member: int in members_of(squad):
		if member == reporter:
			continue
		var ground: Vector3i = BuildSystem.cell_centre(cell)
		ground.y = cell.y * BuildSystem.CELL
		if _perception.receive_report(member, contact, ground, tick_now):
			informed.append(member)
	_delivered += 1
	_events.emit(EVENT_REPORT, {"squad": squad, "reporter": reporter, "contact": contact, "cell": PathingSystem._arr(cell), "informed": informed})


## Assigns each member outside the contact's volume a distinct entry edge, cheapest
## first, in member order. Members inside the volume, or with no volume to enter,
## carry no assignment.
func _plan(squad: int) -> void:
	var members: Array[int] = members_of(squad)
	for member: int in members:
		_assignments.erase(member)
	if members.is_empty():
		return
	var contact: int = _squad_contact(members)
	if contact == EntityIds.NONE:
		return
	var contact_cell: Vector3i = _contact_cell(members, contact)
	var volume: int = _portals.node_at(contact_cell)
	if volume == PortalGraph.EXTERIOR or volume == PortalGraph.SOLID:
		return
	var edges: Array[Array] = _portals.edges_of(volume)
	var ranked: Array[Array] = []
	for e: Array in edges:
		var piece: int = e[0]
		var other: int = e[1]
		if other != PortalGraph.EXTERIOR:
			continue
		ranked.append([_portals.edge_cost(piece, TOOL), piece] as Array[int])
	ranked.sort()
	var next: int = 0
	for member: int in members:
		if next >= ranked.size():
			break
		var here: Vector3i = BuildSystem.cell_of(_actors.position_of(member))
		if _portals.node_at(here) == volume:
			continue
		var entry: Array = ranked[next]
		var piece: int = entry[1]
		var outside: Vector3i = _outside_cell(piece, volume)
		if outside == Vector3i(0, -1, 0):
			continue
		_assignments[member] = PathingSystem._arr(outside)
		next += 1


## The contact the most members know, ties to the lowest contact id.
func _squad_contact(members: Array[int]) -> int:
	var votes: Dictionary = {}
	for member: int in members:
		for contact: int in _actors.actor_ids():
			if contact == member or not _actors.is_alive(contact) or _perception.is_agent(contact) and _perception.squad_of(contact) == _perception.squad_of(member):
				continue
			if _perception.is_alerted(member, contact) or _perception.has_last_known(member, contact):
				votes[contact] = votes.get(contact, 0) + 1
	var best: int = EntityIds.NONE
	var best_votes: int = 0
	var ids: Array = votes.keys()
	ids.sort()
	for c: Variant in ids:
		var id: int = c
		var n: int = votes[c]
		if n > best_votes:
			best = id
			best_votes = n
	return best


## Where the squad believes the contact is: seen now by any member, else the
## freshest last-known position (the member with the most memory left).
func _contact_cell(members: Array[int], contact: int) -> Vector3i:
	var best_memory: int = -1
	var cell: Vector3i = Vector3i.ZERO
	for member: int in members:
		if _perception.sees(member, contact):
			return BuildSystem.cell_of(_actors.position_of(contact))
		if _perception.has_last_known(member, contact) and _perception.memory_of(member, contact) > best_memory:
			best_memory = _perception.memory_of(member, contact)
			cell = BuildSystem.cell_of(_perception.last_known(member, contact))
	return cell


## The air cell on the exterior side of an entry edge, or (0, -1, 0) if neither side
## is exterior air.
func _outside_cell(piece: int, volume: int) -> Vector3i:
	var rec: Dictionary = _build.piece(piece)
	var face: String = rec["face"]
	if face.is_empty():
		return Vector3i(0, -1, 0)
	for c: Vector3i in BuildSystem.face_cells(face):
		if _portals.node_at(c) == PortalGraph.EXTERIOR and _portals.node_at(c) != volume:
			return c
	return Vector3i(0, -1, 0)


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 4 or typeof(state.get("reports")) != TYPE_ARRAY or typeof(state.get("assignments")) != TYPE_DICTIONARY \
			or typeof(state.get("delivered")) != TYPE_INT or typeof(state.get("replan")) != TYPE_BOOL:
		return _restore_fail("shape")
	var delivered: int = state["delivered"]
	if delivered < 0:
		return _restore_fail("negative count")
	var reports_in: Array = state["reports"]
	var reports: Array = []
	for r: Variant in reports_in:
		if typeof(r) != TYPE_DICTIONARY:
			return _restore_fail("report shape")
		var report: Dictionary = r
		if report.size() != 5 or typeof(report.get("due")) != TYPE_INT or typeof(report.get("squad")) != TYPE_INT or typeof(report.get("reporter")) != TYPE_INT \
				or typeof(report.get("contact")) != TYPE_INT or not PathingSystem._is_cell(report.get("cell")):
			return _restore_fail("report fields")
		var reporter: int = report["reporter"]
		var contact: int = report["contact"]
		var squad: int = report["squad"]
		if not _perception.is_agent(reporter) or not _actors.has_actor(contact) or squad <= 0:
			return _restore_fail("report references")
		var due: int = report["due"]
		reports.append({"due": due, "squad": squad, "reporter": reporter, "contact": contact, "cell": PathingSystem._arr(PathingSystem._vec(report["cell"]))})
	var assignments_in: Dictionary = state["assignments"]
	var assignments: Dictionary = {}
	for key: Variant in assignments_in:
		if typeof(key) != TYPE_INT or not PathingSystem._is_cell(assignments_in[key]):
			return _restore_fail("assignment")
		var agent: int = key
		if not _perception.is_agent(agent):
			return _restore_fail("assignment for a non-agent")
		assignments[agent] = PathingSystem._arr(PathingSystem._vec(assignments_in[key]))
	var replan: bool = state["replan"]
	_reports = reports
	_assignments = assignments
	_delivered = delivered
	_replan = replan
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("SquadSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
