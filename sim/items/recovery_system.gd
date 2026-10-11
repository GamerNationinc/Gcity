## City softening on death (M6 spec claim 17, ADR-007 C, design doc §7.2). When a
## corpse is made for an actor with a home (a player) where the district's law_index is
## at or above city_recovery.min_law_index, each item in it, in container order, comes
## back to the actor's base container with probability law_index / 1000: one draw from
## sim.rng() per item, so the sequence is fixed by the seed. Each returned item costs
## city_recovery.fee credits from the wallet, and the return stops at the first item
## the wallet cannot pay for. The rest stays in the body.
class_name RecoverySystem extends SimSystem

const SYSTEM_ID: StringName = &"recovery"
const KIND_RECOVERY: StringName = &"city_recovery"
const CONFIG: StringName = &"city"
const SOURCE_FEE: StringName = &"recovery.fee"
## {actor, corpse, returned: [item ids], fee}
const EVENT_RETURNED: StringName = &"recovery.returned"

var _content: ContentDb
var _items: ItemSystem
var _corpses: CorpseSystem
var _land: LandSystem
var _wallet: WalletSystem
var _events: EventBus
## the sim's generator (not the sim: holding the root would be a reference cycle);
## SimRoot keeps this object for its life and restores only its state
var _rng: RandomNumberGenerator


func _init(content: ContentDb, items: ItemSystem, corpses: CorpseSystem, land: LandSystem, wallet: WalletSystem, events: EventBus) -> void:
	_content = content
	_items = items
	_corpses = corpses
	_land = land
	_wallet = wallet
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim_root: SimRoot) -> void:
	pass


func attach(sim: SimRoot) -> Error:
	if not _content.has(KIND_RECOVERY, CONFIG):
		push_error("RecoverySystem: no %s/%s" % [KIND_RECOVERY, CONFIG])
		return ERR_INVALID_DATA
	_rng = sim.rng()
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	err = _wallet.register_source(SOURCE_FEE)
	if err != OK:
		return err
	return _events.subscribe(CorpseSystem.EVENT_CREATED, _on_corpse)


func _on_corpse(payload: Dictionary) -> void:
	var actor: int = payload["actor"]
	if not _land.has_home(actor):
		return
	var x: int = payload["x"]
	var y: int = payload["y"]
	var z: int = payload["z"]
	var law: int = _land.law_index_at(Vector3i(x, y, z))
	var t: Dictionary = _content.get_entry(KIND_RECOVERY, CONFIG)
	var min_law: int = t["min_law_index"]
	if law < min_law:
		return
	var fee: int = t["fee"]
	var corpse_s: String = payload["corpse"]
	var corpse: StringName = StringName(corpse_s)
	var base: StringName = ItemSystem.base_of(actor)
	var returned: Array[int] = []
	for item: int in _items.items_in(corpse):
		if _rng.randi_range(0, 999) >= law:
			continue
		if fee > 0 and not _wallet.debit(actor, fee, SOURCE_FEE):
			break
		var moved: bool = _items.transfer(item, base)
		assert(moved, "a loose item in a body moves to a base container")
		returned.append(item)
	_corpses.forget_if_empty(corpse)
	if not returned.is_empty():
		_events.emit(EVENT_RETURNED, {"actor": actor, "corpse": corpse_s, "returned": returned, "fee": fee})


func snapshot() -> Dictionary:
	return {}


func restore(state: Dictionary) -> Error:
	if not state.is_empty():
		push_error("RecoverySystem.restore: rejected: it keeps no state")
		return ERR_INVALID_DATA
	return OK
