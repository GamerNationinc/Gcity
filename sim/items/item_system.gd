## Item templates, instances, weapons with sockets, and magazines as ordered containers
## (design doc §11, §13.3; ADR-009; M1 spec claims 6–10).
##
## Every item instance is an entity (an int from [EntityIds]) that lives in exactly one
## container. Containers are named: `world`, `inv.<actor>`, `mag.<magazine item>`,
## `chamber.<weapon item>`, `socket.<weapon item>.<socket>`. Item conservation is the
## system's core property: no command creates, duplicates or destroys an item except
## `item.spawn` (and, later, `weapon.fire` consuming one round).
##
## Stats live in the [StatResolver]: a template's `stats` set bases on the instance's
## entity, an attached part's `modifiers` are added to the weapon's entity, and a
## chambered round inherits the weapon's tags so the wielder's perks reach it.
class_name ItemSystem extends SimSystem

const SYSTEM_ID: StringName = &"items"
const WORLD: StringName = &"world"
const KIND_FRAME: StringName = &"weapon_frame"
const KIND_PART: StringName = &"weapon_part"
const KIND_AMMO: StringName = &"ammo"
const KIND_SOCKET: StringName = &"weapon_socket"
const KIND_CALIBRE: StringName = &"calibre"
const SPAWNABLE: Array[StringName] = [KIND_FRAME, KIND_PART, KIND_AMMO]

const COMMAND_SPAWN: StringName = &"item.spawn"
const COMMAND_LOAD: StringName = &"magazine.load"
const COMMAND_UNLOAD: StringName = &"magazine.unload"
const COMMAND_ATTACH: StringName = &"weapon.attach"
const COMMAND_DETACH: StringName = &"weapon.detach"
const COMMAND_RELOAD_TACTICAL: StringName = &"weapon.reload_tactical"
const COMMAND_RELOAD_EMERGENCY: StringName = &"weapon.reload_emergency"

const MAX_SPAWN_COUNT: int = 100
const STAT_RELOAD_TICKS: StringName = &"reload_ticks"

var _content: ContentDb
var _stats: StatResolver
var _ids: EntityIds
var _name_regex: RegEx = RegEx.create_from_string("^[a-z0-9][a-z0-9_.]*$")

## item id -> {"kind": StringName, "template": StringName, "seed": int, "affixes": Array}
var _items: Dictionary = {}
## container name -> Array[int] item ids, ordered (last = top)
var _containers: Dictionary = {}
## item id -> container name
var _location: Dictionary = {}
## weapon id -> {socket: part id}
var _sockets: Dictionary = {}
## weapon id -> tick until which weapon commands are rejected
var _busy_until: Dictionary = {}
## part id -> Array[int] resolver handles it contributed to its weapon
var _part_handles: Dictionary = {}


func _init(content: ContentDb, stats: StatResolver, ids: EntityIds) -> void:
	_content = content
	_stats = stats
	_ids = ids
	_containers[WORLD] = [] as Array[int]


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


func snapshot() -> Dictionary:
	return {
		"items": _items.duplicate(true),
		"containers": _containers.duplicate(true),
		"sockets": _sockets.duplicate(true),
		"busy_until": _busy_until.duplicate(),
		"part_handles": _part_handles.duplicate(true),
	}


## Validates the content this system reads and registers the system and its commands.
func attach(sim: SimRoot) -> Error:
	var err: Error = validate_content()
	if err != OK:
		return err
	err = sim.register_system(self)
	if err != OK:
		return err
	var registry: CommandRegistry = sim.commands()
	for pair: Array in [
		[COMMAND_SPAWN, _on_spawn], [COMMAND_LOAD, _on_load], [COMMAND_UNLOAD, _on_unload],
		[COMMAND_ATTACH, _on_attach], [COMMAND_DETACH, _on_detach],
		[COMMAND_RELOAD_TACTICAL, _on_reload_tactical], [COMMAND_RELOAD_EMERGENCY, _on_reload_emergency],
	]:
		var kind: StringName = pair[0]
		var handler: Callable = pair[1]
		err = registry.register(kind, handler)
		if err != OK:
			return err
	return OK


