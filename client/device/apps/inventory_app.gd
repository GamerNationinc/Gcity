## The inventory app (design doc §12; M5 spec claim 3): every row is read from the
## item system this frame; every button is an item command. Select on a weapon
## holsters it, or takes it in hand and loads it from what you carry (`WeaponReady`;
## CEOGG's 2026-10-05 sandbox run: "can't load and fire"), on a device carries it (never puts away the one whose screen
## this is: nothing would be left to carry it again with), on a magazine swaps
## it into the wielded weapon, on loose rounds fills the first loose magazine, on a
## part or module fits it to the wielded weapon or carried device; secondary on a
## magazine unloads a round, on a fitted part removes it.
class_name InventoryApp extends DeviceApp

var _cursor: int = 0
## What A does on the row under the cursor, for the prompt line: the buttons were all
## there but nothing said loose rounds load a magazine (the same run).
var _select_hint: String = "use"
var _label: RichTextLabel


func _init() -> void:
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.add_theme_font_size_override("normal_font_size", DeviceShell.BODY_PX)
	_label.add_theme_font_size_override("mono_font_size", DeviceShell.BODY_PX)
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_label)


## The rows, rebuilt from the sim: [{"text", "kind", "id"}].
func _rows(sim: SimRoot, player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var items: ItemSystem = SimAssembly.items_of(sim)
	var stats: StatResolver = SimAssembly.stats_of(sim)
	var wielded: int = actors.wielded(player)
	var device: int = actors.device_of(player)
	var loose_rounds: Dictionary = {}
	for id: int in items.items_in(ItemSystem.inventory_of(player)):
		var kind: StringName = items.item_kind(id)
		var template: StringName = items.item_template(id)
		if kind == ItemSystem.KIND_FRAME:
			var mag: int = items.magazine_of(id)
			var mag_text: String = "no magazine" if mag == EntityIds.NONE else "%d rounds in the magazine" % items.rounds_in(mag).size()
			out.append({"text": "%s%s   chamber %s   %s   hit %d %%" % [template, "   (in hand)" if id == wielded else "", "loaded" if items.chambered(id) != EntityIds.NONE else "empty", mag_text, stats.resolve(id, &"hit_chance") / 10000], "kind": "weapon", "id": id})
			out.append_array(_socket_rows(sim, id, ItemSystem.KIND_SOCKET))
		elif kind == ItemSystem.KIND_DEVICE_FRAME:
			out.append({"text": "%s%s   antenna %d m   memory %d" % [template, "   (carried)" if id == device else "", stats.resolve(id, &"antenna_gain") / 1000, stats.resolve(id, &"memory_capacity") / 1000], "kind": "device", "id": id})
			out.append_array(_socket_rows(sim, id, ItemSystem.KIND_DEVICE_SOCKET))
		elif kind == ItemSystem.KIND_PART:
			if items.capacity_of(ItemSystem.magazine_container(id)) > 0:
				out.append({"text": "%s   %d / %d rounds" % [template, items.rounds_in(id).size(), items.capacity_of(ItemSystem.magazine_container(id))], "kind": "magazine", "id": id})
			else:
				out.append({"text": "%s   (part, loose)" % template, "kind": "part", "id": id})
		elif kind == ItemSystem.KIND_DEVICE_MODULE:
			out.append({"text": "%s   (module, loose)" % template, "kind": "module", "id": id})
		elif kind == ItemSystem.KIND_AMMO:
			loose_rounds[template] = loose_rounds.get(template, 0) + 1
	var templates: Array = loose_rounds.keys()
	templates.sort()
	for t: Variant in templates:
		var template: StringName = t
		var n: int = loose_rounds[t]
		out.append({"text": "%s   ×%d loose" % [template, n], "kind": "rounds", "id": 0, "template": template})
	return out


func _socket_rows(sim: SimRoot, frame: int, socket_kind: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var items: ItemSystem = SimAssembly.items_of(sim)
	var content: ContentDb = sim.get_system(&"content")
	var t: Dictionary = content.get_entry(items.item_kind(frame), items.item_template(frame))
	var sockets: Array = t["sockets"]
	for s: Variant in sockets:
		var socket_s: String = s
		var socket: StringName = StringName(socket_s)
		if socket_kind == ItemSystem.KIND_SOCKET and items.magazine_socket_of(frame) == socket:
			continue
		var part: int = items.socket_part(frame, socket)
		out.append({"text": "    %s: %s" % [socket_s, "empty" if part == EntityIds.NONE else String(items.item_template(part))], "kind": "socket", "id": frame, "socket": socket, "part": part})
	return out


func refresh(sim: SimRoot, player: int) -> bool:
	var rows: Array[Dictionary] = _rows(sim, player)
	if rows.is_empty():
		return _set_text(_label, "Nothing carried.")
	_cursor = clampi(_cursor, 0, rows.size() - 1)
	_select_hint = _hint(rows[_cursor], sim, player)
	var lines: PackedStringArray = PackedStringArray()
	for i: int in rows.size():
		var text: String = rows[i]["text"]
		lines.append(("[color=#ffd866]> %s[/color]" if i == _cursor else "  %s") % text)
	return _set_text(_label, "\n".join(lines))


func handle(action: StringName, sim: SimRoot, player: int) -> bool:
	var rows: Array[Dictionary] = _rows(sim, player)
	if rows.is_empty():
		return false
	match action:
		&"device_up":
			_cursor = posmod(_cursor - 1, rows.size())  # wraps: the last row is one press up
			return true
		&"device_down":
			_cursor = posmod(_cursor + 1, rows.size())
			return true
		&"device_select":
			_primary(rows[clampi(_cursor, 0, rows.size() - 1)], sim, player)
			return true
		&"device_secondary":
			_secondary(rows[clampi(_cursor, 0, rows.size() - 1)], sim, player)
			return true
	return false


func _primary(row: Dictionary, sim: SimRoot, player: int) -> void:
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var items: ItemSystem = SimAssembly.items_of(sim)
	var id: int = row["id"]
	var row_kind: String = row["kind"]
	match row_kind:
		"weapon":
			if actors.wielded(player) == id:
				submit(&"actor.wield", {"actor": player, "weapon": 0})
				note("%s put away" % items.item_template(id))
				return
			submit(&"actor.wield", {"actor": player, "weapon": id})
			var plan: Dictionary = WeaponReady.plan(sim, player, id)
			var commands: Array = plan["commands"]
			for command: Array in commands:
				var kind: StringName = command[0]
				var payload: Dictionary = command[1]
				submit(kind, payload)
			var said: String = plan["say"]
			note("%s in hand. %s" % [items.item_template(id), said])
		"device":
			if actors.device_of(player) == id:
				note("this %s is the screen you are on: putting it away would leave no way back" % items.item_template(id))
				return
			submit(&"actor.equip_device", {"actor": player, "device": id})
		"magazine":
			var weapon: int = actors.wielded(player)
			if weapon == EntityIds.NONE:
				note("wield a weapon to swap its magazine")
				return
			submit(&"weapon.reload_tactical", {"actor": player, "weapon": weapon, "magazine": id})
		"rounds":
			var template: StringName = row["template"]
			var mag: int = _loose_magazine_with_room(items, player)
			if mag == EntityIds.NONE:
				note("no loose magazine with room")
				return
			var room: int = items.capacity_of(ItemSystem.magazine_container(mag)) - items.rounds_in(mag).size()
			var loaded: int = 0
			for round: int in items.items_in(ItemSystem.inventory_of(player)):
				if loaded >= room:
					break
				if items.item_kind(round) == ItemSystem.KIND_AMMO and items.item_template(round) == template:
					submit(&"magazine.load", {"actor": player, "magazine": mag, "round": round})
					loaded += 1
			note("loading %d rounds" % loaded)
		"part":
			var weapon: int = actors.wielded(player)
			if weapon == EntityIds.NONE:
				note("wield a weapon to fit a part")
				return
			submit(&"item.attach", {"actor": player, "weapon": weapon, "part": id})
		"module":
			var device: int = actors.device_of(player)
			if device == EntityIds.NONE:
				note("carry a device to fit a module")
				return
			submit(&"item.attach", {"actor": player, "weapon": device, "part": id})
		"socket":
			var part: int = row["part"]
			var socket: StringName = row["socket"]
			if part == EntityIds.NONE:
				note("%s is empty: pick a loose part or module to fit one" % socket)
				return
			submit(&"item.detach", {"actor": player, "weapon": id, "socket": String(socket)})


func _secondary(row: Dictionary, _sim: SimRoot, player: int) -> void:
	var id: int = row["id"]
	var row_kind: String = row["kind"]
	match row_kind:
		"magazine":
			submit(&"magazine.unload", {"actor": player, "magazine": id})
		"socket":
			var part: int = row["part"]
			var socket: StringName = row["socket"]
			if part == EntityIds.NONE:
				note("%s is empty: nothing to undo" % socket)
				return
			submit(&"item.detach", {"actor": player, "weapon": id, "socket": String(socket)})
		_:
			note("nothing to undo on this row: undo unloads a magazine or removes a fitted part")


static func _loose_magazine_with_room(items: ItemSystem, player: int) -> int:
	for id: int in items.items_in(ItemSystem.inventory_of(player)):
		if items.item_kind(id) == ItemSystem.KIND_PART and items.capacity_of(ItemSystem.magazine_container(id)) > items.rounds_in(id).size():
			return id
	return EntityIds.NONE


func prompts(glyphs: InputGlyphs) -> String:
	return glyphs.line([[&"device_up", "up"], [&"device_down", "down"], [&"device_select", _select_hint], [&"device_secondary", "undo"]])


## What A will do on `row`, in a few words.
static func _hint(row: Dictionary, sim: SimRoot, player: int) -> String:
	var actors: ActorSystem = SimAssembly.actors_of(sim)
	var items: ItemSystem = SimAssembly.items_of(sim)
	var id: int = row["id"]
	var row_kind: String = row["kind"]
	var wielded: int = actors.wielded(player)
	match row_kind:
		"weapon":
			return "put it away" if wielded == id else "take in hand and load"
		"device":
			return "carrying it" if actors.device_of(player) == id else "carry this one"
		"magazine":
			return "put in the %s" % items.item_template(wielded) if wielded != EntityIds.NONE else "(take a gun in hand first)"
		"rounds":
			return "load into a magazine"
		"part":
			return "fit to the %s" % items.item_template(wielded) if wielded != EntityIds.NONE else "(take a gun in hand first)"
		"module":
			return "fit to the device"
		"socket":
			var part: int = row["part"]
			return "take it off" if part != EntityIds.NONE else "(empty)"
	return "use"
