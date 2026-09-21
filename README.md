# Gcity

A cyberpunk survival immersive-sim for the Steam Deck, built in Godot 4 as a systems
engineering exercise: few generic systems, lots of data, every claim demonstrated by a
test that would fail if it were false.

| Start here | |
|---|---|
| `docs/gcity-design.md` | What is being built and why: pillars, architecture, build order M0–M8. |
| `docs/gcity-engineering-standards.md` | How it gets built and proven: stage gates, verification, security, Steam. |
| `CLAUDE.md` | The rules that hold on every commit. |
| `docs/adr/` | The ten open decisions as Architecture Decision Records. |
| `docs/gates/` | The gate ledger: one evidence package and sign-off per milestone. |

## Status

**M2 — Land authority + starter plot**, evidence package submitted (`docs/gates/M2-gate.md`).
G0 and G1 are accepted. The sim has a total `rights_at()` over polygon parcels, a
container with modules on a shared power and heat budget through the stat resolver,
and a validated save format round-tripped as a property. The main scene is the plot
view; the M1 range is `client/main.tscn`.

## Running

Requires Linux x86_64, `python3` (3.10+), `curl`, `unzip`. The pinned engine is fetched
on first use.

```
tools/test.sh
```

To open the project in the editor: `$(tools/godot.sh) --path .`
