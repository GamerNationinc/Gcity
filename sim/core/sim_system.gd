## Base class for every simulation system owned by a [SimRoot].
##
## A system holds authoritative state, advances it once per tick, and exposes that
## state for hashing. It never touches rendering, input or UI (design doc §4.1).
## See docs/extending-sim-systems.md for how to add one.
@abstract
class_name SimSystem extends RefCounted


## Stable identifier. Used as the snapshot key and to reject duplicate registration.
@abstract func system_id() -> StringName


## Advance one tick. Runs after command dispatch, in registration order.
@abstract func tick(sim: SimRoot) -> void


## The system's complete authoritative state, in a form [StateHash] can encode.
## Two systems with equal snapshots must behave identically from here on.
@abstract func snapshot() -> Dictionary