# ---------------------------------------------------------------- content validation

## The build-time validator checks shape and cross-references; this checks meaning the
## sim depends on: modifier classes exist, container sockets carry capacity + calibre.
func validate_content() -> Error:
	for socket: StringName in _content.ids(KIND_SOCKET):
		var contains: StringName = _socket_contains(socket)
		if not contains.is_empty() and contains != KIND_AMMO:
			return _content_fail("weapon_socket/%s contains '%s'; only ammo containers exist at M1" % [socket, contains])
	for frame: StringName in _content.ids(KIND_FRAME):
		var t: Dictionary = _content.get_entry(KIND_FRAME, frame)
		var container_sockets: int = 0
		var sockets: Array = t["sockets"]
		for s: Variant in sockets:
			if not _socket_contains(_as_name(s)).is_empty():
				container_sockets += 1
		if container_sockets != 1:
			return _content_fail("weapon_frame/%s must declare exactly one container socket, has %d" % [frame, container_sockets])
		if _check_stats_list(t["stats"], "weapon_frame/%s" % frame) != OK:
			return ERR_INVALID_DATA
	for part: StringName in _content.ids(KIND_PART):
		var t: Dictionary = _content.get_entry(KIND_PART, part)
		var socket: StringName = _as_name(t["socket"])
		var is_container: bool = not _socket_contains(socket).is_empty()
		if is_container and (typeof(t.get("capacity")) != TYPE_INT or typeof(t.get("calibre")) != TYPE_STRING):
			return _content_fail("weapon_part/%s fits a container socket and needs capacity and calibre" % part)
		if not is_container and (t.has("capacity") or t.has("calibre")):
			return _content_fail("weapon_part/%s is not a container and must not declare capacity or calibre" % part)
		var mods: Array = t["modifiers"]
		for m: Variant in mods:
			var md: Dictionary = m
			var cls: StringName = _as_name(md["class"])
			if not _stats.class_ids().has(cls):
				return _content_fail("weapon_part/%s uses unregistered modifier class '%s'" % [part, cls])
			if not _stats.has_stat(_as_name(md["stat"])):
				return _content_fail("weapon_part/%s modifies unregistered stat '%s'" % [part, md["stat"]])
	for ammo: StringName in _content.ids(KIND_AMMO):
		var t: Dictionary = _content.get_entry(KIND_AMMO, ammo)
		if _check_stats_list(t["stats"], "ammo/%s" % ammo) != OK:
			return ERR_INVALID_DATA
	return OK


func _check_stats_list(list: Variant, where: String) -> Error:
	if typeof(list) != TYPE_ARRAY:
		return _content_fail("%s stats must be an array" % where)
	var arr: Array = list
	var seen: Array[StringName] = []
	for e: Variant in arr:
		var d: Dictionary = e
		var stat: StringName = _as_name(d["stat"])
		if not _stats.has_stat(stat):
			return _content_fail("%s sets unregistered stat '%s'" % [where, stat])
		if seen.has(stat):
			return _content_fail("%s sets stat '%s' twice" % [where, stat])
		seen.append(stat)
	return OK


func _content_fail(reason: String) -> Error:
	push_error("ItemSystem: content rejected: %s" % reason)
	return ERR_INVALID_DATA


# ---------------------------------------------------------------- queries

static func inventory_of(actor: int) -> StringName:
	return StringName("inv.%d" % actor)


static func magazine_container(magazine: int) -> StringName:
	return StringName("mag.%d" % magazine)


static func chamber_container(weapon: int) -> StringName:
	return StringName("chamber.%d" % weapon)


static func socket_container(weapon: int, socket: StringName) -> StringName:
	return StringName("socket.%d.%s" % [weapon, socket])


func has_item(item: int) -> bool:
	return _items.has(item)


func item_kind(item: int) -> StringName:
	if not _items.has(item):
		return &""
	var rec: Dictionary = _items[item]
	return rec["kind"]


func item_template(item: int) -> StringName:
	if not _items.has(item):
		return &""
	var rec: Dictionary = _items[item]
	return rec["template"]


