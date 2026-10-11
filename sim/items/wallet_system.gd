## Credits (M6 spec claim 15): a per-actor integer balance, changed only by registered
## sources (a contract's payout, the city's recovery fee) and never negative. There are
## no shops in M6. Every change emits `wallet.changed {actor, amount, source, balance}`.
class_name WalletSystem extends SimSystem

const SYSTEM_ID: StringName = &"wallet"
const EVENT_CHANGED: StringName = &"wallet.changed"
const MAX_BALANCE: int = 1_000_000_000

var _actors: ActorSystem
var _events: EventBus
var _sources: Dictionary = {}
## actor -> balance (> 0; zeros are not stored)
var _balances: Dictionary = {}


func _init(actors: ActorSystem, events: EventBus) -> void:
	_actors = actors
	_events = events


func system_id() -> StringName:
	return SYSTEM_ID


func tick(_sim: SimRoot) -> void:
	pass


func attach(sim: SimRoot) -> Error:
	return sim.register_system(self)


## Names a system's reason to change balances; a change from an unregistered source is
## refused (invariant 3: a new source is a registration).
func register_source(source: StringName) -> Error:
	if source.is_empty() or _sources.has(source):
		push_error("WalletSystem: source '%s' is empty or already registered" % source)
		return ERR_ALREADY_EXISTS
	_sources[source] = true
	return OK


func has_source(source: StringName) -> bool:
	return _sources.has(source)


func balance_of(actor: int) -> int:
	return _balances.get(actor, 0)


## Adds `amount` (> 0) for a known actor from a registered source. False, changing
## nothing, otherwise or when the balance would pass MAX_BALANCE.
func credit(actor: int, amount: int, source: StringName) -> bool:
	if amount <= 0 or not _sources.has(source) or not _actors.has_actor(actor):
		return false
	var balance: int = balance_of(actor)
	if balance > MAX_BALANCE - amount:
		return false
	return _apply(actor, balance + amount, amount, source)


## Takes `amount` (> 0) when the actor has it. False, changing nothing, otherwise: a
## balance never goes negative.
func debit(actor: int, amount: int, source: StringName) -> bool:
	if amount <= 0 or not _sources.has(source) or not _actors.has_actor(actor):
		return false
	var balance: int = balance_of(actor)
	if balance < amount:
		return false
	return _apply(actor, balance - amount, -amount, source)


func _apply(actor: int, balance: int, amount: int, source: StringName) -> bool:
	if balance == 0:
		_balances.erase(actor)
	else:
		_balances[actor] = balance
	_events.emit(EVENT_CHANGED, {"actor": actor, "amount": amount, "source": source, "balance": balance})
	return true


func snapshot() -> Dictionary:
	return {"balances": _balances.duplicate()}


func restore(state: Dictionary) -> Error:
	if state.size() != 1 or typeof(state.get("balances")) != TYPE_DICTIONARY:
		return _restore_fail("shape")
	var src: Dictionary = state["balances"]
	var out: Dictionary = {}
	for k: Variant in src:
		if typeof(k) != TYPE_INT or typeof(src[k]) != TYPE_INT:
			return _restore_fail("entry")
		var actor: int = k
		var balance: int = src[k]
		if not _actors.has_actor(actor) or balance <= 0 or balance > MAX_BALANCE:
			return _restore_fail("actor %d balance" % actor)
		out[actor] = balance
	_balances = out
	return OK


func _restore_fail(reason: String) -> Error:
	push_error("WalletSystem.restore: rejected: %s" % reason)
	return ERR_INVALID_DATA
