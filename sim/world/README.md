# `sim/world`

The world outside the player's plot: authored sites now, generated regions later
(design doc §5, §15).

| File | What |
|---|---|
| `route_graph.gd` | `RouteGraph` (system id `routes`): the world's nodes and corridors, generated from the world seed alone and **before anything else** — terrain, settlements and sites are consumers of it, so connectivity is true by construction rather than something to verify. Draws from its own generator, never `sim.rng()`, so the map cannot change because another system drew first. A save holds the seed, not the graph (M7 spec claim 1). Generation also emits the site slots: every settlement and point of interest offers one candidate location, part of the world hash (M7 spec claim 5). Every settlement node then has a kit spliced onto it, so a town is a subgraph of the world with its own streets and its district, not a label on a node (M7 spec claim 6). A bound site is stitched on afterwards as a leaf — a `site` node at its slot with one track to the node that offers it — which is the save's overlay rather than the seed's world, so it moves no distance and not the world hash (M7 spec claim 9). |
| `settlement_kits.gd` | `SettlementKits`: `content/settlement/` turned into plain data the graph can splice, plus the check that a kit cannot break the world — a block with no way in, a road too narrow, a kit so wide two towns would interleave. Runs at assembly, which is what keeps "connectivity is true by construction" true through splicing (M7 spec claim 6). |
| `site_tags.gd` | `SiteTags`: what a generated slot is good for, read from `content/site_tag/` rather than written onto the slot at generation. A tag declares the biomes and node kinds it belongs to; every slot that matches carries it. Keeps the world hash free of content, so a fifth tag is one new file and no existing world moves (M7 spec claim 5). |
| `terrain.gd` | `Terrain` (system id `terrain`): what the ground does, from the world seed, as a **consumer** of the route graph. Two fields — a long shallow base that roads follow, and the relief they cross — so a road's grade is the base swing over the shortest an edge can be, and `MAX_GRADE_PERMILLE` is derived from that rather than chosen. Where road and land disagree it emits a bridge, a cutting or a tunnel: the generator may not make a corridor it then blocks (M7 spec claim 7). |
| `site_system.gd` | `SiteSystem` (system id `sites`): `content/site/` entries raised by `site.raise {actor, site}` — every build piece placed as that actor, every agent spawned on its route — and recorded as raised so a save knows and a second raise is refused (M6 spec claim 3). |

**Allowed imports:** `sim/` only.

**Introduced at:** M6 (authored sites), M7 (the route graph). Generated regions and
site binding: M7, on top of the graph.

**Extension point:** a site is one content file; see
[docs/extending-missions.md](../../docs/extending-missions.md).
