# ADR-009: Magazines as ordered containers

Status: proposed — **blocking; must close before M1** (standards §7)
Date: 2026-09-20
Design doc: §13.3 (D-09); §11 items; §12 device

## Context

Tarkov-style: rounds are item instances, magazines are ordered containers of them, the
chambered round is tracked separately, a tactical reload keeps the partial mag and an
emergency reload drops it. This reaches into the inventory model, item instance
identity, the save format and the device's loading UI, so it is a blocking decision
for the item system (M1).

## Options

### A — Ordered containers (assumed by the design doc)
- Cost: inventory supports nested containers with ordering from the start; item
  conservation invariants (standards §3.2) become the item system's core property.
  Loading magazines is a real task with a real time cost.
- Risk: UI cost on a 7" screen with a controller; must be fast and mostly automatic
  at base. Forecloses: nothing.

### B — Magazines as counters (ammo pool per weapon or per caliber)
- Cost: trivial. Risk: mixed ammo types, partial mags and the "caught empty" state
  disappear; retrofitting A later touches every item, save and UI record. Forecloses:
  the Tarkov half of the combat pitch.

### C — Ordered containers in the sim, counter presentation by default
- The sim is A; the device shows counts and offers per-round ordering only when the
  player opens a magazine. Same data, cheaper default UI.

## Decision

Proposed: **C**, which is A in the sim. The sim/client split makes the presentation
choice free to change later; the sim model is the irreversible part.

## Consequences

Easy: ammo variety, penetration-per-round, reload decisions. Hard: the inventory
model is a tree of item instances from day one; M1's "one pistol" includes one
magazine type and the reload operations as first-class commands.

## Verification

Round conservation property across every reload operation, 10 000 generated sequences
(standards §3.2). Save round-trip with partially loaded magazines. Both at G1.

## Sign-off

Approver: CEOGG — _pending_
