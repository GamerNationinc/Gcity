# iw4L: bot navigation (graph, multi-goal search, per-tick budget, caching)

## Problem it solves

Many bots need routes every few ticks on large maps without blowing the frame budget, without
oscillating, and without lying about why a route failed.

## Concepts and data (conceptual only)

- A baked navigation graph: nodes are 3D points sampled on a terrain-aligned tile lattice, with finer
  tiles near geometry changes. Directed edges with a cost and an edge kind (walk, drop down, break
  through a breakable obstacle). Nodes carry a connected-component label so "can A ever reach B" is a
  constant-time check.
- A route request passes through named phases: try a direct approach (destination close and the
  straight path is walkable); attach the start to reachable graph nodes using clearance probes; attach
  the goal (either nodes near a point, or all nodes inside an objective volume); search; validate the
  resulting path against current collision.
- Multi-goal search: the search accepts a set of goal nodes and ends at whichever it reaches first; the
  heuristic is the distance to the nearest goal, inflated by a constant factor to prefer finishing a
  route inside the shared budget over finding the optimal one.
- Tactical positions: around a threat, the space is cut into angular sectors and one precomputed support
  node per sector is a candidate, each checked for line of fire and exposure before routing.
- A shared per-tick expansion quota across all bots. A search keeps its open set and closed set between
  ticks (a resumable cursor), as do the attachment and validation phases; when the quota runs out mid
  search the request reports "budget exhausted" and resumes next tick with no repeated work.
- Three result classes: route, budget exhausted (retry later, not a failure), and terminal failure (no
  start support, no goal support, unreachable, empty or incomplete graph).
- A cache of terminal answers keyed by the request signature (start, goal/objective, graph identity).
  Only answers that follow from graph topology alone are cached; anything that depended on a collision
  query is rechecked next time. The whole cache is dropped when the graph identity changes.
- Per-request telemetry: age in budget slices and a starvation count (slices with no progress); the
  maximum of each is recorded per bot.

## Order of operations / tick structure

Per tick: the controller decides whether its current route still matches its destination (routes are
keyed by destination and reused across think ticks; a new request only when the destination moves
significantly). Requests draw expansions from the shared quota in a fixed order. Route following
advances waypoints on proximity, honours special edge kinds (no corner-cutting into a drop or ledge
segment; breakable obstacles get a dedicated movement mode), and checks walkability. Routes are
cancelled on graph change, respawn, or a task switch to an incompatible destination. A separate stuck
detector notices "commanded to move but not displaced for a while" and tries a fixed set of escape
directions, each checked for walkability and floor, before handing control back to the route.

## The trick that makes it work

Resumable cursors plus a shared quota make cost bounded per tick without making answers wrong: running
out of budget is a distinct outcome from failing, so nothing upstream ever treats "not computed yet" as
"unreachable". Caching only topology-derived failures keeps the cache sound when dynamic obstacles move.

## Failure modes and fixes seen in their history

- A truncated or out-of-range cached graph blob is treated as a cache miss and rebuilt, not read past
  its end. Baked data is untrusted.
- Collision probes include other players in the hull mask, so "static" walkability tests are affected by
  dynamic occupants; that is exactly why collision-dependent failures are never cached.
- Oscillation from repeatedly restarting a search in pursuit of a better path was solved by the inflated
  heuristic and by reusing routes keyed by destination.
- Determinism details they had to handle: nearby-node lists are sorted by distance then index; the open
  heap uses a total order over float scores; lattice sampling is anchored to world coordinates so a
  distant change cannot shift samples; parallel baking merges results in index order.

## What a Gcity version should consider

- Gcity's 1 m build grid makes the graph cheaper: nodes are grid cells, edge kinds (walk, drop, climb,
  breach) are registry entries so a new traversal kind is data. Breach edges tie directly into the M9
  threat director: a wall's HP becomes an edge cost, and the metamorphic relation "raising a wall's HP
  never lowers the chosen breach path's cost" applies.
- Use integer costs and integer (e.g. octile or Manhattan in grid units) heuristics so the open set
  order is exact; break ties by node index. No float heap ordering problem at all.
- Shared per-tick expansion quota owned by the sim, handed out in a fixed bot order (sorted id, possibly
  rotating start index each tick for fairness, with the rotation derived from the tick number so it
  stays deterministic). Searches must be resumable and their partial state must be part of the
  snapshot (or deterministically rebuildable) so replay hashes match.
- Keep "budget exhausted" as a first-class result type; test that no consumer treats it as failure.
- Multi-goal search with a nearest-goal heuristic is the right shape for "go to any breach point",
  "any loot container", "any exit".
- Cache terminal results keyed by request plus graph version; bump the version on any build or
  destruction that changes walkability. Never cache collision-dependent answers.
- Record age and starvation per request as debug telemetry; expose it on the handheld debug overlay.
- Property tests: a path returned is always walkable at the tick it was validated; budget-limited
  search eventually returns the same answer as unlimited search; result never depends on bot iteration
  order.

## Sources read (URLs only)

- https://raw.githubusercontent.com/vladtrc/iw4L/HEAD/docs/BOTS.md
- https://raw.githubusercontent.com/vladtrc/iw4L/HEAD/crates/bots/src/nav.rs
- https://raw.githubusercontent.com/vladtrc/iw4L/HEAD/crates/bots/src/controller.rs
- https://api.github.com/repos/vladtrc/iw4L/contents/crates/bots/src
