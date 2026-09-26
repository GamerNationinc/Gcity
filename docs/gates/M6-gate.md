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
| B. Levels | 5–7 | code and tests in; the search bound waits for the site (group H) | the group B commit |
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

### Group B, as delivered

- Floors: a cell holds an actor on the ground, over a floor or hatch, or over a solid
  cell piece; a step into a cell nothing holds falls to the first that something does.
  Height changes only on a fall, so every existing move is unchanged.
- `actor.climb {actor, dir, facing}`: up or down a ladder on that side, or up onto a
  climbable cell piece ahead, always to a cell that holds the actor. New `ladder`
  piece kind and piece (a passable, climbable vertical face); `crate` is climbable;
  every piece kind carries `climb`, and a climbable face must be vertical and passable.
- Pathing crosses levels: steps land where their falls end, climbs are transitions,
  the heuristic is the horizontal distance; agents climb to the exact cell their path
  names (`climb_onto`), so a side offering a ladder and a crate stays unambiguous.
- Properties: adding a ladder never raises or removes a path (10 000 cases); content
  with climbable crates never costs more than content without (1 000 layouts); the M4
  pathing property holds over both, with an oracle that knows the climb.
- Sight between levels: a floor blocks, a hatch does not (tests; see debt 12).
- All sixteen fixture hashes moved again with the piece-kind content; every other
  system's state compared fixture by fixture is identical before and after.

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
| 9 | `actor.climb` carries `facing` beside the spec's `{actor, dir}`: the sim holds no facing for the player, so the command names the side. Agents climb by `climb_onto(target)`, which the sim checks against the climbs their cell offers. | deviation (payload) | none |
| 10 | Claim 6's metamorphic relation, "adding a `climb` piece never raises the cost of any existing path", holds as stated for ladders, which are passable faces. A climbable crate is a solid cell and can cut a path by standing in it, so for crates the relation is tested as "making a piece climbable never raises a cost" (`test_property_a_climbable_crate_never_costs_more_than_a_plain_one`). | deviation (precision) | none |
| 11 | A ladder holds nobody by itself: each level it joins needs a floor or a hatch. The first version let a ladder hold whoever was beside it; the ladder property found that this stops falls a path relied on, so adding a ladder raised costs. Found in testing, removed before commit. The property also found that a ladder against a climbable crate hid the climb onto the crate; both climbs are now offered. | design note | none |
| 12 | Claim 7 asks for a three-dimensional line walk: perception's walk has been three-dimensional since M4 and a floor panel already blocks it. No perception code changed; tests now show a floor blocking sight between levels and a hatch not. | note | none |
| 13 | Claim 7: pathing's search bound (G4 debt 6) is re-decided by measurement on the site. `cold_storage` is group H's content, so the bound stays at `SEARCH_RADIUS` = 32 until then. | scope | group H |
| 14 | Planning cost per expansion rose with the climb checks. Measured on the desktop over the M4 pathing property: 90 s before group B, 141 s with the first version, 107 s with the climb index now in (+19 %). The Deck is the measurement that counts, with the site and five guards. | performance | G6 Deck run |
| 15 | A climb is instant: one command, one tick. Whether it should take time is a feel question for the Deck run. | tuning | G6 Deck run |
| 16 | The player cannot climb from the client yet: there is no binding. The contextual prompt is group I's (claim 23). | scope | group I |
| 17 | `tests/agents/test_agent_pathing.gd` changed with claim 6: "another level" is now an accepted goal, and the M4 property runs twice, over content with flat crates (unchanged thresholds, both outcomes common) and over the shipped content (climbable crates make most enclosures reachable). The unit stage is slower: the ladder property alone takes about six minutes, almost all of it portal-graph rebuilds (G3 debt 2's dirty set), and the full `tools/test.sh` now takes about 15 minutes in the cloud container. | note | G3 debt 2 |
