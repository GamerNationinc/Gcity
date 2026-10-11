## Quest records (M5 spec claim 9; design doc §12, the quests app). A quest is content:
## objectives are events on the bus credited to an actor named in the payload,
## optionally filtered by tags, counted to a target; the reward is item templates
## spawned into the actor's inventory once on completion. `quest.accept` and
## `quest.abandon` are the actor's, and pause-safe. The director and offers are M7/M8:
## nothing here decides who is offered what.
##
## A contract (M6 spec claim 14) is a quest with a giver (a fixer), a site (a handle; the
## site's placement says where it stands), an item to deliver and scoring. Accepting it needs the fixer within reach,
## spawns the site if it is not yet, and opens a run record counting the §15.4
## counters for the actor from bus events: times detected (perception.alerted on the
## actor), alarms raised (a squad.report about the actor, which is how both a guard's
## report and a sensor's alarm reach the squad), bodies (a site agent the actor
## killed, cameras aside) and traces left (a site camera killed, a breach of a site
## piece; a breached opening, a forced one, counts once at exfil, as does every site
## terminal still logged in). Exfil is leaving the site's exfil polygon carrying the
## deliverable. `contract.deliver` at the fixer hands it over and pays the fixer's base
## credits times the first scoring tier the counters fit (tiers never pay more for a
## louder run), through the wallet, and emits contract.delivered.
class_name QuestSystem extends SimSystem

const SYSTEM_ID: StringName = &"quests"
const KIND_QUEST: StringName = &"quest"
const COMMAND_ACCEPT: StringName = &"quest.accept"
const COMMAND_ABANDON: StringName = &"quest.abandon"
const EVENT_COMPLETED: StringName = &"quest.completed"
const STATUS_ACTIVE: String = "active"
const STATUS_COMPLETED: String = "completed"
const KIND_FIXER: StringName = &"fixer"
const COMMAND_DELIVER: StringName = &"contract.deliver"
const EVENT_EXFIL: StringName = &"contract.exfil"
const EVENT_DELIVERED: StringName = &"contract.delivered"
const SOURCE_CONTRACT: StringName = &"contract.deliver"
const COUNTERS: Array[String] = ["times_detected", "alarms_raised", "bodies", "traces_left"]

var _content: ContentDb
var _actors: ActorSystem
var _items: ItemSystem
var _events: EventBus
var _sites: SiteSystem
var _wallet: WalletSystem
var _hacks: HackSystem
var _perception: PerceptionSystem
## event -> [[quest id, objective index], ...]
var _rules: Dictionary = {}
## actor -> quest id -> {"status": String, "progress": Array[int]} and, for a contract,
## "run": {"counters": {name: int}, "inside": bool, "exfil": bool, "forced": [piece ids]}
var _quests: Dictionary = {}
var _completed: int = 0


func _init(content: ContentDb, actors: ActorSystem, items: ItemSystem, events: EventBus, sites: SiteSystem, wallet: WalletSystem, hacks: HackSystem, perception: PerceptionSystem) -> void:
	_content = content
	_actors = actors
	_items = items
	_events = events
	_sites = sites
	_wallet = wallet
	_hacks = hacks
	_perception = perception


func system_id() -> StringName:
	return SYSTEM_ID


## Exfil (claim 14): an actor carrying a contract's deliverable who was inside its
## site's exfil polygon last tick and is outside it now has got out.
func tick(_sim: SimRoot) -> void:
	var actors: Array = _quests.keys()
	actors.sort()
	for a: Variant in actors:
		var actor: int = a
		var table: Dictionary = _quests[actor]
		var quests: Array = table.keys()
		quests.sort()
		for q: Variant in quests:
			var quest: StringName = StringName(str(q))
			var rec: Dictionary = table[q]
			if rec["status"] != STATUS_ACTIVE or not rec.has("run"):
				continue
			var run: Dictionary = rec["run"]
			var exfil: bool = run["exfil"]
			if exfil:
				continue
			var t: Dictionary = _content.get_entry(KIND_QUEST, quest)
			var site: String = t["site"]
			var inside_now: bool = _actors.is_alive(actor) and _sites.in_exfil(StringName(site), _actors.position_of(actor))
			var was_inside: bool = run["inside"]
			run["inside"] = inside_now
			if was_inside and not inside_now and _deliverable_of(actor, t) != EntityIds.NONE:
				run["exfil"] = true
				var counters: Dictionary = run["counters"]
				var traces: int = counters["traces_left"]
				var forced: Array = run["forced"]
				traces += forced.size()
				for target: int in _sites.targets_of(StringName(site)):
					if _hacks.login_of(target) == actor:
						traces += 1
				counters["traces_left"] = traces
				_events.emit(EVENT_EXFIL, {"actor": actor, "quest": quest})