func container_of(item: int) -> StringName:
	return _location.get(item, &"")


## Items in a container, bottom to top. A copy.
func items_in(container: StringName) -> Array[int]:
	var out: Array[int] = []
	var stored: Variant = _containers.get(container)
	if typeof(stored) == TYPE_ARRAY:
		var arr: Array = stored
		for v: Variant in arr:
			var id: int = v
			out.append(id)
	return out


func item_count() -> int:
	return _items.size()


## Capacity of a container, or -1 for unlimited.
func capacity_of(container: StringName) -> int:
	var text: String = String(container)
	if text.begins_with("mag."):
		var mag: int = int(text.trim_prefix("mag."))
		if not _is_magazine(mag):
			return 0
		var t: Dictionary = _template_of(mag)
		var capacity: int = t.get("capacity", 0)
		return capacity
	if text.begins_with("chamber.") or text.begins_with("socket."):
		return 1
	return -1


func socket_part(weapon: int, socket: StringName) -> int:
	var sockets: Variant = _sockets.get(weapon)
	if typeof(sockets) != TYPE_DICTIONARY:
		return EntityIds.NONE
	var dict: Dictionary = sockets
	return dict.get(socket, EntityIds.NONE)


## The frame's socket that holds rounds (`weapon_socket.contains == ammo`), or "".
func magazine_socket_of(weapon: int) -> StringName:
	if item_kind(weapon) != KIND_FRAME:
		return &""
	var t: Dictionary = _template_of(weapon)
	var sockets: Array = t["sockets"]
	for s: Variant in sockets:
		var name: StringName = _as_name(s)
		if _socket_contains(name) == KIND_AMMO:
			return name
	return &""


func magazine_of(weapon: int) -> int:
	var socket: StringName = magazine_socket_of(weapon)
	if socket.is_empty():
		return EntityIds.NONE
	return socket_part(weapon, socket)


func chambered(weapon: int) -> int:
	var rounds: Array[int] = items_in(chamber_container(weapon))
	return rounds[0] if not rounds.is_empty() else EntityIds.NONE


func rounds_in(magazine: int) -> Array[int]:
	return items_in(magazine_container(magazine))


func is_busy(weapon: int, tick: int) -> bool:
	return _busy_until.get(weapon, -1) > tick


func busy_until(weapon: int) -> int:
	return _busy_until.get(weapon, -1)


# ---------------------------------------------------------------- spawning

## Creates an instance of a template inside `world` or an `inv.<actor>` container.
## Returns the new item id, or 0 with an error.
func spawn(kind: StringName, template: StringName, container: StringName, seed: int) -> int:
	if not SPAWNABLE.has(kind):
		push_error("ItemSystem: cannot spawn kind '%s'" % kind)
		return EntityIds.NONE
	if not _content.has(kind, template):
		push_error("ItemSystem: no template %s/%s" % [kind, template])
		return EntityIds.NONE
	if not _is_open_container(container):
		push_error("ItemSystem: can only spawn into world or an inventory, not '%s'" % container)
		return EntityIds.NONE
	var id: int = _ids.allocate()
	_items[id] = {"kind": kind, "template": template, "seed": seed, "affixes": [] as Array}
	if not _containers.has(container):
		_containers[container] = [] as Array[int]
	var list: Array[int] = _containers[container]
	list.append(id)
	_location[id] = container
	var t: Dictionary = _content.get_entry(kind, template)
	if t.has("stats"):
		var stats: Array = t["stats"]
		for e: Variant in stats:
			var d: Dictionary = e
			var value: int = d["value"]
			_stats.set_base(id, _as_name(d["stat"]), value)
	if t.has("tags"):
		_stats.set_tags(id, _names(t["tags"]))
	return id


# ---------------------------------------------------------------- commands
# Payloads are untrusted: exact key sets, typed fields, ownership, capacity. A handler
# returns false without touching state on any surprise (docs/extending-sim-systems.md).

