# G7 mutation triage (claim 18)

Every mutant that survived the first pass, and what became of it. Three verdicts:

- **hole** — a real gap in the tests. A test now fails on the mutant; each was checked by
  applying the mutant by hand (`tools/mutate.py`'s own operators, run against the file's
  mapped tests) and seeing it killed.
- **equivalent** — no test can tell the mutant from the original, with the reason.
- **harness** — the tests noticed and the tool did not; the tool is fixed.

Pass 1 ran on the Steam Deck (`M7-mutation-pass1.log`, files 1–20) and on the Windows
laptop under WSL2 (`M7-mutation-pass1b.log`, files 21–48). The Deck files were sampled
before `mutate.py` sampled per file, so their mutants differ from what one uninterrupted
run would have picked.

## The harness

`mutate.py` compared a run's `ERROR:` lines with the untouched run's, but not its
`SCRIPT ERROR:` lines. A GDScript runtime error does not fail the test it happens in, so
`stress_system.gd:216` deleted — which makes every calm agent's tick throw — printed
3 309 runtime errors, reported `30 tests, 0 failed`, and was scored a survivor. The unit
stage's `tools/check_test_log.py` fails the same run. `diagnostics()` now reads both, with
a test. The files after `save_file.gd` were run with the fix; the Deck's were not.

`sim/land/land_system.gd` is now mapped to `tests/sim/test_pause.gd` as well: its pause
handler is what those tests drive (`land_system.gd:134`).

## Survivors

80 survivors: 53 holes, 24 equivalent, 2 harness, 1 caught only outside the file's mapped tests.

