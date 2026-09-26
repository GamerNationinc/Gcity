# ADR-003 condition 2: the spike's worst frames, traced

ADR-003 (accepted as B) carried a condition: *the isolated worst frames seen in the spike
(about 1 in 10⁴ frames at 25–92 ms, uncorrelated with meshing) are traced at frame level
before M7*. It was not done before M7 began; CEOGG ruled (2026-09-24) that it be done
before claim 16 streams any wild terrain, and recorded late in the G7 debt log. This is
that trace. Raw data and the harness patch are in `worst-frame-trace/`.

**Finding: the worst frames were the harness measuring itself.** Once a minute the
spike's harness summarised the last minute by scanning *every frame recorded since the
start* — up to 2.4 million in GDScript — and the scan grew with the run. Fixed to read
only the minute it summarises, the minute-mark stalls are gone. What remains is one frame
in 571 589 over budget, with nothing of ours running in it.

## Method

The spike was recovered from `cee8f1d` into a scratch directory (not the repo), its Rust
mesher rebuilt, and the harness given a frame-level trace: for every frame, the time in
the harness's own script, the renderer's measured CPU and GPU time, chunk uploads, mesh
nodes created and freed, static memory, and whether a dig landed. At the end it writes
every frame over the 25 ms budget, and the 60 slowest, with all of that attached. A
`mesh=off` switch runs the identical camera path with no streaming, meshing or digging:
the control. `harness-trace.patch` is the whole change.

Three 30-minute soaks on the Deck, windowed, plugged in, 2026-09-25, pinned engine
4.6.1, same seed and parameters as the original spike:

| Run | Frames | Over 25 ms (after 5 s warm-up) | Of those, within 2.5 s of a minute mark | Max | p99 (whole run) |
|---|---|---|---|---|---|
| terrain on, original harness | 583 272 | 14 | 12 | 92.0 ms | 4.17 ms |
| terrain off (control), original harness | 2 388 740 | 24 | 24 | 144.6 ms | — |
| terrain on, harness fixed | 571 589 | **1** | **0** | 52.5 ms (warm-up) / 39.4 ms after | 4.17 ms |

## What the trace showed

- **Terrain off stutters worse than terrain on.** The control run, with no chunk ever
  meshed, uploaded or freed, had more frames over budget and longer ones. So the stalls
  were not meshing, uploads or node churn.
- **In every over-budget frame, nothing of ours was busy.** Median across them: harness
  script 0.05 ms, renderer CPU 0.6 ms, GPU 2.9 ms (0.37 ms in the control), no uploads, no
  nodes made or freed, no dig. The frame time was spent somewhere none of those see.
- **They land on minute marks.** 36 of 38 over-budget frames across the two original runs
  fall within 2.5 s of a whole minute (t = 900, 1140, 1200, 1260, 1320, 1440, 1500, 1560,
  1620, 1680, 1740 s…), later minutes worse than earlier ones, and the control — which
  runs four times the frame rate and so records four times the frames — worst of all.
- **The cause** is `_record_minute()` → `_window_summary()`, which looped over every
  recorded frame to find the last minute's. Replaced with a binary search into the
  time-ordered array, it reads only that minute's frames.
- **After the fix**: one frame over 25 ms in 30 minutes (39.4 ms at t = 171.9 s, not on a
  minute mark; script 0.05 ms, render 0.9 / 3.4 ms, no churn), and the next slowest
  12.0 ms. We attribute that one to the platform: nothing the game controls ran in it.

The M6 gate saw a similar ~225 ms frame in two client captures and put it down to the
machine; this trace is consistent with that reading and gives no reason to revise it.

## What it means for claim 16

- The meshing approach ADR-003 chose is not the source of isolated stalls. Streaming
  wild terrain can go ahead on it.
- Any in-game frame statistics must be windowed or incremental, never a rescan of
  everything recorded: that is exactly the mistake the harness made. (The client's
  `--capture` writes frame times out at the end and summarises nothing mid-run, so it
  does not have this problem.)
- ADR-003's other half of condition 2 — the streamer promoted from the spike pools its
  mesh nodes — belongs to claim 16's promotion of the mesher and is done there.

## Reproduce

```
git archive cee8f1d spikes/surface_nets_deck | tar -x -C <scratch>
cd <scratch>/spikes/surface_nets_deck && patch -p1 < <repo>/docs/specs/spike-surface-nets-deck-results/worst-frame-trace/harness-trace.patch
cd rust && cargo build --release && cp target/release/libsurface_nets_spike.so ../godot/bin/
cd ../godot && GODOT=<repo>/tools/godot.sh
$($GODOT) --path . -- duration=1800 out=soak-on.json
$($GODOT) --path . -- duration=1800 mesh=off out=soak-off.json
```

(The patch above includes the fix; to see the original stalls, revert its
`_window_summary` hunk.)
