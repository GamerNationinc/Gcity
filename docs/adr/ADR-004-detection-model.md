# ADR-004: Sensor-gated detection vs instant wanted level

Status: proposed
Date: 2026-09-20
Design doc: §7.4 (D-04); §14.1 perception

## Context

Rights violations emit events; something must turn events into consequences. The
design assumes signals propagate to observers (neighbours, cameras, patrols, drones)
weighted by district `informant_density`, accumulating as faction-held suspicion.
That requires the perception system of §14. The alternative, an instant wanted level
on violation, needs nothing but reads as arbitrary and makes stealth meaningless.

## Options

### A — Sensor-gated (assumed throughout the design doc)
- Cost: a full perception system before threat can exist (M4 precedes M8 for this
  reason). Signal propagation and observer models per faction.
- Risk: tuning; a player who is never observed is never punished, which is correct but
  must be legible.
- Forecloses: nothing; the instant model is A with every observer omniscient.

### B — Instant wanted level on violation
- Cost: trivial.
- Risk: reads as arbitrary; no counterplay; contradicts pillar 3 (legibility) and the
  module-shaped counterplay of §7.4 (scrubbers, off-grid power, bribes).
- Forecloses: stealth as a real approach; the habit-map/informant mechanic of §6.4.

## Decision

Proposed: **A.** Because B is a degenerate configuration of A (all observers, infinite
range, instant propagation), A can be shipped with B's numbers for the tutorial and
scripted city fights if legibility needs it, using the same profile mechanism as
combat (§13.1).

## Consequences

Easy: stealth, counterplay modules, faction-scoped knowledge. Hard: M8 depends on M4
being genuinely good; the threat director cannot be tested in isolation from
perception.

## Verification

Metamorphic relation (standards §3.4): increasing `informant_density` never increases
time-to-suspicion-threshold; removing all observers from a district makes suspicion
unreachable there.

## Sign-off

Approver: CEOGG — _pending_
