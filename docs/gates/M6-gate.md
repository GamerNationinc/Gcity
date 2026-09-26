# G6 — M6 "Cold Storage": gate evidence package

Milestone: M6 — "Cold Storage" (design doc §15–16; standards §11 row G6;
`docs/specs/M6-cold-storage.md`, approved 2026-09-26 with ADR-007 and ADR-011 as C)
Status: **in progress**, not submitted. Branch `claude/functional-playable-requirements-0ebcjo`.
The four-part package (specification, verification report, demo script, debt log) is
completed at submission; until then this file carries the progress by group and the
debt log, so deviations are recorded as they happen (CLAUDE.md §1).

---

## Progress by group

| Group | Claims | State | Commits |
|---|---|---|---|
| A. The site is content | 1–4 | code and tests in; Deck raise cost not yet measured | `eefdaa5`, `dfe0208`, `4064bc9`, `8c73f70` |
| B. Levels | 5–7 | not started | |
| C. Doors, locks, breaching | 8–9 | not started | |
| D. Sensors and standing | 10–11 | not started | |
| E. Hacking | 12–13 | not started | |
| F. Death, corpses, recovery | 14–16 | not started | |
| G. Contracts | 17–19 | not started | |
| H. The mission as content | 20–21 | not started | |
| I. Client | 22–26 | not started | |
| J. Fixtures, save, corpus, tools, Deck | 27–32 | not started | |

### Group A, as delivered

- `BuildSystem.place_batch`: a list of pieces as one change, supported as a whole,
  refused whole on any bad entry, one `build.changed` and so one portal rebuild.
  Property: 1 000 generated structures, batch equals one by one in pieces, ids and
  portal graph (`tests/land/test_build_batch.gd`).
- `SiteSystem` (system id `sites`) and `site.raise`; `content/site/home.json` and
  `content/site/m4_building.json`, the latter generated from `client/m4_building.gd`.
  The M4 site equals the M4 building placed command by command, in one rebuild
  (`tests/quests/test_site_system.gd`).
- `actor.spawn {profile, site, point}`; the world view spawns the player at the M4
  site's start and raises the site, and no longer writes a position itself. Fitness
  rule 5 refuses any client call to a sim `set_*` method; it found exactly that one.
- A quest may name a site; accepting it binds it in the record.
- All sixteen fixture hashes moved in `dfe0208`: the new system and new content enter
  the state hash. Every other system's state was compared fixture by fixture before
  and after and is identical.

Screenshots: `docs/gates/screenshots/M6-groupA-site-raise.png` (the ready line: 93
pieces, four guards, 0 rejected, player on the site's start point) and
`M6-groupA-building.png` (the raised building in play).

---

## 4. Debt and deviation log

| # | Item | Kind | Scheduled |
|---|---|---|---|
| 1 | Claim 1 lists `containers`, `terminals` and `sensors` in a site. Group A's schema has parcels, pieces, points and agents only; each of the other three joins the schema with the group that reads it (sensors D, terminals E, containers F), so no field ships that nothing reads. | deviation (order) | groups D, E, F |
| 2 | Claim 1 says the validator checks that every piece is within its support span "at build time". `tools/validate_content.py` checks every reference; support is checked by a headless test that raises every shipped site in a fresh sim (`test_every_shipped_site_raises_and_stands`), which runs in the same CI pass, and again by the raise itself, which refuses a site that would not stand. Re-implementing support in Python would be a second copy of the rule. | deviation (mechanism) | none |
| 3 | Site pieces, points and agents are relative to the site's `origin`, but the patrol routes and parcels they name are content with absolute coordinates, so a site works only at the origin it was authored for. Relocating a site is what M7's generator does; routes relative to a site come with it. | scope | M7 |
| 4 | The spec's property table names `tests/quests/test_site.gd` with 1 000 generated sites. The 1 000-case property is on the batch the raise uses (`tests/land/test_build_batch.gd`), where the equivalence lives; the site level is covered by the M4 site against the command-by-command build and by every shipped site raising. | deviation (placement) | none |
| 5 | CLAUDE.md §3 asks for one `sim/` module per session. Group A touches `sim/land`, `sim/quests`, `sim/agents` and the assembly, as the approved spec groups it; it was done as one commit per module, each passing `tools/test.sh` on its own. | deviation (process) | none |
| 6 | Claim 2: "the gate records the raise cost on the Deck". Not measured yet; the desktop headless run is not evidence. | outstanding | G6 Deck run |
| 7 | Only `home` and `m4_building` ship. `cold_storage` is group H's content; `home` gains the fixer's post in group G. | scope | groups G, H |
| 8 | The world view's status line still reads "Gcity M5 world"; untouched, as the client is group I's. | residue | group I |
