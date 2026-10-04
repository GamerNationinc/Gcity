# Operator archetypes

The enemy roster's visual and role language, extracted from the concept sheet at
`assets/concepts/operator_variants.png` (2026-10-04). This page is design reference
for M6 world population and for anyone replacing the placeholder models; the numbers
live in `content/`, the pipeline contract in `assets/README.md`, and the track's
claims in `docs/specs/A1-operator-variant-assets.md`.

## The faction read

One faction, four kits. Every variant shares the identity set — **bone-white
faceted mask** over the lower face, **green multi-lens goggle array**, **dark hood**
over the helmet line, and the **skull-mask emblem** worn as a chest plate — so a
player reads "same outfit" at a glance and then reads the silhouette and camo for
the threat class. The faction is unnamed until the M6 narrative pass; nothing below
should hard-code a name.

Silhouette is the primary tell at range, palette the secondary:

| | Silhouette tell | Palette |
|---|---|---|
| Heavy Assault | bulk — deep vest, ammo box, widest stance | MultiCam Black (near-black, charcoal, olive trace) |
| Medium Operator | the baseline — standard vest, rifle, day pack | MultiCam (tan/brown/olive) |
| Light Recon | slim — minimal rig, long suppressed rifle | OD / woodland green |
| Drone Hunter | antennas — EW backpack mast cluster, grey blends with concrete | Urban grey (grey disruptive, blue equipment accents) |

## Variant 01 — Heavy Assault

- **Role words (sheet):** max armor · suppressive fire · team support · breach / objectives.
- **Read:** the anchor. Slowest mover, last to break, holds doorways and leans into
  fire. In data: most health, slowest speed, highest stress thresholds, stance
  weights on hold/advance, surrender nearly off.
- **Kit (sheet):** belt-fed LMG with box magazine, spare belt pouches, breaching
  charges, fighting knife, large utility pouch.
- **Placeholder model:** bulkiest torso/vest, ammo box on the chest rig, thick
  shoulder pads, short heavy gun block.

## Variant 02 — Medium Operator

- **Role words (sheet):** versatile · general purpose · recon / patrol · urban / rural.
- **Read:** the baseline body everything else is measured against — deliberately the
  `guard_sim` numbers restated, every stance at neutral weight. If a fight feels
  wrong against a Medium, the tuning problem is upstream, not in the variant.
- **Kit (sheet):** carbine with optic and foregrip, grenades, knife, standard pouch set.
- **Placeholder model:** the reference proportions; mid-length rifle; day pack.

## Variant 03 — Light Recon

- **Role words (sheet):** speed & mobility · scout / survey · long range observation · low signature.
- **Read:** sees first, shoots rarely, leaves early. In data: longest sight range in
  a narrow cone, tightest settled aim (slow to settle — a marksman, not a gunfighter),
  fastest feet, lowest break/rout thresholds, stance weights on
  investigate/flank/retreat, advance low.
- **Kit (sheet):** suppressed DMR with bipod, binoculars, sidearm with light,
  rangefinder, single mag pouch.
- **Placeholder model:** slimmest profile, longest rifle with suppressor block,
  minimal back gear.

## Variant 04 — Drone Hunter

- **Role words (sheet):** anti-UAS · EW / detection · rapid response · close quarters.
- **Read:** the counter-piece to player drones and the fastest responder. In data:
  widest field of view, longest hearing with the highest hearing gain (the EW suite
  "hears" what others can't), fast aim settle at a loose cone (CQB shotgun habits),
  radio latency 1 tick, stance weights on advance/investigate.
- **Kit (sheet):** combat shotgun with blue furniture, machine pistol, handheld RF
  detector, backpack EW station with antenna mast cluster, a downed quad as a trophy.
- **Placeholder model:** grey palette with blue weapon accent, EW backpack with
  three antenna masts — the one silhouette readable from behind.

## Relationship to existing content

- `guard_sim` / `guard_arcade` remain the M4 tuning fixtures and keep the capsule
  look; they are not part of the roster.
- `sentry_drone` is the thing Variant 04 exists to counter and, later, to escort.
- All four variants bind the shared `stance` set; none requires a stance, command or
  schema that does not already exist (ADR-008: same AI, retuned).
