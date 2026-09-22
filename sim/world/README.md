# `sim/world`

The world outside the player's plot: authored sites now, generated regions later
(design doc §5, §15).

| File | What |
|---|---|
| `site_system.gd` | `SiteSystem` (system id `sites`): `content/site/` entries raised by `site.raise {actor, site}` — every build piece placed as that actor, every agent spawned on its route — and recorded as raised so a save knows and a second raise is refused (M6 spec claim 3). |

**Allowed imports:** `sim/` only.

**Introduced at:** M6 (authored sites). Generated regions, site binding and the route
graph: M7.

**Extension point:** a site is one content file; see
[docs/extending-missions.md](../../docs/extending-missions.md).
