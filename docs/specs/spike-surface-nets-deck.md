# Spike: surface-nets-deck

Research spike under standards §9.1, run to close ADR-003. Written before the first
measurement; the pass metric below is the one the ADR pre-declared and is not revised
after the fact. Results are appended in §5 when the runs complete.

```
Spike:        surface-nets-deck
Claim:        volumetric chunk meshing fits 3.0 ms/frame amortised on Deck at the
              streaming radius the wilds need (standards §4.1 row "chunk meshing")
Timebox:      5 days (started 2026-09-20)
Pass metric:  1% low frame time within budget over a 30-minute thermal soak while
              streaming and editing chunks, measured on Deck hardware
Fallback:     ADR-003 option C (heightmap plus authored volumetric pockets), with the
              "under" route of the vertical slice as an authored pocket
Disposal:     spikes/surface_nets_deck/ is deleted or promoted at the ADR sign-off;
              never left in place. Done 2026-09-20: code removed from the tree
              (recoverable at commit cee8f1d), results kept beside this spec
```

## 1. What is measured

Two numbers decide the spike, both taken from the **final 5 minutes** of a 30-minute run
(standards §4.2), and both must hold:

| Metric | Pass |
|---|---|
| Frame time, 1% low (p99 of raw frame time, vsync off, uncapped) | ≤ 25.0 ms |
| Meshing cost, amortised (worker generation + meshing CPU time + main-thread mesh upload time, summed over the window, divided by the number of 40 fps frames in that window, i.e. per 25 ms of wall time) | ≤ 3.0 ms/frame |

Also reported, not gating: 0.1% low, fraction of frames over 25 ms, per-chunk generation
and meshing time, main-thread upload time per chunk, result backlog, resident chunk and
triangle counts, CPU/GPU temperature and clock every 5 s across the whole run, and
the Tier 1 Rust-vs-GDScript ratio for the same algorithm on the same input (standards
§9.2; pass there is ≥5× with equal output).

The meshing number is normalised to 40 fps frames on purpose: the harness runs uncapped,
and dividing by the frames it actually rendered would let a high frame rate shrink the
cost. Uncapped and vsync-off is the pessimistic condition: the shipped game caps at 40 fps,
so the GPU would idle part of each frame and the thermal load would be lower. A number
that passes here passes the capped case.

## 2. Workload

Chosen to stand in for "the streaming radius the wilds need", which the design doc does
not quantify; these parameters are the spike's assumption and are recorded for the ADR.

| Parameter | Value | Reason |
|---|---|---|
| Voxel | 1 m | Digging and building resolution of a 40×40 m plot (design doc §8.1) |
| Chunk | 32³ voxels, 34³ density samples (one sample of padding each side) | Watertight seams by overlapping one cell |
| Streaming radius | 5 chunks horizontally (Euclidean, ≈95 columns), ±2 chunks vertically | ≈160 m view distance; 5 layers cover terrain relief of ±32 m around the camera |
| Resident set | ≈475 chunks | Follows from the two rows above |
| Camera path | Circle of radius 400 m at terrain height + 20 m, 8 m/s | Sprint speed; crosses a chunk boundary every 4 s, forcing a column of ≈55 new chunks each time |
| Edits | Every 2 s, dig a sphere of radius 3 m at the surface 20 m ahead of the camera | Re-meshes up to 8 chunks per edit through the same path a player's shovel would |
| Terrain | 3-octave 2D value-noise heightfield, amplitude ±24 m, plus a 3D noise cave field carved below the surface | Surface density and caves typical of the wilds; no authored content |
| Density overlay | Player edits stored as a sparse map of world-sample deltas over the seeded field | The same shape as `save = seed + overlay` (design doc §5.6) |
| Worker threads | 3 | Leaves main, render and audio threads on a 4c/8t part with AI still to come |
| Uploads per frame | ≤ 4 chunk meshes | Time-slicing on the main thread (design doc §2) |

## 3. Implementation

`spikes/surface_nets_deck/rust/` is a GDExtension in Rust (crate `godot` 0.5.5,
MPL-2.0, pinned by `Cargo.lock` checksum; no other dependencies) exposing one class,
`VoxelWorld`: seeded density generation, the sparse edit overlay, a worker pool over
`std::thread`, naive surface nets producing positions, normals and indices, and
counters. `spikes/surface_nets_deck/godot/` is the harness: streaming around the moving
camera, edits, mesh upload, frame-time capture and JSON output. `tools/thermal_sampler.sh`
(inside the spike directory) logs temperatures and clocks. `analyze.py` turns the JSON
and CSV into the tables in §5.

