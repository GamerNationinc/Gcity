# Study notes index (clean-room study phase)

Projects studied, by web reading only (github.com pages, raw.githubusercontent.com files, GitHub API
JSON listings). Nothing was cloned, downloaded or executed.

Asset status (rule 4):
- iw4L: ships no game assets; it reads the user's own install at runtime. No data files were read.
- skate-3-rust-engine: ships no game assets; set-up converts the user's own disc image into a local data
  folder, and its gameplay tests need that user-supplied data. No data files or fixtures were opened
  (the fixtures folder was only listed). Caution: much of this project's source is a port of logic
  recovered from the retail binary; the notes deliberately keep only generic architecture, and the
  implementing session should not try to reproduce that game's behaviour or feel.

## Notes

1. skate3-player-state-and-frame-order.md: physical modes as a closed registry of enter/exit handlers,
   transitions as tick-applied commands with events, and the fixed per-tick phase order around the solver.
   Contamination check: no code, no copied identifiers (module/file names only), no numeric constants,
   no layouts or offsets; no assets read.
2. skate3-ground-contact-orientation.md: wheel probes with gated normal averaging, fallbacks and "keep
   last normal", soft snap, and rate-limited dual-filter orientation that preserves heading.
   Contamination check: no code, no copied identifiers, no numeric constants (thresholds described by
   role only), no layouts or bit fields; no assets read.
3. skate3-behaviour-graph-and-tuning.md: hierarchical action/motion graphs with priority-tiered
   first-match transitions, data conditions with declared required inputs, and validated layered tuning.
   Contamination check: no code, no copied identifiers, no numeric constants, no formats; graph data
   (user-supplied retail data) not read.
4. iw4l-sim-step-funnel.md: one step function for authority, prediction and replay, canonical input
   ordering, snapshot as return value, and the hardening lessons from random command streams and
   inconsistent snapshots.
   Contamination check: no code, no copied identifiers beyond module/file names, no numeric constants,
   no entity layouts or strides; no assets read.
5. iw4l-bot-navigation.md: baked lattice graph with edge kinds, multi-goal search with resumable cursors
   under a shared per-tick quota, three result classes, and topology-only failure caching.
   Contamination check: no code, no copied identifiers, no tile sizes, quotas or heuristic weights; no
   assets read.
6. iw4l-bot-perception-and-decision.md: three-outcome visibility, memory grace and retention windows,
   shared query tokens, utility tasks with a switching margin, and fresh-sight fire gating.
   Contamination check: no code, no copied identifiers, no ranges, cone angles, windows or budgets; no
   assets read.
7. iw4l-tracing-and-scenario-runner.md: zero-cost opt-in tracing that rejects partial traces, and
   approved scenarios that resolve randomness once into a persisted run record and check liveness.
   Contamination check: no code, no copied identifiers (environment switch names omitted), no buffer
   sizes or durations; no assets read.