func snapshot() -> Dictionary:
	return {"quests": _quests.duplicate(true), "completed": _completed}


func attach(sim: SimRoot) -> Error:
	var err: Error = validate_content()
	if err != OK:
		return err
	err = sim.register_system(self)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_ACCEPT, _on_accept, true)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_ABANDON, _on_abandon, true)
	if err != OK:
		return err
	err = sim.commands().register(COMMAND_DELIVER, _on_deliver)
	if err != OK:
		return err
	err = _wallet.register_source(SOURCE_CONTRACT)
	if err != OK:
		return err
	for pair: Array in [[PerceptionSystem.EVENT_ALERTED, _on_alerted], [SquadSystem.EVENT_REPORT, _on_report], [CombatSystem.EVENT_HIT, _on_hit], [BuildSystem.EVENT_BREACHED, _on_breached]]:
		var event: StringName = pair[0]
		var handler: Callable = pair[1]
		err = _events.subscribe(event, handler)
		if err != OK:
			return err
	_rules.clear()
	for quest: StringName in _content.ids(KIND_QUEST):
		var t: Dictionary = _content.get_entry(KIND_QUEST, quest)
		var objectives: Array = t["objectives"]
		for i: int in objectives.size():
			var o: Dictionary = objectives[i]
			var event_s: String = o["event"]
			var event: StringName = StringName(event_s)
			if not _rules.has(event):
				_rules[event] = []
				err = _events.subscribe(event, _on_event.bind(event))
				if err != OK:
					return err
			var list: Array = _rules[event]
			list.append([quest, i])
	return OK


## Rewards name spawnable kinds and real templates.
func validate_content() -> Error:
	for quest: StringName in _content.ids(KIND_QUEST):
		var t: Dictionary = _content.get_entry(KIND_QUEST, quest)
		var reward: Array = t["reward"]
		for r: Variant in reward:
			var rd: Dictionary = r
			var kind_s: String = rd["kind"]
			var template_s: String = rd["template"]
			if not ItemSystem.SPAWNABLE.has(StringName(kind_s)):
				push_error("QuestSystem: quest/%s rewards a kind that cannot be spawned: %s" % [quest, kind_s])
				return ERR_INVALID_DATA
			if not _content.has(StringName(kind_s), StringName(template_s)):
				push_error("QuestSystem: quest/%s rewards a template that does not exist: %s/%s" % [quest, kind_s, template_s])
				return ERR_INVALID_DATA
		var reason: String = _check_contract(t)
		if not reason.is_empty():
			push_error("QuestSystem: content rejected: quest/%s %s" % [quest, reason])
			return ERR_INVALID_DATA
	for fixer: StringName in _content.ids(KIND_FIXER):
		var f: Dictionary = _content.get_entry(KIND_FIXER, fixer)
		var freward: Array = f["reward"]
		for r: Variant in freward:
			var rd: Dictionary = r
			var fk: String = rd["kind"]
			var ft: String = rd["template"]
			if not ItemSystem.SPAWNABLE.has(StringName(fk)) or not _content.has(StringName(fk), StringName(ft)):
				push_error("QuestSystem: content rejected: fixer/%s rewards %s/%s, which cannot be spawned" % [fixer, fk, ft])
				return ERR_INVALID_DATA
	return OK


## A contract names a real fixer, site and deliverable, and its scoring tiers never
## pay more for a louder run: multipliers are non-increasing down the list, so the
## first tier a louder run fits is never earlier than a quieter run's. Any other quest
## leaves all of these empty.
func _check_contract(t: Dictionary) -> String:
	for key: String in ["giver", "site", "deliver"]:
		if typeof(t.get(key)) != TYPE_STRING:
			return "needs a string %s" % key
	if typeof(t.get("scoring")) != TYPE_DICTIONARY:
		return "needs scoring"
	var giver: String = t["giver"]
	var site: String = t["site"]
	var deliver: String = t["deliver"]
	if giver.is_empty():
		return "" if site.is_empty() and deliver.is_empty() else "names a site or a deliverable without a giver"
	if not _content.has(KIND_FIXER, StringName(giver)):
		return "names unknown fixer '%s'" % giver
	if not _content.has(SiteSystem.KIND_SITE, StringName(site)):
		return "names unknown site '%s'" % site
	if HackSystem.spawnable_kind(_content, StringName(deliver)) == &"":
		return "delivers '%s', which no spawnable kind names" % deliver
	var scoring: Dictionary = t["scoring"]
	var tiers: Array = scoring["tiers"]
	var last: int = 1 << 30
	for v: Variant in tiers:
		var tier: Dictionary = v
		var m: int = tier["multiplier_milli"]
		if m > last:
			return "has a scoring tier paying more than the one before it"
		last = m
	var otherwise: int = scoring["otherwise_milli"]
	if otherwise > last:
		return "pays more when no tier fits than its last tier"
	return ""


