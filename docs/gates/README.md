# Gate ledger

One file per milestone, `M<n>-gate.md`, committed before review. Each holds the four-part
evidence package (specification, verification report, demo script, debt and deviation
log), the answers to the four standing questions (functions, secure, complete,
expandable), and the sign-off line with date and outcome (standards §2).

Outcomes are exactly: **Accepted**, **Accepted with conditions** (conditions listed and
scheduled into a named milestone), or **Rejected**.

| Gate | Milestone | Status |
|---|---|---|
| G0 | M0 — Skeleton | **Accepted** 2026-09-20 by CEOGG |
| G1 | M1 — Stat resolver + one pistol | spec written (`docs/specs/M1-stat-resolver-pistol.md`); implementation blocked on ADR-003 only (G0, ADR-002 and ADR-009 signed 2026-09-20) |
| G2–G8 | see `docs/gcity-engineering-standards.md` §11 | not started |
