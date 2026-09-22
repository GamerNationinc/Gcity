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
