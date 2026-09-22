## Quest records (M5 spec claim 9; design doc §12, the quests app). A quest is content:
## objectives are events on the bus credited to an actor named in the payload,
## optionally filtered by tags, counted to a target; the reward is item templates
## spawned into the actor's inventory once on completion. `quest.accept` and
## `quest.abandon` are the actor's, and pause-safe. The director, offers, dialogue
## and site binding are M6/M7: nothing here decides who is offered what.
class_name QuestSystem extends SimSystem

const SYSTEM_ID: StringName = &"quests"
const KIND_QUEST: StringName = &"quest"
const COMMAND_ACCEPT: StringName = &"quest.accept"
const COMMAND_ABANDON: StringName = &"quest.abandon"
const EVENT_COMPLETED: StringName = &"quest.completed"
const STATUS_ACTIVE: String = "active"
const STATUS_COMPLETED: String = "completed"

var _content: ContentDb
var _actors: ActorSystem
var _items: ItemSystem
var _events: EventBus
## event -> [[quest id, objective index], ...]
var _rules: Dictionary = {}
## actor -> quest id -> {"status": String, "progress": Array[int]}
var _quests: Dictionary = {}
var _completed: int = 0


func _init(content: ContentDb, actors: ActorSystem, items: ItemSystem, events: EventBus) -> void:
	_content = content
	_actors = actors
	_items = items
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


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
	return OK


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
	var objectives: Array = t["objectives"]
	var progress: Array[int] = []
	for i: int in objectives.size():
		progress.append(0)
	var stored: Variant = _quests.get(actor)
	var table: Dictionary = stored if typeof(stored) == TYPE_DICTIONARY else {}
	table[quest] = {"status": STATUS_ACTIVE, "progress": progress}
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
			if rec.size() != 2 or typeof(rec.get("status")) != TYPE_STRING or typeof(rec.get("progress")) != TYPE_ARRAY:
				return _restore_fail("quest record")
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
			table[quest] = {"status": status, "progress": progress}
		out[actor] = table
	_quests = out
	_completed = completed
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("QuestSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
