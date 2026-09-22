# Extending: death, corpses and what it costs

ADR-007 was decided as **C**: a corpse that persists with the gear on it, and a
recovery run to get it back. Design doc §13.4; M6 spec claims 10 and 11.

## What dying does

`ActorSystem` emits `actor.died {actor, x, y, z}` once, on the tick an actor's last
fatal health node reaches zero. It says who and where and nothing else; what happens
to the body is `CorpseSystem`'s business.

`CorpseSystem` makes one corpse entity at that position and moves the dead actor's
whole inventory into `corpse.<id>`. **Nothing is spawned and nothing is destroyed.**
That is the point: M1 claim 10's conservation property — no item command ever changes
how many items exist — now covers dying and looting too, and a corpse test asserts it
over ten thousand generated death-and-loot sequences.

A body with nothing on it is still a body. It is evidence whether or not it is loot,
which is why `RunScoreSystem` counts it as a trace either way.

## Taking it back

`corpse.loot {actor, corpse}` moves everything from the body to a living actor
standing within `CorpseSystem.REACH_MM`. All of it or none: a half-emptied pocket is
a state the device cannot show and the player cannot reason about.

Looting does not remove the body. Somebody stripped it, and that is still something
that happened there.

## Adding to this

- **A new way to die** needs nothing here: any path that drives a fatal node to zero
  emits the event, and the corpse follows.
- **A new kind of container on a body** (a locked case, a bag that needs a tool) is a
  container name and a rule in `ItemSystem`, not a branch in `CorpseSystem`.
- **What a body is worth to a passer-by** reads the same `value` stat visible wealth
  does, because the items are the same items.
