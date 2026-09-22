# Extending: sites, routes and contracts

The minimal diff for a new place and a new job. Design doc §15; M6 spec claims 3, 4,
9. The G6 extension exercise is a second contract against the same site with a
different terminal and payout, content only.

## A new site: one file

`content/site/<id>.json`: `title`, `base` (the world cell everything is relative to),
`parcels` (the parcels the builder must own, empty on unparcelled land), `pieces`
(`{piece, rel, facing}` in an order that keeps every piece within its material's span
of something already placed) and `spawns` (`{profile, rel, facing, squad, route}`).

`site.raise {actor, site}` raises it: every piece is placed **as that actor**, so the
land authority's rights apply exactly as they would to a player, and a site on owned
land needs the owner. A site raises once; a second raise is refused.

The layout is authored in `tools/make_sites.gd` and emitted as JSON, because a
hand-typed list of four hundred cells is not reviewable. Edit the code, run the tool,
re-record the fixture hashes.

### What the geometry has to respect

- **Foundations sit at ground level** and nothing else supports a chain; a basement
  is a gap you leave in the slab, not foundations below it.
- **A floor blocks its own stairwell.** Put a `roof_hatch` at the cell a flight
  passes through, or leave the floor out there.
- **A flight that ends in open air ends there**: the climb is refused rather than
  dropping the actor. Give the top of a flight something to stand on, or a flight of
  its own on the level above.
- **Two pieces cannot share a cell and facing.** `SiteSystem.validate_content`
  refuses the site at assembly rather than silently dropping one, so a collision is
  a failed start, never a missing wall.

## A route in, of a kind that already exists

- **A checked door**: a `door_check` piece whose `access` names an item tag. Any item
  carrying that tag in the actor's inventory opens it; to everyone else it is a wall,
  and it can still be breached like one.
- **A way up**: any piece whose kind has `climb`, with something standable at the top.
- **A way under**: leave a gap in the slab and cover it with a solid piece. Cutting
  or removing that piece is the entry, and the land's `build` right governs who may.

## A new patrol route: one file

`content/patrol_route/<id>.json`: absolute world cells, in order, looped. A route's
cells must be reachable from one another by the pathing rules, including the
climbable steps, or the guard stalls at the first unreachable waypoint.

## A new contract: one file

`content/quest/<id>.json` as `docs/extending-device.md` describes, with objectives on
the events the mission systems emit. Nothing in the sim knows which quest belongs to
which site: the objectives do that by naming events and tags.

## A new payout curve: one file

`content/payout_curve/<id>.json` prices a run. `clean_bonus` is what a run with all
four counters at zero pays; otherwise the payout is `base` less `per_detection`,
`per_alarm`, `per_body` and `per_trace` times their counters, and never below `floor`.
All five are milli-units of the contract's reward, so 1000 is "the stated payout".

The four counters are `RunScoreSystem`'s, and they are raised by events the sim
already emits, not by anything a mission declares:

| Counter | Raised by |
|---|---|
| `times_detected` | `perception.alerted` naming the player as the contact |
| `alarms_raised` | `squad.report` whose reporter had already seen the player |
| `bodies` | `combat.hit` with `killed`, credited to the shooter |
| `traces_left` | read at the end: pieces the player removed, terminals left un-wiped, bodies still lying |

Two consequences worth knowing before tuning a curve:

- **A body costs twice.** It raises `bodies` and, if it is left where it fell, it is
  also a trace. A quiet kill is cheaper than a loud one and dearer than no kill.
- **Traces are a reading, not a tally.** They are counted from the world when the run
  ends, so wiping a terminal before turning in erases that trace, and opening one
  afterwards does not add it back.

`run.begin {actor}` and `run.end {actor}` bracket a run, both pause-safe, so a
contract accepted from the device starts the count without the world running.

## A new standing scalar: one file

`content/standing_rule/<id>.json`, where the file's id is the scalar's name. It says
what raises the number, how often it is revisited and how fast it falls, and nothing
in `sim/` names the scalars themselves.

- `source: "events"` is credited by bus events exactly as skill xp is: an `event`, the
  payload key that names the actor to `credit`, a `tags_any` filter, a `when`
  condition and an `amount`. It decays every `period_ticks`.
- `source: "carried_value"` is not credited at all. It is recomputed on the same clock
  from the resolved `value` of the actor's carried items, so putting the kit down
  lowers it at once rather than waiting for a decay.

`decay.mode` is `flat`, or `direct`/`inverse` scaled by a district index named in
`decay.index`. Heat is `inverse` on `law_index`: it cools fastest where nobody is
looking. A scaled decay never falls below one a period, so a scalar always drains.

`when` is one of the conditions the system registers: `always`, or
`actor_on_foreign_parcel` (the actor is standing inside a parcel someone else owns).
A rule naming an unregistered condition is refused at assembly, not ignored.

### Giving an item a worth

Visible wealth reads the `value` stat. A frame declares it as a base stat; a part or
module declares it as a `value` modifier, which is how a fitted part raises its host
rather than being counted twice. A module loose in the bag therefore shows as nothing,
which is the intent: visible wealth is what a watcher can see you carrying.
