# ADR-008: Arcade-profile enemies: same AI retuned, or a simpler agent

Status: proposed
Date: 2026-09-20
Design doc: §14.6 (D-08); §13.1 combat profiles

## Context

Combat has one pipeline and two data profiles (sim and arcade). Enemy AI could follow
the same pattern or ship a second, simpler agent for arcade contexts (tutorial,
scripted city fights).

## Options

### A — Same AI, different tuning (shorter detection delay, wider error cone, low stress
sensitivity)
- Cost: a tuning asset per profile. Risk: the utility scorer may need a "dumb" clamp so
  arcade enemies do not flank. Forecloses: nothing.

### B — A separate simple agent
- Cost: a second implementation to test, budget and keep legible. Risk: divergent
  behaviour readability between contexts; two AI budgets in §4.1. Forecloses: the
  single-model claim.

## Decision

Proposed: **A.** It matches the combat decision exactly: a profile asset, no code
branch. If tuning cannot produce acceptable arcade behaviour, this ADR is superseded at
the M4 gate with the measured reason.

## Consequences

Easy: one AI to profile on Deck. Hard: the tuning space must include a knob for
tactical sophistication, not just accuracy.

## Verification

M4 metamorphic relations (standards §3.4) hold for both profiles; the M4 demo script
shows the same four guards under both profiles.

## Sign-off

Approver: CEOGG — _pending_