## {"kind": name, "template": name, "container": name, "seed": int, "count": 1..100}
func _on_spawn(_sim: SimRoot, payload: Dictionary) -> bool:
	if not _keys_are(payload, ["kind", "template", "container", "seed", "count"]):
		return false
	var kind: StringName = _payload_name(payload, "kind")
	var template: StringName = _payload_name(payload, "template")
	var container: StringName = _payload_name(payload, "container")
	if kind.is_empty() or template.is_empty() or container.is_empty():
		return false
	if typeof(payload["seed"]) != TYPE_INT or typeof(payload["count"]) != TYPE_INT:
		return false
	var count: int = payload["count"]
	var seed: int = payload["seed"]
	if count < 1 or count > MAX_SPAWN_COUNT:
		return false
	if not SPAWNABLE.has(kind) or not _content.has(kind, template) or not _is_open_container(container):
		return false
	for i: int in range(count):
		var id: int = spawn(kind, template, container, seed + i)
		assert(id != EntityIds.NONE, "spawn validated above must succeed")
	return true


## {"actor": int, "magazine": int, "round": int}: push a loose round into a loose magazine.
func _on_load(_sim: SimRoot, payload: Dictionary) -> bool:
	if not _keys_are(payload, ["actor", "magazine", "round"]) or not _ints(payload, ["actor", "magazine", "round"]):
		return false
	var actor: int = payload["actor"]
	var magazine: int = payload["magazine"]
	var round: int = payload["round"]
	var inv: StringName = inventory_of(actor)
	if _location.get(magazine) != inv or _location.get(round) != inv:
		return false
	if not _is_magazine(magazine) or item_kind(round) != KIND_AMMO:
		return false
	var mag_t: Dictionary = _template_of(magazine)
	var round_t: Dictionary = _template_of(round)
	if mag_t["calibre"] != round_t["calibre"]:
		return false
	var mag_container: StringName = magazine_container(magazine)
	if items_in(mag_container).size() >= capacity_of(mag_container):
		return false
	_move(round, mag_container)
	return true


## {"actor": int, "magazine": int}: pop the top round of a loose magazine into the inventory.
func _on_unload(_sim: SimRoot, payload: Dictionary) -> bool:
	if not _keys_are(payload, ["actor", "magazine"]) or not _ints(payload, ["actor", "magazine"]):
		return false
	var actor: int = payload["actor"]
	var magazine: int = payload["magazine"]
	var inv: StringName = inventory_of(actor)
	if _location.get(magazine) != inv or not _is_magazine(magazine):
		return false
	var rounds: Array[int] = rounds_in(magazine)
	if rounds.is_empty():
		return false
	_move(rounds[rounds.size() - 1], inv)
	return true


## {"actor": int, "weapon": int, "part": int}: fit a loose part into its empty socket.
## Magazines go through the reload commands, never through attach.
func _on_attach(sim: SimRoot, payload: Dictionary) -> bool:
	if not _keys_are(payload, ["actor", "weapon", "part"]) or not _ints(payload, ["actor", "weapon", "part"]):
		return false
	var actor: int = payload["actor"]
	var weapon: int = payload["weapon"]
	var part: int = payload["part"]
	var inv: StringName = inventory_of(actor)
	if _location.get(weapon) != inv or _location.get(part) != inv:
		return false
	if item_kind(weapon) != KIND_FRAME or item_kind(part) != KIND_PART or is_busy(weapon, sim.get_tick()):
		return false
	var part_t: Dictionary = _template_of(part)
	var socket: StringName = _as_name(part_t["socket"])
	if not _socket_contains(socket).is_empty():
		return false
	if not _fits(part, weapon) or socket_part(weapon, socket) != EntityIds.NONE:
		return false
	_move(part, socket_container(weapon, socket))
	_set_socket(weapon, socket, part)
	var handles: Array[int] = []
	var mods: Array = part_t["modifiers"]
	for m: Variant in mods:
		var md: Dictionary = m
		var value: int = md["value"]
		var handle: int = _stats.add_modifier(weapon, {
			"stat": _as_name(md["stat"]), "class": _as_name(md["class"]), "value": value,
			"source": StringName("part.%s" % item_template(part)),
		})
		assert(handle >= 1, "content was validated; modifier must be accepted")
		handles.append(handle)
	_part_handles[part] = handles
	return true


