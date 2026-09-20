# ADR-001: Clean start vs existing codebase

Status: proposed
Date: 2026-09-20
Design doc: §3 (D-01)

## Context

The design assumes a clean start in Godot 4.x with a simulation/presentation split
from the first commit (§4.1). If any prior codebase is to be carried forward, its
structure would have to be reconciled with that split before M0 could be gated.

## Options

### A — Clean start (assumed by the design doc)
- Cost: nothing reused; every system written against the standards from day one.
- Risk: none structural. Schedule risk only if a prior codebase held real value.
- Forecloses: nothing.

### B — Carry forward an existing codebase
- Cost: audit for `sim/`↔`client/` entanglement, untyped GDScript, singletons; a
  migration milestone before M0.
- Risk: inherits architecture that the standards (§1.1) explicitly reject; the gate
  criteria would have to be relaxed to accept it.
- Forecloses: a bit-clean determinism story until the migration is done.

## Decision

Proposed: **A, clean start.** The M0 skeleton in this repository is built on that
assumption. If B is chosen, M0 is re-gated after a migration spec.

## Consequences

Easy: every file in the repo satisfies the standards. Hard: nothing is inherited, so
even trivial infrastructure (test runner, hashing) is written here.

## Verification

The M0 gate passes with a repository containing no code that predates this ADR.

## Sign-off

Approver: CEOGG — _pending_
