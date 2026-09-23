# ADR-010: Are hub interiors simulated while the player is elsewhere?

Status: accepted
Date: 2026-09-20
Design doc: §17 (D-10); §5.1 regions; §6.2 hydration

## Context

Authored regions (city districts, facilities) contain agents, schedules and state. When
the player is out in the wilds, that state can be frozen, advanced by a cheap macro
model, or fully simulated. The macro token model (§6.2) already handles off-screen
agents on the route graph.

## Options

### A — Freeze
- Cost: none. Risk: time visibly stops inside the walls; contracts and fixers do not
  progress; contradicts a living city. Forecloses: city-side events while away (a
  base raid in the starter plot while the player is in the badlands).

### B — Macro model (tokens and schedules, no navmesh, no perception)
- Cost: a schedule/state model per district that the threat director (§7.5) and quest
  director (§5.3) can tick without loaded geometry. Risk: a visible seam when a
  hydrated district disagrees with what the macro model said. Forecloses: nothing;
  full simulation can replace it per district later.

### C — Full simulation
- Cost: CPU. The Deck budget (§4.1) has 3.0 ms for all agents near the player; an
  unloaded district's agents cannot have it. Forecloses: the 40 fps target.

## Decision

**B** (CEOGG, 2026-09-23), as the uniform rule for both region types: everything unloaded runs on
tokens and schedules; everything loaded runs fully. That is the hydration rule of §6.2
applied to hubs.

## Consequences

Easy: a single model for "what happens while you are away", including base raids.
Hard: every hub state that matters while away must be expressible as macro state.

## Verification

Metamorphic: a district's macro state after N ticks unloaded equals the state after
loading, ticking N, and unloading, for the quantities the macro model claims to track.
Recorded at G7.

## Sign-off

Approver: CEOGG — **accepted as B**, 2026-09-23. One uniform hydration rule for both
region types: unloaded runs on tokens and schedules, loaded runs fully. The metamorphic
verification above is a G7 gate item.