`spikes/` carries a `.gdignore` so the main project and its tooling never see it.
Nothing under `sim/`, `client/`, `tools/` or `tests/` changes for this spike.

## 4. Deviations to record

- Run in SteamOS desktop mode (KDE on Wayland), not in the gamescope session, with the
  usual desktop processes resident. This is pessimistic for CPU and memory.
- Collider generation is not measured; the ADR claim is about meshing. Colliders are
  a follow-up cost whichever option wins.
- One power profile per run. Plugged first; battery second if the timebox allows.

## 5. Results

**Outcome: PASS on both pre-declared metrics, in both power profiles, 2026-09-20.**
Two 30-minute soaks on this Deck (AMD Custom APU 0932, SteamOS, desktop mode), plugged
in and then on battery, each from a cold start. Raw artifacts under
`docs/specs/spike-surface-nets-deck-results/`: `soak-plugged.json`, `soak-battery.json`, the two
`*-thermal.csv` files, `bench.json`, the logs and the generated tables.

| Pre-declared metric | Plugged | Battery | Budget | Headroom |
|---|---|---|---|---|
| Frame time 1% low, final 5 min | 4.10 ms | 4.12 ms | ≤ 25.0 ms | 6.1× |
| Meshing amortised per 40 fps frame, final 5 min | 1.12 ms | 1.15 ms | ≤ 3.0 ms | 2.6× |
| Tier 1: Rust vs GDScript, same algorithm, equal output | ×169, all 12 chunks bit-equal | | ≥ 5× | |

### 5.1 Soak, plugged in

Run: `results/soak-plugged.json` — Godot 4.6.1-stable (official), 1800 s, 3 workers, radius 5/±2 chunks, ≤4 uploads/frame, 8.0 m/s, dig every 2.0 s, seed 20260920, vsync disabled, uncapped.

| Metric (final 5 min unless noted) | Value | Pass |
|---|---|---|
| Frame time p50 | 3.03 ms | |
| **Frame time 1% low (p99)** | **4.10 ms** | **pass** (≤ 25.0) |
| Frame time 0.1% low (p99.9) | 4.76 ms | |
| Worst frame | 58.02 ms | |
| Frames over 25 ms | 0.004 % | |
| Average frame rate | 323.5 fps | |
| **Meshing, amortised per 40 fps frame** (workers + upload) | **1.12 ms** | **pass** (≤ 3.0) |
| of which main-thread upload per 40 fps frame | 0.08 ms | |
| Chunks re/meshed per second | 20.0 | |
| Worker time per chunk (generation + meshing) | 2.08 ms | |
| Main-thread upload per chunk | 0.16 ms | |
| Whole run: p99 / p99.9 / worst | 4.17 / 5.01 / 91.78 ms | |
| Whole run: meshing per 40 fps frame | 1.12 ms | |
| Generation / meshing per meshed chunk (all workers, whole run) | 1.61 / 0.48 ms | |
| Resident chunks / triangles at end | 204 / 578,496 | |
| Peak backlog (queued + in flight + waiting) | 405 chunks | |
| Edits applied | 899 | |
| Worker totals: meshed / skipped as air / stale dropped | 35988 / 15427 / 0 | |

Per minute:

| min | fps | p50 | p99 | p99.9 | max | >25 ms | meshing ms/40fps-frame | chunks/s | resident | tris | backlog |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 348 | 2.78 | 3.52 | 4.98 | 89.2 | 0.01% | 1.40 | 25.3 | 218 | 565,510 | 0 |
| 2 | 287 | 3.44 | 4.17 | 5.56 | 17.4 | 0.00% | 1.06 | 18.9 | 197 | 615,840 | 0 |
| 3 | 291 | 3.40 | 4.17 | 5.02 | 17.9 | 0.00% | 1.06 | 20.3 | 218 | 637,684 | 0 |
| 4 | 343 | 2.83 | 3.51 | 4.82 | 12.1 | 0.00% | 1.18 | 22.1 | 200 | 547,852 | 0 |
| 5 | 355 | 2.78 | 3.35 | 8.33 | 91.8 | 0.02% | 1.06 | 19.3 | 205 | 570,746 | 8 |
| 6 | 347 | 2.81 | 3.44 | 4.17 | 10.5 | 0.00% | 0.99 | 17.8 | 220 | 573,694 | 0 |
| 7 | 300 | 3.36 | 4.17 | 4.55 | 11.0 | 0.00% | 1.07 | 18.7 | 221 | 651,306 | 0 |
| 8 | 293 | 3.34 | 4.17 | 5.56 | 21.0 | 0.00% | 1.17 | 21.3 | 223 | 627,114 | 0 |
| 9 | 330 | 3.03 | 3.70 | 4.55 | 8.0 | 0.00% | 1.16 | 22.3 | 200 | 571,954 | 0 |
| 10 | 349 | 2.78 | 3.33 | 5.00 | 9.7 | 0.00% | 1.10 | 18.5 | 215 | 630,580 | 0 |
| 11 | 348 | 2.78 | 3.35 | 4.53 | 13.5 | 0.00% | 0.99 | 17.4 | 203 | 585,448 | 0 |
| 12 | 325 | 3.03 | 3.70 | 4.96 | 12.6 | 0.00% | 1.03 | 18.7 | 219 | 641,444 | 0 |
| 13 | 285 | 3.44 | 4.23 | 8.33 | 46.3 | 0.01% | 1.07 | 19.6 | 200 | 609,014 | 0 |
| 14 | 312 | 3.14 | 4.17 | 5.31 | 13.7 | 0.00% | 1.22 | 22.4 | 199 | 543,500 | 0 |
| 15 | 346 | 2.78 | 3.33 | 4.17 | 16.4 | 0.00% | 1.06 | 20.3 | 226 | 637,772 | 0 |
| 16 | 356 | 2.78 | 3.46 | 4.17 | 49.9 | 0.00% | 1.04 | 18.3 | 196 | 607,092 | 0 |
| 17 | 337 | 2.92 | 3.70 | 4.55 | 17.1 | 0.00% | 1.08 | 18.7 | 222 | 590,728 | 0 |
| 18 | 283 | 3.48 | 4.17 | 6.06 | 18.7 | 0.00% | 1.09 | 19.6 | 180 | 571,818 | 0 |
| 19 | 298 | 3.33 | 4.17 | 4.87 | 19.5 | 0.00% | 1.30 | 21.3 | 198 | 529,204 | 0 |
| 20 | 348 | 2.78 | 3.48 | 4.33 | 23.5 | 0.00% | 1.21 | 20.3 | 227 | 589,208 | 0 |
| 21 | 364 | 2.78 | 3.19 | 4.27 | 26.2 | 0.00% | 1.05 | 18.5 | 205 | 606,296 | 0 |
| 22 | 344 | 2.89 | 3.70 | 4.55 | 30.7 | 0.00% | 1.09 | 19.4 | 214 | 562,994 | 0 |
| 23 | 283 | 3.49 | 4.17 | 5.56 | 32.2 | 0.01% | 1.12 | 18.9 | 193 | 606,206 | 0 |
| 24 | 292 | 3.37 | 4.17 | 5.56 | 27.4 | 0.01% | 1.24 | 21.1 | 214 | 601,910 | 0 |
| 25 | 345 | 2.78 | 3.33 | 4.47 | 26.5 | 0.00% | 1.17 | 20.4 | 200 | 548,506 | 0 |
| 26 | 358 | 2.78 | 3.33 | 3.98 | 22.4 | 0.00% | 1.14 | 20.5 | 212 | 609,262 | 0 |
| 27 | 346 | 2.82 | 3.70 | 4.31 | 30.4 | 0.00% | 1.04 | 18.5 | 224 | 570,166 | 0 |
| 28 | 296 | 3.38 | 4.17 | 4.55 | 25.0 | 0.01% | 1.04 | 17.9 | 220 | 677,926 | 0 |
| 29 | 292 | 3.36 | 4.17 | 4.76 | 42.0 | 0.01% | 1.18 | 20.4 | 197 | 555,198 | 51 |
| 30 | 331 | 3.03 | 3.70 | 4.98 | 58.0 | 0.01% | 1.22 | 23.1 | 204 | 578,496 | 0 |