## {"actor": int, "weapon": int, "socket": name}: remove the part in a socket to the inventory.
func _on_detach(sim: SimRoot, payload: Dictionary) -> bool:
	if not _keys_are(payload, ["actor", "weapon", "socket"]) or not _ints(payload, ["actor", "weapon"]):
		return false
	var actor: int = payload["actor"]
	var weapon: int = payload["weapon"]
	var socket: StringName = _payload_name(payload, "socket")
	var inv: StringName = inventory_of(actor)
	if socket.is_empty() or _location.get(weapon) != inv or item_kind(weapon) != KIND_FRAME:
		return false
	if not _socket_contains(socket).is_empty() or is_busy(weapon, sim.get_tick()):
		return false
	var part: int = socket_part(weapon, socket)
	if part == EntityIds.NONE:
		return false
	_remove_part_modifiers(part)
	_set_socket(weapon, socket, EntityIds.NONE)
	_move(part, inv)
	return true


## {"actor": int, "weapon": int, "magazine": int}: swap magazines, keeping the old one.
func _on_reload_tactical(sim: SimRoot, payload: Dictionary) -> bool:
	return _reload(sim, payload, true)


## Same, dropping the old magazine to the world.
func _on_reload_emergency(sim: SimRoot, payload: Dictionary) -> bool:
	return _reload(sim, payload, false)


func _reload(sim: SimRoot, payload: Dictionary, keep_old: bool) -> bool:
	if not _keys_are(payload, ["actor", "weapon", "magazine"]) or not _ints(payload, ["actor", "weapon", "magazine"]):
		return false
	var actor: int = payload["actor"]
	var weapon: int = payload["weapon"]
	var magazine: int = payload["magazine"]
	var inv: StringName = inventory_of(actor)
	if _location.get(weapon) != inv or _location.get(magazine) != inv:
		return false
	if item_kind(weapon) != KIND_FRAME or not _is_magazine(magazine) or is_busy(weapon, sim.get_tick()):
		return false
	var socket: StringName = magazine_socket_of(weapon)
	var mag_t: Dictionary = _template_of(magazine)
	var frame_t: Dictionary = _template_of(weapon)
	if _as_name(mag_t["socket"]) != socket or mag_t["calibre"] != frame_t["calibre"] or not _fits(magazine, weapon):
		return false
	var old: int = socket_part(weapon, socket)
	if old != EntityIds.NONE:
		_remove_part_modifiers(old)
		_move(old, inv if keep_old else WORLD)
	_move(magazine, socket_container(weapon, socket))
	_set_socket(weapon, socket, magazine)
	var handles: Array[int] = []
	var mods: Array = mag_t["modifiers"]
	for m: Variant in mods:
		var md: Dictionary = m
		var value: int = md["value"]
		var handle: int = _stats.add_modifier(weapon, {
			"stat": _as_name(md["stat"]), "class": _as_name(md["class"]), "value": value,
			"source": StringName("part.%s" % item_template(magazine)),
		})
		assert(handle >= 1, "content was validated; modifier must be accepted")
		handles.append(handle)
	_part_handles[magazine] = handles
	if chambered(weapon) == EntityIds.NONE:
		var rounds: Array[int] = rounds_in(magazine)
		if not rounds.is_empty():
			_chamber(weapon, rounds[rounds.size() - 1])
	var reload_ticks: int = maxi(1, _stats.resolve(weapon, STAT_RELOAD_TICKS) / 1000)
	_busy_until[weapon] = sim.get_tick() + reload_ticks
	return true


# ---------------------------------------------------------------- for the combat system

## Destroys the chambered round: the one sanctioned way an item leaves the world
## besides never having been spawned. Returns the consumed round's id, or 0.
func consume_chambered(weapon: int) -> int:
	var round: int = chambered(weapon)
	if round == EntityIds.NONE:
		return EntityIds.NONE
	var container: StringName = chamber_container(weapon)
	var list: Array[int] = _containers[container]
	list.erase(round)
	_containers.erase(container)
	_location.erase(round)
	_items.erase(round)
	_stats.forget_entity(round)
	return round


