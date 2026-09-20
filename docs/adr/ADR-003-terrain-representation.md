# ADR-003: Heightmap carving vs volumetric voxels

Status: proposed — **blocking; must close before M1** (standards §7)
Date: 2026-09-20
Design doc: §5.5 (D-03); §6.2 vertical parcel rules; §15.2 the "under" route

## Context

This decision fixes meshing, navigation, collider generation and the chunk-delta save
format. Two design features already assume volumetric terrain: vertical parcel extents
(digging under a neighbour is trespass, tunnelling under the city wall) and the
"under" route of the vertical-slice mission (§15.2). The Steam Deck CPU is the
bottleneck (§2), and volumetric meshing is the single most expensive candidate
workload.

## Options

### A — Heightmap with carving (Valheim)
- Cost: low. Meshing is trivial; navmesh baking is standard; save deltas are per-cell
  height changes.
- Risk: no caves, tunnels, overhangs or underground bases. The "under" route and the
  vertical parcel rules would need special-casing or dropping.
- Forecloses: the tunnel/basement play space; part of the ownership pillar.

### B — Volumetric voxels with surface nets
- Cost: roughly 5–10× A in CPU and memory for meshing; runtime navigation on
  generated meshes; larger chunk deltas. Meshing is a guaranteed Rust GDExtension or
  compute spike (standards §9.2 Tier 1/2).
- Risk: frame budget. §4.1 gives chunk meshing 3.0 ms amortised; unproven on Deck.
- Forecloses: nothing design-side.

### C — Heightmap surface plus authored volumetric pockets
- Hand-placed or procedurally slotted underground volumes (service tunnels,
  basements) as separate meshed regions stitched to a heightmap world.
- Cost: two terrain representations behind the `Region` interface (§5.1), which the
  design already has for authored vs wild regions.
- Risk: player digging is limited to pockets; "dig anywhere" is lost.
- Forecloses: freeform tunnelling.

## Decision

Open. The recommended path to a decision is a timeboxed spike (standards §9.1) of B on
Deck hardware:

```
Spike: surface-nets-deck
Claim:       volumetric chunk meshing fits 3.0 ms/frame amortised on Deck at the
             streaming radius the wilds need
Timebox:     5 days
Pass metric: 1% low frame time within budget over a 30-minute thermal soak while
             streaming and editing chunks
Fallback:    C, with the "under" route implemented as an authored pocket
```

## Consequences

Whichever option: all terrain code, the chunk delta format and the navigation tier
under the player follow from it. Every week it stays open is a week of M1–M6 design
that may assume the wrong one.

## Verification

The spike's pass metric, measured on Deck, recorded in `docs/specs/spike-surface-nets-deck.md`.

## Sign-off

Approver: CEOGG — _pending_