| pass | mutant (`sim/…`) | operator | verdict | test, or why |
|---|---|---|---|---|
| 1 | `agents/actor_system.gd:227` | `1 -> 2` | equivalent | the integer square root's upward correction, which the float estimate makes unnecessary at the distances the sim computes (Deck) |
| 1 | `agents/actor_system.gd:334` | deleted | hole | `test_actor_system`: a revived actor comes back whole (Deck) |
| 1 | `agents/corpse_system.gd:243` | `return false -> true` | equivalent | revive cannot fail there (Deck) |
| 1 | `agents/corpse_system.gd:303` | `0 -> 1` | equivalent | an initial value, overwritten on the first pass (Deck) |
| 1 | `agents/corpse_system.gd:307` | `0 -> 1` | equivalent | an initial value, overwritten on the first pass (Deck) |
| 1 | `agents/hydration_system.gd:234` | `< -> <=` | hole | `test_hydration`: a squad of one is still a squad (Deck) |
| 1 | `agents/hydration_system.gd:282` | deleted | equivalent | a squad only takes the gate partway along its last road, so the leg cannot change there (Deck) |
| 1 | `agents/macro_token_system.gd:226` | deleted | hole | `test_macro_token`: a released token stands where its squad handed it back (Deck) |
| 1 | `agents/macro_token_system.gd:412` | `< -> <=` | hole | `test_macro_token`: a token at the slowest pace saves and loads (Deck) |
| 1 | `agents/movement_system.gd:94` | `<= -> <` | hole | `test_vertical_movement`: a fall that does no damage is not an event (the range dummy's profile takes none) |
| 1 | `agents/movement_system.gd:254` | deleted | hole | `test_vertical_movement`: climbing through a solid floor is refused and counted (Deck) |
| 1 | `agents/movement_system.gd:376` | deleted | hole | `test_vertical_movement`: a save with a negative counter is refused (Deck) |
| 1 | `agents/pathing_system.gd:53` | `!= -> ==` | hole | `test_agent_pathing`: a build change re-plans at once and a removed agent leaves no route (Deck) |
| 1 | `agents/pathing_system.gd:236` | deleted | hole | `test_agent_pathing`: the search heads straight for an open goal (expansions counted) |
| 1 | `agents/pathing_system.gd:265` | deleted | equivalent | a path always unwinds to its start (Deck) |
| 1 | `agents/pathing_system.gd:282` | `== -> !=` | hole | `test_agent_pathing`: an arrived route survives a save. The branch it guards cannot be reached (a path runs out only on its goal), but the mutant also leaves an arrived route holding a search, which restore refuses |
| 1 | `agents/raid_token_system.gd:165` | deleted | equivalent | without the reset only a token that then fails or arrives keeps a stale progress, and a finished token is never advanced; one that goes on re-plans and zeroes it |
| 1 | `agents/raid_token_system.gd:184` | deleted | equivalent | the crossing is already none whenever a token stands in its target's volume: a crossing ends by clearing it, and a build change re-plans |
| 1 | `agents/raid_token_system.gd:192` | deleted | hole | `test_raid_token_system`: a token built over where it stands fails |
| 1 | `agents/raid_token_system.gd:260` | `< -> <=` | hole | `test_raid_token_system`: a token that has not started restores |
| 1 | `agents/squad_system.gd:103` | `0 -> 1` | equivalent | the latency is only asked of the observer of an alert, which is always an agent |
| 1 | `agents/squad_system.gd:226` | deleted | hole | `test_squad`: a door to the next room is not an entry |
| 1 | `agents/stance_system.gd:301` | `0 -> 1` | hole | `test_stance_scoring`: an agent that is not alerted scores no advance |
| 1 | `agents/stance_system.gd:541` | `8 -> 9` | equivalent | the refinement gains one candidate nine degrees from the coarse best, visited first; it could only win by tying the best, and the milli-cosine does not tie across nine degrees near its peak |
| 1 | `agents/stance_system.gd:552` | `0 -> 1` | hole | `test_stance_scoring`: the dominant step of a one-cell offset |
| 1 | `agents/stress_system.gd:107` | `return false -> true` | equivalent | only ever asked of agents, and every agent profile must name a stress profile |
| 1 | `agents/stress_system.gd:150` | `0 -> 1` | hole | `test_aim_and_stress`: distance before the start of a one-millimetre segment |
| 1 | `agents/stress_system.gd:216` | deleted | harness | 3 309 runtime errors and `0 failed`; killed by the fixed harness, and by the next row's test |
| 1 | `agents/stress_system.gd:232` | deleted | hole | `test_aim_and_stress`: a calm agent keeps one record and one modifier |
| 1 | `assembly.gd:134` | `!= -> ==` | hole | `test_sim_assembly`: load_save refuses a save made over other content |
| 1 | `assembly.gd:188` | deleted | hole | `test_sim_assembly`: restore_systems refuses a snapshot without systems |
| 1 | `assembly.gd:235` | deleted | hole | `test_sim_assembly`: restore_systems restores the squads |
| 1 | `assembly.gd:271` | `== -> !=` | hole | `test_sim_assembly`: content_of hands back the content the sim was built over |
| 1 | `core/command_registry.gd:26` | deleted | hole | `test_command_registry`: pause-safe is recorded only when asked for |
| 1 | `core/content_db.gd:67` | `return false -> true` | hole | `test_content_db`: has is false for an unknown kind |
| 1 | `core/replay.gd:24` | deleted | equivalent | unreachable: a fixture's commands are at tick 1 or later and Replay refuses a sim that has ticked, so submit cannot fail |
| 1 | `core/replay_fixture.gd:69` | `> -> >=` | hole | `test_replay_fixture`: name length boundary |
| 1 | `core/replay_fixture.gd:139` | `0 -> 1` | equivalent | every branch of the match sets the value or returns |
| 1 | `core/save_file.gd:63` | `> -> >=` | hole | `test_save_file`: size limit boundary |
| 1b | `core/save_file.gd:22` | `64 -> 65` | equivalent | no specification names the depth; the M2 gate asks that 200-deep nesting is refused, which any limit between the state's own depth and 200 does |
| 1b | `core/save_file.gd:127` | `1 -> 2` | hole | `test_save_file`: nesting limit boundary |
| 1b | `core/sim_root.gd:228` | `0 -> 1` | hole | `test_sim_root`: a sim that has not ticked restores |
| 1b | `items/combat_system.gd:160` | `0 -> 1` | hole | `test_combat_system`: something that is not an actor has no hit chance |
| 1b | `items/combat_system.gd:312` | deleted | hole | `test_combat_system`: the last shot survives a save |
| 1b | `items/combat_system.gd:316` | deleted | hole | the same test: the hit node must come back a StringName, and the state hash tells the types apart |
| 1b | `items/item_system.gd:621` | deleted | equivalent | the list belongs to the chamber container, which the next line erases |
| 1b | `items/item_system.gd:870` | `10 -> 11` | outside | moves `m6-loud`'s state hash (`395f1382…` to `ec4cdc01…`), which `test_m6_fixtures` checks; that test is not one of the item system's mapped tests |
| 1b | `land/land_system.gd:134` | deleted | harness | the pause handler is driven by `tests/sim/test_pause.gd`, now mapped to the land system; it kills this |
| 1b | `land/structure_system.gd:192` | `0 -> 1` | hole | `test_structure_system`: an unknown structure has an empty footprint |
| 1b | `land/structure_system.gd:237` | `1 -> 2` | hole | `test_structure_system`: every corner of the footprint is checked to the millimetre (on a plot that widens; on the shipped rectangles two corners always agree) |
| 1b | `land/structure_system.gd:410` | `1 -> 2` | equivalent | a structure's id is never 1: placing one needs an actor, which takes an id first |
| 1b | `nav/portal_graph.gd:100` | `== -> !=` | hole | `test_portal_graph`: a room in a hollow below city ground is a volume |
| 1b | `nav/portal_graph.gd:162` | `< -> <=` | equivalent | inside `if px != py` |
| 1b | `progression/stat_resolver.gd:640` | `< -> <=` | equivalent | inside `if oa != ob` |
| 1b | `quests/site_binder.gd:71` | deleted | hole | `test_site_binder`: a contract wanting somewhere new is not sent where you have been |
| 1b | `quests/site_constraint.gd:48` | `return false -> true` | hole | `test_site_constraint`: a contract that asks for something is not happy nowhere |
| 1b | `quests/terminal_system.gd:194` | `return false -> true` | hole | `test_terminal_system`: nobody without a device can hack |
| 1b | `quests/terminal_system.gd:203` | deleted | hole | `test_terminal_system`: placing an unknown terminal is refused |
| 1b | `threat/standing_system.gd:129` | deleted | hole | `test_standing`: a rule raised by events that names none fails assembly |
| 1b | `threat/standing_system.gd:188` | `<= -> <` | hole | `test_standing`: a rule with no period never decays (the schema allows 0; the mutant divides by it) |
| 1b | `threat/standing_system.gd:224` | deleted | equivalent | standing is clamped at zero, so the skipped case is a zero written over nothing |
| 1b | `world/authored_region.gd:19` | `>= -> >` | hole | `test_regions`: the city owns its west and south edges |
| 1b | `world/discovery.gd:44` | `0 -> 1` | hole | `test_discovery`: places are looked for on the clock, not every tick |
| 1b | `world/region.gd:24` | `return false -> true` | equivalent | overridden by both regions, behind `assert(false)` |
| 1b | `world/region.gd:48` | `0 -> 1` | hole | `test_regions`: the city ground is not dug and is drawn as it reads |
| 1b | `world/region.gd:52` | `1 -> 2` | hole | the same test |
| 1b | `world/region.gd:52` | deleted | hole | the same test |
| 1b | `world/region.gd:53` | deleted | hole | the same test |
| 1b | `world/region.gd:59` | `return false -> true` | hole | the same test |
| 1b | `world/regions.gd:99` | deleted | hole | `test_regions`: regions need content |
| 1b | `world/regions.gd:183` | `2 -> 3` | hole | `test_regions`: a cell across an edge off the grid goes with its centre (nothing requires region bounds to lie on the grid) |
| 1b | `world/regions.gd:208` | `1 -> 2` | equivalent | regions are boxes, so the fourth corner still sees the far edge; a false alarm only sends the box down the cell-by-cell path, which gives the same answers |
| 1b | `world/regions.gd:474` | deleted | equivalent | the restore moves the revision past anything the old log could answer for, so its entries are never read |
| 1b | `world/route_graph.gd:1157` | deleted | hole | `test_route_graph`: neighbours are lowest first |
| 1b | `world/settlement_kits.gd:119` | `>= -> >` | hole | `test_settlement_kits`: a road to one past the last place fails. Killed only because the message changes: a later check refuses the same kit, so the outcome was never wrong |
| 1b | `world/site_system.gd:86` | deleted | hole | `test_site_system`: a site placing two pieces in one spot fails assembly |
| 1b | `world/site_system.gd:245` | `!= -> ==` | hole | `test_site_system`: a raised site records the terminals it placed |
| 1b | `world/terrain.gd:373` | deleted | hole | `test_terrain`: a snapshot from another seed makes that ground |
| 1b | `world/wild_region.gd:30` | `4096 -> 4097` | equivalent | the cache's size, which by its own comment changes nothing but time |
| 1b | `world/wild_region.gd:228` | `1 -> 2` | equivalent | the one caller asks `>= 0` |

## Pass 2: after

Every `sim/` file again (`M7-mutation-pass2-a.log`, `-b.log`, split across two worktrees),
with pass 1's tests and the fixed harness. **221 of 252 scored mutants killed: 87.7 %**
(31 did not compile and are not counted). Files 21–48 drew the same mutants as in pass 1;
the Deck's twenty drew new ones, since they are now sampled per file.

Pass 2 started before the tests below were written, so they are not in its number. The
movement and pathing files were run again once their last tests were in
(`M7-mutation-pass2-agents` in the tree, not kept): the same twelve mutants, the same result.

Survivors of pass 1 that pass 2 drew again survived again only where pass 1 called them
equivalent or outside (`structure_system:410`, `region:24`, `wild_region:30` and `:228`,
`item_system:621` and `:870`, `portal_graph:162`, `stat_resolver:640`, `standing_system:224`,
`regions:474` and `:208`). The new ones:

20 new survivors: 12 holes, 6 equivalent, 1 open, 1 on a defective branch.

| mutant (`sim/…`) | operator | verdict | test, or why |
|---|---|---|---|
| `agents/actor_system.gd:226` | `<= -> <` | equivalent | the square root's upward correction again: the float estimate is exact on perfect squares at these magnitudes |
| `agents/actor_system.gd:415` | `return false -> true` | hole | `test_actor_system`: putting away a device you do not carry is refused |
| `agents/aim_system.gd:187` | `== -> !=` | hole | `test_aim_and_stress`: a quiet agent keeps its aim modifier (the mutant tears it down and makes it again every tick) |
| `agents/corpse_system.gd:225` | `> -> >=` | equivalent | with nothing affordable the fee is zero, and moving no notes changes nothing |
| `agents/corpse_system.gd:258` | `> -> >=` | hole | `test_corpse`: a district exactly at the threshold is not held (no shipped district sits on 200) |
| `agents/hydration_system.gd:198` | `1 -> 2` | hole | `test_hydration`: a squad of one leaves the gate without waiting for a file (the count is only the file the gate rule checks, which is why the squad-of-one test did not see it) |
| `agents/hydration_system.gd:247` | `> -> >=` | hole | `test_hydration`: a token at exactly the agents' pace comes in |
| `agents/macro_token_system.gd:236` | `return false -> true` | hole | `test_macro_token`: dropping a token that is not held is refused |
| `agents/pathing_system.gd:193` | deleted | hole | `test_agent_pathing`: a failed route survives a save (restore refuses a failed route holding a search) |
| `agents/raid_token_system.gd:191` | `< -> <=` | open | a raid path of cost 0 needs a stair (opened for nothing) to be the only way between two volumes; the shipped pieces put stairs inside a volume and join levels by the hatch, and no geometry was found that reaches it. Not claimed equivalent |
| `agents/squad_system.gd:239` | `0 -> 1` | defect | the branch it sits on is itself wrong: see *A defect the run turned up* below |
| `agents/stance_system.gd:295` | `0 -> 1` | equivalent | the `else 0` in hold's score becomes 1 when a contact is known: one point in a million on a scoring weight no specification or content names |
| `agents/stance_system.gd:460` | `2 -> 3` | equivalent | a tuning distance (retreat while closer than twice the retreat distance) no specification names |
| `agents/stance_system.gd:531` | `0 -> 1` | hole | `test_stance_scoring`: facing toward nothing is north |
| `agents/stance_system.gd:589` | `0 -> 1` | equivalent | a stance record is made during a tick, and ticks start at 1, so `since` is never 0 |
| `agents/stress_system.gd:125` | `0 -> 1` | hole | `test_aim_and_stress`: something that is not an agent has no stress penalty |
| `assembly.gd:371` | deleted | hole | `test_sim_assembly`: movement_of requires an assembled sim |
| `core/content_db.gd:60` | deleted | hole | `test_content_db`: ids are sorted and the digest follows every add |
| `core/content_db.gd:89` | deleted | hole | the same test |
| `core/replay_fixture.gd:25` | `0 -> 1` | equivalent | the default of a field every valid parse sets; nothing reads it from an invalid fixture |

## A defect the run turned up

`SquadSystem._plan` hands each member outside the contact's volume the next edge in cost
order. A solid block standing in a wall is an edge too, and has no face, so `_outside_cell`
finds nothing for it; the loop then skips the member *without moving past the edge*, and
every member after it meets the same edge and gets nothing. A block costs what a wall of
the same material does and ties go to the lower piece id, so a block placed before the
walls ranks first among them. Reproduced with the sim unchanged: the M3 demo room with a
foundation block in place of one west wall, placed first, and three watchers told where the
player is: the first member is given the door; the other two are given nothing, with
sixteen walls on offer. The fix is in `sim/agents/` and outside claim 18, so it is not in
this branch; it is in the debt log for CEOGG.
