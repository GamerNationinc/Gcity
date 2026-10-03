# `docs/references/`: design notes from studied codebases

Plain-English design notes on how other projects structure systems Gcity may build,
written under `docs/policy/study-and-rebuild.md`. A note describes behaviour, data flow,
ordering and failure modes; it holds no code, no constants, no identifiers beyond module
names, no file formats. Gcity code is written from these notes and our specs only, never
from the studied source (CLAUDE.md §10). A note is study material, not a decision: what
Gcity builds goes through a spec and, where it touches one, an ADR.

## Study 1 — 2026-10-02

Requested by CEOGG ("read compiled stuff to learn and implement the best logic from").
Read by a separate study agent through web pages only (nothing cloned, downloaded or
run, nothing in the Gcity workspace touched), from
[vladtrc/iw4L](https://github.com/vladtrc/iw4L) and
[SK8-ENGINE/skate-3-rust-engine](https://github.com/SK8-ENGINE/skate-3-rust-engine). Neither
ships game assets; both read the user's own copy of the game. Much of skate-3-rust-engine
is logic recovered from the retail game's binary: its notes keep general structure only,
and a Gcity version must not set out to reproduce that game's behaviour or feel.
Vetted in this session before commit: no code blocks or inline code, no numbers but list
numbering and Gcity's own, no identifiers from their source; one link carrying a game
state id was removed.

| Note | Idea | Where it may matter |
|---|---|---|
| [skate3-player-state-and-frame-order](skate3-player-state-and-frame-order.md) | Movement modes as registered handlers with enter and exit; a mode change applied at one fixed point in the tick and reported as an event | M8 character motion |
| [skate3-ground-contact-orientation](skate3-ground-contact-orientation.md) | Probe per contact point, gated normal averaging with fallbacks, keep the last good normal, two-speed up-vector smoothing | M8 character motion |
| [skate3-behaviour-graph-and-tuning](skate3-behaviour-graph-and-tuning.md) | Layered state-machine trees, priority tiers, conditions as data that declare their inputs, ranged tuning layered on a base profile | M8 animation; content tuning |
| [iw4l-sim-step-funnel](iw4l-sim-step-funnel.md) | One step for authority, prediction and replay; canonical command order; cross-field validation of inputs that parse | Co-op later; fuzz targets now |
| [iw4l-bot-navigation](iw4l-bot-navigation.md) | Multi-goal search on a shared per-tick budget, resumable; "out of budget" distinct from "unreachable" | M9 squads; PathingSystem |
| [iw4l-bot-perception-and-decision](iw4l-bot-perception-and-decision.md) | Seen / checked-not-seen / not checked; a shared query budget; utility with a switching margin; fire only on fresh sight | M9 threat director |
| [iw4l-tracing-and-scenario-runner](iw4l-tracing-and-scenario-runner.md) | Zero-cost opt-in tracing that rejects truncated traces; scenarios resolved once into a saved record | Tooling (`GCITY_PERF`), sandbox fixtures |

The study agent's own index, with its per-note contamination check, is
[INDEX.md](INDEX.md).
