# ADR-011: Movement model

Status: accepted
Date: 2026-10-08
Design doc: §1.2 (lineage), §6.4 (capability tags: walk, vault, jump, climb, mantle),
§15.2 (the routes); M6 spec claims 1–2

## Context

M6 introduces storeys. CEOGG asked for gravity (an actor with nothing under it falls,
including through a breached floor) and for movement as free as Valheim's, with
climbing, parkour, and flips like *skate.*, so the player can explore the world freely.

The sim today moves actors in integer millimetres on the 1 m build grid, in x/z on one
storey. Movement is deterministic, replayed bit for bit, and is the same rule set guards
path with. Free movement would replace that model, not extend it.

References checked on 2026-10-08:

- **ReSkate** (`GamerNationinc/ReSkate-Steamdeck-`) is a launcher and runtime that hooks
  EA's *skate.* under Proton. The skating physics, tricks and animations are inside
  `Skate.exe` and are EA's, so there is no movement code in the fork to reuse. The fork is
  GPL-3, so copying its code into Gcity would put the game under the GPL.
- **Valheim** is in the lineage for its loop, building and support rules (§1.2), not for
  its movement.

## Options

### A — Discrete parkour moves on the grid
Gravity and falling with fall damage, plus climb, mantle and jump as discrete moves (the
§6.4 capability tags) that the client animates.
- Cost: small. Movement stays integer and deterministic, guards can path the same moves,
  and the portal graph prices them as edges.
- Risk: less free-form than a physics character; what the player can do is what the
  move set names.
- Forecloses: nothing, since it is a subset of B's behaviour.

### B — Continuous physics movement in the sim
Fixed-point velocity, gravity and jump arcs, mantling and climbing on any ledge up to a
height, colliding against the build grid.
- Cost: rewrites movement and pathing. It needs a timeboxed spike (standards §9.1) for
  determinism and the Deck budget first.
- Risk: physics drift between runs breaks replay and co-op; agents need their own
  traversal of free geometry (§6.4 traces).
- Forecloses: nothing, but M6 would pause until it lands.

### C — A now, B later
Ship A in M6 so the vertical slice plays. Free movement becomes its own milestone,
preceded by a spike with a declared pass metric (determinism across processes, Deck
cost within the movement share of the frame budget).

## Decision

**Accepted: C** (CEOGG, 2026-10-08).

M6 builds A:
- falling with fall damage from content;
- stairs and ladders as climb edges;
- a mantle onto pieces whose kind allows it;
- a jump across a one-cell gap on the same storey.

Flips and rolls are client-side animation of these moves, and they arrive with a
character rig; actors are capsules today. Free physics movement (B) is a later milestone,
scheduled by CEOGG after G6, with its own spec and spike.

## Consequences

Easy: determinism and replay are untouched; guards and players share one move set; the
routes of §15.2 stay authored puzzles.

Hard: A's move set must be designed so that B can later replace it without changing what
the routes mean. Every move is therefore a capability tag on an edge, which is the shape
the §6.4 traces need anyway.

## Verification

At G6:
- M6 fixtures with a fall, a mantle and a jump;
- the property that every living actor is standing or falling and lands within its fall
  time;
- fall damage from content.

For B: the spike's report before its spec.

## Sign-off

Approver: CEOGG
Date: 2026-10-08
Outcome: accepted (C: discrete grid moves with gravity in M6; free physics movement as a later milestone after a spike)
