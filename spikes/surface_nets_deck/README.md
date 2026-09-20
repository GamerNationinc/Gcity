# spikes/surface_nets_deck

Research spike for ADR-003 (standards §9.1). Spec, pre-declared pass metric and results:
`docs/specs/spike-surface-nets-deck.md`. **Disposal:** deleted or promoted at the ADR
sign-off, never left in place. `spikes/.gdignore` keeps the main project and its
tooling from seeing anything in here.

| Path | What |
|---|---|
| `rust/` | GDExtension (`godot` crate 0.5.5, MPL-2.0, pinned by `Cargo.lock`). Density field, sparse edit overlay, worker pool, surface nets. `cargo test` covers the closed-mesh and chunk-range invariants. |
| `godot/` | Harness project: streaming, digging, mesh upload, frame-time capture, JSON report. `surface_nets_gd.gd` is the GDScript port for the §9.2 Tier 1 comparison. |
| `thermal_sampler.sh` | Temperatures, clocks and power to CSV every 5 s. |
| `analyze.py` | JSON + CSV → the markdown tables in the spec. |
| `results/` | Raw JSON and CSV from the Deck runs. |

## Build and run (on the Deck)

```
cd spikes/surface_nets_deck/rust && cargo build --release && cargo test --release
cp target/release/libsurface_nets_spike.so ../godot/bin/
cd ../godot
GODOT=$(../../../tools/godot.sh)
$GODOT --headless --path . --import
$GODOT --headless --path . -- mode=bench out=../results/bench.json
../thermal_sampler.sh ../results/soak-thermal.csv 5 &
$GODOT --path . -- duration=1800 out=../results/soak.json     # 30-minute soak, windowed
kill %1
python3 ../analyze.py ../results/soak.json ../results/soak-thermal.csv ../results/bench.json
```

Harness arguments after `--`: `duration=<s> workers=<n> radius=<chunks> vradius=<chunks>
uploads=<per frame> speed=<m/s> edit_interval=<s> seed=<n> out=<path> mode=soak|bench`.
Exit status is 0 on pass, 3 on fail.
