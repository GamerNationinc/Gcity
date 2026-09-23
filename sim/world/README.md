# `sim/world`

The world outside the player's plot: authored sites now, generated regions later
(design doc §5, §15).

| File | What |
|---|---|
| `route_graph.gd` | `RouteGraph` (system id `routes`): the world's nodes and corridors, generated from the world seed alone and **before anything else** — terrain, settlements and sites are consumers of it, so connectivity is true by construction rather than something to verify. Draws from its own generator, never `sim.rng()`, so the map cannot change because another system drew first. A save holds the seed, not the graph (M7 spec claim 1). Generation also emits the site slots: every settlement and point of interest offers one candidate location, part of the world hash (M7 spec claim 5). |
| `site_tags.gd` | `SiteTags`: what a generated slot is good for, read from `content/site_tag/` rather than written onto the slot at generation. A tag declares the biomes and node kinds it belongs to; every slot that matches carries it. Keeps the world hash free of content, so a fifth tag is one new file and no existing world moves (M7 spec claim 5). |
| `site_system.gd` | `SiteSystem` (system id `sites`): `content/site/` entries raised by `site.raise {actor, site}` — every build piece placed as that actor, every agent spawned on its route — and recorded as raised so a save knows and a second raise is refused (M6 spec claim 3). |

**Allowed imports:** `sim/` only.

**Introduced at:** M6 (authored sites), M7 (the route graph). Generated regions and
site binding: M7, on top of the graph.

**Extension point:** a site is one content file; see
[docs/extending-missions.md](../../docs/extending-missions.md).
