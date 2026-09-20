# Gate ledger

One file per milestone, `M<n>-gate.md`, committed before review. Each holds the four-part
evidence package (specification, verification report, demo script, debt and deviation
log), the answers to the four standing questions (functions, secure, complete,
expandable), and the sign-off line with date and outcome (standards §2).

Outcomes are exactly: **Accepted**, **Accepted with conditions** (conditions listed and
scheduled into a named milestone), or **Rejected**.

| Gate | Milestone | Status |
|---|---|---|
| G0 | M0 — Skeleton | evidence package submitted, awaiting review |
| G1 | M1 — Stat resolver + one pistol | not started (blocked on G0, ADR-003, ADR-009) |
| G2–G8 | see `docs/gcity-engineering-standards.md` §11 | not started |
