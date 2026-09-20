# ADR-006: Does the device pause time?

Status: proposed
Date: 2026-09-20
Design doc: §12.4 (D-06); §15.2 terminal hack

## Context

The personal device is the entire UI layer and will be open constantly. Pausing makes
it a safe menu in a diegetic costume. Not pausing makes reloading through a menu a real
risk, fits the immersive-sim half of the pitch, and forces every pane to be operable in
about two seconds on a 7" screen with a controller.

## Options

### A — Always pause
- Cost: none. Risk: the device is a menu; the mission's exposed-terminal tension (§15.2)
  is undercut. Forecloses: the "caught with everything empty" failure state (§13.3).

### B — Never pause
- Cost: every app must be usable in ~2 s; a stress test on Deck ergonomics.
- Risk: frustration in the starter plot where there is no threat anyway.

### C — Pause only inside owned or safe parcels (`rights_at()` answers it)
- Cost: one query the land authority already provides. Risk: the rule must be legible;
  the device should show its state (a "secure" indicator).
- Forecloses: nothing; A and B are C with the predicate fixed.

## Decision

Proposed: **C.** Sim-side it is one flag from `LandAuthority.rights_at(position, player)`;
the client reads it to decide whether to submit a pause command. Pausing is itself a
sim command (the sim stops ticking gameplay systems while paused), so the decision
does not touch the sim/client split.

## Consequences

Easy: safe base management, real risk in the field. Hard: UI panes designed for speed
first; the M5 gate's legibility check must be done with the device unpaused in a
hostile parcel.

## Verification

M6 demo script includes a terminal hack with the device open outside a safe parcel
and a guard approaching; the M5 gate records time-to-complete for each core device task
with a controller.

## Sign-off

Approver: Lukas Williams — _pending_