## Moves the seated magazine's top round into an empty chamber. Returns the round, or 0.
func chamber_next(weapon: int) -> int:
	if chambered(weapon) != EntityIds.NONE:
		return EntityIds.NONE
	var magazine: int = magazine_of(weapon)
	if magazine == EntityIds.NONE:
		return EntityIds.NONE
	var rounds: Array[int] = rounds_in(magazine)
	if rounds.is_empty():
		return EntityIds.NONE
	var round: int = rounds[rounds.size() - 1]
	_chamber(weapon, round)
	return round


## Marks a weapon busy until a tick (cycling, reloading). Never shortens an existing window.
func set_busy(weapon: int, until_tick: int) -> void:
	if not _items.has(weapon):
		push_error("ItemSystem: set_busy on unknown item %d" % weapon)
		return
	var current: int = _busy_until.get(weapon, -1)
	_busy_until[weapon] = maxi(until_tick, current)


# ---------------------------------------------------------------- restore

## Loads item state from a snapshot produced by [method snapshot]. Untrusted input:
## every item must exist exactly once in a container of a known name whose capacity
## holds, every template must exist, every socket entry must point at a part in the
## matching socket container. The system is untouched unless everything checks out.
## The resolver's matching state is restored separately from its own snapshot.
func restore(state: Dictionary) -> Error:
	if not _keys_are(state, ["items", "containers", "sockets", "busy_until", "part_handles"]):
		return _restore_fail("key set")
	for key: String in ["items", "containers", "sockets", "busy_until", "part_handles"]:
		if typeof(state[key]) != TYPE_DICTIONARY:
			return _restore_fail("'%s' must be a dictionary" % key)
	var items_in: Dictionary = state["items"]
	var new_items: Dictionary = {}
	for ik: Variant in items_in:
		if typeof(ik) != TYPE_INT or ik < 1 or typeof(items_in[ik]) != TYPE_DICTIONARY:
			return _restore_fail("item key or record")
		var rec: Dictionary = items_in[ik]
		if not _keys_are(rec, ["kind", "template", "seed", "affixes"]) or typeof(rec["seed"]) != TYPE_INT or typeof(rec["affixes"]) != TYPE_ARRAY:
			return _restore_fail("item %d record" % ik)
		var kind: StringName = _as_name(rec["kind"])
		var template: StringName = _as_name(rec["template"])
		if not SPAWNABLE.has(kind) or not _content.has(kind, template):
			return _restore_fail("item %d template %s/%s" % [ik, kind, template])
		var affixes: Array = rec["affixes"]
		if not affixes.is_empty():
			return _restore_fail("item %d has affixes; none exist at M1" % ik)
		new_items[ik] = {"kind": kind, "template": template, "seed": rec["seed"], "affixes": [] as Array}
	var containers_in: Dictionary = state["containers"]
	var new_containers: Dictionary = {}
	var new_location: Dictionary = {}
	for ck: Variant in containers_in:
		var name: StringName = _as_name(ck)
		if name.is_empty() or typeof(containers_in[ck]) != TYPE_ARRAY:
			return _restore_fail("container key or list")
		if not _is_open_container(name) and not _is_closed_container_name(name, new_items):
			return _restore_fail("unknown container '%s'" % name)
		var arr: Array = containers_in[ck]
		var list: Array[int] = []
		for v: Variant in arr:
			if typeof(v) != TYPE_INT or not new_items.has(v) or new_location.has(v):
				return _restore_fail("container '%s' holds an unknown or duplicated item" % name)
			list.append(v)
			new_location[v] = name
		new_containers[name] = list
	if new_location.size() != new_items.size():
		return _restore_fail("%d items but %d placed" % [new_items.size(), new_location.size()])
	if not new_containers.has(WORLD):
		new_containers[WORLD] = [] as Array[int]
	var sockets_in: Dictionary = state["sockets"]
	var new_sockets: Dictionary = {}
	for wk: Variant in sockets_in:
		if typeof(wk) != TYPE_INT or not new_items.has(wk) or typeof(sockets_in[wk]) != TYPE_DICTIONARY:
			return _restore_fail("socket weapon key")
		var wrec: Dictionary = new_items[wk]
		if wrec["kind"] != KIND_FRAME:
			return _restore_fail("sockets on non-weapon %d" % wk)
		var per: Dictionary = sockets_in[wk]
		var out: Dictionary = {}
		for sk: Variant in per:
			var socket: StringName = _as_name(sk)
			var part_v: Variant = per[sk]
			if socket.is_empty() or typeof(part_v) != TYPE_INT or not new_items.has(part_v):
				return _restore_fail("socket entry on weapon %d" % wk)
			var part: int = part_v
			var weapon_id: int = wk
			if new_location.get(part) != socket_container(weapon_id, socket):
				return _restore_fail("part %d is not in socket container %s" % [part, socket])
			out[socket] = part
		new_sockets[wk] = out
	# every socket container that holds something must be indexed
	for name: StringName in new_containers:
		var list: Array[int] = new_containers[name]
		var text: String = String(name)
		if text.begins_with("socket.") and not list.is_empty():
			var parts: PackedStringArray = text.split(".", true, 2)
			var weapon: int = int(parts[1])
			var socket: StringName = StringName(parts[2])
			var indexed: Variant = new_sockets.get(weapon, {})
			var idx: Dictionary = indexed
			if idx.get(socket, EntityIds.NONE) != list[0]:
				return _restore_fail("socket container %s not indexed" % name)
	var busy_in: Dictionary = state["busy_until"]
	var new_busy: Dictionary = {}
	for bk: Variant in busy_in:
		if typeof(bk) != TYPE_INT or not new_items.has(bk) or typeof(busy_in[bk]) != TYPE_INT:
			return _restore_fail("busy_until entry")
		new_busy[bk] = busy_in[bk]
	var handles_in: Dictionary = state["part_handles"]
	var new_handles: Dictionary = {}
	for pk: Variant in handles_in:
		if typeof(pk) != TYPE_INT or not new_items.has(pk) or typeof(handles_in[pk]) != TYPE_ARRAY:
			return _restore_fail("part_handles entry")
		var arr: Array = handles_in[pk]
		var list: Array[int] = []
		for v: Variant in arr:
			if typeof(v) != TYPE_INT or v < 1:
				return _restore_fail("part handle value")
			list.append(v)
		new_handles[pk] = list
	# capacities
	_items = new_items
	for name: StringName in new_containers:
		var list: Array[int] = new_containers[name]
		var cap: int = capacity_of(name)
		if cap >= 0 and list.size() > cap:
			_items = {}
			return _restore_fail("container %s over capacity" % name)
	_containers = new_containers
	_location = new_location
	_sockets = new_sockets
	_busy_until = new_busy
	_part_handles = new_handles
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("ItemSystem.restore: rejected snapshot: %s" % reason)
	return ERR_INVALID_DATA