| Sensor | first 5 min (mean) | last 5 min (mean) | peak |
|---|---|---|---|
| SoC edge temperature (amdgpu) | 71.4 | 71.6 | 74.0 |
| ACPI thermal zone | 71.9 | 72.1 | 74.0 |
| CPU clock, mean of 8 threads (MHz) | 2136 | 2134 | 2425 |
| GPU clock (MHz) | 1555 | 1564 | 1600 |
| GPU/SoC power (W) | 14.90 | 14.85 | 17.18 |
| Memory available (MB) | 7217 | 10150 | 6635 (min) |
| Battery status during run | Discharging, Not charging | | |

### 5.2 Soak, on battery

Same harness, same seed and parameters, charger disconnected for the whole run
(`ACAD/online = 0`, battery status `Discharging` in all 357 samples). Plugged and battery
side by side, final 5 minutes:

| Final 5 min | plugged | battery |
|---|---|---|
| Frame time 1% low (p99) | 4.10 ms | 4.12 ms |
| Frame time 0.1% low (p99.9) | 4.76 ms | 4.76 ms |
| Frames over 25 ms | 0.004 % | 0.005 % |
| Average frame rate | 323 fps | 325 fps |
| Meshing per 40 fps frame | 1.12 ms | 1.15 ms |
| Worker time per chunk | 2.08 ms | 2.15 ms |
| Upload per chunk | 0.16 ms | 0.16 ms |
| Chunks per second | 20.0 | 20.0 |
| SoC edge temperature | 71.6 °C | 71.4 °C |
| CPU clock, mean of 8 threads | 2134 MHz | 2228 MHz |
| GPU clock | 1564 MHz | 1529 MHz |
| GPU/SoC power | 14.85 W | 14.39 W |
| Battery charge start → end | 79 % → 79 % | 79 % → 57 % |
| Pass (both metrics) | yes | yes |

Battery-run thermals over the whole run:

| Sensor | first 5 min (mean) | last 5 min (mean) | peak |
|---|---|---|---|
| SoC edge temperature (amdgpu) | 70.2 | 71.4 | 74.0 |
| ACPI thermal zone | 70.6 | 72.0 | 73.0 |
| CPU clock, mean of 8 threads (MHz) | 2207 | 2228 | 2425 |
| GPU clock (MHz) | 1533 | 1529 | 1600 |
| GPU/SoC power (W) | 14.59 | 14.39 | 17.08 |
| Memory available (MB) | 10426 | 10422 | 10351 (min) |
| Battery status during run | Discharging | | |

The two profiles are indistinguishable on every gameplay-relevant number: the p99 frame
times differ by 0.02 ms and the meshing cost by 0.03 ms per frame. On battery the SoC
ran the CPU slightly higher and the GPU slightly lower at 0.5 W less, which is the
firmware rebalancing within the same 15 W envelope, not a throttle. The run consumed
22 % of the battery in 30 minutes at an uncapped 325 fps; a 40 fps cap would draw far
less. Full per-minute table: `results/soak-battery-tables.md`.

### 5.3 Rust vs GDScript (standards §9.2 Tier 1)

Rust vs GDScript, same algorithm, same 12 chunks (mean of 5 Rust runs each):

| chunk | vertices | Rust | GDScript | ratio | equal output |
|---|---|---|---|---|---|
| (9, -1, 0) | 1229 | 0.52 ms | 97.4 ms | ×189 | yes |
| (8, -1, 6) | 2565 | 0.67 ms | 104.2 ms | ×156 | yes |
| (3, 0, 7) | 1033 | 0.50 ms | 88.7 ms | ×179 | yes |
| (-2, -1, 1) | 1584 | 0.55 ms | 98.5 ms | ×179 | yes |
| (-5, -1, -8) | 2549 | 0.63 ms | 102.2 ms | ×162 | yes |
| (-3, 0, -13) | 1379 | 0.53 ms | 93.5 ms | ×176 | yes |
| (2, 0, -12) | 1252 | 0.51 ms | 90.8 ms | ×177 | yes |
| (9, 0, -5) | 1479 | 0.53 ms | 91.9 ms | ×172 | yes |
| (16, -1, 1) | 2594 | 0.64 ms | 102.3 ms | ×161 | yes |
| (19, -1, 2) | 2242 | 0.62 ms | 101.6 ms | ×163 | yes |
| (18, 0, -4) | 2303 | 0.59 ms | 95.2 ms | ×162 | yes |
| (14, 0, -13) | 2031 | 0.58 ms | 95.7 ms | ×166 | yes |
| **total** | | 6.9 ms | 1162 ms | **×169** | all equal |

