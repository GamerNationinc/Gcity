# ADR-011: Do denied rights refuse a crime, or record it?

Status: accepted
Date: 2026-09-26
Design doc: §7.1 (violations emit events), §7.3 (heat), §8.4 (no-build via ownership), §15.2

## Context

`LandSystem.require(position, actor, right)` answers every rights question and, when the
right is denied, emits `land.violation` **and refuses the act**. That is correct for
building and digging on another's land (§8.4: "You can build there once you've
purchased the parcel"). It makes crime impossible, though: in the corporate core the
`other` row denies `loot`, so the "Cold Storage" mission's locker, terminal and grate
could never be touched. §7.1 says a violation "emits an event; it does not directly set
a wanted level", and §7.3 makes rights violations the source of heat, which only works
if violating is something the player can do.

## Options

### A — Every denied right refuses (today)
- Cost: none. Risk: no theft, no hacking, no breaching in any parcel that forbids them;
  the mission has to sit in a district where others may loot, which contradicts a
  corporate data site. Forecloses: heat from crime.

### B — Every denied right is recorded, never refused
- Cost: small. Risk: building on a neighbour's plot and digging under the city wall
  become legal-with-heat, which §8.4 rules out. Forecloses: ownership as a build gate.

### C — Crimes proceed and are recorded; construction still refuses
- Acts that are crimes against someone else's property ask
  `LandSystem.offend(position, actor, right)`, which never refuses and emits
  `land.violation` with the right named when it is denied. At M6 those acts are:
  - `container.take` from a site container or someone else's corpse, and
    `hack.start` / `hack.spoof`, which ask `loot`;
  - `build.breach`, which asks `build` on the parcel of the piece.
- `build.place`, `build.remove`, `module.install`, `structure.place`, entering and
  (from M7) digging keep `require()` and still refuse.
- Cost: one method and a list of which commands call which. Risk: the list must stay
  deliberate; a new command chooses `require` or `offend` in its own spec.

## Decision

**Accepted: C** (CEOGG, 2026-09-26), on the recommendation in the M6 spec's open point 1.

## Consequences

Easy: crime raises heat through the one existing event, and the standing rules
(M6 spec claim 11) turn violations into heat as content. The site keeps its corporate
district. Hard: every new act on another's property states in its spec which of the two
it uses.

## Verification

At G6: a property that `offend()` never changes the act's outcome and emits exactly one
violation when the right is denied and none when held; a fixture (`m6-front`) where
looting the locker raises heat that the lock check then reads; the existing M2–M5
fixtures reproduce their hashes unchanged, since no existing command moves to `offend`.

## Sign-off

Approver: CEOGG
Date: 2026-09-26
Outcome: accepted
