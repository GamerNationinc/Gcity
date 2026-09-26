# ADR-007: Death cost and kit loss

Status: accepted
Date: 2026-09-20
Design doc: §13.4 (D-07); §7.2 district law index

## Context

Tarkov-grade lethality needs death to cost something, or it is noise. Tarkov's full
kit loss works because a raid is bounded; in a persistent open world it compounds.
No loss makes lethality meaningless.

## Options

### A — Full kit loss on death
- Cost: none. Risk: punishing fast; teaches save-scumming, which the threat design
  (§7.5) explicitly tries to avoid. Forecloses: casual play in the badlands.

### B — No loss
- Cost: none. Risk: lethality becomes a retry timer. Forecloses: the stakes the whole
  combat model is built for.

### C — Corpse persists with gear; recovery run; softened inside city limits
- The body stays at the location as a lootable container (an item instance transfer,
  §11.3); a recovery run gets it back unless someone else got there first. Inside city
  limits the police-response fiction returns some or all of the kit at a cost.
- Cost: corpse persistence in the save overlay; scavenger behaviour for factions with
  the site in range (which the threat director already models).
- Risk: corpse-in-unreachable-place; mitigated by route-graph adjacency of all sites.

## Decision

**Accepted: C** (CEOGG, 2026-09-26), as proposed, with the city softening driven by district `law_index` (§7.2) so it
falls out of existing data rather than a special case.

## Consequences

Easy: stakes without permadeath; a reason to travel with the right kit. Hard: corpse
records in the overlay; the M6 mission must handle a death mid-run.

## Verification

Save round-trip with corpse records; item conservation property (no duplication or
loss across death, corpse, and recovery); an M6 replay fixture with a death in it.

## Sign-off

Approver: CEOGG
Date: 2026-09-26
Outcome: accepted (verification at the M6 gate: save round-trip with corpse records; item conservation across death, corpse and recovery; an M6 replay fixture with a death in it)