# ---------------------------------------------------------------- internals

func _template_of(item: int) -> Dictionary:
	var rec: Dictionary = _items[item]
	var kind: StringName = rec["kind"]
	var template: StringName = rec["template"]
	return _content.get_entry(kind, template)


func _socket_contains(socket: StringName) -> StringName:
	if not _content.has(KIND_SOCKET, socket):
		return &""
	var t: Dictionary = _content.get_entry(KIND_SOCKET, socket)
	return _as_name(t.get("contains", ""))


func _is_magazine(item: int) -> bool:
	if item_kind(item) != KIND_PART:
		return false
	var t: Dictionary = _template_of(item)
	return _socket_contains(_as_name(t["socket"])) == KIND_AMMO


func _fits(part: int, weapon: int) -> bool:
	var t: Dictionary = _template_of(part)
	var fits: Array = t["fits"]
	var frame: StringName = item_template(weapon)
	for f: Variant in fits:
		if _as_name(f) == frame:
			return true
	return false


func _move(item: int, to: StringName) -> void:
	var from: StringName = _location[item]
	var from_list: Array[int] = _containers[from]
	from_list.erase(item)
	if not _containers.has(to):
		_containers[to] = [] as Array[int]
	var to_list: Array[int] = _containers[to]
	var cap: int = capacity_of(to)
	assert(cap < 0 or to_list.size() < cap, "callers check capacity before moving")
	to_list.append(item)
	_location[item] = to
	if from_list.is_empty() and from != WORLD and not String(from).begins_with("inv."):
		_containers.erase(from)


