# ADR-011: Art direction, and where the assets come from

Status: proposed
Date: 2026-09-27
Design doc: §1 (concept, reference lineage), §2 (Deck target); M8 spec (look and feel)

## Context

Nothing in the game has a look yet: capsules, untextured boxes, flat-shaded ground, no
sound. The M8 spec proposes a milestone to fix that, and every claim in it after the
first two depends on two decisions that are creative and financial rather than
technical, so they are CEOGG's: **what the game looks like**, and **where its art and
sound come from**. Constraints either way: the Deck renders it at a locked 40 fps with
8 ms for render submission (standards §4.1); every asset is a dependency with a
recorded licence and hash (standards §5.4, M8 claim 4); pillar 3 (legibility) means a
guard, a door and a line of sight must read at a glance on a 7" screen; and the
long-run bar for the environment is Red Dead Redemption 2 (M7 spec), which this must
not foreclose.

## Decision 1 — Art direction

### A — Grounded near-future grit (recommended)
Readable, slightly stylised realism: PBR materials with a restrained palette, strong
silhouettes, dust and haze in the wilds, sodium and neon in the city. Deus Ex: Mankind
Divided's city and the badlands of Cyberpunk's Night City outskirts, at a fidelity the
Deck can hold. Cost: moderate; stock and CC0 assets get most of the way once a shared
palette and material set are applied over them. Forecloses nothing: it is the
direction RDR2-level detail grows out of.

### B — Stylised low-poly
Flat or lightly textured colour, simple shapes (Firewatch, Sable, low-poly survival
games). Cost: lowest; cheapest on the Deck; the fastest to look finished and unified.
Risk: fights the Tarkov-grade lethality and the RDR2 bar; moving to realism later is a
restart, not an upgrade.

### C — Photorealism
Scanned materials and high-detail characters. Cost: highest; neither the asset
sources nor the Deck budget reach it now. Forecloses: the 40 fps target on the Deck, on
current evidence.

## Decision 2 — Asset sourcing

### A — CC0 first, with a licence manifest (recommended)
Free public-domain packs (characters and animation sets, props, PBR textures, sound
effects), listed per file in `assets/MANIFEST.md` with source, licence and hash, and
unified by the art direction's palette and materials. Allowed licences: CC0 and
CC-BY (with attribution in the credits). Cost: none in money; time in curation.
Risk: a library look until the direction's palette is applied.

### B — A + paid stock where CC0 falls short
Marketplace assets (characters, weapons) where the free ones are not good enough, each
a licence line CEOGG approves. Cost: money per asset. Risk: licence terms that forbid
redistribution in a moddable game; each needs reading.

### C — Generated assets (AI models, textures, sounds)
Fast and bespoke. Risk: licence and provenance are unsettled for commercial release on
Steam, and Steam's content survey asks about it; quality and consistency vary.
Recommended only for placeholders that are replaced before release, if at all.

### D — Commissioned art
The highest quality and a unified look. Cost: money and lead time; a small team
schedule depends on someone outside it.

## Decision

Pending CEOGG. Recommended: **1A** (grounded near-future grit) and **2A**, moving to
**2B** asset by asset where CC0 falls short and CEOGG approves the spend.

## Consequences

Easy (with the recommendation): M8 can start at no cost, the look can grow toward the
long-run bar without a restart, and every asset is traceable to a licence. Hard: a
curated library does not look unified by itself; `docs/art-direction.md` (M8 claim 3)
and a shared material set carry that, and the first `tools/look.sh` view set will show
how far off it is.
