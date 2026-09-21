# ADR-003: Heightmap carving vs volumetric voxels

Status: accepted
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

**Accepted: B — volumetric voxels with surface nets** (CEOGG, 2026-09-20), on the
evidence of the spike below, with two conditions carried into the gates that own them:

1. Colliders and runtime navigation on volumetric chunks are measured at G7 against
   the physics and navigation rows of standards §4.1. (Amended 2026-09-21 with the
   M3 spec approval: chunks do not exist before M7, so G3 cannot measure them.)
2. The isolated worst frames seen in the spike (about 1 in 10⁴ frames at 25–92 ms,
   uncorrelated with meshing) are traced at frame level before M7, and the streamer
   promoted from the spike pools its mesh nodes.

The spike that was proposed here was run as written:

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

Measured 2026-09-20, two 30-minute soaks on the Deck, final 5 minutes: 1% low frame
time 4.10 ms plugged / 4.12 ms on battery (budget 25 ms); meshing 1.12 / 1.15 ms per
40 fps frame (budget 3.0 ms); no thermal throttling; Rust mesher ×169 the GDScript port
with bit-equal output. Raw data under `docs/specs/spike-surface-nets-deck-results/`.
Spike code disposed at this sign-off per standards §9.1; it is recoverable at commit
`cee8f1d` (`spikes/surface_nets_deck/`) for promotion into the first native module at M7.

## Sign-off

Approver: CEOGG — accepted 2026-09-20, with the two conditions above. Option B. Unblocks M1.
