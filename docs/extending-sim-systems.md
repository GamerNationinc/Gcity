# Extending: sim systems and command kinds

The minimal diff to add one more system, and one more command kind, to the sim. This
is the extension exercise the M0 gate performs (standards §2.3, Q4) and the pattern
every later `sim/` module follows.

## A new system

1. Create `sim/<module>/<name>_system.gd`:

   ```gdscript
   class_name HeatSystem extends SimSystem

   var _heat: int = 0

   func system_id() -> StringName:
   	return &"heat"

   func tick(sim: SimRoot) -> void:
   	if _heat > 0:
   		_heat -= 1

   func snapshot() -> Dictionary:
   	return {"heat": _heat}
   ```

2. Register it with the sim before the first tick, wherever the sim is assembled
   (today: `client/local_host.gd` for play, the test for tests):

   ```gdscript
   sim.register_system(HeatSystem.new())
   ```

   Registration order is part of the state: systems tick in that order and the hash
   depends on it. Assemble systems in one place, in one fixed order.

3. Add `tests/<module>/test_<name>_system.gd` extending `GcityTest`, with the
   invariants the system promises. Add a replay fixture if the system changes what a
   run of the sim produces.

Nothing under `sim/core/` changes. If it has to, the abstraction is wrong (Q4 fails).

## A new command kind

A command is how the client changes sim state. The system that owns the state owns the
handler:

```gdscript
const COMMAND_BRIBE: StringName = &"heat.bribe"

func attach(sim: SimRoot) -> Error:
	var err: Error = sim.register_system(self)
	if err != OK:
		return err
	return sim.commands().register(COMMAND_BRIBE, _on_bribe)

## Payload contract: {"credits": int > 0}. Anything else is rejected.
func _on_bribe(_sim: SimRoot, payload: Dictionary) -> bool:
	if payload.size() != 1 or typeof(payload.get("credits")) != TYPE_INT:
		return false
	var credits: int = payload["credits"]
	if credits <= 0:
		return false
	_heat = maxi(0, _heat - credits / 100)
	return true
```

Rules the handler must keep:

- The payload is untrusted (standards §5.2). Reject on any shape or range surprise;
  return `false`, never crash, never partially apply.
- Return `true` only when state changed exactly as the contract says.
- Use `sim.rng()` for randomness and `sim.get_tick()` for time. Nothing else.

The client then submits `SimCommand.new(sim.get_tick() + 1, HeatSystem.COMMAND_BRIBE,
{"credits": 500})`. A fixture with that command in its `commands` array replays it.

## What you may not do

- Reference a client class or `res://client/` path from the system.
- Store state anywhere but on the system (no statics, no autoloads).
- Put anything in `snapshot()` that `StateHash` cannot encode (objects, vectors,
  packed numeric arrays). Convert to ints, strings or nested arrays/dictionaries.
