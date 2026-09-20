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

**M0 — Skeleton.** Sim/client split with a CI-enforced dependency rule, a headless
test harness, a fixed-tick deterministic sim root with canonical state hashing, and
record-and-replay fixtures. No gameplay. See `docs/specs/M0-skeleton.md` and
`docs/gates/M0-gate.md`.

## Running

Requires Linux x86_64, `python3` (3.10+), `curl`, `unzip`. The pinned engine is fetched
on first use.

```
tools/test.sh
```

To open the project in the editor: `$(tools/godot.sh) --path .`