# ---------------------------------------------------------------- queries

func quest_ids() -> Array[StringName]:
	return _content.ids(KIND_QUEST)


func status_of(actor: int, quest: StringName) -> String:
	var rec: Dictionary = _record(actor, quest)
	if rec.is_empty():
		return ""
	return rec["status"]


## Objective counts so far, one per objective; empty if the actor has not accepted it.
func progress_of(actor: int, quest: StringName) -> Array[int]:
	var out: Array[int] = []
	var rec: Dictionary = _record(actor, quest)
	if rec.is_empty():
		return out
	var progress: Array = rec["progress"]
	for v: Variant in progress:
		var n: int = v
		out.append(n)
	return out


## Quests an actor has accepted or completed, in content order.
func quests_of(actor: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for quest: StringName in quest_ids():
		if not _record(actor, quest).is_empty():
			out.append(quest)
	return out


func completed_count() -> int:
	return _completed


func _record(actor: int, quest: StringName) -> Dictionary:
	var stored: Variant = _quests.get(actor)
	if typeof(stored) != TYPE_DICTIONARY:
		return {}
	var table: Dictionary = stored
	var rec_v: Variant = table.get(quest)
	if typeof(rec_v) != TYPE_DICTIONARY:
		return {}
	return rec_v


# ---------------------------------------------------------------- commands

## {"actor": int, "quest": string}: take a quest on. Once completed it stays so.
func _on_accept(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("quest")) != TYPE_STRING:
		return false
	var actor: int = payload["actor"]
	var quest_s: String = payload["quest"]
	var quest: StringName = StringName(quest_s)
	if not _actors.is_alive(actor) or not _content.has(KIND_QUEST, quest):
		return false
	if not _record(actor, quest).is_empty():
		return false
	var t: Dictionary = _content.get_entry(KIND_QUEST, quest)
	var giver: String = t["giver"]
	if not giver.is_empty():
		if not near_fixer(actor, StringName(giver)):
			return false
		var site: String = t["site"]
		if not _sites.is_spawned(StringName(site)) and not _sites.spawn(StringName(site), _sites.placement_of(StringName(site))):
			return false
	var objectives: Array = t["objectives"]
	var progress: Array[int] = []
	for i: int in objectives.size():
		progress.append(0)
	var stored: Variant = _quests.get(actor)
	var table: Dictionary = stored if typeof(stored) == TYPE_DICTIONARY else {}
	var rec: Dictionary = {"status": STATUS_ACTIVE, "progress": progress}
	if not giver.is_empty():
		var counters: Dictionary = {}
		for c: String in COUNTERS:
			counters[c] = 0
		rec["run"] = {"counters": counters, "inside": false, "exfil": false, "forced": [] as Array[int]}
	table[quest] = rec
	_quests[actor] = table
	return true


## {"actor": int, "quest": string}: drop an active quest; its progress is lost.
func _on_abandon(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("quest")) != TYPE_STRING:
		return false
	var actor: int = payload["actor"]
	var quest_s: String = payload["quest"]
	var quest: StringName = StringName(quest_s)
	var rec: Dictionary = _record(actor, quest)
	if rec.is_empty() or rec["status"] != STATUS_ACTIVE or not _actors.is_alive(actor):
		return false
	var table: Dictionary = _quests[actor]
	table.erase(quest)
	if table.is_empty():
		_quests.erase(actor)
	return true


# ---------------------------------------------------------------- contracts

## Whether an actor stands within a fixer's reach, on the fixer's storey.
func near_fixer(actor: int, fixer: StringName) -> bool:
	if not _actors.is_alive(actor) or not _content.has(KIND_FIXER, fixer):
		return false
	var f: Dictionary = _content.get_entry(KIND_FIXER, fixer)
	var cell: Vector3i = SiteSystem._cell(f["cell"])
	var pos: Vector3i = _actors.position_of(actor)
	if BuildSystem.cell_of(pos).y != cell.y:
		return false
	var at: Vector3i = BuildSystem.cell_centre(cell)
	var dx: int = pos.x - at.x
	var dz: int = pos.z - at.z
	var reach: int = f["reach_mm"]
	return dx * dx + dz * dz <= reach * reach


## A contract run's counters, empty when there is none.
func run_of(actor: int, quest: StringName) -> Dictionary:
	var rec: Dictionary = _record(actor, quest)
	if rec.is_empty() or not rec.has("run"):
		return {}
	return rec["run"]


## The multiplier (milli) the first tier the counters fit pays, and that tier's name
## ("" when none fits and `otherwise_milli` applies).
static func score(scoring: Dictionary, counters: Dictionary) -> Array:
	var tiers: Array = scoring["tiers"]
	for v: Variant in tiers:
		var tier: Dictionary = v
		var limits: Dictionary = tier["max"]
		var fits: bool = true
		for c: String in COUNTERS:
			var n: int = counters[c]
			var limit: int = limits[c]
			if n > limit:
				fits = false
				break
		if fits:
			return [tier["multiplier_milli"], tier["name"]]
	return [scoring["otherwise_milli"], ""]


func _deliverable_of(actor: int, t: Dictionary) -> int:
	var deliver: String = t["deliver"]
	for item: int in _items.items_in(ItemSystem.inventory_of(actor)):
		if _items.item_template(item) == StringName(deliver):
			return item
	return EntityIds.NONE


## {"actor": int, "quest": string}: at the fixer, with the deliverable, after exfil.
func _on_deliver(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 2 or typeof(payload.get("actor")) != TYPE_INT or typeof(payload.get("quest")) != TYPE_STRING:
		return false
	var actor: int = payload["actor"]
	var quest_s: String = payload["quest"]
	var quest: StringName = StringName(quest_s)
	var run: Dictionary = run_of(actor, quest)
	if run.is_empty() or _record(actor, quest)["status"] != STATUS_ACTIVE:
		return false
	var exfil: bool = run["exfil"]
	var t: Dictionary = _content.get_entry(KIND_QUEST, quest)
	var giver: StringName = StringName(str(t["giver"]))
	var item: int = _deliverable_of(actor, t)
	if not exfil or item == EntityIds.NONE or not near_fixer(actor, giver):
		return false
	var f: Dictionary = _content.get_entry(KIND_FIXER, giver)
	var base: int = f["base_credits"]
	var counters: Dictionary = run["counters"]
	var scoring: Dictionary = t["scoring"]
	var scored: Array = score(scoring, counters)
	var milli: int = scored[0]
	var tier: String = scored[1]
	var credits: int = base * milli / 1000
	if credits > 0 and not _wallet.credit(actor, credits, SOURCE_CONTRACT):
		return false
	var handed: bool = _items.hand_over(actor, item, giver)
	assert(handed, "the deliverable was in the actor's inventory")
	_reward(actor, f)
	var out: Dictionary = {"actor": actor, "quest": quest, "credits": credits, "multiplier_milli": milli, "tier": tier, "tags": ["quest.%s" % quest]}
	for c: String in COUNTERS:
		out[c] = counters[c]
	_events.emit(EVENT_DELIVERED, out)
	return true


## The open contract runs an event about `actor` counts towards: [[quest, run, site]].
func _runs_of(actor: int) -> Array:
	var out: Array = []
	var stored: Variant = _quests.get(actor)
	if typeof(stored) != TYPE_DICTIONARY:
		return out
	var table: Dictionary = stored
	var quests: Array = table.keys()
	quests.sort()
	for q: Variant in quests:
		var rec: Dictionary = table[q]
		if rec["status"] != STATUS_ACTIVE or not rec.has("run"):
			continue
		var run: Dictionary = rec["run"]
		var exfil: bool = run["exfil"]
		if exfil:
			continue
		var t: Dictionary = _content.get_entry(KIND_QUEST, StringName(str(q)))
		out.append([StringName(str(q)), run, StringName(str(t["site"]))])
	return out


func _count(actor: int, counter: String) -> void:
	for entry: Variant in _runs_of(actor):
		var e: Array = entry
		var run: Dictionary = e[1]
		var counters: Dictionary = run["counters"]
		var n: int = counters[counter]
		counters[counter] = n + 1


func _on_alerted(payload: Dictionary) -> void:
	var contact: int = payload["contact"]
	_count(contact, "times_detected")


func _on_report(payload: Dictionary) -> void:
	var contact: int = payload["contact"]
	_count(contact, "alarms_raised")


func _on_hit(payload: Dictionary) -> void:
	var killed: bool = payload["killed"]
	if not killed:
		return
	var shooter: int = payload["shooter"]
	var target: int = payload["target"]
	for entry: Variant in _runs_of(shooter):
		var e: Array = entry
		var run: Dictionary = e[1]
		var site: StringName = e[2]
		if not _sites.agents_of(site).has(target):
			continue
		var counters: Dictionary = run["counters"]
		var counter: String = "traces_left" if _perception.profile_of(target) == &"camera" else "bodies"
		var n: int = counters[counter]
		counters[counter] = n + 1


## A breach of a site piece: a trace now, or, for an opening (a forced opening),
## once at exfil. The piece is already gone, so whether it was an opening is read from
## the site's content by its place in the site's piece list.
func _on_breached(payload: Dictionary) -> void:
	if not payload.has("actor"):
		return
	var actor: int = payload["actor"]
	var piece: int = payload["piece"]
	for entry: Variant in _runs_of(actor):
		var e: Array = entry
		var run: Dictionary = e[1]
		var site: StringName = e[2]
		var index: int = _sites.pieces_of(site).find(piece)
		if index < 0:
			continue
		var st: Dictionary = _content.get_entry(SiteSystem.KIND_SITE, site)
		var entries: Array = st["pieces"]
		var spec: Dictionary = entries[index]
		var template: String = spec["piece"]
		var bp: Dictionary = _content.get_entry(&"build_piece", StringName(template))
		var kind: Dictionary = _content.get_entry(&"piece_kind", StringName(str(bp["kind"])))
		var passable: bool = kind["passable"]
		if passable:
			var forced: Array = run["forced"]
			forced.append(piece)
		else:
			var counters: Dictionary = run["counters"]
			var n: int = counters["traces_left"]
			counters["traces_left"] = n + 1


# ---------------------------------------------------------------- events

func _on_event(payload: Dictionary, event: StringName) -> void:
	var list: Array = _rules.get(event, [])
	var payload_tags: Array[String] = []
	var tags_v: Variant = payload.get("tags", [])
	if typeof(tags_v) == TYPE_ARRAY:
		var arr: Array = tags_v
		for t: Variant in arr:
			if typeof(t) == TYPE_STRING:
				payload_tags.append(t)
	for entry: Variant in list:
		var pair: Array = entry
		var quest: StringName = pair[0]
		var index: int = pair[1]
		var t: Dictionary = _content.get_entry(KIND_QUEST, quest)
		var objectives: Array = t["objectives"]
		var o: Dictionary = objectives[index]
		var credit_s: String = o["credit"]
		var actor_v: Variant = payload.get(credit_s)
		if typeof(actor_v) != TYPE_INT:
			continue
		var actor: int = actor_v
		var rec: Dictionary = _record(actor, quest)
		if rec.is_empty() or rec["status"] != STATUS_ACTIVE:
			continue
		var wanted: Array = o["tags_any"]
		if not wanted.is_empty():
			var matched: bool = false
			for w: Variant in wanted:
				if payload_tags.has(w):
					matched = true
					break
			if not matched:
				continue
		var progress: Array = rec["progress"]
		var count: int = o["count"]
		var now: int = progress[index]
		if now < count:
			progress[index] = now + 1
		if _all_done(progress, objectives):
			rec["status"] = STATUS_COMPLETED
			_completed += 1
			_reward(actor, t)
			_events.emit(EVENT_COMPLETED, {"actor": actor, "quest": quest})


static func _all_done(progress: Array, objectives: Array) -> bool:
	for i: int in objectives.size():
		var o: Dictionary = objectives[i]
		var count: int = o["count"]
		var n: int = progress[i]
		if n < count:
			return false
	return true


func _reward(actor: int, t: Dictionary) -> void:
	var reward: Array = t["reward"]
	var inv: StringName = ItemSystem.inventory_of(actor)
	var seed: int = 1
	for r: Variant in reward:
		var rd: Dictionary = r
		var kind_s: String = rd["kind"]
		var template_s: String = rd["template"]
		var count: int = rd["count"]
		for i: int in count:
			var id: int = _items.spawn(StringName(kind_s), StringName(template_s), inv, seed)
			assert(id != EntityIds.NONE, "content was validated; a reward spawns")
			seed += 1


# ---------------------------------------------------------------- restore

func restore(state: Dictionary) -> Error:
	if state.size() != 2 or typeof(state.get("quests")) != TYPE_DICTIONARY or typeof(state.get("completed")) != TYPE_INT:
		return _restore_fail("shape")
	var completed: int = state["completed"]
	if completed < 0:
		return _restore_fail("negative count")
	var in_all: Dictionary = state["quests"]
	var out: Dictionary = {}
	for key: Variant in in_all:
		if typeof(key) != TYPE_INT or typeof(in_all[key]) != TYPE_DICTIONARY:
			return _restore_fail("actor key")
		var actor: int = key
		if not _actors.has_actor(actor):
			return _restore_fail("actor %d is not an actor" % actor)
		var table_in: Dictionary = in_all[key]
		var table: Dictionary = {}
		for qk: Variant in table_in:
			if (typeof(qk) != TYPE_STRING and typeof(qk) != TYPE_STRING_NAME) or typeof(table_in[qk]) != TYPE_DICTIONARY:
				return _restore_fail("quest key")
			var quest: StringName = StringName(str(qk))
			if not _content.has(KIND_QUEST, quest):
				return _restore_fail("unknown quest %s" % quest)
			var rec: Dictionary = table_in[qk]
			var t_q: Dictionary = _content.get_entry(KIND_QUEST, quest)
			var contract: bool = not str(t_q["giver"]).is_empty()
			if rec.size() != (3 if contract else 2) or typeof(rec.get("status")) != TYPE_STRING or typeof(rec.get("progress")) != TYPE_ARRAY:
				return _restore_fail("quest record")
			var run: Dictionary = {}
			if contract:
				run = _restore_run(rec.get("run"))
				if run.is_empty():
					return _restore_fail("contract run")
			var status: String = rec["status"]
			if status != STATUS_ACTIVE and status != STATUS_COMPLETED:
				return _restore_fail("quest status")
			var t: Dictionary = _content.get_entry(KIND_QUEST, quest)
			var objectives: Array = t["objectives"]
			var progress_in: Array = rec["progress"]
			if progress_in.size() != objectives.size():
				return _restore_fail("quest progress length")
			var progress: Array[int] = []
			for i: int in progress_in.size():
				if typeof(progress_in[i]) != TYPE_INT:
					return _restore_fail("quest progress value")
				var n: int = progress_in[i]
				var o: Dictionary = objectives[i]
				var count: int = o["count"]
				if n < 0 or n > count:
					return _restore_fail("quest progress range")
				progress.append(n)
			if (status == STATUS_COMPLETED) != _all_done(progress, objectives):
				return _restore_fail("quest status disagrees with its progress")
			var clean: Dictionary = {"status": status, "progress": progress}
			if contract:
				clean["run"] = run
			table[quest] = clean
		out[actor] = table
	_quests = out
	_completed = completed
	return OK


## A contract run from a save, or {} if it is malformed.
func _restore_run(v: Variant) -> Dictionary:
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	var run: Dictionary = v
	if run.size() != 4 or typeof(run.get("counters")) != TYPE_DICTIONARY or typeof(run.get("inside")) != TYPE_BOOL \
			or typeof(run.get("exfil")) != TYPE_BOOL or typeof(run.get("forced")) != TYPE_ARRAY:
		return {}
	var counters_in: Dictionary = run["counters"]
	if counters_in.size() != COUNTERS.size():
		return {}
	var counters: Dictionary = {}
	for c: String in COUNTERS:
		if typeof(counters_in.get(c)) != TYPE_INT:
			return {}
		var n: int = counters_in[c]
		if n < 0:
			return {}
		counters[c] = n
	var forced: Array[int] = []
	var forced_in: Array = run["forced"]
	for f: Variant in forced_in:
		if typeof(f) != TYPE_INT:
			return {}
		var id: int = f
		if id <= 0 or forced.has(id):
			return {}
		forced.append(id)
	var inside: bool = run["inside"]
	var exfil: bool = run["exfil"]
	return {"counters": counters, "inside": inside, "exfil": exfil, "forced": forced}


func _restore_fail(reason: String) -> Error:
	push_error("QuestSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
