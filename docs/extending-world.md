# Extending: the wilds — towns, site tags and contracts that bind to them

The minimal diff for a new kind of town, a new kind of place, and a job out at one.
M7 spec claims 5, 6, 8 and 9. The G7 extension exercise is a second settlement kit
and a fifth site tag, and a contract bound to the new tag, content only: the diff
under `sim/` is empty. Its files are `content/settlement/mining_camp.json`,
`content/site_tag/extraction.json` and `content/quest/claim_jumpers.json`, and
`tests/world/test_world_extension.gd` proves them.

## A new town: one file

`content/settlement/<id>.json`: `title`, `description`, `district` (a
`content/district/` id; its rules apply in the town), `min_blocks` / `max_blocks`,
`nodes`, `edges` and `sockets`.

- **`nodes`** are `{rel: [x, z], kind, block}` in millimetres from the settlement
  node the kit is spliced onto. `kind` is `junction` or `poi`; a gate or another
  settlement inside a town is refused. `block` is empty for the part that is always
  built, or a name: the world builds between `min_blocks` and `max_blocks` of the
  named blocks, chosen from the seed.
- **`edges`** are `{a, b, width}`, indices into `nodes`, width in millimetres.
- **`sockets`** are `{node, width}`: where the world's road comes into the town.
  A socket must be on the always-built part.

Every settlement node in a world takes one of the kits at random, so a second kit
means some towns are built from it and some from the first.

### What assembly refuses (`SettlementKits.validate`)

- A node further than `SettlementKits.MAX_REACH_MM` (200 m) from the anchor: two
  towns can abut, but their streets can never interleave.
- An edge to a node that is not there, or from a node to itself.
- `max_blocks` above the number of named blocks, or `min_blocks` above `max_blocks`.
- An always-built part that does not hold together on its own, or a block that is
  not joined to it directly. A block reachable only through another optional block
  would be cut off whenever that one was not built, and the world would come apart.

## A new kind of place: one file

`content/site_tag/<id>.json`: `title`, `description`, `biomes` and `node_kinds`.
A tag is **a reading over a slot, never a field written at generation**: every slot
whose biome is in `biomes` and whose node's kind is in `node_kinds` carries it. An
empty list matches everything, so `ruin` (both empty) is on every slot and every
contract can always bind somewhere.

Because tags are read rather than written, adding one moves no world hash. The
biomes are `RouteGraph.BIOMES` (`scrub`, `forest`, `rock`, `marsh`, `farmland`); a tag
naming another is refused at assembly as dead content.

## A contract that binds to it

A quest's optional `site` block: `{tags_any, min_km, max_km, undiscovered}`. Taking
the contract (`quest.accept`) binds it to one free slot that carries any of the tags,
lies within the distance band from the gate, and, with `undiscovered`, is somewhere
the player has not found yet. The pick is a hash of the world seed and the quest id,
so the same world gives the same place. The quest never names a slot.

## What moves when you add one

- **A new kit changes every world.** Generation is a function of the seed and the
  kits, so every replay fixture hash moves (the route graph's world hash is in the
  state). Worse, the place a contract binds to can move, and the M6 fixtures walk to
  wherever Cold Storage was bound. Re-run `tools/make_m6_fixtures.gd` and
  `tools/make_m7_fixtures.gd`, check that each run reports the outcome it is named for,
  then re-record every hash (`tools/test.sh replay` prints them).
- **A new tag moves nothing** unless a contract asks for it.
- **A new contract with a `site` block** changes nothing until it is accepted.

## Checklist

1. The file(s) above; `python3 tools/validate_content.py` is clean.
2. For a kit: a world with a town from it holds together
   (`RouteGraph.everywhere_is_reachable`) and its places are on the gate's roads.
3. For a tag: the slots it describes carry it and no others.
4. For a contract: accepting it binds a slot with the tag it asked for.
5. `tools/test.sh` passes with every fixture re-recorded, and `git diff --stat -- sim/`
   is empty.
