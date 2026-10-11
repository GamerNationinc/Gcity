# Hostile site files (M6 spec claim 22)

Each file is one hostile site and whatever content it needs, as
`{"description", "expect", "entries": {kind: entry}}`. The site is added as
`site/zz_hostile` and any other entry under the id the site names (`zz_off_the_floor`,
`zz_unknown_effect`). `expect` is where it must be refused:

- `refused_at_assembly`: the content is invalid; `SimAssembly.build` returns null.
- `refused_at_spawn`: the content is well formed but cannot be raised; `site.spawn` is
  rejected and the sim's state hash does not move.

`tests/land/test_hostile_sites.gd` runs every file here.