Tier 1 criterion (≥5× with equal output): **pass**.

### 5.4 Observations

- **Steady state is flat, in both profiles.** Minutes 2 through 30 sit between 0.99
  and 1.30 ms of meshing per 40 fps frame and 3.2 to 4.2 ms p99 frame time, with no trend. Clocks and
  temperature are identical in the first and last five minutes (≈71.5 °C, ≈2135 MHz
  CPU, ≈1560 MHz GPU, ≈14.9 W), so the 15 W part did not throttle under this load.
- **Per-chunk cost is dominated by density generation, not meshing.** 1.61 ms to sample
  a 34³ chunk against 0.48 ms to run surface nets on it. The noise is naive scalar code;
  generation is the first thing to optimise if the budget ever tightens, and it is also
  the part a real world generator replaces.
- **Main-thread cost is small.** Mesh upload is 0.16 ms per chunk and 0.08 ms per 40 fps
  frame, so the ≤4 uploads/frame cap never bit; the result backlog was 0 in 28 of 30
  per-minute samples.
- **Initial fill is the worst case.** The peak backlog of 405 chunks is the first
  seconds after start, when ≈475 chunks are requested at once; it drained inside the
  first minute. A region transition (design doc §5.1) will look like this and should
  happen behind the load window the design already provides.
- **Isolated worst frames.** About 1 frame in 10 000 (0.004 % in the final window) took
  25 to 92 ms; the 0.1 % low is 4.76 ms, so these are rarer than one per thousand. They
  are not explained by meshing (backlog 0, meshing flat when they occur). Candidates,
  in order: the harness freeing ≈55 mesh nodes with `queue_free` at each chunk-column
  crossing, a desktop-mode compositor stall, GDScript allocation. They need a
  frame-level trace (Tracy, standards §4.2) before M7 and are recorded here as a
  follow-up, not a fail: at 40 fps that is one hitch every four minutes in a harness
  that does none of the pooling a shipped streamer would.
- **Memory.** Available memory rose from 7.2 GB to 10.2 GB during the run because a
  desktop process released memory; the spike itself held ≈475 chunks of densities
  (≈80 MB) plus ≈600 k triangles of meshes without visible growth.

### 5.5 Deviations from the protocol

- Desktop mode, not gamescope; usual desktop processes resident (Steam, browser).
  Pessimistic for CPU and memory, as stated in §4.
- Both power profiles were run (standards §4.2), sequentially rather than interleaved;
  the battery run started from 79 % charge, not full.
- No colliders, no LOD, no navigation on the generated mesh; those are M2/M3/M7 costs
  whichever terrain option wins and are outside the ADR-003 claim.
- Frame times were captured with the engine's process delta, not Tracy. The JSON
  artifact carries per-minute distributions rather than a per-frame trace.

### 5.6 Recommendation for ADR-003

The claim holds with margin: naive surface nets over 1 m voxels, streamed at a 160 m
radius with continuous digging, costs about a third of its frame budget on the target
hardware, does not degrade over 30 minutes, and does not change when the charger is
pulled. Nothing measured here argues for the
heightmap fallback. Recommend **option B (volumetric, surface nets)** be accepted, with
two open conditions carried into the gates that own them (the third is closed):

1. Colliders and runtime navigation on volumetric chunks are measured at G3 against
   the physics and navigation rows of standards §4.1.
2. The isolated worst frames above are traced at frame level before M7 and the
   streamer promoted from this spike pools its mesh nodes.
3. (Closed 2026-09-20.) The battery-profile soak was run and is in §5.2; both profiles
   pass with the same margin.

**Disposal:** if ADR-003 accepts B, the Rust mesher and worker pool are promoted into
the project's first native module at M7 (their tests come with them) and the harness is
deleted; if it does not, the whole of `spikes/surface_nets_deck/` is deleted.
