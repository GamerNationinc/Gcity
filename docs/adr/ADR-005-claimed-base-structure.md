# ADR-005: Claimed base keeps player structure vs faction template

Status: proposed
Date: 2026-09-20
Design doc: §9.4 (D-05); §5.6 save overlay

## Context

When a raid resolves to takeover, ownership flips (one parcel write) and the base
becomes a faction POI. What is on the parcel afterward is the open question.

## Options

### A — Keep the player's structure under the new owner
- Cost: zero at build time (pieces are already data). The save overlay must hold a full
  structure under a non-player owner; raid AI must path through a base designed to stop
  it (the portal graph already handles that: every wall is an expensive edge).
- Risk: save size for large bases; degenerate structures with no traversable interior.
- Forecloses: nothing.

### B — Replace with a faction template
- Cost: a template set per faction; a swap step at takeover.
- Risk: reads as the world erasing the player's work; loses the reclaim-your-own-base
  fantasy the design calls "free".
- Forecloses: the emotional payoff of §9.4.

## Decision

Proposed: **A.** The portal graph is the reason it costs nothing: faction agents plan on
it exactly as raiders did.

## Consequences

Easy: reclaim missions, persistent consequences. Hard: the save overlay's structure
records must be owner-agnostic from M2 (when the save format is first written), which
is the real reason to decide this before M2, not M8.

## Verification

Save round-trip property (standards §3.2) over generated bases with non-player owners;
a raid replay against a player-built base finds a path (portal graph connectivity
invariant).

## Sign-off

Approver: CEOGG — _pending_
