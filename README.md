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

**M3 — Portal graph + build system + grey-box 3D**, evidence package submitted
(`docs/gates/M3-gate.md`); G0–G2 accepted. Build pieces on a 1 m grid with support
propagation, a portal graph where every wall is a priced edge, raid planning and a dumb
raid token, actor movement, and a walkable grey-box 3D world with the M1 pistol. The
main scene is the world view; the plot view is `client/plot_view.tscn` and the M1
range `client/main.tscn`.

## Running

Requires Linux x86_64, `python3` (3.10+), `curl`, `unzip`. The pinned engine is fetched
on first use.

```
tools/test.sh
```

To open the project in the editor: `$(tools/godot.sh) --path .`