func _set_socket(weapon: int, socket: StringName, part: int) -> void:
	if not _sockets.has(weapon):
		_sockets[weapon] = {}
	var dict: Dictionary = _sockets[weapon]
	if part == EntityIds.NONE:
		dict.erase(socket)
		if dict.is_empty():
			_sockets.erase(weapon)
	else:
		dict[socket] = part


func _remove_part_modifiers(part: int) -> void:
	var stored: Variant = _part_handles.get(part)
	if typeof(stored) == TYPE_ARRAY:
		var handles: Array = stored
		for h: Variant in handles:
			var handle: int = h
			var err: Error = _stats.remove_modifier(handle)
			assert(err == OK, "part handles are always live modifiers")
	_part_handles.erase(part)


func _chamber(weapon: int, round: int) -> void:
	_move(round, chamber_container(weapon))
	var frame_t: Dictionary = _template_of(weapon)
	var round_t: Dictionary = _template_of(round)
	var tags: Array[StringName] = _names(round_t["tags"])
	for t: StringName in _names(frame_t["tags"]):
		if not tags.has(t):
			tags.append(t)
	_stats.set_tags(round, tags)
	_stats.set_inherits(round, weapon)


func _is_open_container(name: StringName) -> bool:
	if name == WORLD:
		return true
	var text: String = String(name)
	if not text.begins_with("inv."):
		return false
	var rest: String = text.trim_prefix("inv.")
	return rest.is_valid_int() and int(rest) >= 1 and str(int(rest)) == rest


func _is_closed_container_name(name: StringName, items: Dictionary) -> bool:
	var text: String = String(name)
	var parts: PackedStringArray = text.split(".")
	if parts.size() < 2 or not parts[1].is_valid_int():
		return false
	var owner: int = int(parts[1])
	if not items.has(owner):
		return false
	var rec: Dictionary = items[owner]
	match parts[0]:
		"mag":
			if parts.size() != 2 or rec["kind"] != KIND_PART:
				return false
			var kind: StringName = rec["kind"]
			var template: StringName = rec["template"]
			var t: Dictionary = _content.get_entry(kind, template)
			return _socket_contains(_as_name(t["socket"])) == KIND_AMMO
		"chamber":
			return parts.size() == 2 and rec["kind"] == KIND_FRAME
		"socket":
			return parts.size() == 3 and rec["kind"] == KIND_FRAME and _content.has(KIND_SOCKET, StringName(parts[2]))
		_:
			return false


static func _keys_are(dict: Dictionary, keys: Array[String]) -> bool:
	if dict.size() != keys.size():
		return false
	for key: String in keys:
		if not dict.has(key):
			return false
	return true


static func _ints(dict: Dictionary, keys: Array[String]) -> bool:
	for key: String in keys:
		if typeof(dict[key]) != TYPE_INT:
			return false
	return true


## A String or StringName payload field as a validated name, or "" if neither.
func _payload_name(payload: Dictionary, key: String) -> StringName:
	var name: StringName = _as_name(payload[key])
	if name.is_empty() or not _name_regex.search(String(name)):
		return &""
	return name


static func _as_name(v: Variant) -> StringName:
	match typeof(v):
		TYPE_STRING_NAME:
			return v
		TYPE_STRING:
			var s: String = v
			return StringName(s)
		_:
			return &""


static func _names(list: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if typeof(list) != TYPE_ARRAY:
		return out
	var arr: Array = list
	for v: Variant in arr:
		var n: StringName = _as_name(v)
		if not n.is_empty():
			out.append(n)
	return out
